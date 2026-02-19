import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fmp/services/audio/audio_types.dart' show FmpAudioDevice;
import 'package:fmp/i18n/strings.g.dart';
import '../../../core/utils/icon_helpers.dart';
import '../../../data/models/play_queue.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';
import '../track_thumbnail.dart';
import '../../../core/constants/ui_constants.dart';

/// 迷你播放器
/// 显示在页面底部，展示当前播放的歌曲信息和控制按钮
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只监听当前曲目，判断是否显示
    final currentTrack = ref.watch(currentTrackProvider);

    // 没有正在播放的歌曲时不显示
    if (currentTrack == null) {
      return const SizedBox.shrink();
    }

    return const _MiniPlayerContent();
  }
}

/// 迷你播放器内容（拆分后的主体）
class _MiniPlayerContent extends ConsumerStatefulWidget {
  const _MiniPlayerContent();

  @override
  ConsumerState<_MiniPlayerContent> createState() => _MiniPlayerContentState();
}

class _MiniPlayerContentState extends ConsumerState<_MiniPlayerContent> {
  /// 鼠标是否悬停在迷你播放器上
  bool _isHovering = false;

  /// 是否为桌面平台
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: () => context.push(RoutePaths.player),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 主内容容器
            Container(
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
                  // 进度条占位（固定 2px 高度）
                  const SizedBox(height: 2),

                  // 内容
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          // 封面和歌曲信息
                          const Expanded(child: _MiniPlayerTrackInfo()),

                          // 控制按钮
                          const _MiniPlayerControls(),

                          // 桌面端音频设备选择和音量控制
                          if (isDesktop) ...[
                            const SizedBox(width: 8),
                            _MiniPlayerVolumeControl(colorScheme: colorScheme),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 可交互的进度条（定位在顶部）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _MiniPlayerProgressBar(isParentHovering: _isHovering),
            ),
          ],
        ),
      ),
    );
  }
}

/// 迷你播放器 - 进度条组件
class _MiniPlayerProgressBar extends ConsumerStatefulWidget {
  const _MiniPlayerProgressBar({required this.isParentHovering});

  final bool isParentHovering;

  @override
  ConsumerState<_MiniPlayerProgressBar> createState() => _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState extends ConsumerState<_MiniPlayerProgressBar> {
  /// 是否正在拖动进度条
  bool _isDragging = false;

  /// 拖动时的临时进度值
  double _dragProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 只监听进度值
    final progress = ref.watch(audioControllerProvider.select((s) => s.progress));
    final controller = ref.read(audioControllerProvider.notifier);

    // 显示的进度：拖动时显示拖动进度，否则显示实际播放进度
    final displayProgress = _isDragging ? _dragProgress : progress.clamp(0.0, 1.0);
    
    // 是否应该展开：父组件悬停或正在拖动
    final isExpanded = widget.isParentHovering || _isDragging;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        // 阻止事件冒泡到父级 GestureDetector
      },
      onTap: () {
        // 阻止事件冒泡，不触发跳转到播放器页面
      },
      onHorizontalDragStart: (details) {
        setState(() {
          _isDragging = true;
          _dragProgress = progress.clamp(0.0, 1.0);
        });
      },
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = details.localPosition;
          final progress = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
          setState(() => _dragProgress = progress);
        }
      },
      onHorizontalDragEnd: (details) {
        controller.seekToProgress(_dragProgress);
        setState(() => _isDragging = false);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final progress = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                controller.seekToProgress(progress);
              },
              // 悬停时扩大点击区域，视觉元素锚定在顶部
              child: SizedBox(
                height: isExpanded ? 18 : 2,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topLeft,
                  children: [
                    // 背景轨道
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: AnimatedContainer(
                        duration: AnimationDurations.fast,
                        height: isExpanded ? 6 : 2,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: AppRadius.borderRadiusXs,
                        ),
                      ),
                    ),
                    // 已播放部分
                    Positioned(
                      left: 0,
                      width: constraints.maxWidth * displayProgress,
                      top: 0,
                      child: AnimatedContainer(
                        duration: AnimationDurations.fast,
                        height: isExpanded ? 6 : 2,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: AppRadius.borderRadiusXs,
                        ),
                      ),
                    ),
                    // 圆形指示器（悬停或拖动时显示）
                    if (isExpanded)
                      Positioned(
                        left: constraints.maxWidth * displayProgress - 6,
                        top: -3, // 使圆心对齐 6px 轨道中心
                        child: AnimatedOpacity(
                          opacity: isExpanded ? 1.0 : 0.0,
                          duration: AnimationDurations.fast,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 迷你播放器 - 歌曲信息组件
class _MiniPlayerTrackInfo extends ConsumerWidget {
  const _MiniPlayerTrackInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // 只监听当前曲目
    final track = ref.watch(currentTrackProvider);

    if (track == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => context.push(RoutePaths.player),
      child: Row(
        children: [
          // 封面
          TrackThumbnail(
            track: track,
            size: AppSizes.thumbnailMedium,
            borderRadius: 8,
            showPlayingIndicator: false,
          ),
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
        ],
      ),
    );
  }
}

/// 迷你播放器 - 控制按钮组件
class _MiniPlayerControls extends ConsumerWidget {
  const _MiniPlayerControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // 只监听播放状态相关字段
    final isPlaying = ref.watch(audioControllerProvider.select((s) => s.isPlaying));
    final isBuffering = ref.watch(audioControllerProvider.select((s) => s.isBuffering));
    final isLoading = ref.watch(audioControllerProvider.select((s) => s.isLoading));
    final isShuffleEnabled = ref.watch(audioControllerProvider.select((s) => s.isShuffleEnabled));
    final loopMode = ref.watch(audioControllerProvider.select((s) => s.loopMode));
    final isMixMode = ref.watch(audioControllerProvider.select((s) => s.isMixMode));
    final canPlayPrevious = ref.watch(audioControllerProvider.select((s) => s.canPlayPrevious));
    final canPlayNext = ref.watch(audioControllerProvider.select((s) => s.canPlayNext));

    final controller = ref.read(audioControllerProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顺序/乱序按钮
        IconButton(
          icon: Icon(
            isShuffleEnabled ? Icons.shuffle : Icons.arrow_forward,
            size: 20,
          ),
          color: isShuffleEnabled ? colorScheme.primary : null,
          tooltip: isMixMode
              ? t.audio.mixPlaylistNoAdd
              : (isShuffleEnabled ? t.player.shuffleOn : t.player.shuffleOff),
          visualDensity: VisualDensity.compact,
          onPressed: isMixMode ? null : () => controller.toggleShuffle(),
        ),

        // 循环模式按钮
        IconButton(
          icon: Icon(
            loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
            size: 20,
          ),
          color: loopMode != LoopMode.none ? colorScheme.primary : null,
          tooltip: switch (loopMode) {
            LoopMode.none => t.player.loopOff,
            LoopMode.all => t.player.loopAll,
            LoopMode.one => t.player.loopOne,
          },
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.cycleLoopMode(),
        ),

        // 上一首按钮
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 24),
          visualDensity: VisualDensity.compact,
          onPressed: canPlayPrevious ? () => controller.previous() : null,
        ),

        // 播放/暂停按钮
        SizedBox(
          width: 40,
          height: 40,
          child: isBuffering || isLoading
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
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 28,
                  ),
                  onPressed: () => controller.togglePlayPause(),
                ),
        ),

        // 下一首按钮
        IconButton(
          icon: const Icon(Icons.skip_next, size: 24),
          visualDensity: VisualDensity.compact,
          onPressed: canPlayNext ? () => controller.next() : null,
        ),
      ],
    );
  }
}

/// 迷你播放器 - 音量控制组件（桌面端）
class _MiniPlayerVolumeControl extends ConsumerWidget {
  final ColorScheme colorScheme;

  const _MiniPlayerVolumeControl({required this.colorScheme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只监听音量和音频设备
    final volume = ref.watch(audioControllerProvider.select((s) => s.volume));
    final audioDevices = ref.watch(audioControllerProvider.select((s) => s.audioDevices));
    final currentFmpAudioDevice = ref.watch(audioControllerProvider.select((s) => s.currentAudioDevice));

    final controller = ref.read(audioControllerProvider.notifier);
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 音频设备选择器
        if (audioDevices.length > 1)
          _buildFmpAudioDeviceSelector(context, audioDevices, currentFmpAudioDevice, controller),

        // 音量控制
        if (isNarrow)
          _buildCompactVolumeControl(context, volume, controller)
        else
          _buildFullVolumeControl(volume, controller),
      ],
    );
  }

  Widget _buildFmpAudioDeviceSelector(
    BuildContext context,
    List<FmpAudioDevice> devices,
    FmpAudioDevice? currentDevice,
    AudioController controller,
  ) {
    const menuWidth = 220.0;

    return MenuAnchor(
      consumeOutsideTap: true,
      alignmentOffset: const Offset(-menuWidth / 2 + 20, 16),
      builder: (context, menuController, child) {
        return IconButton(
          icon: const Icon(Icons.speaker, size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: t.player.audioDevice,
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
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(menuWidth, 0)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
        ),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: () => controller.setAudioDeviceAuto(),
          leadingIcon: currentDevice == null || currentDevice.name == 'auto'
              ? Icon(Icons.check, size: 18, color: colorScheme.primary)
              : const SizedBox(width: 18),
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Text(t.player.audioDeviceAuto),
          ),
        ),
        const Divider(height: 1),
        ...devices.where((d) => d.name != 'auto' && d.name != 'openal').map((device) {
          final isSelected = currentDevice?.name == device.name;
          return MenuItemButton(
            onPressed: () => controller.setAudioDevice(device),
            leadingIcon: isSelected
                ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                : const SizedBox(width: 18),
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(
                _formatDeviceName(device),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }),
      ],
    );
  }

  String _formatDeviceName(FmpAudioDevice device) {
    final displayName = device.description.isNotEmpty ? device.description : device.name;

    final match = RegExp(r'喇叭\s*\((.+)\)$').firstMatch(displayName);
    if (match != null) {
      return match.group(1) ?? displayName;
    }

    final matchEn = RegExp(r'Speakers?\s*\((.+)\)$', caseSensitive: false).firstMatch(displayName);
    if (matchEn != null) {
      return matchEn.group(1) ?? displayName;
    }

    return displayName;
  }

  Widget _buildCompactVolumeControl(BuildContext context, double volume, AudioController controller) {
    return MenuAnchor(
      builder: (context, menuController, child) {
        return IconButton(
          icon: Icon(getVolumeIcon(volume), size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: t.player.volume,
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
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
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
                value: volume,
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

  Widget _buildFullVolumeControl(double volume, AudioController controller) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(getVolumeIcon(volume), size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: volume > 0 ? t.player.mute : t.player.unmute,
          onPressed: () => controller.toggleMute(),
        ),
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
              value: volume,
              min: 0.0,
              max: 1.0,
              onChanged: (value) => controller.setVolume(value),
            ),
          ),
        ),
      ],
    );
  }
}
