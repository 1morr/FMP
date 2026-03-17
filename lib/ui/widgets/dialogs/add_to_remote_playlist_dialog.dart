import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/logger.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../data/sources/bilibili_source.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/refresh_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../services/account/bilibili_favorites_service.dart';
import 'add_to_youtube_playlist_dialog.dart';
import '../track_thumbnail.dart';

/// 顯示添加到遠程收藏夾對話框（自動路由到對應平台）
Future<bool> showAddToRemotePlaylistDialog({
  required BuildContext context,
  required Track track,
}) async {
  return showAddToRemotePlaylistDialogMulti(context: context, tracks: [track]);
}

/// 顯示添加到遠程收藏夾對話框（多首歌曲，自動路由到對應平台）
Future<bool> showAddToRemotePlaylistDialogMulti({
  required BuildContext context,
  required List<Track> tracks,
}) async {
  if (tracks.isEmpty) return false;

  final sourceType = tracks.first.sourceType;
  switch (sourceType) {
    case SourceType.bilibili:
      return _showBilibiliSheet(context, tracks);
    case SourceType.youtube:
      return showAddToYouTubePlaylistDialog(context: context, tracks: tracks);
  }
}

/// Bilibili 收藏夾 sheet
Future<bool> _showBilibiliSheet(BuildContext context, List<Track> tracks) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _BilibiliRemoteFavSheet(tracks: tracks),
  );
  return result ?? false;
}

class _BilibiliRemoteFavSheet extends ConsumerStatefulWidget {
  final List<Track> tracks;
  const _BilibiliRemoteFavSheet({required this.tracks});

  @override
  ConsumerState<_BilibiliRemoteFavSheet> createState() =>
      _BilibiliRemoteFavSheetState();
}

class _BilibiliRemoteFavSheetState extends ConsumerState<_BilibiliRemoteFavSheet> {
  List<BilibiliFavFolder>? _folders;
  Set<int> _selectedIds = {};
  Set<int> _originalIds = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _submitProgress;
  final _newFolderController = TextEditingController();

  List<Track> get _tracks => widget.tracks;
  bool get _isMulti => _tracks.length > 1;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _newFolderController.dispose();
    super.dispose();
  }

  Future<void> _showCreateFolderDialog() async {
    bool isPrivate = false;
    final result = await showDialog<({String name, bool isPrivate})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t.remote.createFolder),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _newFolderController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: t.remote.folderNameHint,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context,
                        (name: value.trim(), isPrivate: isPrivate));
                  }
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(t.remote.privacyPublic),
                    icon: const Icon(Icons.public, size: 18),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(t.remote.privacyPrivate),
                    icon: const Icon(Icons.lock, size: 18),
                  ),
                ],
                selected: {isPrivate},
                onSelectionChanged: (v) =>
                    setDialogState(() => isPrivate = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.general.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = _newFolderController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context,
                      (name: name, isPrivate: isPrivate));
                }
              },
              child: Text(t.general.confirm),
            ),
          ],
        ),
      ),
    );

    _newFolderController.clear();

    if (result != null && mounted) {
      try {
        final favService = ref.read(bilibiliFavoritesServiceProvider);
        final folder = await favService.createFavFolder(
          title: result.name,
          isPrivate: result.isPrivate,
        );
        if (!mounted) return;
        setState(() {
          _folders?.insert(0, folder);
          _selectedIds.add(folder.id);
        });
      } on BilibiliFavoritesException catch (e) {
        if (!mounted) return;
        ToastService.error(context, e.message);
      } catch (e) {
        if (!mounted) return;
        ToastService.error(context, e.toString());
      }
    }
  }

  Future<void> _loadFolders() async {
    try {
      final favService = ref.read(bilibiliFavoritesServiceProvider);
      // 用第一首歌查詢收藏夾狀態（多選時不標記已收藏狀態）
      final aid = _isMulti ? null : await favService.getVideoAid(_tracks.first);
      final folders = await favService.getFavFolders(videoAid: aid);

      if (!mounted) return;
      final original = <int>{};
      if (!_isMulti) {
        for (final f in folders) {
          if (f.isFavorited) original.add(f.id);
        }
      }
      setState(() {
        _folders = folders;
        _originalIds = original;
        _selectedIds = Set.from(original);
        _isLoading = false;
      });
    } on BilibiliFavoritesException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _submit() async {
    final toAdd = _selectedIds.difference(_originalIds).toList();
    final toRemove = _originalIds.difference(_selectedIds).toList();

    if (toAdd.isEmpty && toRemove.isEmpty) {
      ToastService.show(context, t.remote.noChanges);
      Navigator.pop(context, false);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final favService = ref.read(bilibiliFavoritesServiceProvider);

      for (var i = 0; i < _tracks.length; i++) {
        final track = _tracks[i];
        if (_isMulti && mounted) {
          setState(() {
            _submitProgress = '${i + 1}/${_tracks.length}';
          });
        }
        final aid = await favService.getVideoAid(track);
        await favService.updateVideoFavorites(
          videoAid: aid,
          addFolderIds: toAdd,
          removeFolderIds: toRemove,
        );
      }

      // 同步本地歌單
      await _syncLocalPlaylists(toAdd, toRemove);

      if (!mounted) return;
      ToastService.success(context, t.remote.updated);
      Navigator.pop(context, true);
    } on BilibiliFavoritesException catch (e) {
      if (!mounted) return;
      ToastService.error(context, e.message);
      setState(() {
        _isSubmitting = false;
        _submitProgress = null;
      });
    } catch (e) {
      if (!mounted) return;
      ToastService.error(context, e.toString());
      setState(() {
        _isSubmitting = false;
        _submitProgress = null;
      });
    }
  }

  /// 同步本地歌單：遠程移除→本地也移除，然後觸發重新整理
  Future<void> _syncLocalPlaylists(List<int> toAdd, List<int> toRemove) async {
    final service = ref.read(playlistServiceProvider);
    final playlists = await service.getAllPlaylists();
    final changedFolderIds = {...toAdd, ...toRemove};
    final sourceIds = _tracks.map((t) => t.sourceId).toList();

    AppLogger.info('Syncing local playlists: toAdd=$toAdd, toRemove=$toRemove, '
        'tracks=${sourceIds.length}, local playlists count=${playlists.length}', 'RemoteFav');

    for (final playlist in playlists) {
      if (playlist.importSourceType != SourceType.bilibili ||
          playlist.sourceUrl == null) {
        continue;
      }
      final fid = BilibiliSource.parseFavoritesId(playlist.sourceUrl!);
      if (fid == null) continue;
      final fidInt = int.tryParse(fid);

      if (fidInt == null || !changedFolderIds.contains(fidInt)) continue;

      AppLogger.info('Matched playlist "${playlist.name}" (id=${playlist.id}) '
          'with folder $fidInt', 'RemoteFav');

      // 遠程移除 → 先從本地歌單移除（即時 UI 反饋）
      if (toRemove.contains(fidInt)) {
        try {
          final trackRepo = ref.read(trackRepositoryProvider);
          final playlistSvc = ref.read(playlistServiceProvider);
          final tracks = await trackRepo.getBySourceIds(sourceIds);
          final matchingIds = tracks
              .where((t) =>
                  t.sourceType == _tracks.first.sourceType &&
                  t.belongsToPlaylist(playlist.id))
              .map((t) => t.id)
              .toList();
          if (matchingIds.isNotEmpty) {
            await playlistSvc.removeTracksFromPlaylist(
                playlist.id, matchingIds);
            AppLogger.info('Removed ${matchingIds.length} tracks from local playlist', 'RemoteFav');
          }
        } catch (e) {
          AppLogger.error('Failed to remove from local playlist: $e', 'RemoteFav');
        }
      }

      // 觸發歌單重新整理（從遠端重新拉取同步）
      try {
        AppLogger.info('Triggering refresh for playlist "${playlist.name}"', 'RemoteFav');
        ref.read(refreshManagerProvider.notifier).refreshPlaylist(playlist);
      } catch (e) {
        AppLogger.error('Failed to trigger refresh: $e', 'RemoteFav');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 拖拽指示條
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: AppRadius.borderRadiusXs,
              ),
            ),
            // 標題
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(t.remote.dialogTitle,
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            // 歌曲信息
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusLg,
              ),
              child: _isMulti
                  ? Row(
                      children: [
                        Icon(Icons.music_note, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          '${_tracks.length} ${t.remote.tracksCount}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        TrackThumbnail(
                          track: _tracks.first,
                          size: AppSizes.thumbnailMedium,
                          borderRadius: 4,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _tracks.first.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _tracks.first.artist ?? '',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: colorScheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            // 新建收藏夾
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                  child: Icon(
                    Icons.add,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(t.remote.createFolder),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusLg,
                ),
                onTap: _isSubmitting ? null : _showCreateFolderDialog,
              ),
            ),
            const Divider(),
            // 收藏夾列表
            Expanded(child: _buildFolderList(colorScheme, scrollController)),
            // 確認按鈕
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting || _isLoading ? null : _submit,
                    child: _isSubmitting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                              if (_submitProgress != null) ...[
                                const SizedBox(width: 8),
                                Text(_submitProgress!,
                                    style: const TextStyle(color: Colors.white)),
                              ],
                            ],
                          )
                        : Text(_getButtonText()),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFolderList(
      ColorScheme colorScheme, ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_errorMessage!,
              style: TextStyle(color: colorScheme.error),
              textAlign: TextAlign.center),
        ),
      );
    }
    final folders = _folders;
    if (folders == null || folders.isEmpty) {
      return Center(child: Text(t.remote.loading));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        final isSelected = _selectedIds.contains(folder.id);

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusMd,
              color: colorScheme.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: folder.coverUrl != null
                ? ImageLoadingService.loadImage(
                    networkUrl: folder.coverUrl,
                    placeholder: Icon(
                      folder.isDefault ? Icons.star : Icons.folder_outlined,
                      color: colorScheme.outline,
                    ),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    targetDisplaySize: 40,
                  )
                : Icon(
                    folder.isDefault ? Icons.star : Icons.folder_outlined,
                    color: colorScheme.outline,
                  ),
          ),
          title: Text(folder.title),
          subtitle: Text('${folder.mediaCount}'),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: colorScheme.primary)
              : Icon(Icons.circle_outlined, color: colorScheme.outline),
          selected: isSelected,
          selectedTileColor:
              colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusLg),
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(folder.id);
              } else {
                _selectedIds.add(folder.id);
              }
            });
          },
        );
      },
    );
  }

  String _getButtonText() {
    final toAdd = _selectedIds.difference(_originalIds);
    final toRemove = _originalIds.difference(_selectedIds);
    if (toAdd.isEmpty && toRemove.isEmpty) return t.remote.confirm;
    if (toAdd.isNotEmpty && toRemove.isEmpty) {
      return t.remote.addToCount(count: toAdd.length.toString());
    }
    return t.remote.confirm;
  }
}
