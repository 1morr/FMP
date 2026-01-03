import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/models/play_queue.dart';
import '../../../services/audio/audio_provider.dart';

/// 播放器页面（全屏）
class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('正在播放'),
        actions: [
          // 播放速度
          PopupMenuButton<double>(
            icon: Text(
              '${playerState.speed}x',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            onSelected: (speed) => controller.setSpeed(speed),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 0.5, child: Text('0.5x')),
              const PopupMenuItem(value: 0.75, child: Text('0.75x')),
              const PopupMenuItem(value: 1.0, child: Text('1.0x')),
              const PopupMenuItem(value: 1.25, child: Text('1.25x')),
              const PopupMenuItem(value: 1.5, child: Text('1.5x')),
              const PopupMenuItem(value: 2.0, child: Text('2.0x')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: 显示更多选项
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 封面图
            Expanded(
              flex: 3,
              child: _buildCoverArt(context, playerState, colorScheme),
            ),
            const SizedBox(height: 32),

            // 歌曲信息
            _buildTrackInfo(context, playerState, colorScheme),
            const SizedBox(height: 32),

            // 进度条
            _buildProgressBar(context, playerState, controller, colorScheme),
            const SizedBox(height: 24),

            // 播放控制
            _buildPlaybackControls(context, playerState, controller, colorScheme),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 封面图
  Widget _buildCoverArt(
    BuildContext context,
    PlayerState state,
    ColorScheme colorScheme,
  ) {
    final thumbnailUrl = state.currentTrack?.thumbnailUrl;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator(
                    color: colorScheme.primary,
                  ),
                ),
                errorWidget: (context, url, error) => _buildDefaultCover(colorScheme),
              )
            : _buildDefaultCover(colorScheme),
      ),
    );
  }

  /// 默认封面
  Widget _buildDefaultCover(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.music_note,
        size: 120,
        color: colorScheme.primary,
      ),
    );
  }

  /// 歌曲信息
  Widget _buildTrackInfo(
    BuildContext context,
    PlayerState state,
    ColorScheme colorScheme,
  ) {
    final track = state.currentTrack;

    return Column(
      children: [
        Text(
          track?.title ?? '暂无播放',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          track?.artist ?? '选择一首歌曲开始播放',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 进度条
  Widget _buildProgressBar(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: state.progress.clamp(0.0, 1.0),
            onChanged: (value) => controller.seekToProgress(value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(state.position),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                _formatDuration(state.duration ?? Duration.zero),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 播放控制按钮
  Widget _buildPlaybackControls(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 播放模式
        IconButton(
          icon: Icon(_getPlayModeIcon(state.playMode)),
          color: state.playMode != PlayMode.sequential
              ? colorScheme.primary
              : null,
          onPressed: () => controller.cyclePlayMode(),
          tooltip: _getPlayModeTooltip(state.playMode),
        ),

        // 上一首
        IconButton(
          icon: const Icon(Icons.skip_previous),
          iconSize: 40,
          onPressed: state.canPlayPrevious ? () => controller.previous() : null,
        ),

        // 播放/暂停
        _buildPlayPauseButton(context, state, controller, colorScheme),

        // 下一首
        IconButton(
          icon: const Icon(Icons.skip_next),
          iconSize: 40,
          onPressed: state.canPlayNext ? () => controller.next() : null,
        ),

        // 快进10秒
        IconButton(
          icon: const Icon(Icons.forward_10),
          onPressed: state.hasCurrentTrack
              ? () => controller.seekForward()
              : null,
        ),
      ],
    );
  }

  /// 播放/暂停按钮
  Widget _buildPlayPauseButton(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    if (state.isBuffering || state.isLoading) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              color: colorScheme.onPrimary,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    return FilledButton(
      onPressed: state.hasCurrentTrack
          ? () => controller.togglePlayPause()
          : null,
      style: FilledButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(20),
      ),
      child: Icon(
        state.isPlaying ? Icons.pause : Icons.play_arrow,
        size: 40,
      ),
    );
  }

  /// 获取播放模式图标
  IconData _getPlayModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequential:
        return Icons.repeat;
      case PlayMode.loop:
        return Icons.repeat;
      case PlayMode.loopOne:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  /// 获取播放模式提示
  String _getPlayModeTooltip(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequential:
        return '顺序播放';
      case PlayMode.loop:
        return '列表循环';
      case PlayMode.loopOne:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }

  /// 格式化时长
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
