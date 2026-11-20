import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/domain/temporary_play.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/glass_menu.dart';
import 'package:fmp/ui/common/table_focus.dart';
import 'package:fmp/ui/common/confirm_dialog.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/now_playing/play_modes.dart';
import 'package:fmp/ui/queue/queue_layout.dart';
import 'package:fmp/ui/queue/queue_rows.dart';
import 'package:fmp/ui/queue/temporary_card.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

enum _MenuAction { play, moveToNext, remove }

/// 佇列：外殼的一個分頁（`docs/design/queue.html`）。手機與平板是觸控列表，
/// 桌面與窄視窗是表格；播放順序是播過的、正在播的、摺線、接下來的。
/// 打開時捲到正在播的那首，點標題捲回去。臨時播放時正在播的不在佇列裡：
/// 卡片插在要回去的那首上方，打開時捲到卡片。
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage> {
  /// 捲過這個位置，大標題就讓進頂列的小標題。
  static const _titleGoneOffset = 40.0;

  final _headKey = GlobalKey();
  final _focus = FocusNode(debugLabel: 'queue table');
  late final KeyboardFocus _keyboard;
  final _menuAnchor = GlobalKey(debugLabel: 'queue menu anchor');
  final _scrolled = ValueNotifier(false);
  late final ScrollController _scroll;
  bool _initialized = false;
  bool _aligned = false;

  /// 大標題那一塊量到的高；量到之前用 [QueueLayout.headEstimate]。
  double? _headHeight;

  /// 表格選取的那一列，用 [QueueEntry.id] 認。
  int? _selectedId;

  /// 量到之前臨時播放卡片的估計高，只用在第一個畫面的捲動範圍。
  static const _cardEstimate = 200.0;

  QueueController get _queue => ref.read(queueProvider.notifier);

  @override
  void initState() {
    super.initState();
    _keyboard = KeyboardFocus(_focus)..addListener(_onKeyboardFocus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    // 第一個畫面就在正在播的那首：先用估計的大標題高度算，畫完再用量到的
    // 高度對一次。
    final queue = ref.read(queueProvider);
    final temporary = ref.read(temporaryPlayProvider) != null;
    final layout = QueueLayout.of(FormFactor.of(context));
    final insets = ShellInsets.of(context);
    final content =
        insets.top +
        layout.headEstimate +
        QueueItem.of(queue, temporary: temporary).fold(
          0.0,
          (sum, item) => sum + item.extent(layout, cardExtent: _cardEstimate),
        ) +
        insets.bottom;
    final initial =
        _currentOffset(queue, layout, layout.headEstimate, temporary: temporary)
            .clamp(
              0.0,
              math.max(0.0, content - MediaQuery.sizeOf(context).height),
            )
            .toDouble();
    _scrolled.value = initial > _titleGoneOffset;
    _scroll = ScrollController(initialScrollOffset: initial)
      ..addListener(() => _scrolled.value = _scroll.offset > _titleGoneOffset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrolled.dispose();
    _keyboard.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 讓正在播的那列落在第三列（上面露出兩首播過的）要捲到哪裡；臨時播放
  /// 時是卡片，觸控版上面露出一首多一點（`docs/design/queue.html`）。列表
  /// 每一項的高都是定值，直接加起來，不必等遠處的列建出來；卡片在目標的
  /// 位置或之後，不必量。
  double _currentOffset(
    Queue queue,
    QueueLayout layout,
    double head, {
    required bool temporary,
  }) {
    final items = QueueItem.of(queue, temporary: temporary);
    final at = items.indexWhere(
      (item) => temporary
          ? item is TemporaryCardItem
          : item is TrackItem && item.index == queue.currentIndex,
    );
    if (at < 0) return 0;
    final before = items
        .take(at)
        .fold(0.0, (sum, item) => sum + item.extent(layout));
    final above = temporary && !layout.isTable
        ? layout.rowExtent + 10
        : 2 * layout.rowExtent;
    return math.max(0.0, head + before - above);
  }

  /// 臨時播放卡片在 [width] 寬的列表裡的高。
  double _cardExtent(
    QueueLayout layout,
    Queue queue,
    TemporaryPlay temporary,
    Duration rewind,
    double width,
  ) {
    final entry = queue.current;
    return QueueTemporaryCard.extent(
      context,
      table: layout.isTable,
      width: width,
      returnText: entry == null
          ? null
          : QueueTemporaryCard.returnText(
              context,
              table: layout.isTable,
              returnTo: entry,
              returnIndex: queue.currentIndex,
              resumeAt: temporary.resumeAt(entry, rewind),
              rewind: rewind,
            ),
    );
  }

  /// 捲到正在播的那首。
  void _toCurrent({required bool animate}) {
    if (!_scroll.hasClients) return;
    final layout = QueueLayout.of(FormFactor.of(context));
    final target = _currentOffset(
      ref.read(queueProvider),
      layout,
      _headHeight ?? layout.headEstimate,
      temporary: ref.read(temporaryPlayProvider) != null,
    ).clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    if (animate) {
      _scroll.animateTo(
        target,
        duration: FmpMotion.mid,
        curve: FmpMotion.outCurve,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _afterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _headHeight = _headKey.currentContext?.size?.height ?? _headHeight;
      if (_aligned || _headHeight == null) return;
      _aligned = true;
      _toCurrent(animate: false);
    });
  }

  int _indexOf(int id) =>
      ref.read(queueProvider).entries.indexWhere((e) => e.id == id);

  Future<void> _confirmClear() async {
    final t = context.t.queue.clearConfirm;
    final count = ref.read(queueProvider).entries.length;
    final confirmed = await showConfirmDialog(
      context,
      title: t.title,
      message: t.message(count: count),
      cancelLabel: t.cancel,
      confirmLabel: t.confirm,
      destructive: true,
    );
    if (confirmed && mounted) {
      _selectedId = null;
      await _queue.clear();
    }
  }

  void _remove(int index) {
    final entries = ref.read(queueProvider).entries;
    // 移除選取的那列後，選取移到下一列（沒有就上一列），連按 Delete 能一路刪。
    if (entries[index].id == _selectedId) {
      final next = index + 1 < entries.length ? index + 1 : index - 1;
      setState(() => _selectedId = next >= 0 ? entries[next].id : null);
    }
    _queue.remove(index);
  }

  void _select(int id) {
    setState(() => _selectedId = id);
    _focus.requestFocus();
  }

  void _onReorder(List<QueueItem> items, int from, int to) {
    if (items[from] case final TrackItem item) {
      final target = QueueItem.entryIndexAfterReorder(items, from, to);
      if (target != item.index) _queue.move(item.index, target);
    }
  }

  /// 用鍵盤移進表格時，還沒選取就選正在播的那首（沒有就第一首），外框才有
  /// 地方畫（`table_focus.dart`）。
  void _onKeyboardFocus() {
    if (_keyboard.value && _selectedId == null) {
      final queue = ref.read(queueProvider);
      if (queue.entries.isNotEmpty) {
        _selectedId = queue.entries[queue.currentIndex ?? 0].id;
      }
    }
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // 焦點在頁面裡的按鈕（例如清空佇列）時，↩ 是按那顆鈕，不是播選取的列。
    if (event is KeyUpEvent || _selectedId == null || !node.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final index = _indexOf(_selectedId!);
    if (index < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final entries = ref.read(queueProvider).entries;
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (isMenuKey(event)) {
      final at = anchorOf(_menuAnchor);
      if (at != null) _showMenu(_selectedId!, at);
    } else if (!alt && key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) setState(() => _selectedId = entries[index - 1].id);
    } else if (!alt && key == LogicalKeyboardKey.arrowDown) {
      if (index < entries.length - 1) {
        setState(() => _selectedId = entries[index + 1].id);
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _queue.playAt(index);
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _remove(index);
    } else if (HardwareKeyboard.instance.isAltPressed &&
        key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) _queue.move(index, index - 1);
    } else if (HardwareKeyboard.instance.isAltPressed &&
        key == LogicalKeyboardKey.arrowDown) {
      if (index < ref.read(queueProvider).entries.length - 1) {
        _queue.move(index, index + 1);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _showMenu(int id, Offset at) async {
    final t = context.t.queue;
    final queue = ref.read(queueProvider);
    final index = _indexOf(id);
    if (index < 0) return;
    final current = queue.currentIndex;
    final action = await showGlassMenu<_MenuAction>(
      context: context,
      at: at,
      entries: [
        GlassMenuItem(
          value: _MenuAction.play,
          label: t.playFromHere,
          icon: FmpIcons.play,
          shortcut: WindowChrome.enterKeyLabel,
        ),
        GlassMenuItem(
          value: _MenuAction.moveToNext,
          label: t.moveToNext,
          icon: FmpIcons.nextUp,
          // 沒有目前那首、或已經是正在播的或緊接在它後面時，沒有可移的。
          enabled: current != null && index != current && index != current + 1,
        ),
        const GlassMenuDivider(),
        GlassMenuItem(
          value: _MenuAction.remove,
          label: t.remove,
          icon: FmpIcons.close,
          shortcut: 'Delete',
          destructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    final now = _indexOf(id);
    if (now < 0) return;
    switch (action) {
      case _MenuAction.play:
        await _queue.playAt(now);
      case _MenuAction.moveToNext:
        _queue.moveToNext(now);
      case _MenuAction.remove:
        _remove(now);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 開、關隨機都會換掉正在播的那首的位置，畫面跟著捲到它。
    ref.listen(queueProvider.select((queue) => queue.shuffled), (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toCurrent(animate: true);
      });
    });
    final queue = ref.watch(queueProvider);
    final temporary = ref.watch(temporaryPlayProvider);
    final rewind = ref.watch(temporaryPlayRewindProvider);
    final playing = ref.watch(
      playbackProvider.select((state) => state?.playing ?? false),
    );
    final layout = QueueLayout.of(FormFactor.of(context));
    final insets = ShellInsets.of(context);
    final bar = ShellInsets.topBarOf(context);
    _afterBuild();

    final head = KeyedSubtree(
      key: _headKey,
      child: _head(context, layout, queue),
    );
    final horizontal = switch (layout) {
      QueueLayout.phone => EdgeInsets.zero,
      QueueLayout.tablet => const EdgeInsets.only(left: 4, right: 24),
      _ => EdgeInsets.fromLTRB(
        math.max(0, insets.left - 10),
        0,
        math.max(0, insets.right - 10),
        0,
      ),
    };

    final Widget scroll;
    if (queue.isEmpty) {
      scroll = CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: insets.top)),
          SliverPadding(
            padding: horizontal,
            sliver: SliverToBoxAdapter(child: head),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: insets.bottom),
              child: layout.isTable
                  ? Center(child: _empty(context))
                  : Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 120),
                        child: _empty(context),
                      ),
                    ),
            ),
          ),
        ],
      );
    } else {
      final items = QueueItem.of(queue, temporary: temporary != null);
      // 沒有目前那首時當成在最後一首之後：全部都是播過的。
      final current = queue.currentIndex ?? queue.entries.length;
      double extentOf(QueueItem item, double width) {
        if (item is! TemporaryCardItem) return item.extent(layout);
        return _cardExtent(layout, queue, temporary!, rewind, width);
      }

      scroll = CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: insets.top)),
          SliverPadding(
            padding: horizontal,
            sliver: SliverToBoxAdapter(child: head),
          ),
          SliverPadding(
            padding: horizontal,
            sliver: SliverReorderableList(
              itemCount: items.length,
              itemExtentBuilder: (index, dimensions) =>
                  extentOf(items[index], dimensions.crossAxisExtent),
              proxyDecorator: (child, index, animation) =>
                  queueLift(context, child),
              onReorderItem: (from, to) => _onReorder(items, from, to),
              findChildIndexCallback: (key) {
                if (key is! ValueKey<int>) return null;
                final at = items.indexWhere(
                  (item) => item is TrackItem && item.entry.id == key.value,
                );
                return at < 0 ? null : at;
              },
              itemBuilder: (context, i) => _item(
                context,
                layout,
                items,
                i,
                queue: queue,
                current: current,
                playing: playing,
                temporary: temporary,
                rewind: rewind,
              ),
            ),
          ),
          SliverPadding(
            padding: horizontal,
            sliver: SliverToBoxAdapter(
              child: QueueEndNote(
                repeat: queue.repeat,
                shuffled: queue.shuffled,
                table: layout.isTable,
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: insets.bottom)),
        ],
      );
    }

    Widget page = Stack(
      children: [
        Positioned.fill(child: scroll),
        Positioned(
          top: bar.top,
          left: bar.left,
          right: bar.right,
          height: bar.height,
          child: ShellTopBarArea(child: _topBar(context, layout, queue)),
        ),
      ],
    );
    if (layout.isTable) {
      // 整頁只為了接表格的按鍵；對螢幕閱讀器，可聚焦的是一列一列
      // （`FocusableTableRow`）。
      page = Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        includeSemantics: false,
        child: page,
      );
    }
    return page;
  }

  Widget _item(
    BuildContext context,
    QueueLayout layout,
    List<QueueItem> items,
    int i, {
    required Queue queue,
    required int current,
    required bool playing,
    required TemporaryPlay? temporary,
    required Duration rewind,
  }) {
    final table = layout.isTable;
    switch (items[i]) {
      case TemporaryCardItem():
        return QueueTemporaryCard(
          key: const ValueKey('temporary'),
          temporary: temporary!,
          returnTo: queue.current,
          returnIndex: queue.currentIndex,
          table: table,
        );
      case PlayedCaption(:final count):
        return QueueCaption(
          key: const ValueKey('played'),
          count: count,
          table: table,
        );
      case UpNextFold(:final count, :final duration, :final shuffled):
        return QueueFold(
          key: const ValueKey('fold'),
          count: count,
          duration: duration,
          shuffled: shuffled,
          table: table,
        );
      case TrackItem(:final index, :final entry):
        final id = entry.id;
        // 臨時播放時正在播的不在佇列裡，目前那首是要回去的地方。
        final isCurrent = index == current && temporary == null;
        final returnNote = index == current && temporary != null
            ? context.t.queue.temporary.returnRow(
                position: formatDuration(temporary.resumeAt(entry, rewind)),
              )
            : null;
        if (table) {
          return QueueTableRow(
            key: ValueKey(id),
            entry: entry,
            index: index,
            flatIndex: i,
            isCurrent: isCurrent,
            dimmed: index < current,
            selected: id == _selectedId,
            focused: id == _selectedId && _keyboard.value,
            menuAnchor: id == _selectedId ? _menuAnchor : null,
            playing: isCurrent && playing,
            returnNote: returnNote,
            onSelect: () => _select(id),
            onPlay: () => _queue.playAt(_indexOf(id)),
            onRemove: () => _remove(_indexOf(id)),
            onMenu: (position) => _showMenu(id, position),
          );
        }
        final previous = i > 0 ? items[i - 1] : null;
        return QueueTouchRow(
          key: ValueKey(id),
          entry: entry,
          flatIndex: i,
          isCurrent: isCurrent,
          dimmed: index < current,
          // 正在播的列上下不畫分隔線。
          separator:
              previous is TrackItem && !isCurrent && previous.index != current,
          playing: isCurrent && playing,
          returnNote: returnNote,
          onPlay: () => _queue.playAt(_indexOf(id)),
          onRemove: () => _remove(_indexOf(id)),
        );
    }
  }

  Widget _empty(BuildContext context) => QueueEmpty(
    onSearch: () => context.push(Destination.search.path),
    onLibrary: () => context.go(Destination.library.path),
  );

  /// 大標題（可點，捲回正在播的那首）與它下面的「n 首 · 時長」；表格版另有
  /// 快捷鍵提示與表頭。
  Widget _head(BuildContext context, QueueLayout layout, Queue queue) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    final t = context.t;
    final empty = queue.isEmpty;
    final min = context.fmpMetrics.minTarget;
    final title = ShellButton(
      key: const Key('queue-title'),
      onTap: empty ? null : () => _toCurrent(animate: true),
      focusRadius: 6,
      // 點擊區至少 [FmpMetrics.minTarget] 見方（平板的字比 44 窄），字靠左。
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(minWidth: min, minHeight: min),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Semantics(
            header: true,
            child: Text(t.shell.nav.queue, style: text.large),
          ),
        ),
      ),
    );
    final total = empty
        ? null
        : Text(
            queueTotalText(
              t,
              queue.entries.length,
              QueueItem.totalDuration(queue),
            ),
            style: text.foot.tabular.copyWith(color: colors.label2),
          );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        if (total != null) ...[const SizedBox(height: 2), total],
      ],
    );
    switch (layout) {
      case QueueLayout.phone:
      case QueueLayout.tablet:
        return Padding(
          padding: EdgeInsets.fromLTRB(
            ShellInsets.of(context).left,
            0,
            ShellInsets.of(context).right,
            6,
          ),
          child: titleBlock,
        );
      case QueueLayout.wideTable:
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  titleBlock,
                  if (!empty) ...[
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: QueueKeyHints(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!empty) const QueueTableHeader(),
          ],
        );
      case QueueLayout.narrowTable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  titleBlock,
                  const Spacer(),
                  const PlayModeToggles(glass: false),
                  const SizedBox(width: 12),
                  FmpButton(
                    label: t.queue.clear,
                    icon: FmpIcons.trash,
                    size: FmpButtonSize.small,
                    touchTarget: true,
                    onTap: empty ? null : _confirmClear,
                  ),
                ],
              ),
            ),
            if (!empty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: QueueKeyHints(),
              ),
              const QueueTableHeader(),
            ],
          ],
        );
    }
  }

  /// 頂列（`.ptop`、`.wtop`）：左邊是大標題捲出去後淡入的小標題，右邊是
  /// 隨機、循環與清空。
  Widget _topBar(BuildContext context, QueueLayout layout, Queue queue) {
    final colors = context.fmpColors;
    final t = context.t.queue;
    final phone = layout == QueueLayout.phone;
    final clear = queue.isEmpty ? null : _confirmClear;
    return Row(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _scrolled,
          builder: (context, scrolled, _) => IgnorePointer(
            ignoring: !scrolled,
            child: ExcludeFocus(
              excluding: !scrolled,
              child: ExcludeSemantics(
                excluding: !scrolled,
                child: AnimatedOpacity(
                  opacity: scrolled ? 1 : 0,
                  duration: FmpMotion.mid,
                  child: ShellButton(
                    key: const Key('queue-small-title'),
                    onTap: () => _toCurrent(animate: true),
                    focusRadius: 8,
                    // 點擊區至少 [FmpMetrics.minTarget] 見方（平板的字比 44 窄）。
                    builder: (context, _) => ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: context.fmpMetrics.minTarget,
                        minHeight: context.fmpMetrics.minTarget,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: phone ? 6 : 0,
                          vertical: 12,
                        ),
                        child: Text(
                          context.t.shell.nav.queue,
                          style: TextStyle(
                            fontSize: phone ? 17 : 15,
                            fontWeight: phone
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: colors.label,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        ...switch (layout) {
          QueueLayout.phone || QueueLayout.tablet => [
            const PlayModeToggles(glass: true),
            const SizedBox(width: 8),
            GlassIconButton(
              icon: FmpIcons.trash,
              tooltip: t.clear,
              touch: true,
              onTap: clear,
            ),
          ],
          QueueLayout.wideTable => [
            const PlayModeToggles(glass: false),
            const SizedBox(width: 12),
            FmpButton(
              label: t.clear,
              icon: FmpIcons.trash,
              size: FmpButtonSize.small,
              touchTarget: true,
              onTap: clear,
            ),
          ],
          // 窄視窗的隨機、循環與清空在標題那一列。
          QueueLayout.narrowTable => const <Widget>[],
        },
      ],
    );
  }
}
