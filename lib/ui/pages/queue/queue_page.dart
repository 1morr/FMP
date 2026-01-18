import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';
import '../../widgets/track_thumbnail.dart';

/// 播放队列页
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage> {
  ScrollController? _scrollController;
  static const double _itemHeight = 72.0;
  bool _initialScrollDone = false;
  int? _lastCurrentIndex;

  /// 本地队列副本，用于解决拖拽时的闪烁问题
  List<Track>? _localQueue;
  int? _localCurrentIndex;

  @override
  void initState() {
    super.initState();
    _initScrollController();
  }

  void _initScrollController() {
    final autoScroll = ref.read(autoScrollToCurrentTrackProvider);
    final currentIndex = ref.read(audioControllerProvider).currentIndex ?? 0;

    if (autoScroll && currentIndex > 0) {
      // 估算初始滚动位置（稍微往上一点，之后会微调到 30% 位置）
      final initialOffset = (currentIndex * _itemHeight - 200).clamp(0.0, double.infinity);
      _scrollController = ScrollController(initialScrollOffset: initialOffset);
    } else {
      _scrollController = ScrollController();
    }
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  void _scrollToCurrentTrack(int currentIndex) {
    if (_scrollController == null || !_scrollController!.hasClients) return;

    final viewportHeight = _scrollController!.position.viewportDimension;
    final maxExtent = _scrollController!.position.maxScrollExtent;
    final targetOffset = currentIndex * _itemHeight - (viewportHeight * 0.3);

    _scrollController!.jumpTo(targetOffset.clamp(0.0, maxExtent));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);
    final providerQueue = playerState.queue;
    final providerCurrentIndex = playerState.currentIndex ?? -1;
    final autoScroll = ref.watch(autoScrollToCurrentTrackProvider);

    // 同步本地队列与provider
    // 当provider队列与本地队列内容一致时（只是顺序可能不同），不需要同步
    // 只有在长度变化或元素变化时才需要同步
    final providerIds = providerQueue.map((t) => t.id).toSet();
    final localIds = _localQueue?.map((t) => t.id).toSet();
    final needsSync = _localQueue == null ||
        providerQueue.length != _localQueue!.length ||
        !providerIds.containsAll(localIds ?? {}) ||
        !localIds!.containsAll(providerIds);

    if (needsSync) {
      _localQueue = List.from(providerQueue);
    }
    // 始终同步当前播放索引（不影响队列顺序）
    _localCurrentIndex = providerCurrentIndex;

    final queue = _localQueue!;
    final currentIndex = _localCurrentIndex ?? -1;

    // 首次渲染后微调到精确的 30% 位置
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToCurrentTrack(currentIndex);
        }
      });
    }
    _lastCurrentIndex = currentIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text('播放队列 (${queue.length})'),
        actions: [
          if (queue.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: '随机打乱',
              onPressed: () {
                ref.read(audioControllerProvider.notifier).shuffleQueue();
                ToastService.show(context, '队列已打乱');
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空队列',
              onPressed: () => _showClearQueueDialog(context),
            ),
          ],
        ],
      ),
      body: queue.isEmpty
          ? _buildEmptyState(context, colorScheme)
          : _buildQueueList(context, queue, currentIndex, colorScheme),
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
            '播放队列为空',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '添加歌曲到队列开始播放',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go(RoutePaths.search),
            icon: const Icon(Icons.search),
            label: const Text('去搜索'),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(
    BuildContext context,
    List<Track> queue,
    int currentIndex,
    ColorScheme colorScheme,
  ) {
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
                      '正在播放第 ${currentIndex + 1} 首',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${queue.length} 首',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // 队列列表
        Expanded(
          child: ReorderableListView.builder(
            scrollController: _scrollController!,
            itemCount: queue.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              // ReorderableListView 的 newIndex 在向下移动时需要减 1
              if (newIndex > oldIndex) newIndex--;
              if (oldIndex == newIndex) return;

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
            },
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final animValue = Curves.easeInOut.transform(animation.value);
                  final elevation = 1 + animValue * 8;
                  final scale = 1 + animValue * 0.02;
                  return Transform.scale(
                    scale: scale,
                    child: Material(
                      elevation: elevation,
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      child: child,
                    ),
                  );
                },
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final track = queue[index];
              final isPlaying = index == currentIndex;

              return SizedBox(
                key: ValueKey('queue_${index}_${track.id}'),
                height: _itemHeight,
                child: _QueueTrackTile(
                  track: track,
                  index: index,
                  isPlaying: isPlaying,
                  onTap: () => ref.read(audioControllerProvider.notifier).playAt(index),
                  onRemove: () => ref.read(audioControllerProvider.notifier).removeFromQueue(index),
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
        title: const Text('清空队列'),
        content: const Text('确定要清空播放队列吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(audioControllerProvider.notifier).clearQueue();
              Navigator.pop(context);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

/// 队列歌曲项
class _QueueTrackTile extends StatelessWidget {
  final Track track;
  final int index;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueTrackTile({
    required this.track,
    required this.index,
    required this.isPlaying,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽手柄
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            // 封面
            TrackThumbnail(
              track: track,
              size: 48,
              isPlaying: isPlaying,
            ),
          ],
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isPlaying ? colorScheme.primary : null,
            fontWeight: isPlaying ? FontWeight.w600 : null,
          ),
        ),
        subtitle: Text(
          track.artist ?? '未知艺术家',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (track.durationMs != null)
              Text(
                DurationFormatter.formatMs(track.durationMs!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            IconButton(
              icon: const Icon(Icons.close),
              iconSize: 20,
              color: colorScheme.outline,
              onPressed: onRemove,
              tooltip: '从队列移除',
            ),
          ],
        ),
        onTap: onTap,
      );
  }
}
