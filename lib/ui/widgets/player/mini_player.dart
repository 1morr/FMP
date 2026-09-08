import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/core/utils/platform_utils.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/ui/router.dart';
import 'package:fmp/ui/widgets/images/track_thumbnail.dart';
import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/core/utils/duration_formatter.dart';
import 'package:fmp/ui/widgets/player/mini_player_desktop_controls.dart';
import 'package:fmp/ui/widgets/player/mini_player_play_pause_button.dart';

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Semantics(
        button: true,
        label: t.player.openPlayer,
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
                            if (isDesktopPlatform)
                              const MiniPlayerDesktopControls(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 可交互的进度条（定位在顶部，RepaintBoundary 隔离高频重绘）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: RepaintBoundary(
                  child: _MiniPlayerProgressBar(isParentHovering: _isHovering),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 讀屏軟體按一次 increase / decrease 走多久。
const Duration _semanticsSeekStep = Duration(seconds: 5);

/// 把 0..1 的比例換成讀屏軟體念得出來的時間位置。
///
/// 播放頁的 `Slider` 用 `semanticFormatterCallback` 做同一件事；沒有它讀屏
/// 軟體念的是「50%」，而沒有人能從 50% 知道會跳到哪裡。
String _formatProgress(double progress, Duration duration) {
  if (duration <= Duration.zero) return '';
  return DurationFormatter.formatMs(
    (duration.inMilliseconds * progress.clamp(0.0, 1.0)).round(),
  );
}

/// 從 [progress] 往前／後移動 [step]，回傳新的比例。
double _shifted(double progress, Duration duration, Duration step) {
  if (duration <= Duration.zero) return progress;
  final delta = step.inMilliseconds / duration.inMilliseconds;
  return (progress + delta).clamp(0.0, 1.0);
}

/// 迷你播放器 - 进度条组件
class _MiniPlayerProgressBar extends ConsumerStatefulWidget {
  const _MiniPlayerProgressBar({required this.isParentHovering});

  final bool isParentHovering;

  @override
  ConsumerState<_MiniPlayerProgressBar> createState() =>
      _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState
    extends ConsumerState<_MiniPlayerProgressBar> {
  /// 是否正在拖动进度条
  bool _isDragging = false;

  /// 拖动时的临时进度值
  double _dragProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 只監聽進度與總長度。總長度是給讀屏軟體念出時間位置用的 —— 只有比例的話
    // 它會念「50%」，而進度條上有意義的是「1 分 23 秒 / 共 3 分 39 秒」。
    final playback = ref.watch(
      audioControllerProvider.select(
        (s) => (progress: s.progress, duration: s.duration),
      ),
    );
    final progress = playback.progress;
    // 還沒解析出總長度時當作零，`_formatProgress` 會回空字串 —— 讀屏軟體
    // 念得出「播放進度」這個標籤，只是暫時沒有值。
    final duration = playback.duration ?? Duration.zero;
    final controller = ref.read(audioControllerProvider.notifier);

    // 显示的进度：拖动时显示拖动进度，否则显示实际播放进度
    final displayProgress = _isDragging
        ? _dragProgress
        : progress.clamp(0.0, 1.0);

    // 是否应该展开：父组件悬停或正在拖动
    final isExpanded = widget.isParentHovering || _isDragging;

    // 這條進度條在觸控裝置上永遠只有 2dp 高（`isExpanded` 只有滑鼠停留或拖動
    // 時才為真），撐到 48dp 會蓋住整個迷你播放器。所以它不是靠加大命中區來變
    // 得可用，而是以 slider 語意存在：讀屏軟體用 increase / decrease 操作它，
    // 那兩個動作不受 tap target 尺寸規範約束。
    //
    // 兩層 GestureDetector 都排除語意：外層那個的 onTap 是空的（只為了擋住
    // 事件冒泡到「進入播放頁」），內層只有 onTapUp，但兩者都會讓 Flutter 掛
    // 上一個 2dp 高的可點節點。
    return Semantics(
      // 自己成一個節點。沒有 container 的話這些屬性會併進迷你播放器那個
      // 「進入播放頁」的按鈕節點，變成一個同時是 button 又是 slider、標籤是
      // 兩句話黏在一起的東西。
      container: true,
      slider: true,
      label: t.player.progressBar,
      value: _formatProgress(displayProgress, duration),
      increasedValue: _formatProgress(
        _shifted(displayProgress, duration, _semanticsSeekStep),
        duration,
      ),
      decreasedValue: _formatProgress(
        _shifted(displayProgress, duration, -_semanticsSeekStep),
        duration,
      ),
      onIncrease: () => controller.seekToProgress(
        _shifted(displayProgress, duration, _semanticsSeekStep),
      ),
      onDecrease: () => controller.seekToProgress(
        _shifted(displayProgress, duration, -_semanticsSeekStep),
      ),
      child: GestureDetector(
        excludeFromSemantics: true,
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
            final progress = (localPosition.dx / box.size.width).clamp(
              0.0,
              1.0,
            );
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
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final progress =
                      (details.localPosition.dx / constraints.maxWidth).clamp(
                        0.0,
                        1.0,
                      );
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
                                    color: colorScheme.shadow.withValues(
                                      alpha: 0.3,
                                    ),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
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
    final isPlaying = ref.watch(
      audioControllerProvider.select((s) => s.isPlaying),
    );
    final isBuffering = ref.watch(
      audioControllerProvider.select((s) => s.isBuffering),
    );
    final isLoading = ref.watch(
      audioControllerProvider.select((s) => s.isLoading),
    );
    final queueControls = ref.watch(queueControlStateProvider);
    final isShuffleEnabled = queueControls.isShuffleEnabled;
    final loopMode = queueControls.loopMode;
    final isMixMode = queueControls.isMixMode;
    final canPlayPrevious = queueControls.canPlayPrevious;
    final canPlayNext = queueControls.canPlayNext;

    final controller = ref.read(audioControllerProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顺序/乱序按钮
        IconButton(
          icon: const Icon(Icons.shuffle, size: 20),
          color: isShuffleEnabled ? colorScheme.primary : null,
          tooltip: isMixMode
              ? t.audio.mixPlaylistNoAdd
              : (isShuffleEnabled ? t.player.shuffleOn : t.player.shuffleOff),
          visualDensity: VisualDensity.compact,
          onPressed: isMixMode ? null : () => controller.toggleShuffle(),
        ),

        // 上一首按钮
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 24),
          tooltip: t.player.previous,
          visualDensity: VisualDensity.compact,
          onPressed: canPlayPrevious ? () => controller.previous() : null,
        ),

        // 播放/暂停按钮
        MiniPlayerPlayPauseButton(
          isPlaying: isPlaying,
          isLoading: isBuffering || isLoading,
          onPressed: () => controller.togglePlayPause(),
          tooltip: isPlaying ? t.general.pause : t.general.play,
        ),

        // 下一首按钮
        IconButton(
          icon: const Icon(Icons.skip_next, size: 24),
          tooltip: t.player.next,
          visualDensity: VisualDensity.compact,
          onPressed: canPlayNext ? () => controller.next() : null,
        ),

        // 循环模式按钮（與全螢幕播放器一致，置於最右）
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
      ],
    );
  }
}
