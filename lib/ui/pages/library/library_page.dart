import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../providers/download_provider.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../data/sources/source_provider.dart';
import '../../../core/services/toast_service.dart';
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
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  /// 是否處於排序模式
  bool _isReorderMode = false;

  /// 本地排序狀態（用於拖拽時的即時反饋）
  List<Playlist>? _localPlaylists;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistListProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // 同步本地狀態
    if (!_isReorderMode) {
      _localPlaylists = null;
    } else if (_localPlaylists == null && !state.isLoading) {
      _localPlaylists = List.from(state.playlists);
    }

    final displayPlaylists = _localPlaylists ?? state.playlists;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.download_done),
          tooltip: '已下载',
          onPressed: () async {
            ref.invalidate(downloadedCategoriesProvider);
            await ref.read(downloadedCategoriesProvider.future);
            if (context.mounted) {
              context.pushNamed(RouteNames.downloaded);
            }
          },
        ),
        title: Text(_isReorderMode ? '拖拽排序' : '音乐库'),
        actions: [
          // 排序模式按鈕
          if (state.playlists.length > 1)
            IconButton(
              icon: Icon(
                _isReorderMode ? Icons.check : Icons.swap_vert,
                color: _isReorderMode ? colorScheme.primary : null,
              ),
              tooltip: _isReorderMode ? '完成排序' : '排序歌单',
              onPressed: () {
                setState(() {
                  _isReorderMode = !_isReorderMode;
                  if (!_isReorderMode) {
                    _localPlaylists = null;
                  }
                });
              },
            ),
          if (!_isReorderMode) ...[
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
        ],
      ),
      body: Stack(
        children: [
          state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : displayPlaylists.isEmpty
                  ? _buildEmptyState(context, ref)
                  : _isReorderMode
                      ? _buildReorderableGrid(context, ref, displayPlaylists)
                      : _buildPlaylistGrid(context, ref, displayPlaylists),
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        return _PlaylistCard(playlist: playlists[index]);
      },
    );
  }

  Widget _buildReorderableGrid(
    BuildContext context,
    WidgetRef ref,
    List<Playlist> playlists,
  ) {
    return ReorderableGridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      dragStartDelay: Duration.zero, // 立即開始拖拽，無需長按
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _ReorderablePlaylistCard(
          key: ValueKey(playlist.id),
          playlist: playlist,
        );
      },
      onReorder: (oldIndex, newIndex) {
        setState(() {
          final item = _localPlaylists!.removeAt(oldIndex);
          _localPlaylists!.insert(newIndex, item);
        });
        // 異步保存到數據庫
        _savePlaylistOrder();
      },
    );
  }

  Future<void> _savePlaylistOrder() async {
    if (_localPlaylists == null) return;

    final service = ref.read(playlistServiceProvider);
    await service.reorderPlaylists(_localPlaylists!);
    // 刷新 provider
    ref.invalidate(playlistListProvider);
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

/// 可拖拽的歌單卡片（排序模式下使用）
class _ReorderablePlaylistCard extends ConsumerWidget {
  final Playlist playlist;

  const _ReorderablePlaylistCard({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverAsync = ref.watch(playlistCoverProvider(playlist.id));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              Expanded(
                child: coverAsync.when(
                  skipLoadingOnReload: true,
                  data: (coverData) => coverData.hasCover
                      ? ImageLoadingService.loadImage(
                          localPath: coverData.localPath,
                          networkUrl: coverData.networkUrl,
                          placeholder: const ImagePlaceholder.track(),
                          fit: BoxFit.cover,
                        )
                      : const ImagePlaceholder.track(),
                  loading: () => const ImagePlaceholder.track(),
                  error: (error, stack) => const ImagePlaceholder.track(),
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
                    Text(
                      '${playlist.trackCount} 首',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 拖拽指示器
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.drag_handle,
                size: 20,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
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

    // 預加載歌單詳情數據，這樣進入詳情頁時數據已經準備好
    ref.read(playlistDetailProvider(playlist.id));

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
                    skipLoadingOnReload: true,
                    data: (coverData) => coverData.hasCover
                        ? ImageLoadingService.loadImage(
                            localPath: coverData.localPath,
                            networkUrl: coverData.networkUrl,
                            placeholder: const ImagePlaceholder.track(),
                            fit: BoxFit.cover,
                          )
                        : const ImagePlaceholder.track(),
                    loading: () => const ImagePlaceholder.track(),
                    error: (error, stack) => const ImagePlaceholder.track(),
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
                      if (playlist.isMix) ...[
                        Icon(
                          Icons.radio,
                          size: 12,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Mix',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.tertiary,
                              ),
                        ),
                      ] else ...[
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
              // Mix播放列表显示不同的菜单
              if (playlist.isMix) ...[
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('播放Mix'),
                  onTap: () {
                    Navigator.pop(context);
                    _playMix(context, ref);
                  },
                ),
              ] else ...[
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
              ],
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑歌单'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(context, ref);
                },
              ),
              // 刷新选项仅对导入的非Mix歌单显示
              if (playlist.isImported && !playlist.isMix)
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
        ToastService.show(context, '歌单为空');
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(result.tracks);
    
    if (added && context.mounted) {
      ToastService.show(context, '已添加 ${result.tracks.length} 首歌曲到队列');
    }
  }

  void _shuffleAddToQueue(BuildContext context, WidgetRef ref) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ToastService.show(context, '歌单为空');
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(result.tracks)..shuffle();
    final added = await controller.addAllToQueue(shuffled);
    
    if (added && context.mounted) {
      ToastService.show(context, '已随机添加 ${result.tracks.length} 首歌曲到队列');
    }
  }

  Future<void> _playMix(BuildContext context, WidgetRef ref) async {
    if (playlist.mixPlaylistId == null || playlist.mixSeedVideoId == null) {
      ToastService.show(context, 'Mix信息不完整');
      return;
    }

    try {
      // 获取 Mix 的初始 tracks
      final youtubeSource = ref.read(youtubeSourceProvider);
      final result = await youtubeSource.fetchMixTracks(
        playlistId: playlist.mixPlaylistId!,
        currentVideoId: playlist.mixSeedVideoId!,
      );

      if (result.tracks.isEmpty) {
        if (context.mounted) {
          ToastService.show(context, '无法加载Mix内容');
        }
        return;
      }

      // 播放 Mix
      final controller = ref.read(audioControllerProvider.notifier);
      await controller.playMixPlaylist(
        playlistId: playlist.mixPlaylistId!,
        seedVideoId: playlist.mixSeedVideoId!,
        title: playlist.name,
        tracks: result.tracks,
      );
    } catch (e) {
      if (context.mounted) {
        ToastService.show(context, '播放Mix失败: $e');
      }
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
