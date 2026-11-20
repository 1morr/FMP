import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/charts/charts.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/track_actions.dart';
import 'package:fmp/ui/home/chart_rows.dart';
import 'package:fmp/ui/home/chart_section.dart';
import 'package:fmp/ui/home/continue_listening.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

/// 首頁的四種版面（`docs/design/home.html`）：手機與平板是觸控列表，窄視窗
/// 與桌面是桌面密度；手機、平板、窄視窗一次看一張榜（chip 切換），桌面每個
/// 音源一欄，只有一個音源時照窄視窗把 10 名排成兩欄。
enum HomeLayout {
  phone,
  tablet,
  window,
  wide;

  static HomeLayout of(FormFactor form) => switch (form.widthClass) {
    WidthClass.narrow => phone,
    WidthClass.medium => form.density == Density.touch ? tablet : window,
    WidthClass.wide => wide,
  };
}

/// 首頁：App 打開在這裡（brief〈第一版的功能〉）。區塊照重要性排：近期熱門
/// （每個宣告 `charts` 的音源一張榜，[chartsProvider]）、繼續聽；沒有內容的
/// 區塊連標題一起不出現。最近更新的匯入歌單在 M3，第一次打開的提示也跟著
/// 匯入在 M3 才放（2026-11-20 擁有者同意），這裡都不畫。
///
/// 每次出現時沒有榜或榜超過 1 小時的音源在背景重抓（ARCHITECTURE〈快取〉）；
/// 觸控版下拉強制重抓。點榜上一首是臨時播放：觸控點一下，滑鼠單擊選取、
/// 雙擊或 ↩ 才播（brief〈播放〉）。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// 捲過這個位置，大標題就讓進頂列的小標題。
  static const _titleGoneOffset = 40.0;

  final _scroll = ScrollController();
  final _scrolled = ValueNotifier(false);
  final _focus = FocusNode(debugLabel: 'home charts');

  /// 手機與桌面的榜展開到第 10 名。
  bool _expanded = false;

  /// 滑鼠選取的那首；↩ 播它。
  TrackRef? _selected;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _scrolled.value = _scroll.offset > _titleGoneOffset,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(chartsProvider.notifier).refreshStale());
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrolled.dispose();
    _focus.dispose();
    super.dispose();
  }

  Charts get _charts => ref.read(chartsProvider.notifier);

  void _play(Track track) =>
      unawaited(trackActionRunner(context, ref)(TrackAction.play, [track]));

  void _menu(Track track, Offset at) =>
      unawaited(showTrackActions(context, ref, track, at: at));

  void _select(Track track) {
    setState(() => _selected = track.ref);
    _focus.requestFocus();
  }

  /// 畫面上看得到的榜上曲目，依 ↑／↓ 的順序：桌面一欄接一欄，窄視窗是選中的
  /// 那張榜；排成兩欄的榜照名次（5 的下一個是右欄的 6）。
  List<Track> _visibleTracks() {
    final charts = ref.read(chartsProvider);
    if (charts.sources.isEmpty) return const [];
    final window = HomeLayout.of(FormFactor.of(context)) == HomeLayout.window;
    final sources = window
        ? [_chosenOf(charts, ref.read(homeChartSourceProvider))]
        : charts.sources;
    final shown = sources.length == 1 || _expanded ? chartLength : chartPreview;
    return [for (final s in sources) ...?s.chart?.tracks.take(shown)];
  }

  /// 桌面的鍵盤：↑／↓ 移動選取，↩ 臨時播放選取的那首。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final tracks = _visibleTracks();
    final at = tracks.indexWhere((t) => t.ref == _selected);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter when at >= 0:
        if (event is KeyDownEvent) _play(tracks[at]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown when tracks.isNotEmpty:
        setState(
          () => _selected = tracks[math.min(at + 1, tracks.length - 1)].ref,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when tracks.isNotEmpty:
        setState(() => _selected = tracks[math.max(at - 1, 0)].ref);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayout.of(FormFactor.of(context));
    final insets = ShellInsets.of(context);
    final bar = ShellInsets.topBarOf(context);
    final charts = ref.watch(chartsProvider);
    final showContinue = hasContinueListening(ref.watch(queueProvider));
    final touch = layout == HomeLayout.phone || layout == HomeLayout.tablet;

    final horizontal = switch (layout) {
      HomeLayout.phone => EdgeInsets.zero,
      HomeLayout.tablet => const EdgeInsets.only(left: 4, right: 24),
      // 列與標題各自內縮 4（`.hm-dr`、`.ty-large`），大標題和其他頁一樣離
      // 內容區左緣 [ShellInsets] 的距離。
      _ => EdgeInsets.only(left: insets.left - 4, right: insets.right - 4),
    };
    final titlePadding = switch (layout) {
      HomeLayout.phone ||
      HomeLayout.tablet => const EdgeInsets.symmetric(horizontal: 20),
      _ => const EdgeInsets.symmetric(horizontal: 4),
    };

    final sections = <Widget>[
      Padding(
        padding: titlePadding,
        child: Semantics(
          header: true,
          child: Text(context.t.shell.nav.home, style: context.fmpText.large),
        ),
      ),
      // 插件還在載入（還不知道有哪些音源）時先畫標題與骨架，載完不會把下面
      // 的區塊往下推。
      ?switch (layout) {
        HomeLayout.wide => _wideCharts(charts),
        _ when charts.starting => _startingCharts(desk: !touch),
        _ when charts.sources.isEmpty => null,
        HomeLayout.phone => _oneAtATime(charts, twoColumns: false),
        HomeLayout.tablet => _oneAtATime(charts, twoColumns: true),
        HomeLayout.window => _windowCharts(charts),
      },
      // 桌面寬版的詳情面板開著時已經列了下一首，首頁不重複（設計稿）。
      if (showContinue &&
          !(layout == HomeLayout.wide &&
              ShellInsets.detailPanelOpenOf(context)))
        Padding(
          padding: EdgeInsets.only(top: touch ? 0 : 8),
          child: ContinueListening(desk: !touch),
        ),
    ];

    Widget scroll = ListView(
      controller: _scroll,
      // 內容不滿一頁時也拉得動，下拉刷新才用得了。
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
      children: [
        for (final section in sections)
          Padding(padding: horizontal, child: section),
      ],
    );
    if (touch) {
      scroll = RefreshIndicator(
        edgeOffset: insets.top - 24,
        color: context.fmpColors.label2,
        backgroundColor: context.fmpColors.cell,
        onRefresh: _charts.refresh,
        child: scroll,
      );
    } else {
      scroll = Focus(focusNode: _focus, onKeyEvent: _onKey, child: scroll);
    }

    return Stack(
      children: [
        Positioned.fill(child: scroll),
        // `.edge-top`：捲動後頂列底下淡出內容，小標題不壓在列上。照「玻璃效果
        // 關閉」那版的實心漸層畫，不做模糊。
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: bar.top + bar.height + 24,
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _scrolled,
              builder: (context, scrolled, _) => AnimatedOpacity(
                opacity: scrolled ? 1 : 0,
                duration: FmpMotion.mid,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        context.fmpColors.bg,
                        context.fmpColors.bg,
                        context.fmpColors.bg.withValues(alpha: 0),
                      ],
                      stops: const [0, .7, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: bar.top,
          left: bar.left,
          right: bar.right,
          height: bar.height,
          child: _topBar(context, layout),
        ),
      ],
    );
  }

  /// 頂列（`.ptop`、`.wtop`）只有大標題捲出去後淡入的小標題；首頁沒有需要
  /// 常駐的動作（設計稿：頂列不放按鈕）。
  Widget _topBar(BuildContext context, HomeLayout layout) {
    final phone = layout == HomeLayout.phone;
    return IgnorePointer(
      child: ValueListenableBuilder<bool>(
        valueListenable: _scrolled,
        builder: (context, scrolled, _) => ExcludeSemantics(
          excluding: !scrolled,
          child: AnimatedOpacity(
            opacity: scrolled ? 1 : 0,
            duration: FmpMotion.mid,
            // 手機的小標題置中（`.ptitle`），桌面靠左（`.wt`）。
            child: Align(
              alignment: phone ? Alignment.center : Alignment.centerLeft,
              child: Text(
                context.t.shell.nav.home,
                style: TextStyle(
                  fontSize: phone ? 17 : 15,
                  fontWeight: phone ? FontWeight.w600 : FontWeight.w700,
                  letterSpacing: 0,
                  color: context.fmpColors.label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _startingCharts({required bool desk}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChartsHeading(desk: desk),
      for (var i = 1; i <= chartPreview; i++)
        ChartSkeletonRow(rank: i, desk: desk),
    ],
  );

  /// 寬版：插件還在載入時照一個音源的版面畫骨架（兩欄 10 列，M1 只有 B 站，
  /// 啟動時不會先一欄再兩欄）；載完換成真的版面，內容替換照 `DESIGN.md`
  /// 〈狀態變化對照〉交叉淡出（減少動態效果時照樣）。
  Widget _wideCharts(ChartsState charts) {
    final Widget content;
    if (charts.starting) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ChartsHeading(desk: true),
          const ChartColumnHeader.placeholder(),
          _twoColumnSkeleton(),
        ],
      );
    } else if (charts.sources.isEmpty) {
      content = const SizedBox(width: double.infinity);
    } else {
      content = _columns(charts);
    }
    return AnimatedSwitcher(
      duration: FmpMotion.mid,
      switchInCurve: FmpMotion.outCurve,
      switchOutCurve: FmpMotion.outCurve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey(('wide charts', charts.starting)),
        child: content,
      ),
    );
  }

  /// 桌面密度的「從沒載入過、又沒有網路」：標題下一段合成的說明。
  Widget _offlineBlock(Widget heading) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading,
      ChartErrorBlock(
        manifest: null,
        error: null,
        onRetry: () => unawaited(_charts.refresh()),
      ),
    ],
  );

  /// 桌面密度一個音源沒有榜、抓失敗時的說明，「重試」只重抓它。
  Widget _failedBlock(SourceChart source, AppError error) => ChartErrorBlock(
    manifest: source.manifest,
    error: error,
    onRetry: () => unawaited(_charts.refresh(only: source.manifest.id)),
  );

  /// 選中的音源：選過、而且還在的那個；不然是第一個。
  SourceChart _chosen(ChartsState charts) =>
      _chosenOf(charts, ref.watch(homeChartSourceProvider));

  static SourceChart _chosenOf(ChartsState charts, String? id) =>
      charts.sources.firstWhere(
        (s) => s.manifest.id == id,
        orElse: () => charts.sources.first,
      );

  void _choose(String id) =>
      ref.read(homeChartSourceProvider.notifier).select(id);

  /// 手機與平板：chip 一次看一張榜。手機先 5 名、就地展開到 10 名；平板 10
  /// 名直接排成兩欄、不放時長（設計稿〈待確認〉34）。
  Widget _oneAtATime(ChartsState charts, {required bool twoColumns}) {
    final source = _chosen(charts);
    final id = source.manifest.id;
    final children = <Widget>[const ChartsHeading(desk: false)];
    if (charts.neverLoadedOffline) {
      children.add(OfflineChartsCard(onRetry: _charts.refresh));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    children.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ChartChips(
          sources: charts.sources,
          selected: id,
          desk: false,
          onSelect: _choose,
        ),
      ),
    );
    final view = ChartView.of(source);
    final caption = ChartCaption(
      source: source,
      desk: false,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
    );
    final Widget body;
    switch (view) {
      case ChartFailed(:final error):
        body = ChartErrorCard(
          manifest: source.manifest,
          error: error,
          othersShown: charts.sources.length > 1,
          onRetry: () => unawaited(_charts.refresh(only: id)),
        );
      case ChartLoading():
        final skeletons = [
          for (var i = 1; i <= chartPreview; i++)
            ChartSkeletonRow(rank: i, desk: false),
        ];
        body = Column(children: [caption, ...skeletons]);
      case ChartReady(:final tracks):
        Widget row(int i) {
          final (:isCurrent, :playing) = playingStateOf(ref, tracks[i]);
          return HomeTouchRow(
            key: ValueKey(('chart', i, tracks[i].ref)),
            track: tracks[i],
            rank: i + 1,
            isCurrent: isCurrent,
            playing: playing,
            separator: i % chartPreview != 0,
            showDuration: !twoColumns,
            onTap: () => _play(tracks[i]),
            onMore: (at) => _menu(tracks[i], at),
          );
        }

        final first = [
          for (var i = 0; i < tracks.length && i < chartPreview; i++) row(i),
        ];
        final rest = [
          for (var i = chartPreview; i < tracks.length; i++) row(i),
        ];
        if (twoColumns) {
          body = Column(
            children: [
              caption,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: first)),
                  Expanded(child: Column(children: rest)),
                ],
              ),
            ],
          );
        } else {
          body = Column(
            children: [
              caption,
              ...first,
              if (rest.isNotEmpty) ...[
                ExpandingRows(
                  expanded: _expanded,
                  child: Column(children: rest),
                ),
                ChartMoreRow(
                  expanded: _expanded,
                  count: tracks.length,
                  onTap: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ],
          );
        }
    }
    children.add(
      AnimatedSwitcher(
        duration: FmpMotion.fast,
        child: KeyedSubtree(key: ValueKey(id), child: body),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// 窄視窗：桌面密度的 chip 一次看一張榜，10 名排成兩欄（左 1–5、右 6–10）。
  Widget _windowCharts(ChartsState charts) {
    final source = _chosen(charts);
    final id = source.manifest.id;
    const heading = ChartsHeading(
      desk: true,
      padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
    );
    if (charts.neverLoadedOffline) return _offlineBlock(heading);
    final view = ChartView.of(source);
    final body = _twoColumnChart(source, view);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: ChartChips(
            sources: charts.sources,
            selected: id,
            desk: true,
            onSelect: _choose,
          ),
        ),
        if (view is! ChartFailed)
          ChartCaption(
            source: source,
            desk: true,
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          ),
        AnimatedSwitcher(
          duration: FmpMotion.fast,
          child: KeyedSubtree(key: ValueKey(id), child: body),
        ),
      ],
    );
  }

  /// 桌面密度一張榜的 10 名排成兩欄（窄視窗、只有一個音源的桌面）；沒有榜時
  /// 失敗是說明（只重試它），載入中是兩欄骨架。欄夠寬時列尾有時長。
  Widget _twoColumnChart(SourceChart source, ChartView view) => switch (view) {
    ChartFailed(:final error) => _failedBlock(source, error),
    ChartLoading() => _twoColumnSkeleton(),
    ChartReady(:final tracks) => LayoutBuilder(
      builder: (context, constraints) {
        final column = (constraints.maxWidth - 12) / 2;
        return _twoColumns([
          for (final (i, track) in tracks.indexed)
            _deskRow(track, i, column >= ChartDeskRow.durationFrom),
        ]);
      },
    ),
  };

  Widget _twoColumnSkeleton() => _twoColumns([
    for (var i = 1; i <= chartLength; i++)
      ChartSkeletonRow(rank: i, desk: true),
  ]);

  /// 左 1–5、右 6–10，欄間 12。
  Widget _twoColumns(List<Widget> rows) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Column(children: rows.take(chartPreview).toList())),
      const SizedBox(width: 12),
      Expanded(child: Column(children: rows.skip(chartPreview).toList())),
    ],
  );

  Widget _deskRow(Track track, int i, bool showDuration) {
    final (:isCurrent, :playing) = playingStateOf(ref, track);
    return ChartDeskRow(
      key: ValueKey(('chart', i, track.ref)),
      track: track,
      rank: i + 1,
      isCurrent: isCurrent,
      playing: playing,
      selected: track.ref == _selected,
      showDuration: showDuration,
      onSelect: () => _select(track),
      onPlay: () => _play(track),
      onMenu: (at) => _menu(track, at),
    );
  }

  /// 桌面：兩個以上的音源時每個音源一欄，每欄先 5 名，一顆「顯示第 6–10 名」
  /// 所有欄一起展開；只有一個音源時 10 名排成兩欄、不用展開（2026-11-20
  /// 擁有者定，票 18b）。欄夠寬時列尾有時長。
  Widget _columns(ChartsState charts) {
    const heading = ChartsHeading(desk: true);
    if (charts.neverLoadedOffline) return _offlineBlock(heading);
    if (charts.sources case [final source]) {
      final view = ChartView.of(source);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          ChartColumnHeader(manifest: source.manifest),
          if (view is ChartReady && view.error != null)
            ChartCaption(
              source: source,
              desk: true,
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
            ),
          _twoColumnChart(source, view),
        ],
      );
    }
    final canExpand = charts.sources.any(
      (s) => (s.chart?.tracks.length ?? 0) > chartPreview,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        LayoutBuilder(
          builder: (context, constraints) {
            final count = charts.sources.length;
            final column = (constraints.maxWidth - 12 * (count - 1)) / count;
            final showDuration = column >= ChartDeskRow.durationFrom;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, source) in charts.sources.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _column(source, showDuration)),
                ],
              ],
            );
          },
        ),
        if (canExpand)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: FmpButton(
                label: _expanded
                    ? context.t.home.showLess
                    : context.t.home.showMore(
                        from: chartPreview + 1,
                        to: charts.sources
                            .map((s) => s.chart?.tracks.length ?? 0)
                            .reduce(math.max),
                      ),
                trailingIcon: _expanded ? FmpIcons.chevU : FmpIcons.chevD,
                size: FmpButtonSize.small,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ),
          ),
      ],
    );
  }

  Widget _column(SourceChart source, bool showDuration) {
    final view = ChartView.of(source);
    final Widget body;
    switch (view) {
      case ChartFailed(:final error):
        body = _failedBlock(source, error);
      case ChartLoading():
        body = Column(
          children: [
            for (var i = 1; i <= chartPreview; i++)
              ChartSkeletonRow(rank: i, desk: true),
          ],
        );
      case ChartReady(:final tracks, :final error):
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              ChartCaption(
                source: source,
                desk: true,
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
              ),
            for (final (i, track) in tracks.indexed.take(chartPreview))
              _deskRow(track, i, showDuration),
            ExpandingRows(
              expanded: _expanded,
              child: Column(
                children: [
                  for (final (i, track) in tracks.indexed.skip(chartPreview))
                    _deskRow(track, i, showDuration),
                ],
              ),
            ),
          ],
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartColumnHeader(manifest: source.manifest),
        body,
      ],
    );
  }
}
