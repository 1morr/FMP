import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/glass_menu.dart';
import 'package:fmp/ui/common/confirm_dialog.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/queue/queue_layout.dart';
import 'package:fmp/ui/queue/queue_rows.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

enum _MenuAction { play, moveToNext, remove }

/// 佇列：外殼的一個分頁（`docs/design/queue.html`）。手機與平板是觸控列表，
/// 桌面與窄視窗是表格；播放順序是播過的、正在播的、摺線、接下來的。
/// 打開時捲到正在播的那首，點標題捲回去。
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
  final _scrolled = ValueNotifier(false);
  late final ScrollController _scroll;
  bool _initialized = false;
  bool _aligned = false;

  /// 大標題那一塊量到的高；量到之前用 [QueueLayout.headEstimate]。
  double? _headHeight;

  /// 表格選取的那一列，用 [QueueEntry.id] 認。
  int? _selectedId;

  QueueController get _queue => ref.read(queueProvider.notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    // 第一個畫面就在正在播的那首：先用估計的大標題高度算，畫完再用量到的
    // 高度對一次。
    final queue = ref.read(queueProvider);
    final layout = QueueLayout.of(FormFactor.of(context));
    final insets = ShellInsets.of(context);
    final content =
        insets.top +
        layout.headEstimate +
        QueueItem.of(queue)
            .fold(0.0, (sum, item) => sum + item.extent(layout)) +
        insets.bottom;
    final initial = _currentOffset(queue, layout, layout.headEstimate)
        .clamp(0.0, math.max(0.0, content - MediaQuery.sizeOf(context).height))
        .toDouble();
    _scrolled.value = initial > _titleGoneOffset;
    _scroll = ScrollController(initialScrollOffset: initial)
      ..addListener(() => _scrolled.value = _scroll.offset > _titleGoneOffset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrolled.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 讓正在播的那列落在第三列（上面露出兩首播過的）要捲到哪裡。列表每一項
  /// 的高都是定值，直接加起來，不必等遠處的列建出來。
  double _currentOffset(Queue queue, QueueLayout layout, double head) {
    final items = QueueItem.of(queue);
    final at = items.indexWhere(
      (item) => item is TrackItem && item.index == queue.currentIndex,
    );
    if (at < 0) return 0;
    final before = items
        .take(at)
        .fold(0.0, (sum, item) => sum + item.extent(layout));
    return math.max(0.0, head + before - 2 * layout.rowExtent);
  }

  /// 捲到正在播的那首。
  void _toCurrent({required bool animate}) {
    if (!_scroll.hasClients) return;
    final layout = QueueLayout.of(FormFactor.of(context));
    final target = _currentOffset(
      ref.read(queueProvider),
      layout,
      _headHeight ?? layout.headEstimate,
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _selectedId == null) {
      return KeyEventResult.ignored;
    }
    final index = _indexOf(_selectedId!);
    if (index < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
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
    final queue = ref.watch(queueProvider);
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
      final items = QueueItem.of(queue);
      // 沒有目前那首時當成在最後一首之後：全部都是播過的。
      final current = queue.currentIndex ?? queue.entries.length;
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
              itemExtentBuilder: (index, _) => items[index].extent(layout),
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
                current: current,
                playing: playing,
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
          child: _topBar(context, layout, queue),
        ),
      ],
    );
    if (layout.isTable) {
      page = Focus(focusNode: _focus, onKeyEvent: _onKey, child: page);
    }
    return page;
  }

  Widget _item(
    BuildContext context,
    QueueLayout layout,
    List<QueueItem> items,
    int i, {
    required int current,
    required bool playing,
  }) {
    final table = layout.isTable;
    switch (items[i]) {
      case PlayedCaption(:final count):
        return QueueCaption(
          key: const ValueKey('played'),
          count: count,
          table: table,
        );
      case UpNextFold(:final count, :final duration):
        return QueueFold(
          key: const ValueKey('fold'),
          count: count,
          duration: duration,
          table: table,
        );
      case TrackItem(:final index, :final entry):
        final id = entry.id;
        final isCurrent = index == current;
        if (table) {
          return QueueTableRow(
            key: ValueKey(id),
            entry: entry,
            index: index,
            flatIndex: i,
            isCurrent: isCurrent,
            dimmed: index < current,
            selected: id == _selectedId,
            playing: isCurrent && playing,
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
    final title = GestureDetector(
      key: const Key('queue-title'),
      behavior: HitTestBehavior.opaque,
      onTap: empty ? null : () => _toCurrent(animate: true),
      child: Semantics(
        header: true,
        button: !empty,
        child: Text(t.shell.nav.queue, style: text.large),
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
                  FmpButton(
                    label: t.queue.clear,
                    icon: FmpIcons.trash,
                    size: FmpButtonSize.small,
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

  /// 頂列（`.ptop`、`.wtop`）：左邊是大標題捲出去後淡入的小標題，右邊是清空。
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
            child: ExcludeSemantics(
              excluding: !scrolled,
              child: AnimatedOpacity(
                opacity: scrolled ? 1 : 0,
                duration: FmpMotion.mid,
                child: GestureDetector(
                  key: const Key('queue-small-title'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toCurrent(animate: true),
                  child: Semantics(
                    button: true,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: phone ? 6 : 0,
                        vertical: 12,
                      ),
                      child: Text(
                        context.t.shell.nav.queue,
                        style: TextStyle(
                          fontSize: phone ? 17 : 15,
                          fontWeight: phone ? FontWeight.w600 : FontWeight.w700,
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
        const Spacer(),
        switch (layout) {
          QueueLayout.phone || QueueLayout.tablet => GlassIconButton(
            icon: FmpIcons.trash,
            tooltip: t.clear,
            touch: true,
            onTap: clear,
          ),
          QueueLayout.wideTable => FmpButton(
            label: t.clear,
            icon: FmpIcons.trash,
            size: FmpButtonSize.small,
            onTap: clear,
          ),
          // 窄視窗的清空鈕在標題那一列。
          QueueLayout.narrowTable => const SizedBox.shrink(),
        },
      ],
    );
  }
}
