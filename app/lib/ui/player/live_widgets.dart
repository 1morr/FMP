import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/format/count_text.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

// 收聽直播時播放列、播放頁與右側面板共用的元件（ADR 0031 §決定 7，M3 design §9.4）。
// 直播時 `QueueState.current` 是 `null`：三處都讀 [nowPlayingLiveProvider] 畫直播版，
// 沒有進度條，也沒有上一首、下一首。

/// 有東西在播（佇列或臨時播放的曲目，或直播間）：播放列與播放頁依它出現或關閉。
bool hasNowPlaying(QueueState? queue) =>
    queue != null && (queue.current != null || queue.live != null);

/// 收聽中的直播間；不在收聽直播時為 `null`。`playbackLiveProvider` 還沒跟上佇列時（換台的
/// 那一刻佇列先發出）先用佇列裡的目標，不讓畫面閃回上一個直播間。
final nowPlayingLiveProvider = Provider<LiveInfo?>((ref) {
  final target = ref.watch(
    playbackQueueProvider.select((queue) => queue.value?.live?.target),
  );
  if (target == null) return null;
  final info = ref.watch(playbackLiveProvider).value;
  return info != null && info.target == target ? info : LiveInfo.of(target);
});

/// 直播的狀態標示（寫在主播之前，同音樂的「重試中」）：重新連線中、等待網路連線、已停止
/// （暫停就是停止串流）、無法播放。直播已結束、查詢失敗由 [LiveBadge] 標示，這裡是 `null`。
String? liveStatusLabel(
  Translations t,
  PlaybackState state,
  LiveInfo info, {
  String? sourceName,
}) {
  if (info.phase != LivePhase.listening) return null;
  return switch (state) {
    Retrying(waitingForNetwork: true) => t.player.waitingForNetwork,
    Retrying() => t.player.liveReconnecting,
    Paused() => t.player.liveStopped,
    Failed(:final error) => t.player.liveCannotPlay(
      reason: errorMessage(t, error, sourceName: sourceName),
    ),
    Idle() || Loading() || Playing() || Buffering() => null,
  };
}

/// 「直播中」標記；直播已結束、查詢失敗時換成那兩種（ADR 0031 §決定 7、D10：查詢失敗不是
/// 已結束）。照 YouTube、Twitch、B 站的紅色「直播」標記；三種顏色與圖示都不同。
class LiveBadge extends ConsumerWidget {
  const LiveBadge({super.key, required this.phase});

  final LivePhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    final tokens = AppTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon, text) = switch (phase) {
      LivePhase.listening => (
        scheme.error,
        scheme.onError,
        Icons.sensors,
        t.liveBadge,
      ),
      LivePhase.ended => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.stop_circle_outlined,
        t.liveEnded,
      ),
      LivePhase.statusFailed => (
        tokens.warning.container,
        tokens.warning.onContainer,
        Icons.error_outline,
        t.liveStatusFailed,
      ),
    };
    // 階段改變時讀出來，不搶焦點（同播放列的狀態標示）。
    return Semantics(
      liveRegion: true,
      child: StatusTag(
        icon: icon,
        text: text,
        background: background,
        foreground: foreground,
      ),
    );
  }
}

/// 帶圖示的小標記（直播的階段、電台與直播間的狀態）：只是文字，不能點。形狀同插件頁的
/// `PluginTag`；顏色由呼叫端給成對的背景與前景，[border] 給的話背景透明、只畫邊框。
class StatusTag extends StatelessWidget {
  const StatusTag({
    super.key,
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    this.border,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final style = Theme.of(context).textTheme.labelMedium;
    final border = this.border;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: border == null ? background : null,
        border: border == null ? null : Border.all(color: border),
        borderRadius: BorderRadius.circular(tokens.radius.small),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.x2,
          vertical: tokens.spacing.x1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: style?.fontSize, color: foreground),
            SizedBox(width: tokens.spacing.x1),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 標記、已收聽時間（出聲時，取播放進度的位置；暫停後再播、重連都從 0 起算）、人數
/// （`live-info` 每分鐘更新）。取代音樂的進度條。
class LiveFacts extends ConsumerWidget {
  const LiveFacts({
    super.key,
    required this.info,
    this.alignment = WrapAlignment.start,
  });

  final LiveInfo info;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final state = ref.watch(playbackStateProvider).value ?? const Idle();
    final audible =
        info.phase == LivePhase.listening &&
        (state is Playing || state is Buffering);
    final position = audible
        ? ref.watch(playbackProgressProvider).value?.position
        : null;
    final online = info.online;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: spacing.x3,
      runSpacing: spacing.x1,
      children: [
        LiveBadge(phase: info.phase),
        if (position != null)
          Text(t.liveListened(time: formatDuration(position)), style: style),
        if (online != null)
          Text(
            t.liveOnline(
              count: formatCount(ref.watch(uiLocaleProvider), online),
            ),
            style: style,
          ),
      ],
    );
  }
}

/// 停止收聽、回到佇列（`stopLive`）。直播沒有上一首、下一首，它佔那個位置。
class StopLiveButton extends ConsumerWidget {
  const StopLiveButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: ref.watch(translationsProvider).player.stopLive,
    icon: const Icon(Icons.stop),
    onPressed: () => unawaited(ref.read(playbackControllerProvider).stopLive()),
  );
}

/// 直播間的詳細（播放頁「詳細」分頁與右側面板，同曲目的 [TrackDetails]）：封面、直播標題、
/// 狀態、標記與人數、主播、音源；[showStop] 時多一個「停止收聽」鈕（面板沒有別的控制）。
class LiveDetails extends ConsumerWidget {
  const LiveDetails({
    super.key,
    required this.info,
    this.showStop = false,
    this.scrollController,
  });

  final LiveInfo info;
  final bool showStop;

  /// 放在底部面板時，面板給的捲動控制器；其他地方沒有。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.player;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final pluginId = info.target.pluginId;
    final source = ref.watch(pluginNameProvider(pluginId)) ?? pluginId;
    final state = ref.watch(playbackStateProvider).value ?? const Idle();
    final status = liveStatusLabel(
      translations,
      state,
      info,
      sourceName: source,
    );
    final host = info.hostName;
    final online = info.online;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - spacing.x8).clamp(
                0.0,
                AppLayout.trackDetailsArtworkMax,
              )
            : AppLayout.trackDetailsArtworkMax;
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.all(spacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ArtworkImage(
                  pluginId: pluginId,
                  artwork: info.artwork,
                  size: size,
                ),
              ),
              SizedBox(height: spacing.x4),
              Text(info.title, style: theme.textTheme.titleLarge),
              if (status != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              SizedBox(height: spacing.x2),
              LiveFacts(info: info),
              if (showStop) ...[
                SizedBox(height: spacing.x3),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: Text(t.stopLive),
                  onPressed: () => unawaited(
                    ref.read(playbackControllerProvider).stopLive(),
                  ),
                ),
              ],
              SizedBox(height: spacing.x4),
              if (host != null) DetailsField(label: t.liveHost, value: host),
              if (online != null)
                DetailsField(
                  label: t.liveViewers,
                  value: formatCount(ref.watch(uiLocaleProvider), online),
                ),
              DetailsField(
                label: translations.playerPage.detailsSource,
                value: source,
              ),
            ],
          ),
        );
      },
    );
  }
}
