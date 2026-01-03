import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';

/// 迷你播放器
/// 显示在页面底部，展示当前播放的歌曲信息和控制按钮
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

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
              color: colorScheme.outlineVariant.withOpacity(0.3),
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
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    // 封面
                    _buildThumbnail(track.thumbnailUrl, colorScheme),
                    const SizedBox(width: 12),

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
                    _buildPlayPauseButton(playerState, controller, colorScheme),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: playerState.canPlayNext
                          ? () => controller.next()
                          : null,
                    ),
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

  /// 播放/暂停按钮
  Widget _buildPlayPauseButton(
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    if (state.isBuffering || state.isLoading) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: colorScheme.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
      onPressed: () => controller.togglePlayPause(),
    );
  }
}
