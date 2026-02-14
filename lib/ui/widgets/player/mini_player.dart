import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart' show AudioDevice;
import 'package:fmp/i18n/strings.g.dart';
import '../../../core/utils/icon_helpers.dart';
import '../../../data/models/play_queue.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';
import '../track_thumbnail.dart';
import '../../../core/constants/app_constants.dart';

/// 迷你播放器
/// 显示在页面底部，展示当前播放的歌曲信息和控制按钮
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  /// 是否为桌面平台
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 鼠标是否悬停在播放器上
  bool _isHovering = false;

  /// 是否正在拖动进度条
  bool _isDragging = false;

  /// 拖动时的临时进度值
  double _dragProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);

    // 没有正在播放的歌曲时不显示
    if (!playerState.hasCurrentTrack) {
      return const SizedBox.shrink();
    }

    final track = playerState.currentTrack!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) {
        if (!_isDragging) {
          setState(() => _isHovering = false);
        }
      },
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
                    // 封面
                    TrackThumbnail(
                      track: track,
                      size: AppConstants.thumbnailSizeMedium,
                      borderRadius: AppConstants.borderRadiusMedium,
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

                    // 控制按钮
                    _buildShuffleButton(playerState, controller, colorScheme),
                    _buildLoopModeButton(playerState, controller, colorScheme),
                    _buildPreviousButton(playerState, controller),
                    _buildPlayPauseButton(playerState, controller, colorScheme),
                    _buildNextButton(playerState, controller),

                    // 桌面端音频设备选择和音量控制
                    if (isDesktop) ...[
                      const SizedBox(width: 8),
                      if (playerState.audioDevices.length > 1)
                        _buildAudioDeviceSelector(context, playerState, controller, colorScheme),
                      _buildVolumeControl(context, playerState, controller, colorScheme),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
            // 可交互的进度条（定位在顶部，可向上超出边界）
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildInteractiveProgressBar(playerState, controller, colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建可交互的进度条
  Widget _buildInteractiveProgressBar(
    PlayerState playerState,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    // 显示的进度：拖动时显示拖动进度，否则显示实际播放进度
    final displayProgress = _isDragging ? _dragProgress : playerState.progress.clamp(0.0, 1.0);

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
          _dragProgress = playerState.progress.clamp(0.0, 1.0);
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
        setState(() {
          _isDragging = false;
          _isHovering = false;
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
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
                height: _isHovering || _isDragging ? 18 : 2,
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
                        duration: const Duration(milliseconds: 150),
                        height: _isHovering || _isDragging ? 6 : 2,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 已播放部分
                    Positioned(
                      left: 0,
                      width: constraints.maxWidth * displayProgress,
                      top: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: _isHovering || _isDragging ? 6 : 2,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 圆形指示器（悬停或拖动时显示）
                    if (_isHovering || _isDragging)
                      Positioned(
                        left: constraints.maxWidth * displayProgress - 6,
                        top: -3, // 使圆心对齐 6px 轨道中心
                        child: AnimatedOpacity(
                          opacity: _isHovering || _isDragging ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
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

  /// 顺序/乱序按钮（Mix 模式下禁用）
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
      tooltip: state.isMixMode
          ? t.audio.mixPlaylistNoAdd
          : (state.isShuffleEnabled ? t.player.shuffleOn : t.player.shuffleOff),
      visualDensity: VisualDensity.compact,
      onPressed: state.isMixMode ? null : () => controller.toggleShuffle(),
    );
  }

  /// 循环模式按钮
  Widget _buildLoopModeButton(
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    final (icon, tooltip) = switch (state.loopMode) {
      LoopMode.none => (Icons.repeat, t.player.loopOff),
      LoopMode.all => (Icons.repeat, t.player.loopAll),
      LoopMode.one => (Icons.repeat_one, t.player.loopOne),
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
    // 使用固定尺寸的 SizedBox 包装，确保加载和正常状态下大小一致
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
              onPressed: () => controller.togglePlayPause(),
            ),
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

  /// 音频输出设备选择器（仅桌面端）
  Widget _buildAudioDeviceSelector(
    BuildContext context,
    PlayerState state,
    AudioController controller,
    ColorScheme colorScheme,
  ) {
    final currentDevice = state.currentAudioDevice;
    final devices = state.audioDevices;

    // 计算菜单宽度以便居中对齐
    const menuWidth = 220.0;
    
    return MenuAnchor(
      consumeOutsideTap: true,
      // 向左偏移使菜单居中于图标，向上偏移使菜单显示在图标上方
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
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      menuChildren: [
        // 自动选项（跟随系统默认）
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
        // 设备列表
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

  /// 格式化设备名称
  String _formatDeviceName(AudioDevice device) {
    // 优先使用 description（人类可读名称），如果为空则使用 name
    final displayName = device.description.isNotEmpty ? device.description : device.name;
    
    // Windows 设备名称格式通常是 "喇叭 (设备名称)"，提取括号内的实际设备名
    // 但要排除像 "(R)" 这样的商标符号
    final match = RegExp(r'喇叭\s*\((.+)\)$').firstMatch(displayName);
    if (match != null) {
      return match.group(1) ?? displayName;
    }
    
    // 英文格式 "Speakers (Device Name)"
    final matchEn = RegExp(r'Speakers?\s*\((.+)\)$', caseSensitive: false).firstMatch(displayName);
    if (matchEn != null) {
      return matchEn.group(1) ?? displayName;
    }
    
    return displayName;
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
              getVolumeIcon(state.volume),
              size: 20,
            ),
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
            getVolumeIcon(state.volume),
            size: 20,
          ),
          visualDensity: VisualDensity.compact,
          tooltip: state.volume > 0 ? t.player.mute : t.player.unmute,
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
}
