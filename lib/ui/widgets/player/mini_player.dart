import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../data/models/play_queue.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';

/// 迷你播放器
/// 显示在页面底部，展示当前播放的歌曲信息和控制按钮
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  /// 是否为桌面平台
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);

    // 没有正在播放的歌曲时不显示
    if (!playerState.hasCurrentTrack) {
      return const SizedBox.shrink();
    }

    final track = playerState.currentTrack!;

    return GestureDetector(
      onTap: () => context.push(RoutePaths.player),
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
        child: Column(
          children: [
            // 进度条
            LinearProgressIndicator(
              value: playerState.progress.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(colorScheme.primary),
            ),

            // 内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    // 封面
                    _buildThumbnail(track.thumbnailUrl, colorScheme),
                    const SizedBox(width: 8),

                    // 歌曲信息
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (track.artist != null)
                            Text(
                              track.artist!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),

                    // 控制按钮
                    _buildShuffleButton(playerState, controller, colorScheme),
                    _buildLoopModeButton(playerState, controller, colorScheme),
                    _buildPreviousButton(playerState, controller),
                    _buildPlayPauseButton(playerState, controller, colorScheme),
                    _buildNextButton(playerState, controller),

                    // 桌面端音量控制
                    if (isDesktop) ...[
                      const SizedBox(width: 8),
                      _buildVolumeControl(context, playerState, controller, colorScheme),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 封面缩略图
  Widget _buildThumbnail(String? thumbnailUrl, ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: thumbnailUrl != null
          ? CachedNetworkImage(
              imageUrl: thumbnailUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => _buildDefaultThumbnail(colorScheme),
              errorWidget: (context, url, error) => _buildDefaultThumbnail(colorScheme),
            )
          : _buildDefaultThumbnail(colorScheme),
    );
  }

  Widget _buildDefaultThumbnail(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.music_note,
        color: colorScheme.primary,
      ),
    );
  }

  /// 顺序/乱序按钮
  Widget _buildShuffleButton(
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    return IconButton(
      icon: Icon(
        state.isShuffleEnabled ? Icons.shuffle : Icons.arrow_forward,
        size: 20,
      ),
      color: state.isShuffleEnabled ? colorScheme.primary : null,
      tooltip: state.isShuffleEnabled ? '随机播放' : '顺序播放',
      visualDensity: VisualDensity.compact,
      onPressed: () => controller.toggleShuffle(),
    );
  }

  /// 循环模式按钮
  Widget _buildLoopModeButton(
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    final (icon, tooltip) = switch (state.loopMode) {
      LoopMode.none => (Icons.repeat, '不循环'),
      LoopMode.all => (Icons.repeat, '列表循环'),
      LoopMode.one => (Icons.repeat_one, '单曲循环'),
    };

    return IconButton(
      icon: Icon(icon, size: 20),
      color: state.loopMode != LoopMode.none ? colorScheme.primary : null,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () => controller.cycleLoopMode(),
    );
  }

  /// 上一首按钮
  Widget _buildPreviousButton(
    PlayerState state,
    AudioController controller,
  ) {
    return IconButton(
      icon: const Icon(Icons.skip_previous, size: 24),
      visualDensity: VisualDensity.compact,
      onPressed: state.canPlayPrevious
          ? () => controller.previous()
          : null,
    );
  }

  /// 播放/暂停按钮
  Widget _buildPlayPauseButton(
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    if (state.isBuffering || state.isLoading) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: colorScheme.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(
        state.isPlaying ? Icons.pause : Icons.play_arrow,
        size: 28,
      ),
      visualDensity: VisualDensity.compact,
      onPressed: () => controller.togglePlayPause(),
    );
  }

  /// 下一首按钮
  Widget _buildNextButton(
    PlayerState state,
    AudioController controller,
  ) {
    return IconButton(
      icon: const Icon(Icons.skip_next, size: 24),
      visualDensity: VisualDensity.compact,
      onPressed: state.canPlayNext
          ? () => controller.next()
          : null,
    );
  }

  /// 音量控制（仅桌面端）
  Widget _buildVolumeControl(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    // 窄屏时使用弹出式音量控制
    if (isNarrow) {
      return MenuAnchor(
        builder: (context, menuController, child) {
          return IconButton(
            icon: Icon(
              _getVolumeIcon(state.volume),
              size: 20,
            ),
            visualDensity: VisualDensity.compact,
            tooltip: '音量',
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          ),
        ],
      );
    }

    // 宽屏时显示完整音量控制
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 静音/音量图标按钮
        IconButton(
          icon: Icon(
            _getVolumeIcon(state.volume),
            size: 20,
          ),
          visualDensity: VisualDensity.compact,
          tooltip: state.volume > 0 ? '静音' : '取消静音',
          onPressed: () => controller.toggleMute(),
        ),
        // 音量滑块
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

  /// 根据音量获取对应图标
  IconData _getVolumeIcon(double volume) {
    if (volume <= 0) {
      return Icons.volume_off;
    } else if (volume < 0.5) {
      return Icons.volume_down;
    } else {
      return Icons.volume_up;
    }
  }
}
