import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/parts.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/search/search_history.dart';
import 'package:fmp/ui/common/empty_state.dart';
import 'package:fmp/ui/common/table_focus.dart';
import 'package:fmp/ui/common/track_actions.dart';
import 'package:fmp/ui/search/search_field.dart';
import 'package:fmp/ui/search/search_parts.dart';
import 'package:fmp/ui/search/search_query.dart';
import 'package:fmp/ui/search/search_rows.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:fmp/ui/toast/toast.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fmp/ui/common/expanding_rows.dart';
import 'package:fmp/ui/common/motion.dart';

/// 搜尋頁（`docs/design/search.html`）：搜尋欄沒有送出過的字時是搜尋紀錄，
/// 送出後是每個音源的結果。手機與平板是觸控列表，桌面與窄視窗是表格（密度
/// 跟裝置走，設計稿〈待確認〉28）。搜尋欄依寬度放在 dock、側欄或這一頁的
/// 頂端（中寬度，`DESIGN.md`〈中寬度〉）。
///
/// 點一首是臨時播放（brief〈播放〉）：觸控點一下；滑鼠單擊選取，雙擊或按 ↩
/// 才播。要放進佇列用 ⋮、右鍵或多選。
///
/// 多 P 影片（[hasParts]）可以展開列出分 P：點父列把整組當成一首臨時播放，
/// 點分 P 只播那一段；選單與多選的佇列動作拆成每個分 P（[trackActionRunner]）。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
    with SingleTickerProviderStateMixin {
  /// 結果第一次回來（骨架換成結果）的交叉淡出：out 280，減少動態效果時照樣
  /// （`DESIGN.md`〈狀態變化對照〉的內容替換）。
  late final _arrival = AnimationController(
    vsync: this,
    duration: FmpMotion.mid,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final _arrivalFade = CurvedAnimation(
    parent: _arrival,
    curve: FmpMotion.outCurve,
  );

  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'search results');
  late final KeyboardFocus _keyboard;
  final _menuAnchor = GlobalKey(debugLabel: 'search menu anchor');

  late final DockHidden _dock;

  /// 選取的曲目（滑鼠的選取，或觸控的多選）。
  final _selected = <TrackRef>{};

  /// ⇧ 點選一段的起點；也是 ↩ 要播的那首。
  TrackRef? _anchor;

  /// 觸控的多選模式（長按一列進入）。
  bool _selecting = false;

  /// 畫面上是結果（不是搜尋紀錄）；紀錄時不載入下一頁。
  bool _showingResults = false;

  /// 展開了分 P 的多 P 影片。
  final _expanded = <TrackRef>{};

  @override
  void initState() {
    super.initState();
    _dock = ref.read(dockHiddenProvider.notifier);
    _keyboard = KeyboardFocus(_focus)..addListener(_onKeyboardFocus);
    _scroll.addListener(_maybeLoadMore);
    _afterFrame(_maybeLoadMore);
  }

  @override
  void dispose() {
    _arrivalFade.dispose();
    _arrival.dispose();
    _scroll.dispose();
    _keyboard.dispose();
    _focus.dispose();
    // 離開搜尋頁時把 dock 還給外殼；不能在卸載的途中改 provider。
    if (_selecting) {
      final dock = _dock;
      unawaited(Future.microtask(() => dock.set(false)));
    }
    super.dispose();
  }

  /// 捲到離底不到 400 時載入下一頁（設計稿：捲到底自動載入）；篩選到一個
  /// 音源時只載它。第一頁填不滿畫面時沒得捲，畫完也檢查一次。
  void _maybeLoadMore() {
    if (!_showingResults) return;
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    if (_scroll.position.extentAfter < 400) {
      ref
          .read(searchProvider.notifier)
          .loadMore(only: ref.read(searchFilterProvider));
    }
  }

  void _afterFrame(VoidCallback f) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) f();
      });

  void _play(Track track) =>
      unawaited(trackActionRunner(context, ref)(TrackAction.play, [track]));

  /// 只臨時播放一個分 P。
  void _playPart(Track part) =>
      unawaited(ref.read(queueProvider.notifier).playTemporarily(part));

  /// 展開或收起 [track] 的分 P；列不出來就收起並提示原因。
  Future<void> _toggleParts(Track track) async {
    if (_expanded.contains(track.ref)) {
      setState(() => _expanded.remove(track.ref));
      return;
    }
    setState(() => _expanded.add(track.ref));
    final container = ProviderScope.containerOf(context, listen: false);
    final toasts = ref.read(toastProvider.notifier);
    final t = context.t;
    try {
      await readParts(container, track);
    } on AppError catch (error) {
      final name =
          container.read(pluginManifestProvider(track.ref.pluginId))?.name ??
          '';
      toasts.show(partsFailedToast(t, track, error, name));
      if (mounted) setState(() => _expanded.remove(track.ref));
    }
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _anchor = null;
      _selecting = false;
    });
    _dock.set(false);
  }

  // ---- 滑鼠的選取 ----

  void _pointerSelect(PointerDownEvent event, List<Track> tracks, int index) {
    final picked = tracks[index].ref;
    final keys = HardwareKeyboard.instance;
    final toggle = WindowChrome.commandKeyPressed;
    setState(() {
      if (keys.isShiftPressed && _anchor != null) {
        final from = tracks.indexWhere((t) => t.ref == _anchor);
        if (from >= 0) {
          _selected
            ..clear()
            ..addAll([
              for (
                var i = math.min(from, index);
                i <= math.max(from, index);
                i++
              )
                tracks[i].ref,
            ]);
          return;
        }
      }
      if (toggle) {
        if (!_selected.remove(picked)) _selected.add(picked);
        _anchor = picked;
        return;
      }
      // 右鍵按在已選取的列上：保留多選，選單作用在這一首。
      if (event.buttons & kSecondaryButton != 0 && _selected.contains(picked)) {
        return;
      }
      _selected
        ..clear()
        ..add(picked);
      _anchor = picked;
    });
    // 同一下按下也讓搜尋欄失焦（點欄位外面），失焦把焦點交給頁面；等這個
    // frame 過了再拿，↩ 與 Esc 才進得來。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// 用鍵盤移進表格時，還沒選取就選第一首，外框才有地方畫
  /// （`table_focus.dart`）。
  void _onKeyboardFocus() {
    final tracks = _tracksOf(
      ref.read(searchProvider),
      ref.read(searchFilterProvider),
    );
    if (_keyboard.value && _anchor == null && tracks.isNotEmpty) {
      _selectOnly(tracks.first.ref);
    }
    setState(() {});
  }

  /// 畫面上的結果：全部音源交錯，或篩選的那一個（同 [build]）。
  List<Track> _tracksOf(SearchState? search, String? filter) {
    if (search == null) return const [];
    if (filter == null) return search.tracks;
    return interleave([
      for (final s in search.sources)
        if (s.manifest.id == filter) s,
    ]);
  }

  void _selectOnly(TrackRef track) {
    _selected
      ..clear()
      ..add(track);
    _anchor = track;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, List<Track> tracks) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && _selected.isNotEmpty) {
      _clearSelection();
      return KeyEventResult.handled;
    }
    // 焦點在頁面裡的按鈕（chip、⋮）時，↩、方向鍵與選單鍵是那顆鈕的，不是
    // 表格的；Esc 在頁面裡哪裡都清掉選取。
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final at = tracks.indexWhere((t) => t.ref == _anchor);
    if (isMenuKey(event) && at >= 0) {
      final point = menuAnchorOf(_menuAnchor);
      if (point != null) {
        showTrackActions(context, ref, tracks[at], at: point);
      }
      return KeyEventResult.handled;
    }
    final keys = HardwareKeyboard.instance;
    if (!keys.isShiftPressed &&
        !keys.isAltPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) &&
        tracks.isNotEmpty) {
      final next = key == LogicalKeyboardKey.arrowUp
          ? math.max(0, at - 1)
          : math.min(tracks.length - 1, at + 1);
      setState(() => _selectOnly(tracks[next].ref));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final track = tracks.where((t) => t.ref == _anchor).firstOrNull;
      if (track != null && _selected.contains(track.ref)) {
        _play(track);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ---- 觸控的多選 ----

  void _startSelecting(Track track) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(track.ref);
    });
    if (FormFactor.of(context).widthClass == WidthClass.narrow) {
      _dock.set(true);
    }
  }

  void _toggle(Track track) => setState(() {
    if (!_selected.remove(track.ref)) _selected.add(track.ref);
  });

  Future<void> _runSelection(TrackAction action, List<Track> tracks) async {
    final chosen = [
      for (final t in tracks)
        if (_selected.contains(t.ref)) t,
    ];
    final run = trackActionRunner(context, ref);
    _clearSelection();
    await run(action, chosen);
  }

  @override
  Widget build(BuildContext context) {
    // 換了搜尋（新的查詢或排序）就清掉選取，也捲回頂端。
    ref.listen(searchProvider.select((s) => (s?.query, s?.sort)), (_, _) {
      if (_selected.isNotEmpty || _selecting) _clearSelection();
      if (_expanded.isNotEmpty) setState(_expanded.clear);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    // 結果換了（新的一頁回來、換篩選）之後畫面可能還填不滿：畫完再看一次。
    ref.listen(searchProvider, (previous, next) {
      _afterFrame(_maybeLoadMore);
      final filter = ref.read(searchFilterProvider);
      if (_tracksOf(previous, filter).isEmpty &&
          _tracksOf(next, filter).isNotEmpty) {
        _arrival.forward(from: 0);
      }
    });
    ref.listen(searchFilterProvider, (_, _) => _afterFrame(_maybeLoadMore));
    final controller = ref.watch(searchQueryProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context, controller.text.trim()),
    );
  }

  Widget _build(BuildContext context, String typed) {
    final form = FormFactor.of(context);
    final table = form.density == Density.pointer;
    final phone = form.widthClass == WidthClass.narrow;
    final medium = form.widthClass == WidthClass.medium;
    final search = ref.watch(searchProvider);
    // 還沒送出過、或欄位裡的字和這次的搜尋不同（正在打新的字）時是紀錄。
    final history = search == null || typed != search.query;
    // 從紀錄換到結果時，結果可能填不滿畫面：畫完看一次要不要載下一頁。
    if (!history && !_showingResults) _afterFrame(_maybeLoadMore);
    _showingResults = !history;
    final filter = ref.watch(searchFilterProvider);
    final visible = search == null
        ? const <SourceResults>[]
        : [
            for (final s in search.sources)
              if (filter == null || s.manifest.id == filter) s,
          ];
    final tracks = _tracksOf(search, filter);
    final insets = ShellInsets.of(context);
    final horizontal = switch ((table, phone)) {
      (true, _) => EdgeInsets.only(
        left: math.max(0, insets.left - 10),
        right: math.max(0, insets.right - 10),
      ),
      (false, true) => EdgeInsets.zero,
      (false, false) => const EdgeInsets.only(left: 4, right: 24),
    };

    final head = <Widget>[
      if (medium)
        _mediumTop(context, table, showHints: !history && table)
      else
        _title(context, phone, history ? null : search.query, table),
      if (!history)
        SearchFilterBar(
          search: search,
          filter: filter,
          table: table,
          onFilter: ref.read(searchFilterProvider.notifier).select,
          hints: !medium && table
              ? SearchKeyHints(commandKey: WindowChrome.commandKeyLabel)
              : null,
        ),
    ];
    // 找不到（`.srh-empty`）：每個音源都成功、都沒有結果時。
    final empty = !history && nothingFoundIn(visible)
        ? EmptyState(
            icon: FmpIcons.search,
            title: context.t.search.empty.title(query: search.query),
            titleStyle: context.fmpText.title3.copyWith(
              fontWeight: FontWeight.w700,
            ),
            body: context.t.search.empty.body,
          )
        : null;
    final body = history
        ? _history(context, typed, table)
        : empty != null
        ? const <Widget>[]
        : _results(context, search, visible, tracks, table);

    final scroll = CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: insets.top)),
        SliverPadding(
          padding: horizontal,
          sliver: SliverList.list(children: [...head, ...body]),
        ),
        ?empty,
        SliverToBoxAdapter(child: SizedBox(height: insets.bottom + 80)),
      ],
    );

    final playing = ref.watch(playbackProvider.select((s) => s != null));
    final count = _selected.length;
    Widget page = Stack(
      children: [
        Positioned.fill(child: scroll),
        if (phone && _selecting) _phoneSelectionTop(context, tracks),
        // 多選的動作列出現與消失：從底部滑上來（`DESIGN.md`〈狀態變化對照〉
        // 的小元件），手機的 dock 同時往下離開（外殼）。
        if (phone)
          Positioned(
            // 多選頂列插在前面時，動作列的過場不能被錯配到它身上。
            key: const ValueKey('selection bar slot'),
            left: 14,
            right: 14,
            bottom:
                30 +
                math.max(0.0, MediaQuery.viewPaddingOf(context).bottom - 34),
            child: AppearSwitcher(
              child: _selecting
                  ? PhoneSelectionBar(
                      key: const ValueKey('selection bar'),
                      onAction: (a) => _runSelection(a, tracks),
                    )
                  : null,
            ),
          )
        else
          Positioned(
            key: const ValueKey('selection bar slot'),
            left: 0,
            right: 0,
            bottom: playing ? 94 : 24,
            child: Center(
              child: AppearSwitcher(
                child: (table ? count >= 2 : _selecting && count > 0)
                    ? SelectionActionBar(
                        key: const ValueKey('selection bar'),
                        count: count,
                        onAction: (a) => _runSelection(a, tracks),
                        onClear: _clearSelection,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
    if (table) {
      // 整頁只為了接表格的按鍵；對螢幕閱讀器，可聚焦的是一列一列
      // （`FocusableTableRow`）。
      page = Focus(
        focusNode: _focus,
        includeSemantics: false,
        // 沒有結果（搜尋紀錄、找不到）時不是 Tab 停點：沒有列可畫外框。
        skipTraversal: tracks.isEmpty,
        onKeyEvent: (node, event) => _onKey(node, event, tracks),
        child: page,
      );
    }
    return page;
  }

  /// 大標題：手機一律「搜尋」；桌面搜過之後是「『夜』的搜尋結果」。
  Widget _title(BuildContext context, bool phone, String? query, bool table) {
    final t = context.t;
    final style = context.fmpText.large;
    final colors = context.fmpColors;
    final text = query == null || phone
        ? Text(t.shell.nav.search, style: style)
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: t.search.resultsTitle.query(query: query)),
                TextSpan(
                  text: t.search.resultsTitle.rest,
                  style: TextStyle(
                    color: colors.label3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
    return Padding(
      padding: EdgeInsets.only(
        left: table ? 10 : 20,
        right: table ? 10 : 20,
        bottom: table ? 14 : 10,
      ),
      child: Semantics(header: true, child: text),
    );
  }

  /// 中寬度的頂端（`.srh-mf`、`.srh-mtop`）：細欄沒有搜尋欄，欄位在這裡；
  /// 窄視窗的欄位右邊是快速鍵提示。
  Widget _mediumTop(
    BuildContext context,
    bool table, {
    required bool showHints,
  }) {
    const field = SearchField(placement: SearchFieldPlacement.page);
    if (!table) {
      // 觸控欄位的點擊區 44 比看得到的 40 高，多的 4 從下面的間距扣。
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 16, 6),
        child: field,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(
        children: [
          field,
          const Spacer(),
          if (showHints)
            SearchKeyHints(commandKey: WindowChrome.commandKeyLabel),
        ],
      ),
    );
  }

  List<Widget> _history(BuildContext context, String typed, bool table) {
    final t = context.t;
    final items = ref.watch(searchHistoryProvider).value ?? const <String>[];
    final shown = typed.isEmpty
        ? items
        : [
            for (final q in items)
              if (q.toLowerCase().contains(typed.toLowerCase())) q,
          ];
    // 沒有紀錄時只留大標題，欄位的提示文字已經說明能做什麼。
    if (shown.isEmpty) return const [];
    final notifier = ref.read(searchHistoryProvider.notifier);
    return [
      SearchSectionHeader(
        title: t.search.history.title,
        table: table,
        trailing: PlainTextButton(
          label: t.search.history.clear,
          table: table,
          onTap: notifier.clear,
        ),
      ),
      for (final (i, q) in shown.indexed)
        SearchHistoryRow(
          key: ValueKey('history $q'),
          query: q,
          typed: typed,
          separator: i > 0,
          table: table,
          onTap: () => searchFor(ref, q),
          onRemove: () => notifier.remove(q),
        ),
    ];
  }

  /// 還沒有結果時的骨架列數。
  static const _startSkeletons = 5;

  List<Widget> _results(
    BuildContext context,
    SearchState search,
    List<SourceResults> visible,
    List<Track> tracks,
    bool table,
  ) {
    final t = context.t;
    final notifier = ref.read(searchProvider.notifier);
    final failed = [
      for (final s in visible)
        if (s.error != null) s,
    ];
    final others = search.sources.length > 1;
    Widget error(SourceResults s) => table
        ? SearchErrorLine(
            source: s,
            othersShown: others && visible.length > 1,
            onRetry: () => notifier.retry(s.manifest.id),
          )
        : SearchErrorCard(
            source: s,
            othersShown: others && visible.length > 1,
            onRetry: () => notifier.retry(s.manifest.id),
          );

    // 只看一個出錯、還沒有結果的音源：整頁換成那張說明。
    if (visible.length == 1 && failed.length == 1 && tracks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: error(failed.single),
        ),
      ];
    }
    final loading = search.starting || visible.any((s) => s.loading);
    final playback = ref.watch(playbackProvider);
    final current = playback?.track.ref;
    final playing = playback?.playing ?? false;
    final narrowTable = FormFactor.of(context).widthClass == WidthClass.medium;
    final allLoaded =
        !loading && tracks.isNotEmpty && visible.every((s) => s.isEnd);
    return [
      SearchSectionHeader(
        title: t.search.online,
        count: loading && tracks.isEmpty ? null : tracks.length,
        table: table,
      ),
      if (table) SearchTableHeader(narrow: narrowTable),
      for (final s in failed) error(s),
      for (final (i, track) in tracks.indexed) ...[
        SkeletonCrossFade(
          key: ValueKey(('arrival', track.ref)),
          fade: _arrivalFade,
          // 剛回來的前幾列底下是原本的骨架，一起交叉淡出。
          skeleton: i < _startSkeletons
              ? SearchSkeletonRow(index: i, table: table)
              : null,
          child: _row(context, tracks, i, table, narrowTable, current, playing),
        ),
        ..._partRows(context, track, table, narrowTable, current, playing),
      ],
      if (loading)
        for (var i = 0; i < (tracks.isEmpty ? _startSkeletons : 2); i++)
          SearchSkeletonRow(index: i, table: table),
      if (allLoaded) SearchFoot(t.search.allLoaded, table: table),
    ];
  }

  /// [track] 已經列出來的分 P；還沒列過（或列失敗）是 null。不替沒展開過的
  /// 影片打請求。
  List<Track>? _knownParts(Track track) {
    // 棄用訊息指向的 `provider.exist` 在 riverpod 3.5.0 還沒有，先用 exists。
    // ignore: deprecated_member_use
    if (!ref.exists(partsProvider(track))) return null;
    return ref.watch(partsProvider(track)).value;
  }

  /// 結果的第 [i] 首（表格列或觸控列）。多 P 影片收起時，正在播的是它的
  /// 任一個分 P 就標成目前的曲目；展開時由分 P 列標。
  Widget _row(
    BuildContext context,
    List<Track> tracks,
    int i,
    bool table,
    bool narrowTable,
    TrackRef? current,
    bool playing,
  ) {
    final track = tracks[i];
    final parts = hasParts(
      track,
      ref.watch(pluginManifestProvider(track.ref.pluginId)),
    );
    final expanded = parts && _expanded.contains(track.ref);
    final loadingParts = expanded && ref.watch(partsProvider(track)).isLoading;
    final isCurrent = expanded
        ? false
        : track.ref == current ||
              (parts &&
                  (_knownParts(track)?.any((p) => p.ref == current) ?? false));
    if (table) {
      return SearchTableRow(
        // 測試與實跑靠它找第幾首（`test/support/shell.dart`）。
        key: ValueKey(track.ref),
        track: track,
        index: i,
        narrow: narrowTable,
        isCurrent: isCurrent,
        playing: playing,
        selected: _selected.contains(track.ref),
        focused: track.ref == _anchor && _keyboard.value,
        menuAnchor: track.ref == _anchor ? _menuAnchor : null,
        // 中間隔著展開的分 P 列時不相接。
        joinAbove:
            i > 0 &&
            _selected.contains(tracks[i - 1].ref) &&
            !_expanded.contains(tracks[i - 1].ref),
        joinBelow:
            i < tracks.length - 1 &&
            _selected.contains(tracks[i + 1].ref) &&
            !expanded,
        onPointerDown: (event) => _pointerSelect(event, tracks, i),
        onPlay: () => _play(track),
        onMenu: (at) => showTrackActions(context, ref, track, at: at),
        partCount: parts ? track.partCount : null,
        expanded: expanded,
        loadingParts: loadingParts,
        onToggleParts: () => _toggleParts(track),
      );
    }
    return SearchTouchRow(
      key: ValueKey(track.ref),
      track: track,
      separator: i > 0,
      isCurrent: isCurrent,
      playing: playing,
      selecting: _selecting,
      selected: _selected.contains(track.ref),
      onTap: () => _selecting ? _toggle(track) : _play(track),
      onLongPress: () => _selecting ? _toggle(track) : _startSelecting(track),
      onMore: (at) => showTrackActions(context, ref, track, at: at),
      partCount: parts ? track.partCount : null,
      expanded: expanded,
      loadingParts: loadingParts,
      onToggleParts: () => _toggleParts(track),
    );
  }

  /// 多 P 影片底下的分 P 列：展開與收起用首頁同一個展開元件（高度跟著
  /// 變，減少動態效果時只淡入淡出）；不是多 P 影片沒有。
  List<Widget> _partRows(
    BuildContext context,
    Track track,
    bool table,
    bool narrowTable,
    TrackRef? current,
    bool playing,
  ) {
    final manifest = ref.watch(pluginManifestProvider(track.ref.pluginId));
    if (!hasParts(track, manifest)) return const [];
    final expanded = _expanded.contains(track.ref);
    final parts = expanded
        ? ref.watch(partsProvider(track)).value ?? const <Track>[]
        : const <Track>[];
    return [
      ExpandingRows(
        key: ValueKey(('parts', track.ref)),
        expanded: expanded && parts.isNotEmpty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _partRowsOf(parts, table, narrowTable, current, playing),
        ),
      ),
    ];
  }

  List<Widget> _partRowsOf(
    List<Track> parts,
    bool table,
    bool narrowTable,
    TrackRef? current,
    bool playing,
  ) {
    return [
      for (final (i, part) in parts.indexed)
        table
            ? SearchPartTableRow(
                // 第一個分 P 和父列是同一首曲目，鍵要分開。
                key: ValueKey(('part', part.ref)),
                part: part,
                number: i + 1,
                narrow: narrowTable,
                isCurrent: part.ref == current,
                onPlay: () => _playPart(part),
                onMenu: (at) => showTrackActions(context, ref, part, at: at),
              )
            : SearchPartTouchRow(
                key: ValueKey(('part', part.ref)),
                part: part,
                number: i + 1,
                isCurrent: part.ref == current,
                playing: playing,
                selecting: _selecting,
                onTap: () => _playPart(part),
                onMore: (at) => showTrackActions(context, ref, part, at: at),
              ),
    ];
  }

  /// 手機多選時的頂列（`.ptop`）：「取消」「已選擇 n 首」「全選」。
  Widget _phoneSelectionTop(BuildContext context, List<Track> tracks) {
    final t = context.t;
    final bar = ShellInsets.topBarOf(context);
    return Positioned(
      top: bar.top,
      left: bar.left,
      right: bar.right,
      height: bar.height,
      child: ShellTopBarArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              t.search.selection.selected(count: _selected.length),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ).copyWith(color: context.fmpColors.label),
            ),
            Row(
              children: [
                GlassTextButton(
                  label: t.search.selection.cancel,
                  onTap: _clearSelection,
                ),
                const Spacer(),
                GlassTextButton(
                  label: t.search.selection.selectAll,
                  accent: true,
                  onTap: () => setState(
                    () => _selected.addAll([for (final t in tracks) t.ref]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
