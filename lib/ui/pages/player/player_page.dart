import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/play_queue.dart';
import '../../../services/audio/audio_provider.dart';

/// 播放器页面（全屏）
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  /// 是否为桌面平台
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 是否正在拖动进度条
  bool _isDragging = false;

  /// 拖动时的临时进度值
  double _dragProgress = 0.0;

  @override
  Widget build(BuildContext context) {
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
          // 桌面端音量控制（紧凑版）
          if (isDesktop)
            _buildCompactVolumeControl(context, playerState, controller, colorScheme),
          // 更多选项（包含倍速）
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            offset: const Offset(0, 48), // 向下偏移，与子菜单位置一致
            onSelected: (value) {
              if (value == 'speed') {
                // 延迟显示子菜单，等主菜单关闭后再显示
                Future.delayed(const Duration(milliseconds: 100), () {
                  _showSpeedMenu(context, controller, playerState.speed, colorScheme);
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'speed',
                child: Row(
                  children: [
                    const Icon(Icons.speed, size: 20),
                    const SizedBox(width: 12),
                    Text('${playerState.speed}x'),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
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
            ? Image.network(
                thumbnailUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    _buildDefaultCover(colorScheme),
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
    // 显示的进度：拖动时显示拖动进度，否则显示实际播放进度
    final displayProgress = _isDragging ? _dragProgress : state.progress.clamp(0.0, 1.0);

    // 显示的位置：拖动时根据拖动进度计算，否则显示实际位置
    final displayPosition = _isDragging && state.duration != null
        ? Duration(milliseconds: (state.duration!.inMilliseconds * _dragProgress).round())
        : state.position;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: displayProgress,
            onChangeStart: (value) {
              setState(() {
                _isDragging = true;
                _dragProgress = value;
              });
            },
            onChanged: (value) {
              // 拖动过程中只更新本地状态，不触发 seek
              setState(() => _dragProgress = value);
            },
            onChangeEnd: (value) {
              // 拖动结束时才触发 seek
              controller.seekToProgress(value);
              setState(() => _isDragging = false);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(displayPosition),
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
        // 顺序/乱序按钮
        IconButton(
          icon: Icon(state.isShuffleEnabled ? Icons.shuffle : Icons.arrow_forward),
          color: state.isShuffleEnabled ? colorScheme.primary : null,
          onPressed: () => controller.toggleShuffle(),
          tooltip: state.isShuffleEnabled ? '随机播放' : '顺序播放',
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

        // 循环模式按钮
        IconButton(
          icon: Icon(_getLoopModeIcon(state.loopMode)),
          color: state.loopMode != LoopMode.none ? colorScheme.primary : null,
          onPressed: () => controller.cycleLoopMode(),
          tooltip: _getLoopModeTooltip(state.loopMode),
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
    const double buttonSize = 80;

    if (state.isBuffering || state.isLoading) {
      return SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            minimumSize: const Size(buttonSize, buttonSize),
            maximumSize: const Size(buttonSize, buttonSize),
            padding: EdgeInsets.zero,
          ),
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

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: FilledButton(
        onPressed: state.hasCurrentTrack
            ? () => controller.togglePlayPause()
            : null,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          minimumSize: const Size(buttonSize, buttonSize),
          maximumSize: const Size(buttonSize, buttonSize),
          padding: EdgeInsets.zero,
        ),
        child: Icon(
          state.isPlaying ? Icons.pause : Icons.play_arrow,
          size: 40,
        ),
      ),
    );
  }

  /// 显示倍速选择菜单
  void _showSpeedMenu(
    BuildContext context,
    AudioController controller,
    double currentSpeed,
    ColorScheme colorScheme,
  ) {
    // 获取屏幕尺寸，将菜单定位在右上角
    final screenSize = MediaQuery.of(context).size;
    final position = RelativeRect.fromLTRB(
      screenSize.width - 150, // 距离左边
      kToolbarHeight + MediaQuery.of(context).padding.top, // 距离顶部
      8, // 距离右边
      0,
    );

    showMenu<double>(
      context: context,
      position: position,
      items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) => PopupMenuItem(
        value: speed,
        child: Row(
          children: [
            if (currentSpeed == speed)
              Icon(Icons.check, size: 18, color: colorScheme.primary)
            else
              const SizedBox(width: 18),
            const SizedBox(width: 8),
            Text('${speed}x'),
          ],
        ),
      )).toList(),
    ).then((value) {
      if (value != null) {
        controller.setSpeed(value);
      }
    });
  }

  /// 紧凑音量控制（AppBar用，仅桌面端）
  Widget _buildCompactVolumeControl(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 音量图标按钮
        IconButton(
          icon: Icon(_getVolumeIcon(state.volume), size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: state.volume > 0 ? '静音' : '取消静音',
          onPressed: () => controller.toggleMute(),
        ),
        // 音量滑块
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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

  /// 获取循环模式图标
  IconData _getLoopModeIcon(LoopMode mode) {
    switch (mode) {
      case LoopMode.none:
        return Icons.repeat;
      case LoopMode.all:
        return Icons.repeat;
      case LoopMode.one:
        return Icons.repeat_one;
    }
  }

  /// 获取循环模式提示
  String _getLoopModeTooltip(LoopMode mode) {
    switch (mode) {
      case LoopMode.none:
        return '不循环';
      case LoopMode.all:
        return '列表循环';
      case LoopMode.one:
        return '单曲循环';
    }
  }

  /// 格式化时长
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
