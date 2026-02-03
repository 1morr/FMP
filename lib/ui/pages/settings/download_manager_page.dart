import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/download_task.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/download_settings_provider.dart';

/// 下载管理页面
class DownloadManagerPage extends ConsumerWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    final downloadService = ref.watch(downloadServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          // 批量操作菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'pause_all':
                  await downloadService.pauseAll();
                  break;
                case 'resume_all':
                  await downloadService.resumeAll();
                  break;
                case 'clear_completed':
                  await downloadService.clearCompleted();
                  break;
                case 'clear_queue':
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('清空队列'),
                      content: const Text('确定要清空所有下载任务吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await downloadService.clearQueue();
                    await downloadService.clearCompleted();
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'pause_all',
                child: ListTile(
                  leading: Icon(Icons.pause),
                  title: Text('全部暂停'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'resume_all',
                child: ListTile(
                  leading: Icon(Icons.play_arrow),
                  title: Text('全部继续'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear_completed',
                child: ListTile(
                  leading: Icon(Icons.done_all),
                  title: Text('清除已完成'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear_queue',
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('清空队列'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('加载失败: $error')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_done, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('没有下载任务', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          // 按状态分组
          final downloading = tasks.where((t) => t.isDownloading).toList();
          final pending = tasks.where((t) => t.isPending).toList();
          final paused = tasks.where((t) => t.isPaused).toList();
          final failed = tasks.where((t) => t.isFailed).toList();
          final completed = tasks.where((t) => t.isCompleted).toList();

          // 获取最大并发下载数，用于固定"正在下载"区域高度
          final maxConcurrent = ref.watch(maxConcurrentDownloadsProvider);

          return ListView(
            children: [
              if (downloading.isNotEmpty || pending.isNotEmpty) ...[
                _SectionHeader(title: '正在下载', count: downloading.length),
                _FixedHeightDownloadingSection(
                  tasks: downloading,
                  maxSlots: maxConcurrent,
                ),
              ],
              if (pending.isNotEmpty) ...[
                _SectionHeader(title: '等待中', count: pending.length),
                ...pending.map((task) => _DownloadTaskTile(task: task)),
              ],
              if (paused.isNotEmpty) ...[
                _SectionHeader(title: '已暂停', count: paused.length),
                ...paused.map((task) => _DownloadTaskTile(task: task)),
              ],
              if (failed.isNotEmpty) ...[
                _SectionHeader(title: '失败', count: failed.length),
                ...failed.map((task) => _DownloadTaskTile(task: task)),
              ],
              if (completed.isNotEmpty) ...[
                _SectionHeader(title: '已完成', count: completed.length),
                ...completed.map((task) => _DownloadTaskTile(task: task)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 固定高度的正在下载区域
/// 根据 maxConcurrentDownloads 设置固定高度，避免下方内容跳动
class _FixedHeightDownloadingSection extends ConsumerWidget {
  final List<DownloadTask> tasks;
  final int maxSlots;

  // 每个 ListTile 的估算高度（包括进度条和边距）
  static const double _tileHeight = 88.0;

  const _FixedHeightDownloadingSection({
    required this.tasks,
    required this.maxSlots,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixedHeight = _tileHeight * maxSlots;

    return SizedBox(
      height: fixedHeight,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: maxSlots,
        itemBuilder: (context, index) {
          if (index < tasks.length) {
            return _DownloadTaskTile(task: tasks[index]);
          }
          // 空槽位占位符
          return SizedBox(height: _tileHeight);
        },
      ),
    );
  }
}

/// 区域标题
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 下载任务项
class _DownloadTaskTile extends ConsumerWidget {
  final DownloadTask task;

  const _DownloadTaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadService = ref.watch(downloadServiceProvider);
    final trackAsync = ref.watch(trackByIdProvider(task.trackId));
    
    // 从内存中获取实时进度（如果有的话）
    final progressState = ref.watch(downloadProgressStateProvider);
    final memProgress = progressState[task.id];
    
    // 优先使用内存中的进度，否则使用数据库中的进度
    final progress = memProgress?.$1 ?? task.progress;
    final downloadedBytes = memProgress?.$2 ?? task.downloadedBytes;
    final totalBytes = memProgress?.$3 ?? task.totalBytes;
    
    final title = trackAsync.maybeWhen(
      data: (track) => track?.title ?? '未知歌曲',
      orElse: () => '加载中...',
    );
    final artist = trackAsync.maybeWhen(
      data: (track) => track?.artist ?? '',
      orElse: () => '',
    );

    return ListTile(
      leading: _buildStatusIcon(),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (artist.isNotEmpty)
            Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (task.isDownloading || task.isPending) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 2),
            Text(
              _buildProgressText(progress, downloadedBytes, totalBytes),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          if (task.isFailed && task.errorMessage != null)
            Text(
              task.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 暂停/继续按钮
          if (task.isDownloading || task.isPending)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () => downloadService.pauseTask(task.id),
              tooltip: '暂停',
            ),
          if (task.isPaused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => downloadService.resumeTask(task.id),
              tooltip: '继续',
            ),
          // 重试按钮（失败时）
          if (task.isFailed)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => downloadService.retryTask(task.id),
              tooltip: '重试',
            ),
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => downloadService.cancelTask(task.id),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.pending:
        return const Icon(Icons.hourglass_empty, color: Colors.orange);
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.grey);
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  String _buildProgressText(double progress, int downloadedBytes, int? totalBytes) {
    final percentText = '${(progress * 100).toStringAsFixed(1)}%';
    if (totalBytes != null && totalBytes > 0) {
      final downloaded = _formatBytes(downloadedBytes);
      final total = _formatBytes(totalBytes);
      return '$downloaded / $total ($percentText)';
    }
    return percentText;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }
}
