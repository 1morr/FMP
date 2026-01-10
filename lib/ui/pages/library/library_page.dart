import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/playlist.dart';
import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/refresh_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';
import '../../widgets/refresh_progress_indicator.dart';
import 'widgets/create_playlist_dialog.dart';
import 'widgets/import_url_dialog.dart';

/// 音乐库页
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playlistListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.download_done),
          tooltip: '已下载',
          onPressed: () => context.pushNamed(RouteNames.downloaded),
        ),
        title: const Text('音乐库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: '从 URL 导入',
            onPressed: () => _showImportDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建歌单',
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      body: Stack(
        children: [
          state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.playlists.isEmpty
                  ? _buildEmptyState(context, ref)
                  : _buildPlaylistGrid(context, ref, state.playlists),
          // 刷新进度指示器固定在底部
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PlaylistRefreshProgress(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_music,
              size: 80,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              '暂无歌单',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '创建你的第一个歌单或从 B站 导入收藏夹',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('新建歌单'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _showImportDialog(context, ref),
                  icon: const Icon(Icons.link),
                  label: const Text('从 URL 导入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistGrid(
    BuildContext context,
    WidgetRef ref,
    List<Playlist> playlists,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 响应式网格列数
        final crossAxisCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
                ? 4
                : constraints.maxWidth > 400
                    ? 3
                    : 2;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            return _PlaylistCard(playlist: playlists[index]);
          },
        );
      },
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const CreatePlaylistDialog(),
    );
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const ImportUrlDialog(),
    );
  }
}

/// 歌单卡片
class _PlaylistCard extends ConsumerWidget {
  final Playlist playlist;

  const _PlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverAsync = ref.watch(playlistCoverProvider(playlist.id));
    final isRefreshing = ref.watch(isPlaylistRefreshingProvider(playlist.id));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // 使用 Future.microtask 延迟导航，避免在 LayoutBuilder 布局期间触发导航
          final id = playlist.id;
          Future.microtask(() {
            if (context.mounted) {
              context.push('${RoutePaths.library}/$id');
            }
          });
        },
        onLongPress: () => _showOptionsMenu(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面 - 使用 Expanded 填充剩余空间
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  coverAsync.when(
                    data: (coverUrl) => coverUrl != null
                        ? Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return _buildPlaceholder(colorScheme);
                            },
                            errorBuilder: (context, error, stackTrace) =>
                                _buildPlaceholder(colorScheme),
                          )
                        : _buildPlaceholder(colorScheme),
                    loading: () => _buildPlaceholder(colorScheme),
                    error: (error, stack) => _buildPlaceholder(colorScheme),
                  ),
                  // 刷新指示器覆盖层
                  if (isRefreshing)
                    Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 信息
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (playlist.isImported) ...[
                        Icon(
                          Icons.link,
                          size: 12,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '${playlist.trackCount} 首',
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

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: 48,
          color: colorScheme.outline,
        ),
      ),
    );
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRefreshing = ref.read(isPlaylistRefreshingProvider(playlist.id));

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
              leading: const Icon(Icons.edit),
              title: const Text('编辑歌单'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(context, ref);
              },
            ),
            if (playlist.isImported)
              ListTile(
                leading: isRefreshing
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(colorScheme.primary),
                        ),
                      )
                    : const Icon(Icons.refresh),
                title: Text(isRefreshing ? '正在刷新...' : '刷新歌单'),
                enabled: !isRefreshing,
                onTap: isRefreshing
                    ? null
                    : () {
                        Navigator.pop(context);
                        _refreshPlaylist(context, ref);
                      },
              ),
            ListTile(
              leading: Icon(Icons.delete, color: colorScheme.error),
              title: Text('删除歌单', style: TextStyle(color: colorScheme.error)),
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
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('歌单为空')),
        );
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    controller.addAllToQueue(result.tracks);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${result.tracks.length} 首歌曲到队列')),
      );
    }
  }

  void _shuffleAddToQueue(BuildContext context, WidgetRef ref) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('歌单为空')),
        );
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(result.tracks)..shuffle();
    controller.addAllToQueue(shuffled);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已随机添加 ${result.tracks.length} 首歌曲到队列')),
      );
    }
  }

  void _refreshPlaylist(BuildContext context, WidgetRef ref) {
    // 提示会在 RefreshManagerNotifier 中通过 ToastService 显示
    // 不需要在这里处理，因为大歌单刷新时间长，context 可能已失效
    ref.read(refreshManagerProvider.notifier).refreshPlaylist(playlist);
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => CreatePlaylistDialog(playlist: playlist),
    );
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定要删除 "${playlist.name}" 吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(playlistListProvider.notifier)
                  .deletePlaylist(playlist.id);
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
}
