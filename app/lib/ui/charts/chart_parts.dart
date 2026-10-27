import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/charts/chart_entries.dart';
import 'package:fmp/charts/chart_jobs.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/settings/network_settings.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/empty_state/loading_state.dart';
import 'package:fmp/ui/format/date_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/library/add_to_remote.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/track_markers.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_selection.dart';

// 首頁排行區塊與探索頁共用的部分（M4 design §9.1–§9.3、ADR 0016 §決定 7）：榜單的狀態行、
// 「有快取／載入中／離線／更新失敗」四種內容、一列排行曲目與它的選單。

/// 榜單 [chart] 那一行說明：「音源 · 更新於 時間」，最近一次更新失敗（只在記憶體，
/// `chartFailuresProvider`）時接著「更新失敗」。還沒有快取時只有音源。
class ChartStatusLine extends ConsumerWidget {
  const ChartStatusLine({super.key, required this.chart});

  final ChartEntry chart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).charts;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final content = ref.watch(chartContentProvider(chart.key)).value;
    final failed = ref.watch(
      chartFailuresProvider.select((failures) => failures.contains(chart.key)),
    );
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final text = content == null
        ? chart.sourceName
        : t.source(
            source: chart.sourceName,
            status: t.updatedAt(
              time: formatDateTime(
                ref.watch(uiLocaleProvider),
                content.fetchedAt,
              ),
            ),
          );
    // 放不下時「更新失敗」換到下一行，不截掉。
    return Wrap(
      spacing: spacing.x2,
      children: [
        Text(text, style: style),
        if (failed)
          Text(
            t.updateFailed,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// 一個榜單的內容區（ADR 0016 §決定 7）：快取有內容就交給 [builder]（含空的榜單）；沒有快取
/// 時，不在線是離線空狀態，在線而最近一次更新失敗是失敗說明（[failedHint]），排行刷新間隔關閉
/// 是「自動更新已關閉」與怎麼手動載入（[offHint]），其餘是載入中：排行工作登記時發現沒有快取就
/// 立即到期（`ChartJobs`），寫入快取後 `chartContentProvider` 跟著重讀。快取讀不出來（快取庫開
/// 不起來）在線時也是失敗說明：工作寫不進去，不會有內容，轉圈只會一直轉下去。
class ChartContent extends ConsumerWidget {
  const ChartContent({
    super.key,
    required this.chart,
    required this.failedHint,
    required this.offHint,
    required this.builder,
    this.refreshing = false,
    this.compact = false,
  });

  final ChartKey chart;

  /// 首頁的區塊：失敗與「自動更新已關閉」用緊湊橫條，不佔整頁的置中版面。
  final bool compact;
  final String failedHint;

  /// 刷新間隔關閉時怎麼手動載入。
  final String offHint;

  /// 這個榜單的插件正在手動刷新（探索頁的「刷新」）：間隔關閉時也轉圈，不顯示「自動更新已關閉」。
  final bool refreshing;
  final Widget Function(BuildContext context, ChartCacheEntry content) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cached = ref.watch(chartContentProvider(chart));
    if (cached.value case final content?) return builder(context, content);
    final t = ref.watch(translationsProvider).charts;
    final status = ref.watch(networkStatusProvider);
    if (status != NetworkStatus.online) return OfflineMessage(status: status);
    final failed =
        cached.hasError ||
        ref.watch(
          chartFailuresProvider.select((failures) => failures.contains(chart)),
        );
    if (failed) {
      return EmptyState(
        icon: Icons.error_outline,
        error: true,
        compact: compact,
        title: t.failed,
        body: failedHint,
      );
    }
    // 間隔關閉時工作不會自己跑（尊重「關閉」）：說明，不轉圈。設定還沒讀出來時照載入中。
    final off = ref.watch(
      networkProvider.select(
        (network) =>
            network.hasValue && network.value!.chartRefreshInterval == null,
      ),
    );
    if (off && !refreshing) {
      return EmptyState(
        icon: Icons.update_disabled,
        compact: compact,
        title: t.off,
        body: offHint,
      );
    }
    return LoadingState(message: t.loading);
  }
}

/// 空的榜單（插件給了 0 首）。
class ChartEmpty extends ConsumerWidget {
  const ChartEmpty({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => EmptyState(
    icon: Icons.music_off_outlined,
    title: ref.watch(translationsProvider).charts.empty,
  );
}

/// 一首排行曲目的選單項目（同歷史頁與首頁「最近播放」）：播放、下一首播放、加入佇列、
/// 開始 Mix、加入歌單…、加入遠端歌單…。
List<Widget> chartTrackMenu(
  BuildContext context,
  WidgetRef ref,
  TrackInfo track,
) {
  final t = ref.watch(translationsProvider).home;
  final inMix = ref.watch(inMixProvider);
  final canMix = ref.watch(canStartMixProvider(track.sourceTypeId));

  void playNext() {
    if (ref.read(playbackControllerProvider).playNext([track])) {
      ref.read(toasterProvider).success(t.addedToNext);
    }
  }

  void addToQueue() {
    if (ref.read(playbackControllerProvider).addToQueue([track])) {
      ref.read(toasterProvider).success(t.addedToQueue);
    }
  }

  return [
    MenuItemButton(
      leadingIcon: const Icon(Icons.play_arrow),
      onPressed: () => playChartTrack(ref, track),
      child: Text(t.play),
    ),
    MenuItemButton(
      leadingIcon: const Icon(Icons.queue_play_next),
      onPressed: inMix ? null : playNext,
      child: Text(inMix ? t.playNextInMix : t.playNext),
    ),
    MenuItemButton(
      leadingIcon: const Icon(Icons.add_to_queue),
      onPressed: inMix ? null : addToQueue,
      child: Text(inMix ? t.addToQueueInMix : t.addToQueue),
    ),
    if (canMix)
      MenuItemButton(
        leadingIcon: const Icon(Icons.auto_awesome),
        onPressed: () => unawaited(startMixFrom(ref, track)),
        child: Text(t.startMix),
      ),
    AddToPlaylistItem(
      onPressed: () => unawaited(showAddToPlaylist(context, [track])),
    ),
    AddToRemoteItem(
      pluginIds: {track.sourceTypeId},
      onPressed: () => unawaited(showAddToRemote(context, [track])),
    ),
  ];
}

/// 點一首排行曲目：臨時播放（同搜尋結果）。
void playChartTrack(WidgetRef ref, TrackInfo track) =>
    unawaited(ref.read(playbackControllerProvider).playTemporary(track));

/// 一列排行曲目：名次、封面、曲名、作者（音源不可用時是原因）、列尾（「⋯」或多選的勾選框）。
/// 點一下臨時播放。
class ChartTrackTile extends ConsumerWidget {
  const ChartTrackTile({
    super.key,
    required this.rank,
    required this.track,
    required this.row,
  });

  /// 第幾名（從 1 起）。
  final int rank;
  final TrackInfo track;
  final TrackRowSlots row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final uploader =
        ref.watch(sourceUnavailableProvider(track.sourceTypeId)) ??
        track.uploader;
    final playing = watchIsPlaying(ref, track);
    return ListTile(
      selected: row.selected,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppLayout.chartRankWidth,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(width: spacing.x2),
          TrackCover(track: track, playing: playing),
        ],
      ),
      title: Text(
        track.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: playingTitleStyle(context, playing: playing),
      ),
      subtitle: uploader == null
          ? null
          : Text(uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: row.trailing,
      onTap: row.onTap ?? () => playChartTrack(ref, track),
      onLongPress: row.onLongPress,
    );
  }
}
