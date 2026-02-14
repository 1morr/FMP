import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';
import '../../../i18n/strings.g.dart';
import '../../widgets/track_thumbnail.dart';

/// 播放队列页
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage> {
  /// 用于快速跳转到指定索引
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  static const double _itemHeight = AppSizes.queueItemHeight;
  bool _initialScrollDone = false;
  int? _lastCurrentIndex;

  /// 本地队列副本，用于解决拖拽时的闪烁问题
  List<Track>? _localQueue;
  int? _localCurrentIndex;
  int? _lastQueueVersion;

  /// 拖拽状态
  int? _draggingIndex;
  int? _dragTargetIndex;

  /// 是否在顶部区域（用于切换跳转按钮方向）
  bool _isNearTop = true;

  @override
  void initState() {
    super.initState();
    // 监听滚动位置，判断是否在顶部区域
    _itemPositionsListener.itemPositions.addListener(_onPositionsChanged);
  }

  void _onPositionsChanged() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // 找到最小索引（最靠近顶部的可见项）
    final minIndex = positions.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    final isNearTop = minIndex <= 2; // 前3项视为顶部区域

    if (_isNearTop != isNearTop) {
      setState(() {
        _isNearTop = isNearTop;
      });
    }
  }

  /// 跳转到顶部或底部
  void _scrollToTopOrBottom(int queueLength) {
    if (!_itemScrollController.isAttached || queueLength == 0) return;

    if (_isNearTop) {
      // 在顶部，跳转到底部
      _itemScrollController.jumpTo(
        index: queueLength - 1,
        alignment: 0.7,
      );
    } else {
      // 不在顶部，跳转到顶部
      _itemScrollController.jumpTo(index: 0);
    }
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onPositionsChanged);
    super.dispose();
  }

  /// 智能滚动到当前播放的歌曲
  /// - 如果已在可视范围内，不滚动
  /// - 如果是小范围移动（如顺序下一首），只滚动到刚好可见
  /// - 如果是大范围跳转（如随机播放），跳转到视口中央偏上位置
  void _scrollToCurrentTrack(int currentIndex, {int? previousIndex}) {
    if (!_itemScrollController.isAttached) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      // 没有可见项信息，直接跳转
      _itemScrollController.jumpTo(index: currentIndex, alignment: 0.3);
      return;
    }

    // 检查当前项是否大部分可见（允许 20% 被遮挡）
    final currentPosition = positions.where((p) => p.index == currentIndex).firstOrNull;
    if (currentPosition != null) {
      final visibleRatio = (currentPosition.itemTrailingEdge.clamp(0, 1) - 
                           currentPosition.itemLeadingEdge.clamp(0, 1));
      if (visibleRatio >= 0.8) {
        // 80% 以上可见，不需要滚动
        return;
      }
    }

    // 获取当前可见范围
    final visibleIndices = positions.map((p) => p.index).toList();
    final minVisible = visibleIndices.reduce((a, b) => a < b ? a : b);
    final maxVisible = visibleIndices.reduce((a, b) => a > b ? a : b);

    // 判断是小范围移动还是大范围跳转
    final prevIdx = previousIndex ?? currentIndex;
    final distance = (currentIndex - prevIdx).abs();
    // 如果目标在可见范围内，或距离小于等于3，视为小范围移动
    final isInVisibleRange = currentIndex >= minVisible && currentIndex <= maxVisible;
    final isSmallMove = isInVisibleRange || distance <= 3;

    const smallMoveDuration = Duration(milliseconds: 50);

    if (isSmallMove) {
      // 小范围移动：平滑滚动到刚好可见
      if (currentIndex > maxVisible) {
        // 目标在下方，滚动到底部可见（留出迷你播放器空间）
        _itemScrollController.scrollTo(
          index: currentIndex,
          alignment: 0.88,
          duration: smallMoveDuration,
        );
      } else if (currentIndex < minVisible) {
        // 目标在上方，滚动到顶部可见
        _itemScrollController.scrollTo(
          index: currentIndex,
          alignment: 0.0,
          duration: smallMoveDuration,
        );
      }
      // 如果在可见范围内但大部分被遮挡，做小幅调整
      else if (currentPosition != null) {
        final visibleRatio = (currentPosition.itemTrailingEdge.clamp(0, 1) - 
                             currentPosition.itemLeadingEdge.clamp(0, 1));
        if (visibleRatio < 0.8) {
          if (currentPosition.itemLeadingEdge < 0) {
            _itemScrollController.scrollTo(
              index: currentIndex,
              alignment: 0.0,
              duration: smallMoveDuration,
            );
          } else if (currentPosition.itemTrailingEdge > 1) {
            _itemScrollController.scrollTo(
              index: currentIndex,
              alignment: 0.88,
              duration: smallMoveDuration,
            );
          }
        }
      }
    } else {
      // 大范围跳转：瞬间跳转到视口中央偏上位置
      _itemScrollController.jumpTo(index: currentIndex, alignment: 0.3);
    }
  }

  /// 处理拖拽开始
  void _onDragStart(int index) {
    setState(() {
      _draggingIndex = index;
      _dragTargetIndex = index;
    });
  }

  /// 处理拖拽更新（悬停在某个项目上）
  void _onDragUpdate(int targetIndex) {
    if (_dragTargetIndex != targetIndex) {
      setState(() {
        _dragTargetIndex = targetIndex;
      });
    }
  }

  /// 处理拖拽结束
  void _onDragEnd() {
    final oldIndex = _draggingIndex;
    final newIndex = _dragTargetIndex;

    setState(() {
      _draggingIndex = null;
      _dragTargetIndex = null;
    });

    if (oldIndex == null || newIndex == null || oldIndex == newIndex) return;

    // 先更新本地状态（同步），避免闪烁
    setState(() {
      final track = _localQueue!.removeAt(oldIndex);
      _localQueue!.insert(newIndex, track);

      // 调整本地当前索引
      final localIdx = _localCurrentIndex;
      if (localIdx != null) {
        if (oldIndex == localIdx) {
          _localCurrentIndex = newIndex;
        } else if (oldIndex < localIdx && newIndex >= localIdx) {
          _localCurrentIndex = localIdx - 1;
        } else if (oldIndex > localIdx && newIndex <= localIdx) {
          _localCurrentIndex = localIdx + 1;
        }
      }
    });

    // 然后同步到 provider（异步）
    ref.read(audioControllerProvider.notifier).moveInQueue(oldIndex, newIndex);
  }

  /// 处理拖拽取消
  void _onDragCancel() {
    setState(() {
      _draggingIndex = null;
      _dragTargetIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);
    final providerQueue = playerState.queue;
    final providerCurrentIndex = playerState.currentIndex ?? -1;
    final autoScroll = ref.watch(autoScrollToCurrentTrackProvider);

    // 同步本地队列与provider
    final queueVersion = playerState.queueVersion;
    final needsSync = _localQueue == null || _lastQueueVersion != queueVersion;

    if (needsSync) {
      _localQueue = List.from(providerQueue);
      _lastQueueVersion = queueVersion;
    }
    _localCurrentIndex = providerCurrentIndex;

    final queue = _localQueue!;
    final currentIndex = _localCurrentIndex ?? -1;

    // 首次渲染后跳转到当前播放位置
    if (autoScroll && !_initialScrollDone && currentIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_initialScrollDone) {
          _initialScrollDone = true;
          _scrollToCurrentTrack(currentIndex);
        }
      });
    }

    // 切歌时自动滚动
    if (autoScroll && _lastCurrentIndex != null && _lastCurrentIndex != currentIndex && currentIndex >= 0) {
      final prevIndex = _lastCurrentIndex!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToCurrentTrack(currentIndex, previousIndex: prevIndex);
        }
      });
    }
    _lastCurrentIndex = currentIndex;

    final isMixMode = playerState.isMixMode;
    final mixTitle = playerState.mixTitle;
    final isLoadingMoreMix = playerState.isLoadingMoreMix;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 56,
        leading: queue.isNotEmpty
            ? IconButton(
                icon: Icon(_isNearTop ? Icons.vertical_align_bottom : Icons.vertical_align_top),
                tooltip: _isNearTop ? t.queue.scrollToBottom : t.queue.scrollToTop,
                onPressed: () => _scrollToTopOrBottom(queue.length),
              )
            : null,
        title: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
              child: Text(
                isMixMode
                    ? 'Mix · ${mixTitle ?? ''}'
                    : t.queue.titleWithCount(count: '${queue.length}'),
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
        actions: [
          if (queue.isNotEmpty) ...[
            if (!isMixMode)
              IconButton(
                icon: const Icon(Icons.shuffle),
                tooltip: t.queue.shuffle,
                onPressed: () {
                  ref.read(audioControllerProvider.notifier).shuffleQueue();
                  ToastService.success(context, t.queue.shuffled);
                },
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: t.queue.clear,
              onPressed: () => _showClearQueueDialog(context),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: queue.isEmpty
          ? _buildEmptyState(context, colorScheme)
          : _buildQueueList(
              context,
              queue,
              currentIndex,
              colorScheme,
              isMixMode: isMixMode,
              isLoadingMoreMix: isLoadingMoreMix,
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            t.queue.emptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            t.queue.emptySubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go(RoutePaths.search),
            icon: const Icon(Icons.search),
            label: Text(t.queue.goSearch),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(
    BuildContext context,
    List<Track> queue,
    int currentIndex,
    ColorScheme colorScheme, {
    required bool isMixMode,
    required bool isLoadingMoreMix,
  }) {
    // Mix 模式下在底部添加加载指示器
    final hasBottomIndicator = isMixMode;
    final itemCount = hasBottomIndicator ? queue.length + 1 : queue.length;

    return Column(
      children: [
        // 当前播放提示 - 可点击跳转
        if (currentIndex >= 0 && currentIndex < queue.length)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _scrollToCurrentTrack(currentIndex),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Row(
                  children: [
                    Icon(
                      Icons.play_circle_filled,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.queue.nowPlaying(index: '${currentIndex + 1}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      t.queue.totalCount(count: '${queue.length}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // 队列列表 - 使用 ScrollablePositionedList 实现快速跳转
        Expanded(
          child: ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: itemCount,
            // 添加 addAutomaticKeepAlives 减少重建
            addAutomaticKeepAlives: true,
            itemBuilder: (context, index) {
              // 底部指示器（Mix 模式下显示加载动画或留白）
              if (index == queue.length) {
                return SizedBox(
                  key: const ValueKey('queue_bottom_indicator'),
                  height: 48,
                  child: isLoadingMoreMix
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                );
              }

              final track = queue[index];
              final isPlaying = index == currentIndex;
              final isDragging = _draggingIndex == index;
              final isDragTarget = _dragTargetIndex == index && _draggingIndex != null && _draggingIndex != index;

              // 使用 RepaintBoundary 隔离重绘
              return RepaintBoundary(
                child: _DraggableQueueItem(
                  key: ValueKey('queue_${track.id}_$index'),
                  track: track,
                  index: index,
                  isPlaying: isPlaying,
                  isDragging: isDragging,
                  isDragTarget: isDragTarget,
                  itemHeight: _itemHeight,
                  onTap: () => ref.read(audioControllerProvider.notifier).playAt(index),
                  onRemove: () => ref.read(audioControllerProvider.notifier).removeFromQueue(index),
                  onDragStart: () => _onDragStart(index),
                  onDragUpdate: _onDragUpdate,
                  onDragEnd: _onDragEnd,
                  onDragCancel: _onDragCancel,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showClearQueueDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.queue.clear),
        content: Text(t.queue.clearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(audioControllerProvider.notifier).clearQueue();
              Navigator.pop(context);
            },
            child: Text(t.queue.clearButton),
          ),
        ],
      ),
    );
  }
}

/// 可拖拽的队列项 - 简化结构，减少嵌套
class _DraggableQueueItem extends StatelessWidget {
  final Track track;
  final int index;
  final bool isPlaying;
  final bool isDragging;
  final bool isDragTarget;
  final double itemHeight;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onDragStart;
  final void Function(int) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  const _DraggableQueueItem({
    super.key,
    required this.track,
    required this.index,
    required this.isPlaying,
    required this.isDragging,
    required this.isDragTarget,
    required this.itemHeight,
    required this.onTap,
    required this.onRemove,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 构建列表项内容（复用于正常显示和拖拽反馈）
    Widget buildTileContent({bool isFeedback = false}) {
      return SizedBox(
        height: itemHeight,
        child: Material(
          color: isFeedback ? colorScheme.surfaceContainerHigh : Colors.transparent,
          elevation: isFeedback ? 8 : 0,
          borderRadius: isFeedback ? AppRadius.borderRadiusLg : null,
          child: InkWell(
            onTap: isFeedback ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [

                  // 封面
                  TrackThumbnail(
                    track: track,
                    size: 48,
                    isPlaying: isPlaying,
                  ),
                  const SizedBox(width: 12),
                  // 标题和艺术家
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: isPlaying ? colorScheme.primary : colorScheme.onSurface,
                            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist ?? t.general.unknownArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 时长
                  if (track.durationMs != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        DurationFormatter.formatMs(track.durationMs!),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  // 删除按钮
                  if (!isFeedback)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: colorScheme.outline,
                      onPressed: onRemove,
                      tooltip: t.queue.removeFromQueue,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        onDragUpdate(index);
        return true;
      },
      onAcceptWithDetails: (details) {
        onDragEnd();
      },
      builder: (context, candidateData, rejectedData) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽目标指示器（显示在项目上方）
            if (isDragTarget)
              Container(
                height: 2,
                color: colorScheme.primary,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
            // 实际的列表项
            LongPressDraggable<int>(
              data: index,
              delay: AnimationDurations.fast, // 缩短长按延迟
              onDragStarted: onDragStart,
              onDraggableCanceled: (_, __) => onDragCancel(),
              feedback: SizedBox(
                width: MediaQuery.of(context).size.width - 32,
                child: buildTileContent(isFeedback: true),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: buildTileContent(),
              ),
              child: buildTileContent(),
            ),
          ],
        );
      },
    );
  }
}
