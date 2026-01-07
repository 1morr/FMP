import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/refresh_provider.dart';

/// 歌单刷新进度指示器组件
/// 显示在页面底部，展示所有正在刷新的歌单进度
class PlaylistRefreshProgress extends ConsumerWidget {
  const PlaylistRefreshProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshState = ref.watch(refreshManagerProvider);

    if (!refreshState.hasActiveRefresh) {
      return const SizedBox.shrink();
    }

    final activeRefreshList = refreshState.activeRefreshList;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 如果只有一个刷新任务，显示单行简洁视图
              if (activeRefreshList.length == 1)
                _buildSingleRefreshItem(context, activeRefreshList.first)
              // 如果有多个刷新任务，显示紧凑列表
              else
                _buildMultipleRefreshList(context, activeRefreshList),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSingleRefreshItem(
      BuildContext context, PlaylistRefreshState refreshState) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '正在刷新: ${refreshState.playlistName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (refreshState.total > 0)
                Text(
                  '${refreshState.current}/${refreshState.total}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: refreshState.progress > 0 ? refreshState.progress : null,
              backgroundColor: colorScheme.surfaceContainerLow,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              minHeight: 4,
            ),
          ),
          if (refreshState.currentItem != null) ...[
            const SizedBox(height: 4),
            Text(
              refreshState.currentItem!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMultipleRefreshList(
      BuildContext context, List<PlaylistRefreshState> refreshList) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '正在刷新 ${refreshList.length} 个歌单',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
        // 进度列表
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: refreshList.length,
            itemBuilder: (context, index) {
              final item = refreshList[index];
              return _buildCompactRefreshItem(context, item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompactRefreshItem(
      BuildContext context, PlaylistRefreshState refreshState) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  refreshState.playlistName,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: refreshState.progress > 0
                        ? refreshState.progress
                        : null,
                    backgroundColor: colorScheme.surfaceContainerLow,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (refreshState.total > 0)
            Text(
              '${refreshState.current}/${refreshState.total}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
        ],
      ),
    );
  }
}

/// 刷新状态提示组件（用于 Snackbar 等场景）
class RefreshResultSnackBar {
  static SnackBar success({
    required String playlistName,
    required int addedCount,
    required int skippedCount,
  }) {
    return SnackBar(
      content: Text(
        '$playlistName 刷新完成！'
        '${addedCount > 0 ? '新增 $addedCount 首' : '无新增'}'
        '${skippedCount > 0 ? '，跳过 $skippedCount 首' : ''}',
      ),
      duration: const Duration(seconds: 3),
    );
  }

  static SnackBar error({
    required String playlistName,
    required String errorMessage,
  }) {
    return SnackBar(
      content: Text('$playlistName 刷新失败: $errorMessage'),
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.red[700],
    );
  }
}
