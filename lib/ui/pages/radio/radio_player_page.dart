import 'dart:ui' show PointerDeviceKind;

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
import '../../widgets/layout/expandable_text_section.dart';
import '../../widgets/layout/immersive_player_scaffold.dart';
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
    // 桌面寬版比照音樂播放器：封面限制 maxWidth 420 並置中
    final isWideLayout =
        Breakpoints.isDesktop(MediaQuery.sizeOf(context).width);

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
        body: station == null
            ? _buildEmptyState(context, colorScheme)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // 封面圖
                    Expanded(
                      flex: 3,
                      child: isWideLayout
                          ? Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 420),
                                child: _buildCoverArt(station, colorScheme),
                              ),
                            )
                          : _buildCoverArt(station, colorScheme),
                    ),
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
                        radioState, radioController, colorScheme),
                  ],
                ),
              ),
      ),
    );
  }

  /// 封面圖
  Widget _buildCoverArt(RadioStation station, ColorScheme colorScheme) {
    return CoverArtContainer(
      colorScheme: colorScheme,
      child: RadioCoverImage(
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

  /// 空狀態（無播放中的電台），比照音樂播放器空狀態品質
  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.radio,
            size: 120,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            t.radio.noPlaying,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
    ColorScheme colorScheme,
  ) {
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
          onPressed: isDisabled ? null : () => controller.sync(),
        ),
        // 播放/暫停（大）
        PlayerPlayPauseButton(
          isLoading: state.isBuffering || state.isLoading,
          isPlaying: state.isPlaying,
          enabled: true,
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
          onPressed: isDisabled ? null : () => controller.reload(),
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
    final textTheme = Theme.of(context).textTheme;
    final station = state.currentStation;

    // 限制最大高度，避免 Windows 全屏时弹窗过高
    final screenHeight = MediaQuery.of(context).size.height;
    const maxSheetHeight = 800.0;
    final maxRatio = (maxSheetHeight / screenHeight).clamp(0.4, 0.95);
    final initRatio = maxRatio < 0.6 ? maxRatio : 0.6;

    return DraggableScrollableSheet(
      initialChildSize: initRatio,
      minChildSize: 0.0,
      maxChildSize: maxRatio,
      snap: true,
      snapSizes: [0.0, initRatio, if (maxRatio > initRatio) maxRatio],
      builder: (context, scrollController) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                // 頂部拖動手柄和標題欄
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // 拖動手柄
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                          borderRadius: AppRadius.borderRadiusXs,
                        ),
                      ),
                      // 標題欄
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t.radio.liveRoomInfo,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                ),

                // 內容區域
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverToBoxAdapter(
                    child: station == null
                        ? Text(t.radio.unableToGetInfo)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 封面（點擊跳轉到直播間，與桌面 Detail Panel 一致）
                              MouseRegion(
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

                              const SizedBox(height: 16),

                              // 標題（點擊跳轉到直播間）
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => UrlLauncherService.instance
                                      .openBilibiliLive(station.sourceId),
                                  child: Text(
                                    station.title,
                                    style: textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // 主播信息（點擊跳轉到個人空間）
                              if (station.hostName != null)
                                MouseRegion(
                                  cursor: station.hostUid != null
                                      ? SystemMouseCursors.click
                                      : SystemMouseCursors.basic,
                                  child: GestureDetector(
                                    onTap: station.hostUid != null
                                        ? () => UrlLauncherService.instance
                                            .openBilibiliSpace(station.hostUid!)
                                        : null,
                                    child: Row(
                                      children: [
                                        AvatarImage(
                                          networkUrl: station.hostAvatarUrl,
                                          size: 40,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            station.hostName!,
                                            style:
                                                textTheme.bodyLarge?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (station.hostUid != null)
                                          Icon(
                                            Icons.chevron_right,
                                            size: 20,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 16),

                              // 統計數據
                              DetailStatsRow(
                                items: [
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
                              ),

                              // 主播公告
                              if (state.announcement != null &&
                                  state.announcement!.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 16),
                                ExpandableTextSection(
                                  icon: Icons.campaign_outlined,
                                  title: t.radio.announcement,
                                  content: state.announcement!,
                                ),
                              ],

                              // 直播間簡介
                              if (state.description != null &&
                                  state.description!.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 16),
                                ExpandableTextSection(
                                  icon: Icons.info_outline_rounded,
                                  title: t.radio.description,
                                  content: state.description!,
                                ),
                              ],

                              // 標籤
                              if (state.tags != null &&
                                  state.tags!.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                const Divider(),
                                const SizedBox(height: 16),
                                _buildTagsSection(context, state.tags!),
                              ],

                              const SizedBox(height: 20),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  Widget _buildTagsSection(BuildContext context, String tags) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tagList = tags.split(',').where((t) => t.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tag, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              t.radio.tags,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tagList
              .map((tag) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.borderRadiusXl,
                    ),
                    child: Text(
                      tag.trim(),
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
