import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/charts/chart_entries.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/charts/chart_parts.dart';
import 'package:fmp/ui/charts/explore_page.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';
import 'package:fmp/ui/tracks/track_selection.dart';

/// 首頁每個榜單顯示的曲目數（M4 design §9.2）。
const homeChartTrackCount = 5;

/// 首頁的「排行」區塊（M4 design §9.2、§10.2，ADR 0033 §決定 6）：每個啟用的榜單（[charts]，
/// 依使用者的順序）一個子區塊——榜單名稱、音源與「更新於」（失敗時加「更新失敗」）、前 5 首
/// （點一下臨時播放，選單同「最近播放」）、「查看全部」（在首頁的巢狀導覽裡開探索頁的那個分頁）。
///
/// 版面照舊版首頁的排行：內容區放得下幾欄（[AppLayout.chartColumnMinWidth]）就並排幾欄，
/// 放不下就一個榜單一列往下排。沒有快取時是載入中或離線空狀態（[ChartContent]）。
class HomeCharts extends ConsumerWidget {
  const HomeCharts({super.key, required this.charts});

  /// 啟用的榜單，不是空的。
  final List<ChartEntry> charts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).charts;
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, 0),
          child: Semantics(
            header: true,
            child: Text(t.title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final fit = (constraints.maxWidth / AppLayout.chartColumnMinWidth)
                .floor();
            final columns = fit < 1
                ? 1
                : fit > charts.length
                ? charts.length
                : fit;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var start = 0; start < charts.length; start += columns)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = start; i < start + columns; i++)
                        Expanded(
                          child: i < charts.length
                              ? _ChartPreview(
                                  key: ValueKey(charts[i].key),
                                  chart: charts[i],
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 一個榜單的子區塊：標題列（名稱、狀態行、「查看全部」）與前 [homeChartTrackCount] 首。
class _ChartPreview extends ConsumerWidget {
  const _ChartPreview({super.key, required this.chart});

  final ChartEntry chart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.charts;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x3, spacing.x2, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        chart.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    ChartStatusLine(chart: chart),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => unawaited(openExplore(context, chart.key)),
                child: Text(translations.home.viewAll),
              ),
            ],
          ),
        ),
        ChartContent(
          chart: chart.key,
          failedHint: t.failedHint,
          builder: (context, content) {
            if (content.tracks.isEmpty) return const ChartEmpty();
            return Column(
              children: [
                for (final (index, track)
                    in content.tracks.take(homeChartTrackCount).indexed)
                  _HomeChartRow(
                    key: ValueKey((index, track.key)),
                    rank: index + 1,
                    track: track,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 首頁的一列排行曲目：選單在右鍵、長按與「⋯」（[TrackRowMenu]）；首頁沒有多選。
class _HomeChartRow extends ConsumerWidget {
  const _HomeChartRow({super.key, required this.rank, required this.track});

  final int rank;
  final TrackInfo track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackRowMenu(
      moreTooltip: ref.watch(translationsProvider).home.more,
      menuChildren: chartTrackMenu(context, ref, track),
      builder: (context, more, openMenu) => ChartTrackTile(
        rank: rank,
        track: track,
        row: TrackRowSlots(
          selecting: false,
          selected: false,
          trailing: more,
          onTap: null,
          onLongPress: openMenu,
        ),
      ),
    );
  }
}
