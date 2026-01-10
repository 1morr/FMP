import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/track.dart';
import '../../../providers/download_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';

/// 已下载页面 - 显示分类网格
class DownloadedPage extends ConsumerWidget {
  const DownloadedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(downloadedCategoriesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('已下载'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleAppBarAction(context, ref, value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'play_all',
                child: ListTile(
                  leading: Icon(Icons.play_arrow),
                  title: Text('播放全部'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'shuffle_all',
                child: ListTile(
                  leading: Icon(Icons.shuffle),
                  title: Text('随机播放'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'download_manager',
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('下载管理'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
            ],
          ),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildCategoryGrid(context, ref, categories);
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
    WidgetRef ref,
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

  void _handleAppBarAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_all':
      case 'shuffle_all':
        final tracksAsync = ref.read(downloadedTracksProvider);
        final tracks = tracksAsync.valueOrNull ?? [];
        if (tracks.isEmpty) return;

        final controller = ref.read(audioControllerProvider.notifier);
        if (action == 'shuffle_all') {
          final shuffled = List<Track>.from(tracks)..shuffle();
          controller.addAllToQueue(shuffled);
        } else {
          controller.addAllToQueue(tracks);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加 ${tracks.length} 首歌曲到队列')),
          );
        }
        break;
      case 'download_manager':
        context.pushNamed(RouteNames.downloadManager);
        break;
    }
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
      final coverFile = File(category.coverPath!);
      if (coverFile.existsSync()) {
        return Image.file(
          coverFile,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) =>
              _buildDefaultCover(colorScheme),
        );
      }
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
}
