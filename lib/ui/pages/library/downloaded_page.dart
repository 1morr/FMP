import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/download_path_provider.dart';
import '../../../providers/download/file_exists_cache.dart';
import '../../../providers/playlist_provider.dart' show allPlaylistsProvider, playlistDetailProvider;
import '../../../services/audio/audio_provider.dart';
import '../../../services/download/download_path_sync_service.dart';
import '../../router.dart';

/// 已下载页面 - 显示分类网格
class DownloadedPage extends ConsumerStatefulWidget {
  const DownloadedPage({super.key});

  @override
  ConsumerState<DownloadedPage> createState() => _DownloadedPageState();
}

class _DownloadedPageState extends ConsumerState<DownloadedPage> {
  // initState 中不再強制刷新，因為導航前已經預加載了數據
  // 這避免了"先顯示舊封面再顯示新封面"的閃爍問題

  Future<void> _syncLocalFiles() async {
    final syncService = ref.read(downloadPathSyncServiceProvider);

    if (!mounted) return;

    final result = await showDialog<(int, int)?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SyncProgressDialog(syncService: syncService),
    );

    if (result != null && mounted) {
      final (added, removed) = result;
      // 刷新分类列表
      ref.invalidate(downloadedCategoriesProvider);

      if (added > 0 || removed > 0) {
        // 刷新文件存在性缓存
        ref.invalidate(fileExistsCacheProvider);
        // 刷新所有歌单详情（因为 track 的 downloadPaths 已更新）
        final playlists = await ref.read(allPlaylistsProvider.future);
        for (final playlist in playlists) {
          ref.invalidate(playlistDetailProvider(playlist.id));
        }
      }

      if (!mounted) return;

      final message = StringBuffer('同步完成');
      if (added > 0) {
        message.write(': 添加 $added 首');
      }
      if (removed > 0) {
        message.write(added > 0 ? ', ' : ': ');
        message.write('移除 $removed 首');
      }
      if (added == 0 && removed == 0) {
        message.write(': 无变化');
      }
      ToastService.show(context, message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(downloadedCategoriesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('已下载'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: '同步本地文件',
            onPressed: _syncLocalFiles,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '下载管理',
            onPressed: () => context.pushNamed(RouteNames.downloadManager),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('加载失败: $error'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _syncLocalFiles,
                icon: const Icon(Icons.sync),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildCategoryGrid(context, categories);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_done,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              '暂无已下载的歌曲',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '在歌曲菜单中选择"下载"来下载歌曲',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid(
    BuildContext context,
    List<DownloadedCategory> categories,
  ) {
    // 使用 maxCrossAxisExtent 实现平滑缩放，与音乐库页面一致
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        return _CategoryCard(category: categories[index]);
      },
    );
  }
}

/// 同步进度对话框
class _SyncProgressDialog extends StatefulWidget {
  final DownloadPathSyncService syncService;

  const _SyncProgressDialog({required this.syncService});

  @override
  State<_SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<_SyncProgressDialog> {
  int _current = 0;
  int _total = 0;
  String _status = '正在扫描...';
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _executeSync();
  }

  Future<void> _executeSync() async {
    try {
      final (added, removed) = await widget.syncService.syncLocalFiles(
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _current = current;
              _total = total;
              _status = '正在扫描 ($current/$total)...';
            });
          }
        },
      );

      if (mounted) {
        Navigator.pop(context, (added, removed));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '同步失败: $e';
          _isComplete = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('同步本地文件'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isComplete)
            CircularProgressIndicator(
              value: _total > 0 ? _current / _total : null,
            ),
          const SizedBox(height: 16),
          Text(_status),
        ],
      ),
      actions: _isComplete
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ]
          : null,
    );
  }
}

/// 分类卡片
class _CategoryCard extends ConsumerWidget {
  final DownloadedCategory category;

  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // 使用 Future.microtask 延迟导航，避免在 LayoutBuilder 布局期间触发导航
          final cat = category;
          Future.microtask(() {
            if (context.mounted) {
              context.push(
                '${RoutePaths.downloaded}/${Uri.encodeComponent(cat.folderName)}',
                extra: cat,
              );
            }
          });
        },
        onLongPress: () => _showOptionsMenu(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域
            Expanded(
              child: _buildCover(colorScheme),
            ),

            // 信息
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.download_done,
                        size: 12,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${category.trackCount} 首',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(ColorScheme colorScheme) {
    if (category.coverPath != null) {
      return ImageLoadingService.loadImage(
        localPath: category.coverPath,
        networkUrl: null,
        placeholder: _buildDefaultCover(colorScheme),
        fit: BoxFit.cover,
      );
    }
    return _buildDefaultCover(colorScheme);
  }

  Widget _buildDefaultCover(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.tertiaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.folder,
          size: 48,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('添加所有'),
                onTap: () {
                  Navigator.pop(context);
                  _addAllToQueue(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.shuffle),
                title: const Text('随机添加'),
                onTap: () {
                  Navigator.pop(context);
                  _shuffleAddToQueue(context, ref);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text('删除整个分类', style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirm(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addAllToQueue(BuildContext context, WidgetRef ref) async {
    final tracksAsync = await ref.read(downloadedCategoryTracksProvider(category.folderPath).future);

    if (tracksAsync.isEmpty) {
      if (context.mounted) {
        ToastService.show(context, '分类为空');
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(tracksAsync);

    if (added && context.mounted) {
      ToastService.show(context, '已添加 ${tracksAsync.length} 首歌曲到队列');
    }
  }

  void _shuffleAddToQueue(BuildContext context, WidgetRef ref) async {
    final tracksAsync = await ref.read(downloadedCategoryTracksProvider(category.folderPath).future);

    if (tracksAsync.isEmpty) {
      if (context.mounted) {
        ToastService.show(context, '分类为空');
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(tracksAsync)..shuffle();
    final added = await controller.addAllToQueue(shuffled);

    if (added && context.mounted) {
      ToastService.show(context, '已随机添加 ${tracksAsync.length} 首歌曲到队列');
    }
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('确定要删除 "${category.displayName}" 的所有下载文件吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteCategory(context, ref);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCategory(BuildContext context, WidgetRef ref) async {
    try {
      // 获取分类中的所有歌曲
      final tracks = await ref.read(downloadedCategoryTracksProvider(category.folderPath).future);
      final trackRepo = ref.read(trackRepositoryProvider);

      // 清除每首歌的下载路径
      for (final track in tracks) {
        await trackRepo.clearDownloadPath(track.id);
      }

      // 删除整个文件夹
      final folder = Directory(category.folderPath);
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }

      // 刷新分类列表
      ref.invalidate(downloadedCategoriesProvider);

      if (context.mounted) {
        ToastService.show(context, '已删除 "${category.displayName}"');
      }
    } catch (e) {
      if (context.mounted) {
        ToastService.show(context, '删除失败: $e');
      }
    }
  }
}
