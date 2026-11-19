import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/charts/charts.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/filter_chip_button.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/source_error_card.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/search/search_parts.dart' show searchErrorReason;
import 'package:material_ui/material_ui.dart';

/// 手機與中寬度一次看一張榜時選的音源；記在這次開 App 的記憶體裡（設計稿：
/// chip 記住上次的音源；同搜尋的音源篩選，不存資料庫）。null 是還沒選過，
/// 用第一個音源。
final homeChartSourceProvider = NotifierProvider<HomeChartSource, String?>(
  HomeChartSource.new,
);

class HomeChartSource extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String pluginId) => state = pluginId;
}

/// 手機與桌面先列幾名，展開到 [chartLength]。
const chartPreview = 5;

/// 一個音源的榜在畫面上怎麼畫。
sealed class ChartView {
  const ChartView();

  /// 有榜就畫榜（失敗時加一句它是多久以前的，2026-11-20 擁有者同意）；
  /// 沒有榜時失敗畫說明卡，其他畫骨架。
  factory ChartView.of(SourceChart source) => switch (source) {
    SourceChart(:final chart?) => ChartReady(
      chart.tracks,
      fetchedAt: chart.fetchedAt,
      error: source.error,
    ),
    SourceChart(:final error?) => ChartFailed(error),
    _ => const ChartLoading(),
  };
}

class ChartLoading extends ChartView {
  const ChartLoading();
}

class ChartFailed extends ChartView {
  const ChartFailed(this.error);

  final AppError error;
}

class ChartReady extends ChartView {
  const ChartReady(this.tracks, {required this.fetchedAt, this.error});

  final List<Track> tracks;
  final DateTime fetchedAt;

  /// 這次重抓失敗的原因；有的話畫面寫明榜是多久以前的。
  final AppError? error;
}

/// 「這是 n 分鐘／小時／天前的榜」。不到 1 分鐘算 1 分鐘。
String chartAgeText(Translations t, Duration age) {
  if (age < const Duration(hours: 1)) {
    return t.home.age.minutes(n: math.max(1, age.inMinutes));
  }
  if (age < const Duration(days: 1)) return t.home.age.hours(n: age.inHours);
  return t.home.age.days(n: age.inDays);
}

/// 一個音源抓榜失敗的原因（brief〈錯誤、log 與診斷〉的錯誤分類）。
String chartErrorReason(Translations t, AppError error, String source) =>
    switch (error) {
      RateLimited() || NetworkError() => searchErrorReason(t, error, source),
      _ => t.home.error.failed,
    };

/// 榜名，照 App 的語言（ADR 0039 的 `chartTitle`）。
String chartTitleOf(BuildContext context, PluginManifest manifest) =>
    manifest.chartTitle(context.t.$meta.locale.languageTag) ?? manifest.name;

/// 「近期熱門」區塊的標題。
class ChartsHeading extends StatelessWidget {
  const ChartsHeading({super.key, required this.desk, this.padding});

  final bool desk;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = Text(
      context.t.home.charts,
      style: desk
          ? TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: colors.label,
            )
          : context.fmpText.title3.copyWith(fontWeight: FontWeight.w700),
    );
    return Padding(
      padding:
          padding ??
          (desk
              ? const EdgeInsets.fromLTRB(4, 18, 4, 8)
              : const EdgeInsets.fromLTRB(20, 20, 20, 4)),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: desk ? 28 : 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Semantics(header: true, child: text),
        ),
      ),
    );
  }
}

/// 榜名下面的一行（`.hm-cap`）：平常是「音樂區排行榜 · 前 10 名」；這次抓
/// 失敗、畫的是上次的榜時，改寫原因與多久以前（`.hm-stale`）。
class ChartCaption extends ConsumerWidget {
  const ChartCaption({
    super.key,
    required this.source,
    required this.desk,
    required this.padding,
  });

  final SourceChart source;
  final bool desk;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final style = TextStyle(
      fontSize: desk ? 12 : 13,
      height: desk ? 16 / 12 : 18 / 13,
      letterSpacing: 0,
      color: colors.label2,
    );
    final view = ChartView.of(source);
    final Widget line;
    if (view case ChartReady(:final error?, :final fetchedAt)) {
      final now = ref.watch(chartsClockProvider)();
      final offline = error is NetworkError;
      line = Row(
        children: [
          FmpIcon(
            offline ? FmpIcons.wifi : FmpIcons.warn,
            size: desk ? 14 : 15,
            color: offline ? colors.label2 : colors.warn,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                offline
                    ? t.home.offline
                    : t.home.notUpdated(source: source.manifest.name),
                chartAgeText(t, now.difference(fetchedAt)),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );
    } else {
      final count = view is ChartReady ? view.tracks.length : chartLength;
      line = Text(
        t.home.chartCaption(
          title: chartTitleOf(context, source.manifest),
          count: count,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Padding(
      padding: padding,
      child: Align(alignment: Alignment.centerLeft, child: line),
    );
  }
}

/// 音源 chip 一排（`.hm-chips`、`.hm-mchips`）：一次看一張榜；失敗的音源帶
/// 警示符號。
class ChartChips extends StatelessWidget {
  const ChartChips({
    super.key,
    required this.sources,
    required this.selected,
    required this.desk,
    required this.onSelect,
  });

  final List<SourceChart> sources;
  final String selected;
  final bool desk;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.t.home.chartSources,
      container: true,
      child: Wrap(
        spacing: desk ? 6 : 8,
        runSpacing: desk ? 6 : 0,
        children: [
          for (final s in sources)
            FilterChipButton(
              key: ValueKey(('chart-chip', s.manifest.id)),
              label: s.manifest.name,
              pluginId: s.manifest.id,
              on: s.manifest.id == selected,
              table: desk,
              warn: s.error != null,
              height: desk ? null : 34,
              touchTarget: !desk,
              onTap: () => onSelect(s.manifest.id),
            ),
        ],
      ),
    );
  }
}

/// 第一次打開就沒有網路：每個音源都沒抓到過時合成一張（`.hm-err` 不帶音源）。
class OfflineChartsCard extends StatelessWidget {
  const OfflineChartsCard({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SourceErrorCard(
      pluginId: null,
      title: t.home.error.offlineTitle,
      reason: t.home.error.offlineBody,
      retryLabel: t.search.error.retry,
      onRetry: onRetry,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
    );
  }
}

/// 一個音源沒有榜、抓失敗時的說明卡（觸控版，同搜尋頁的那張）。
class ChartErrorCard extends StatelessWidget {
  const ChartErrorCard({
    super.key,
    required this.manifest,
    required this.error,
    required this.othersShown,
    required this.onRetry,
  });

  final PluginManifest manifest;
  final AppError error;
  final bool othersShown;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SourceErrorCard(
      pluginId: manifest.id,
      title: t.home.error.title(source: manifest.name),
      reason: [
        chartErrorReason(t, error, manifest.name),
        if (othersShown) t.search.error.othersShown,
      ].join(),
      retryLabel: t.search.error.retry,
      onRetry: onRetry,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
    );
  }
}

/// 桌面一欄的說明（`.hm-derr`）：警示符號＋標題、原因、「重試 X」。沒有
/// [manifest] 時是三欄合成的「沒有網路」。
class ChartErrorBlock extends StatelessWidget {
  const ChartErrorBlock({
    super.key,
    required this.manifest,
    required this.error,
    required this.onRetry,
  });

  final PluginManifest? manifest;
  final AppError? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final m = manifest;
    final title = m == null
        ? t.home.error.offlineTitle
        : t.home.error.title(source: m.name);
    final reason = m == null
        ? t.home.error.offlineBody
        : chartErrorReason(t, error!, m.name);
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FmpIcon(
                  m == null ? FmpIcons.wifi : FmpIcons.warn,
                  size: 16,
                  color: m == null ? colors.label2 : colors.warn,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 17 / 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: colors.label,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              style: TextStyle(
                fontSize: 12.5,
                height: 17 / 12.5,
                letterSpacing: 0,
                color: colors.label2,
              ),
            ),
            const SizedBox(height: 8),
            FmpButton(
              label: m == null
                  ? t.search.error.retry
                  : t.search.error.retrySource(source: m.name),
              icon: FmpIcons.refresh,
              size: FmpButtonSize.small,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// 桌面一欄的欄頂（`.hm-ch`）：音源符號＋全名「· 榜名」，底下一條細線。
class ChartColumnHeader extends StatelessWidget {
  const ChartColumnHeader({super.key, required this.manifest});

  final PluginManifest manifest;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Container(
      height: 30,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.sep, width: .5)),
      ),
      child: Row(
        children: [
          SourceMarkIcon(pluginId: manifest.id, size: 14),
          const SizedBox(width: 6),
          Text(
            manifest.name,
            style: TextStyle(
              fontSize: 12.5,
              height: 16 / 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: colors.label,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '· ${chartTitleOf(context, manifest)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0,
                color: colors.label3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [track] 是不是正在播的那首（`isCurrent`），和它有沒有出聲（`playing`）。
({bool isCurrent, bool playing}) playingStateOf(WidgetRef ref, Track track) {
  final state = ref.watch(playbackProvider);
  final isCurrent = state?.track.ref == track.ref;
  return (
    isCurrent: isCurrent,
    playing: isCurrent && (state?.playing ?? false),
  );
}

/// 展開、收起的那幾列：平常高度跟著變（morph，不彈跳）；系統開「減少動態
/// 效果」時只淡入淡出（`docs/design/DESIGN.md`〈動態〉）。
class ExpandingRows extends StatelessWidget {
  const ExpandingRows({super.key, required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shown = expanded ? child : const SizedBox(width: double.infinity);
    if (MediaQuery.disableAnimationsOf(context)) {
      return AnimatedSwitcher(
        duration: FmpMotion.mid,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(key: ValueKey(expanded), child: shown),
      );
    }
    return ClipRect(
      child: AnimatedSize(
        duration: FmpMotion.morph,
        curve: FmpMotion.morphCurve,
        alignment: Alignment.topCenter,
        child: shown,
      ),
    );
  }
}
