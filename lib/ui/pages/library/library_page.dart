import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../core/utils/icon_helpers.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/download/download_provider.dart';

import '../../../data/models/playlist.dart';
import '../../../providers/library/playlist_provider.dart';
import '../../../providers/search/refresh_provider.dart';
import '../../../services/library/playlist_service.dart';
import '../../router.dart';
import '../../widgets/menus/context_menu_region.dart';
import '../../widgets/feedback/error_display.dart';
import '../../widgets/images/playlist_cover_image.dart';
import '../../widgets/menus/playlist_card_actions.dart';
import '../../widgets/indicators/refresh_progress_indicator.dart';
import 'widgets/create_playlist_dialog.dart';
import 'widgets/import_playlist_dialog.dart';

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
    final coverMapAsync = ref.watch(playlistCoverMapProvider);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: state.playlists.length > 1 ? 112 : 56,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.download_done),
              tooltip: t.library.downloaded,
              onPressed: () async {
                ref.invalidate(downloadedCategoriesProvider);
                await ref.read(downloadedCategoriesProvider.future);
                if (context.mounted) {
                  context.pushNamed(RouteNames.downloaded);
                }
              },
            ),
            if (state.playlists.length > 1)
              IconButton(
                icon: Icon(
                  _isReorderMode ? Icons.check : Icons.swap_vert,
                  color: _isReorderMode ? colorScheme.primary : null,
                ),
                tooltip: _isReorderMode
                    ? t.library.main.finishSort
                    : t.library.main.sortPlaylists,
                onPressed: () {
                  if (_isReorderMode && _localPlaylists != null) {
                    // 退出排序模式時直接更新 provider 狀態，避免閃爍
                    ref
                        .read(playlistListProvider.notifier)
                        .updatePlaylistsOrder(_localPlaylists!);
                  }
                  setState(() {
                    _isReorderMode = !_isReorderMode;
                    if (!_isReorderMode) {
                      _localPlaylists = null;
                    }
                  });
                },
              ),
          ],
        ),
        title: Text(_isReorderMode ? t.library.main.sortMode : t.library.title),
        actions: [
          if (!_isReorderMode) ...[
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: t.library.main.newPlaylist,
              onPressed: () => _showCreateDialog(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: t.library.main.importPlaylist,
              onPressed: () => _showImportDialog(context, ref),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          state.isLoading && displayPlaylists.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : displayPlaylists.isEmpty
                  ? _buildEmptyState(context, ref)
                  : _isReorderMode
                      ? _buildReorderableGrid(
                          context,
                          ref,
                          displayPlaylists,
                          coverMapAsync,
                        )
                      : _buildPlaylistGrid(
                          context,
                          ref,
                          displayPlaylists,
                          coverMapAsync,
                        ),
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
    return ErrorDisplay.empty(
      icon: Icons.library_music,
      title: t.library.main.noPlaylists,
      message: t.library.main.noPlaylistsHint,
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add),
            label: Text(t.library.main.newPlaylist),
          ),
          OutlinedButton.icon(
            onPressed: () => _showImportDialog(context, ref),
            icon: const Icon(Icons.link),
            label: Text(t.library.main.importPlaylist),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistGrid(
    BuildContext context,
    WidgetRef ref,
    List<Playlist> playlists,
    AsyncValue<Map<int, PlaylistCoverData>> coverMapAsync,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      // 预加载视口外 500px 的卡片，减少快速滚动时封面图空白
      scrollCacheExtent: const ScrollCacheExtent.pixels(500),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: AppSizes.cardAspectRatio,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _PlaylistCard(
          key: ValueKey(playlist.id),
          playlist: playlist,
          coverAsync: _coverForPlaylist(coverMapAsync, playlist.id),
        );
      },
    );
  }

  Widget _buildReorderableGrid(
    BuildContext context,
    WidgetRef ref,
    List<Playlist> playlists,
    AsyncValue<Map<int, PlaylistCoverData>> coverMapAsync,
  ) {
    return ReorderableGridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: AppSizes.cardAspectRatio,
      ),
      dragStartDelay: Duration.zero, // 立即開始拖拽，無需長按
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return _ReorderablePlaylistCard(
          key: ValueKey(playlist.id),
          playlist: playlist,
          coverAsync: _coverForPlaylist(coverMapAsync, playlist.id),
        );
      },
      onReorder: (oldIndex, newIndex) async {
        final previousPlaylists = List<Playlist>.from(_localPlaylists!);
        final updatedPlaylists = List<Playlist>.from(_localPlaylists!);
        final item = updatedPlaylists.removeAt(oldIndex);
        updatedPlaylists.insert(newIndex, item);

        setState(() {
          _localPlaylists = updatedPlaylists;
        });

        try {
          await _savePlaylistOrder(updatedPlaylists);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _localPlaylists = previousPlaylists;
          });
        }
      },
    );
  }

  Future<void> _savePlaylistOrder(List<Playlist> playlists) async {
    final service = ref.read(playlistServiceProvider);
    await service.reorderPlaylists(playlists);
    // 不立即刷新 provider，避免閃爍
    // 退出排序模式時會刷新
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
      builder: (context) => const ImportPlaylistDialog(),
    );
  }
}

AsyncValue<PlaylistCoverData> _coverForPlaylist(
  AsyncValue<Map<int, PlaylistCoverData>> coverMapAsync,
  int playlistId,
) {
  return coverMapAsync.when(
    skipLoadingOnReload: true,
    data: (coverMap) => AsyncData<PlaylistCoverData>(
      coverMap[playlistId] ?? const PlaylistCoverData(),
    ),
    loading: () => const AsyncLoading<PlaylistCoverData>(),
    error: (error, stackTrace) => AsyncError<PlaylistCoverData>(
      error,
      stackTrace,
    ),
  );
}

/// 可拖拽的歌單卡片（排序模式下使用）
class _ReorderablePlaylistCard extends ConsumerWidget {
  final Playlist playlist;
  final AsyncValue<PlaylistCoverData> coverAsync;

  const _ReorderablePlaylistCard({
    super.key,
    required this.playlist,
    required this.coverAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

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
                      ? PlaylistCoverImage(
                          localPath: coverData.localPath,
                          networkUrl: coverData.networkUrl,
                          placeholder: const ImagePlaceholder.track(),
                          fit: BoxFit.cover,
                          width: 200,
                          variant: PlaylistCoverVariant.card,
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.tertiary,
                                    ),
                          ),
                        ] else ...[
                          if (playlist.isImported) ...[
                            Icon(
                              getImportSourceIcon(playlist.importSourceType),
                              size: 12,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            t.library.trackCount(n: playlist.trackCount),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
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
          // 拖拽指示器
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.7),
                borderRadius: AppRadius.borderRadiusSm,
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
  final AsyncValue<PlaylistCoverData> coverAsync;

  const _PlaylistCard({
    super.key,
    required this.playlist,
    required this.coverAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRefreshing = ref.watch(isPlaylistRefreshingProvider(playlist.id));

    return ContextMenuRegion(
      menuBuilder: (context) => _buildContextMenuItems(context, ref),
      onSelected: (value) => _handleContextMenuAction(context, ref, value),
      child: Card(
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
                          ? PlaylistCoverImage(
                              localPath: coverData.localPath,
                              networkUrl: coverData.networkUrl,
                              placeholder: const ImagePlaceholder.track(),
                              fit: BoxFit.cover,
                              width: 200,
                              variant: PlaylistCoverVariant.card,
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.tertiary,
                                    ),
                          ),
                        ] else ...[
                          if (playlist.isImported) ...[
                            Icon(
                              getImportSourceIcon(playlist.importSourceType),
                              size: 12,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            t.library.trackCount(n: playlist.trackCount),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
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
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildContextMenuItems(
      BuildContext context, WidgetRef ref) {
    final isRefreshing = ref.read(isPlaylistRefreshingProvider(playlist.id));
    return PlaylistCardActions.buildPopupMenuEntries(
      context: context,
      items: PlaylistCardActions.buildMenuItems(
        playlist: playlist,
        isRefreshing: isRefreshing,
      ),
    );
  }

  void _handleContextMenuAction(
      BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case PlaylistCardActions.actionPlayMix:
        _playMix(context, ref);
      case PlaylistCardActions.actionAddAll:
        _addAllToQueue(context, ref);
      case PlaylistCardActions.actionShuffleAdd:
        _shuffleAddToQueue(context, ref);
      case PlaylistCardActions.actionEdit:
        _showEditDialog(context, ref);
      case PlaylistCardActions.actionRefresh:
        _refreshPlaylist(context, ref);
      case PlaylistCardActions.actionDelete:
        _showDeleteConfirm(context, ref);
    }
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    final isRefreshing = ref.read(isPlaylistRefreshingProvider(playlist.id));
    final items = PlaylistCardActions.buildMenuItems(
      playlist: playlist,
      isRefreshing: isRefreshing,
    );

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlaylistCardActions.buildBottomSheetTiles(
              context: context,
              items: items,
              onSelected: (value) =>
                  _handleContextMenuAction(context, ref, value),
            ),
          ),
        ),
      ),
    );
  }

  void _addAllToQueue(BuildContext context, WidgetRef ref) async {
    await PlaylistCardActions.addAllToQueue(context, ref, playlist);
  }

  void _shuffleAddToQueue(BuildContext context, WidgetRef ref) async {
    await PlaylistCardActions.shuffleAddToQueue(context, ref, playlist);
  }

  Future<void> _playMix(BuildContext context, WidgetRef ref) async {
    await PlaylistCardActions.playMix(context, ref, playlist);
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

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.library.main.deletePlaylist),
        content:
            Text(t.library.main.deletePlaylistConfirm(name: playlist.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.general.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(playlistListProvider.notifier).deletePlaylist(playlist.id);
      if (context.mounted) {
        ToastService.success(context, t.library.main.playlistDeleted);
      }
    }
  }
}
