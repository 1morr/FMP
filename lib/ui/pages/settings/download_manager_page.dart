import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/download_task.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/download_settings_provider.dart';
import '../../../core/constants/ui_constants.dart';
import '../../widgets/error_display.dart';

/// 下载管理页面
class DownloadManagerPage extends ConsumerWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    final downloadService = ref.watch(downloadServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.downloadManager.title),
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
                      title: Text(t.settings.downloadManager.clearQueue),
                      content: Text(t.settings.downloadManager.clearQueueConfirm),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(t.general.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(t.general.confirm),
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
              PopupMenuItem(
                value: 'pause_all',
                child: ListTile(
                  leading: const Icon(Icons.pause),
                  title: Text(t.settings.downloadManager.pauseAll),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'resume_all',
                child: ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(t.settings.downloadManager.resumeAll),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'clear_completed',
                child: ListTile(
                  leading: const Icon(Icons.done_all),
                  title: Text(t.settings.downloadManager.clearCompleted),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'clear_queue',
                child: ListTile(
                  leading: const Icon(Icons.clear_all),
                  title: Text(t.settings.downloadManager.clearQueue),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(t.settings.downloadManager.loadFailed(error: '$error'))),
        data: (tasks) {
          if (tasks.isEmpty) {
            return ErrorDisplay.empty(
              icon: Icons.download_done,
              title: t.settings.downloadManager.noTasks,
              message: '',
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
                _SectionHeader(title: t.settings.downloadManager.downloading, count: downloading.length),
                _FixedHeightDownloadingSection(
                  tasks: downloading,
                  maxSlots: maxConcurrent,
                ),
              ],
              if (pending.isNotEmpty) ...[
                _SectionHeader(title: t.settings.downloadManager.waiting, count: pending.length),
                ...pending.map((task) => _DownloadTaskTile(task: task)),
              ],
              if (paused.isNotEmpty) ...[
                _SectionHeader(title: t.settings.downloadManager.paused, count: paused.length),
                ...paused.map((task) => _DownloadTaskTile(task: task)),
              ],
              if (failed.isNotEmpty) ...[
                _SectionHeader(title: t.settings.downloadManager.failed, count: failed.length),
                ...failed.map((task) => _DownloadTaskTile(task: task)),
              ],
              if (completed.isNotEmpty) ...[
                _SectionHeader(title: t.settings.downloadManager.completed, count: completed.length),
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
              borderRadius: AppRadius.borderRadiusLg,
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
      data: (track) => track?.title ?? t.settings.downloadManager.unknownTrack,
      orElse: () => t.general.loading,
    );
    final artist = trackAsync.maybeWhen(
      data: (track) => track?.artist ?? '',
      orElse: () => '',
    );

    return ListTile(
      leading: _buildStatusIcon(context),
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
              tooltip: t.settings.downloadManager.pause,
            ),
          if (task.isPaused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => downloadService.resumeTask(task.id),
              tooltip: t.settings.downloadManager.resume,
            ),
          // 重试按钮（失败时）
          if (task.isFailed)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => downloadService.retryTask(task.id),
              tooltip: t.settings.downloadManager.retry,
            ),
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => downloadService.cancelTask(task.id),
            tooltip: t.settings.downloadManager.delete,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    switch (task.status) {
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.pending:
        return Icon(Icons.hourglass_empty, color: colorScheme.tertiary);
      case DownloadStatus.paused:
        return Icon(Icons.pause_circle, color: colorScheme.outline);
      case DownloadStatus.completed:
        return Icon(Icons.check_circle, color: colorScheme.primary);
      case DownloadStatus.failed:
        return Icon(Icons.error, color: colorScheme.error);
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
