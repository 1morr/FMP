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
import '../../../i18n/strings.g.dart';
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

      final message = StringBuffer(t.library.downloadedPage.syncComplete);
      if (added > 0) {
        message.write(': ${t.library.downloadedPage.syncAdded(n: added)}');
      }
      if (removed > 0) {
        message.write(added > 0 ? ', ' : ': ');
        message.write(t.library.downloadedPage.syncRemoved(n: removed));
      }
      if (added == 0 && removed == 0) {
        message.write(': ${t.library.downloadedPage.syncNoChanges}');
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
        title: Text(t.library.downloaded),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: t.library.downloadedPage.syncLocalFiles,
            onPressed: _syncLocalFiles,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: t.library.downloadedPage.downloadManager,
            onPressed: () => context.pushNamed(RouteNames.downloadManager),
          ),
          const SizedBox(width: 8),
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
              Text(t.library.loadFailedWithError(error: error.toString())),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _syncLocalFiles,
                icon: const Icon(Icons.sync),
                label: Text(t.library.retry),
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
              t.library.downloadedPage.noDownloads,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              t.library.downloadedPage.noDownloadsHint,
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
  String _status = t.library.downloadedPage.scanning;
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
              _status = t.library.downloadedPage.scanningProgress(current: current, total: total);
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
          _status = t.library.downloadedPage.syncFailed(error: e.toString());
          _isComplete = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.library.downloadedPage.syncLocalFiles),
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
                child: Text(t.general.close),
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
                        t.library.trackCount(n: category.trackCount),
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
                title: Text(t.library.addAll),
                onTap: () {
                  Navigator.pop(context);
                  _addAllToQueue(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.shuffle),
                title: Text(t.library.shuffleAdd),
                onTap: () {
                  Navigator.pop(context);
                  _shuffleAddToQueue(context, ref);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text(t.library.downloadedPage.deleteCategory, style: TextStyle(color: colorScheme.error)),
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
        ToastService.warning(context, t.library.main.categoryEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(tracksAsync);

    if (added && context.mounted) {
      ToastService.success(context, t.library.addedToQueue(n: tracksAsync.length));
    }
  }

  void _shuffleAddToQueue(BuildContext context, WidgetRef ref) async {
    final tracksAsync = await ref.read(downloadedCategoryTracksProvider(category.folderPath).future);

    if (tracksAsync.isEmpty) {
      if (context.mounted) {
        ToastService.warning(context, t.library.main.categoryEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(tracksAsync)..shuffle();
    final added = await controller.addAllToQueue(shuffled);

    if (added && context.mounted) {
      ToastService.success(context, t.library.shuffledAddedToQueue(n: tracksAsync.length));
    }
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.library.downloadedPage.deleteCategoryTitle),
        content: Text(t.library.downloadedPage.deleteCategoryConfirm(name: category.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteCategory(context, ref);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.general.delete),
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
        ToastService.success(context, t.library.downloadedPage.categoryDeleted(name: category.displayName));
      }
    } catch (e) {
      if (context.mounted) {
        ToastService.error(context, t.library.downloadedPage.deleteFailed(error: e.toString()));
      }
    }
  }
}
