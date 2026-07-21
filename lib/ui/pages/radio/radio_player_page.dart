import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/radio_station.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/relative_time_formatter.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../providers/audio/audio_player_selectors.dart';
import '../../../services/platform/url_launcher_service.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/images/avatar_image.dart';
import '../../widgets/images/radio_cover_image.dart';
import '../../widgets/layout/detail_stats_row.dart';
import '../../widgets/radio/radio_detail_body.dart';
import '../../widgets/layout/immersive_player_scaffold.dart';
import '../../widgets/layout/capped_draggable_sheet.dart';
import '../../widgets/player/blurred_cover_backdrop.dart';
import '../../widgets/player/compact_volume_control.dart';
import '../../widgets/player/cover_art_container.dart';
import '../../widgets/player/fmp_audio_device_selector.dart';
import '../../widgets/player/player_play_pause_button.dart';

/// 電台播放器頁面（全屏）
class RadioPlayerPage extends ConsumerWidget {
  const RadioPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final radioState = ref.watch(radioControllerProvider);
    final radioController = ref.read(radioControllerProvider.notifier);
    // 與音樂頁一致，透過共享的 desktopAudioDeviceStateProvider 取得裝置狀態
    // （provider 內部為窄 select，避免對 audioControllerProvider 做全狀態 watch）。
    final desktopAudioDeviceState = ref.watch(desktopAudioDeviceStateProvider);
    final volume = ref.watch(
      audioControllerProvider.select((state) => state.volume),
    );
    final audioController = ref.read(audioControllerProvider.notifier);

    final station = radioState.currentStation;
    // 桌面寬版比照音樂播放器：整個內容欄（封面 + 資訊 + 控制列）置中。封面為
    // 1:1，理想邊長由可用高度驅動（4K 全屏時放大、小視窗時縮小），但實際大小
    // 由 Flexible 依剩餘空間收斂，從結構上避免 Column 溢出（不依賴高度常數估算）。
    final size = MediaQuery.sizeOf(context);
    final isWideLayout = Breakpoints.isDesktop(size.width);
    // 封面理想邊長：可用高度（扣除外距）的 52%，夾在 [280, 680]。僅作上限——
    // 空間不足時 Flexible 會把它壓到實際可用高度。
    final coverIdealSide =
        ((size.height - 48) * 0.52).clamp(280.0, 680.0).toDouble();
    final contentMaxWidth = isWideLayout ? 720.0 : 420.0;

    final appBarActions = <Widget>[
        // 桌面端音頻設備選擇器
        if (isDesktopPlatform && desktopAudioDeviceState.hasSelectableDevices)
          FmpAudioDeviceSelector(
            state: desktopAudioDeviceState,
            controller: audioController,
            colorScheme: colorScheme,
          ),
        // 桌面端音量控制（緊湊版）
        if (isDesktopPlatform)
          CompactVolumeControl(
            volume: volume,
            controller: audioController,
            colorScheme: colorScheme,
            muteTooltip: t.radio.mute,
            unmuteTooltip: t.radio.unmute,
          ),
        // 直播間資訊
        IconButton(
          icon: const Icon(Icons.info_outline),
          tooltip: t.radio.info,
          onPressed: () =>
              _showLiveInfoDialog(context, radioState, colorScheme),
        ),
        const SizedBox(width: 8),
      ];

    return Scaffold(
      appBar: null,
      body: ImmersivePlayerScaffold(
        backdrop: RadioBlurredBackdrop(
          networkUrl: station?.thumbnailUrl,
          colorScheme: colorScheme,
          surfaceOverlayAlpha: 0,
          surfaceContainerOverlayAlpha: 0,
        ),
        appBarActions: appBarActions,
        colorScheme: colorScheme,
        // 與音樂播放器一致：無電台時仍渲染完整播放器骨架，僅以佔位內容與
        // 停用控制列呈現空狀態。
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: _buildPlayerColumn(
                context,
                radioState,
                radioController,
                colorScheme,
                coverIdealSide: isWideLayout ? coverIdealSide : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 播放器內容欄：封面 + 電台資訊 + 開播標記 + 狀態列 + 播放控制。
  ///
  /// [coverIdealSide] 不為 null 時（桌面寬版），封面以此為理想邊長、並包在
  /// Flexible 內：空間足夠（如 4K 全屏）時用滿理想邊長，空間不足時自動縮小以
  /// 避免溢出。為 null 時（窄版）封面以 Expanded 液態隨欄寬。
  Widget _buildPlayerColumn(
    BuildContext context,
    RadioState radioState,
    RadioController radioController,
    ColorScheme colorScheme, {
    double? coverIdealSide,
  }) {
    final cover = _buildCoverArt(radioState.currentStation, colorScheme);
    return Column(
      children: [
        // 封面圖：寬版以理想邊長為上限、Flexible 依剩餘空間收斂；窄版液態。
        if (coverIdealSide != null)
          Flexible(
            child: Center(
              child: SizedBox(
                width: coverIdealSide,
                height: coverIdealSide,
                child: cover,
              ),
            ),
          )
        else
          Expanded(flex: 3, child: cover),
        const SizedBox(height: 32),

        // 電台資訊
        _buildStationInfo(context, radioState, colorScheme),
        const SizedBox(height: 16),

        // 已開播時長標記
        _buildLiveTag(context, radioState),
        const SizedBox(height: 16),

        // 狀態行
        _buildStatusBar(context, radioState, colorScheme),
        const SizedBox(height: 24),

        // 播放控制
        _buildPlaybackControls(
          radioState,
          radioController,
          colorScheme,
          hasStation: radioState.currentStation != null,
        ),
      ],
    );
  }

  /// 封面圖（無電台時顯示佔位圖，與音樂播放器空狀態一致）
  Widget _buildCoverArt(RadioStation? station, ColorScheme colorScheme) {
    return CoverArtContainer(
      colorScheme: colorScheme,
      child: station == null
          ? _buildCoverPlaceholder(colorScheme)
          : RadioCoverImage(
              networkUrl: station.thumbnailUrl,
              placeholder: _buildCoverPlaceholder(colorScheme),
              fit: BoxFit.cover,
              variant: RadioCoverVariant.hero,
            ),
    );
  }

  Widget _buildCoverPlaceholder(ColorScheme colorScheme) {
    return ImagePlaceholder(
      icon: Icons.radio,
      iconSize: 120,
      iconColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );
  }

  /// 電台資訊（固定高度，避免佈局跳動）
  Widget _buildStationInfo(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    final station = state.currentStation;

    return SizedBox(
      height: 80, // 固定高度：標題兩行 + 間距 + 主播名一行
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            station?.title ?? t.radio.unknownStation,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            station?.hostName ?? t.radio.live,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// 已開播時長標記（固定高度，避免佈局跳動）
  Widget _buildLiveTag(BuildContext context, RadioState state) {
    final parts = <String>[];

    if (state.liveStartTime != null) {
      parts.add(t.radio
          .startedBroadcast(time: formatRelativeTime(state.liveStartTime!)));
    }
    if (state.isPlaying) {
      parts.add(DurationFormatter.format(state.playDuration));
    }

    return SizedBox(
      height: 24,
      child: AnimatedOpacity(
        opacity: state.isPlaying ? 1.0 : 0.0,
        duration: AnimationDurations.fast,
        child: Text(
          parts.isEmpty ? '' : parts.join(' · '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// 狀態行（固定高度，避免佈局跳動）
  Widget _buildStatusBar(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      height: 24, // 固定高度
      child: Text(
        _getStatusText(state),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: state.isReconnecting
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 獲取狀態文字
  String _getStatusText(RadioState state) {
    if (state.isReconnecting) {
      return t.radio.reconnecting;
    }
    if (state.isBuffering) {
      return t.radio.buffering;
    }
    if (!state.isPlaying) {
      return t.radio.paused;
    }

    final parts = <String>[];
    if (state.viewerCount != null) {
      parts.add(t.radio.viewersCount(count: formatCount(state.viewerCount!)));
    }
    return parts.isEmpty ? t.radio.live : parts.join(' · ');
  }

  /// 播放控制按鈕：跳到最新 / 播放-暫停 / 重新載入
  Widget _buildPlaybackControls(
    RadioState state,
    RadioController controller,
    ColorScheme colorScheme, {
    required bool hasStation,
  }) {
    // sync/reload 僅在實際播放中可用（與既有 reload 選單、mini sync 一致）。
    final isDisabled = state.isBuffering || state.isLoading || !state.isPlaying;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 跳到最新：先 seek 到直播邊緣，無法 seek 則重連（RadioController.sync）。
        IconButton(
          icon: const Icon(Icons.sync),
          iconSize: 40,
          tooltip: t.radio.syncLive,
          onPressed:
              isDisabled || !hasStation ? null : () => controller.sync(),
        ),
        // 播放/暫停（大）；無電台時停用（比照音樂播放器空狀態）。
        PlayerPlayPauseButton(
          isLoading: state.isBuffering || state.isLoading,
          isPlaying: state.isPlaying,
          enabled: hasStation,
          onPressed: () {
            if (state.isPlaying) {
              controller.pause();
            } else {
              controller.resume();
            }
          },
          colorScheme: colorScheme,
        ),
        // 重新載入：無條件重新連接直播流（RadioController.reload）。
        IconButton(
          icon: const Icon(Icons.refresh),
          iconSize: 40,
          tooltip: t.radio.reloadLive,
          onPressed:
              isDisabled || !hasStation ? null : () => controller.reload(),
        ),
      ],
    );
  }

  /// 顯示直播間信息彈窗
  void _showLiveInfoDialog(
    BuildContext context,
    RadioState state,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LiveInfoDialog(state: state),
    );
  }
}

/// 直播間信息彈窗
class _LiveInfoDialog extends StatelessWidget {
  final RadioState state;

  const _LiveInfoDialog({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final station = state.currentStation;

    return CappedDraggableSheet(
      icon: Icons.info_outline_rounded,
      title: t.radio.liveRoomInfo,
      onClose: () => Navigator.of(context).pop(),
      bodySlivers: (context, scrollController) => [
        // 內容區域
        SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                    child: station == null
                        ? Text(t.radio.unableToGetInfo)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RadioDetailBody(
                                // 封面（點擊跳轉到直播間，與桌面 Detail Panel 一致）
                                cover: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => UrlLauncherService.instance
                                        .openBilibiliLive(station.sourceId),
                                    child: ClipRRect(
                                      borderRadius: AppRadius.borderRadiusXl,
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: RadioCoverImage(
                                          networkUrl: station.thumbnailUrl,
                                          placeholder:
                                              _buildCoverPlaceholder(context),
                                          fit: BoxFit.cover,
                                          variant: RadioCoverVariant.hero,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                title: station.title,
                                titleMaxLines: 3,
                                onTitleTap: () => UrlLauncherService.instance
                                    .openBilibiliLive(station.sourceId),
                                // 主播列（點擊跳轉到個人空間）
                                hostName: station.hostName,
                                hostAvatar: AvatarImage(
                                  networkUrl: station.hostAvatarUrl,
                                  size: 40,
                                ),
                                avatarSize: 40,
                                avatarGap: 12,
                                compactHostName: false,
                                onHostTap: station.hostUid != null
                                    ? () => UrlLauncherService.instance
                                        .openBilibiliSpace(station.hostUid!)
                                    : null,
                                hostTrailing: station.hostUid != null
                                    ? Icon(
                                        Icons.chevron_right,
                                        size: 20,
                                        color: colorScheme.onSurfaceVariant,
                                      )
                                    : null,
                                stats: [
                                  if (state.viewerCount != null)
                                    DetailStatItem(
                                      icon: Icons.visibility_rounded,
                                      label:
                                          formatCount(state.viewerCount!),
                                    ),
                                  if (state.isPlaying)
                                    DetailStatItem(
                                      icon: Icons.schedule_outlined,
                                      label: t.radio.played(
                                          duration: DurationFormatter.format(
                                              state.playDuration)),
                                    ),
                                  if (state.liveStartTime != null)
                                    DetailStatItem(
                                      icon: Icons.play_circle_outline,
                                      label: t.radio.startedAt(
                                          time: formatRelativeTime(
                                              state.liveStartTime!)),
                                    ),
                                  if (state.areaName != null)
                                    DetailStatItem(
                                      icon: Icons.category_outlined,
                                      label: state.areaName!,
                                    ),
                                  DetailStatItem(
                                    icon: state.isPlaying
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    label: state.isPlaying
                                        ? t.radio.live
                                        : t.radio.stopped,
                                  ),
                                ],
                                announcement: state.announcement,
                                announcementTitle: t.radio.announcement,
                                description: state.description,
                                descriptionTitle: t.radio.description,
                                tags: state.tags,
                                tagsTitle: t.radio.tags,
                                spacingAfterCover: 16,
                                spacingAfterTitle: 16,
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                  ),
                ),
      ],
    );
  }

  Widget _buildCoverPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ImagePlaceholder(
      icon: Icons.radio,
      iconSize: 64,
      iconColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    );
  }
}
