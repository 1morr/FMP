import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../providers/download_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';

/// 已下载页面 - 显示分类网格
class DownloadedPage extends ConsumerStatefulWidget {
  const DownloadedPage({super.key});

  @override
  ConsumerState<DownloadedPage> createState() => _DownloadedPageState();
}

class _DownloadedPageState extends ConsumerState<DownloadedPage> {
  @override
  void initState() {
    super.initState();
    // 进入页面时刷新数据
    Future.microtask(() {
      ref.invalidate(downloadedCategoriesProvider);
    });
  }

  Future<void> _refresh() async {
    // 刷新分类列表
    ref.invalidate(downloadedCategoriesProvider);
    await ref.read(downloadedCategoriesProvider.future);
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
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
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
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无已下载的歌曲',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '在歌曲菜单中选择"下载"来下载歌曲',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(
    BuildContext context,
    List<DownloadedCategory> categories,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 响应式网格列数 - 与音乐库页面相同
        final crossAxisCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : constraints.maxWidth > 400
                    ? 3
                    : 2;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            return _CategoryCard(category: categories[index]);
          },
        );
      },
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
    controller.addAllToQueue(tracksAsync);

    if (context.mounted) {
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
    controller.addAllToQueue(shuffled);

    if (context.mounted) {
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
