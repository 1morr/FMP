import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/charts/chart_entries.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/ui/charts/chart_parts.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_selection.dart';

/// 在 [context] 所在的 Navigator 開探索頁、選 [chart] 的分頁：外殼裡是首頁的巢狀導覽（首頁
/// 排行的「查看全部」，ADR 0033 §決定 5），導覽與播放列留著。
Future<void> openExplore(BuildContext context, ChartKey chart) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 自己的 Material：理由見 `AppShell` 的根頁。
        builder: (_) => Material(
          type: MaterialType.transparency,
          child: ExplorePage(initial: chart),
        ),
      ),
    );

/// 探索頁多選的鍵：哪個榜單的第幾首（同一首可能在榜單上出現兩次，位置才分得開）。
typedef ExploreRowKey = ({ChartKey chart, int index});

/// 探索頁（M4 design §9.3、§10.7，ADR 0033 §決定 7）：每個啟用的榜單一個分頁（順序同首頁），
/// 分頁裡是完整的清單；快取、失敗、離線的狀態同首頁（[ChartContent]）。點一首臨時播放，選單
/// 同首頁的排行；長按或選單的「選取」進入多選（加入佇列、加入歌單…、加入遠端歌單…）。
///
/// 標題列的「刷新」立刻跑目前分頁那個插件的排行工作（`ChartJobs.runNow`）：離線不發、以
/// 提示說明；全部榜單都失敗是錯誤提示；單一榜單失敗只看分頁的「更新失敗」。
///
/// 榜單的增減（設定頁停用、插件停用）時分頁跟著變，留在原本的榜單上；那個榜單不見了就回到
/// 第一個。
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key, required this.initial});

  /// 一開始選的榜單（「查看全部」的那一個）。
  final ChartKey initial;

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage>
    with TickerProviderStateMixin {
  final _selection = TrackSelection<ExploreRowKey>();
  TabController? _tabs;
  List<ChartKey> _tabKeys = const [];
  late ChartKey _current = widget.initial;

  /// 正在手動刷新的插件（工具列「刷新」）；`null`＝沒有。
  String? _refreshing;

  @override
  void dispose() {
    _tabs?.dispose();
    _selection.dispose();
    super.dispose();
  }

  /// 分頁換成 [keys]（依順序）：留在目前的榜單上，它不在了就是第一個。
  void _syncTabs(List<ChartKey> keys) {
    if (listEquals(keys, _tabKeys)) return;
    final old = _tabs;
    _tabKeys = keys;
    if (keys.isEmpty) {
      _tabs = null;
    } else {
      final found = keys.indexOf(_current);
      final index = found < 0 ? 0 : found;
      _current = keys[index];
      final controller = TabController(
        length: keys.length,
        vsync: this,
        initialIndex: index,
      );
      controller.addListener(() {
        if (!identical(_tabs, controller)) return;
        final key = _tabKeys[controller.index];
        if (key != _current) setState(() => _current = key);
      });
      _tabs = controller;
    }
    // 舊的控制器還被這一幀的 TabBar 用著：畫完再丟。
    if (old != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  /// 已選的列的曲目，依畫面順序。
  List<TrackInfo> _tracksOf(List<ExploreRowKey> keys) => [
    for (final key in keys)
      if (ref.read(chartContentProvider(key.chart)).value?.tracks
          case final tracks? when key.index < tracks.length)
        tracks[key.index],
  ];

  Future<void> _refresh(String pluginId) async {
    setState(() => _refreshing = pluginId);
    // 刷新期間頁面可能被關掉：之後要讀的先拿好。
    final container = ProviderScope.containerOf(context, listen: false);
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).charts;
    try {
      switch (await ref.read(chartJobsProvider.notifier).runNow(pluginId)) {
        case RunNowResult.completed:
          toaster.success(t.refreshed);
        case RunNowResult.offline:
          toaster.warning(t.refreshOffline);
        // 自動的那一次正在跑（結果照樣寫進快取），或工作剛被移除（榜單停用）：沒有可說的。
        case RunNowResult.alreadyRunning || RunNowResult.unknown:
          break;
      }
    } on Object catch (error, stackTrace) {
      // 全部榜單都失敗：失敗而網路不是 online 時寫離線的字樣（同歌單的手動刷新）。
      if (container.read(networkStatusProvider) != NetworkStatus.online) {
        toaster.warning(t.refreshOffline);
      } else {
        toaster.error(
          AppError.wrap(error, stackTrace, pluginId: pluginId),
          operation: 'Failed to refresh the charts',
          tag: chartsLogTag,
          sentence: (reason) => t.refreshFailed(reason: reason),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translations = ref.watch(translationsProvider);
    final t = translations.charts;
    final charts = ref.watch(enabledChartsProvider);
    if (charts != null) _syncTabs([for (final chart in charts) chart.key]);
    final tabs = _tabs;
    final current = charts == null || tabs == null
        ? null
        : charts.firstWhere((chart) => chart.key == _current);
    // 榜單的內容換了（刷新寫入）：位置當鍵，已選的位置不再是同一首，離開選取模式。
    if (current != null) {
      ref.listen(chartContentProvider(current.key), (previous, next) {
        final before = previous?.value?.fetchedAt;
        if (before != null && before != next.value?.fetchedAt) {
          _selection.exit();
        }
      });
    }
    final tracks = current == null
        ? const <TrackInfo>[]
        : ref.watch(chartContentProvider(current.key)).value?.tracks ??
              const <TrackInfo>[];
    return TrackSelectionScope<ExploreRowKey>(
      selection: _selection,
      keys: [
        if (current != null)
          for (var index = 0; index < tracks.length; index++)
            (chart: current.key, index: index),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrackSelectionBar<ExploreRowKey>(
            tracks: (keys) async => _tracksOf(keys),
            pluginIds: (keys) => {
              for (final track in _tracksOf(keys)) track.sourceTypeId,
            },
            child: PageAppBar(
              title: t.explore,
              actions: [
                IconButton(
                  tooltip: t.refresh,
                  icon: const Icon(Icons.refresh),
                  onPressed: current == null || _refreshing != null
                      ? null
                      : () => unawaited(_refresh(current.pluginId)),
                ),
              ],
            ),
          ),
          if (charts != null && charts.isEmpty)
            Expanded(
              // 有榜單而全部停用：到設定頁打開；一個榜單都沒有（沒有提供排行的插件）：說明要裝插件。
              child: (ref.watch(chartEntriesProvider)?.isEmpty ?? true)
                  ? EmptyState(
                      icon: Icons.leaderboard_outlined,
                      title: t.noSource,
                      body: t.noSourceHint,
                    )
                  : EmptyState(
                      icon: Icons.leaderboard_outlined,
                      title: t.noCharts,
                      body: t.noChartsHint,
                    ),
            ),
          if (charts != null && tabs != null) ...[
            TabBar(
              controller: tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final chart in charts)
                  Tab(
                    text: t.tab(title: chart.title, source: chart.sourceName),
                  ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: tabs,
                children: [
                  for (final chart in charts)
                    _ChartTab(
                      key: ValueKey(chart.key),
                      chart: chart,
                      refreshing: _refreshing == chart.pluginId,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一個分頁：狀態行（音源、更新於、更新失敗）與完整的清單。
class _ChartTab extends ConsumerWidget {
  const _ChartTab({super.key, required this.chart, required this.refreshing});

  final ChartEntry chart;

  /// 這個榜單的插件正在手動刷新。
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.x4,
            spacing.x3,
            spacing.x4,
            spacing.x1,
          ),
          child: ChartStatusLine(chart: chart),
        ),
        Expanded(
          child: ChartContent(
            chart: chart.key,
            failedHint: translations.charts.exploreFailedHint,
            offHint: translations.charts.exploreOffHint,
            refreshing: refreshing,
            builder: (context, content) {
              if (content.tracks.isEmpty) return const ChartEmpty();
              return ListView.builder(
                padding: EdgeInsets.only(bottom: spacing.x4),
                itemCount: content.tracks.length,
                itemBuilder: (context, index) {
                  final track = content.tracks[index];
                  return SelectableTrackRow<ExploreRowKey>(
                    key: ValueKey((index, track.key)),
                    selectionKey: (chart: chart.key, index: index),
                    moreTooltip: translations.home.more,
                    menuChildren: chartTrackMenu(context, ref, track),
                    builder: (context, row) =>
                        ChartTrackTile(rank: index + 1, track: track, row: row),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
