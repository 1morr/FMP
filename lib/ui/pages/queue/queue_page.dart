import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/track.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';
import '../../widgets/now_playing_indicator.dart';

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
    final queue = playerState.queue;
    final currentIndex = playerState.currentIndex ?? -1;
    final autoScroll = ref.watch(autoScrollToCurrentTrackProvider);

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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('队列已打乱')),
                );
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
                key: ValueKey(track.id),
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

    return Dismissible(
      key: ValueKey('dismiss_${track.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: colorScheme.errorContainer,
        child: Icon(
          Icons.delete,
          color: colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => onRemove(),
      child: ListTile(
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
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildThumbnail(colorScheme),
                  ),
                  if (isPlaying)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: colorScheme.primary.withValues(alpha: 0.8),
                      ),
                      child: const Center(
                        child: NowPlayingIndicator(
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
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
                _formatDuration(track.durationMs!),
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
      ),
    );
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildThumbnail(ColorScheme colorScheme) {
    // 已下载歌曲优先使用本地封面
    if (track.downloadedPath != null) {
      final dir = Directory(track.downloadedPath!).parent;
      final coverFile = File('${dir.path}/cover.jpg');
      if (coverFile.existsSync()) {
        return Image.file(
          coverFile,
          fit: BoxFit.cover,
          width: 48,
          height: 48,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(
              Icons.music_note,
              color: colorScheme.outline,
            ),
          ),
        );
      }
    }

    // 回退到网络封面
    if (track.thumbnailUrl != null) {
      return Image.network(
        track.thumbnailUrl!,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(
            Icons.music_note,
            color: colorScheme.outline,
          ),
        ),
      );
    }

    // 无封面时显示占位符
    return Center(
      child: Icon(
        Icons.music_note,
        color: colorScheme.outline,
      ),
    );
  }
}
