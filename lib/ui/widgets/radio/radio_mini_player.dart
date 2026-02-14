import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/utils/icon_helpers.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/radio/radio_controller.dart';
import '../../router.dart';

/// 電台迷你播放器
/// 顯示在頁面底部，展示當前播放的電台資訊和控制按鈕
/// 樣式與音樂迷你播放器一致
class RadioMiniPlayer extends ConsumerStatefulWidget {
  const RadioMiniPlayer({super.key});

  @override
  ConsumerState<RadioMiniPlayer> createState() => _RadioMiniPlayerState();
}

class _RadioMiniPlayerState extends ConsumerState<RadioMiniPlayer> {
  /// 是否為桌面平台
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radioState = ref.watch(radioControllerProvider);
    final radioController = ref.read(radioControllerProvider.notifier);
    // 使用 AudioController 管理音量（共享同一個 AudioService）
    final audioState = ref.watch(audioControllerProvider);
    final audioController = ref.read(audioControllerProvider.notifier);

    // 沒有電台在播放時不顯示
    if (!radioState.hasCurrentStation) {
      return const SizedBox.shrink();
    }

    final station = radioState.currentStation!;

    return GestureDetector(
      onTap: () => context.push(RoutePaths.radioPlayer),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              // 封面
              _buildThumbnail(station, colorScheme),
              const SizedBox(width: 8),

              // 電台資訊
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.title,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    _buildStatusRow(radioState, colorScheme, context),
                  ],
                ),
              ),

              // 同步按鈕
              _buildSyncButton(radioState, radioController, colorScheme),

              // 播放/暫停按鈕
              _buildPlayStopButton(radioState, radioController, colorScheme),

              // 桌面端音量控制
              if (isDesktop) ...[
                const SizedBox(width: 8),
                _buildVolumeControl(
                    context, audioState, audioController, colorScheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(dynamic station, ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: AppRadius.borderRadiusLg,
      child: SizedBox(
        width: 48,
        height: 48,
        child: ImageLoadingService.loadImage(
            networkUrl: station.thumbnailUrl,
            placeholder: _buildPlaceholder(colorScheme),
            fit: BoxFit.cover,
            width: 48,
            height: 48,
          ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.radio,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }

  Widget _buildStatusRow(
    RadioState radioState,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    final parts = <String>[];

    // 主播名稱
    if (radioState.currentStation?.hostName != null) {
      parts.add(radioState.currentStation!.hostName!);
    }

    // 已播放時長
    if (radioState.isPlaying) {
      parts.add(_formatDuration(radioState.playDuration));
    }

    // 觀眾數
    if (radioState.viewerCount != null) {
      parts.add(t.radio.viewersCount(count: _formatCount(radioState.viewerCount!)));
    }

    // 重連/緩衝狀態
    if (radioState.isReconnecting) {
      parts.add(t.radio.reconnecting);
    } else if (radioState.isBuffering) {
      parts.add(t.radio.buffering);
    }

    return Text(
      parts.isEmpty ? t.radio.isLive : parts.join(' · '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 播放/暫停按鈕
  Widget _buildPlayStopButton(
    RadioState state,
    RadioController controller,
    ColorScheme colorScheme,
  ) {
    // 使用固定尺寸的 SizedBox 包裝，確保載入和正常狀態下大小一致
    return SizedBox(
      width: 40,
      height: 40,
      child: state.isBuffering || state.isLoading
          ? Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: colorScheme.primary,
                  strokeWidth: 2,
                ),
              ),
            )
          : IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                state.isPlaying ? Icons.pause : Icons.play_arrow,
                size: 28,
              ),
              onPressed: () {
                if (state.isPlaying) {
                  controller.pause();
                } else {
                  controller.resume();
                }
              },
            ),
    );
  }

  /// 同步按鈕（重新載入直播流）
  Widget _buildSyncButton(
    RadioState state,
    RadioController controller,
    ColorScheme colorScheme,
  ) {
    final isDisabled = state.isBuffering || state.isLoading || !state.isPlaying;

    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.sync,
          size: 22,
          color: isDisabled ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38) : null,
        ),
        tooltip: t.radio.syncLive,
        onPressed: isDisabled ? null : () => controller.sync(),
      ),
    );
  }

  /// 音量控制（僅桌面端）
  Widget _buildVolumeControl(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    // 窄屏時使用彈出式音量控制
    if (isNarrow) {
      return MenuAnchor(
        builder: (context, menuController, child) {
          return IconButton(
            icon: Icon(
              getVolumeIcon(state.volume),
              size: 20,
            ),
            visualDensity: VisualDensity.compact,
            tooltip: t.radio.volume,
            onPressed: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
          );
        },
        style: MenuStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXl),
          ),
        ),
        alignmentOffset: const Offset(0, -170),
        menuChildren: [
          SizedBox(
            width: 40,
            height: 120,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: colorScheme.primary,
                  inactiveTrackColor: colorScheme.surfaceContainerHighest,
                  thumbColor: colorScheme.primary,
                  overlayColor: colorScheme.primary.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: state.volume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (value) => controller.setVolume(value),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 寬屏時顯示完整音量控制
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 靜音/音量圖標按鈕
        IconButton(
          icon: Icon(
            getVolumeIcon(state.volume),
            size: 20,
          ),
          visualDensity: VisualDensity.compact,
          tooltip: state.volume > 0 ? t.radio.mute : t.radio.unmute,
          onPressed: () => controller.toggleMute(),
        ),
        // 音量滑塊
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.surfaceContainerHighest,
              thumbColor: colorScheme.primary,
              overlayColor: colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: state.volume,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => controller.setVolume(value),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatCount(int count) => formatCount(count);
}
