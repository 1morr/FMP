import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/logger.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/remote_playlist_sync_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../services/account/bilibili_favorites_service.dart';
import '../track_thumbnail.dart';

Future<bool> showAddToBilibiliPlaylistDialog({
  required BuildContext context,
  required List<Track> tracks,
}) async {
  if (tracks.isEmpty) return false;
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

class _BilibiliRemoteFavSheetState
    extends ConsumerState<_BilibiliRemoteFavSheet> {
  List<BilibiliFavFolder>? _folders;
  Set<int> _selectedIds = {};
  Set<int> _originalIds = {};
  Set<int> _partialIds = {};
  final Set<int> _deselectedPartialIds = {};
  bool _isLoading = true;
  bool _isCheckingMulti = false;
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
                    Navigator.pop(
                      context,
                      (name: value.trim(), isPrivate: isPrivate),
                    );
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
                  Navigator.pop(context, (name: name, isPrivate: isPrivate));
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
      } catch (_) {
        if (!mounted) return;
        ToastService.error(context, t.remote.error.unknown(code: 'UNKNOWN'));
      }
    }
  }

  Future<void> _loadFolders() async {
    try {
      final favService = ref.read(bilibiliFavoritesServiceProvider);

      if (_isMulti) {
        final folders = await favService.getFavFolders();
        if (!mounted) return;
        setState(() {
          _folders = folders;
          _isLoading = false;
          _isCheckingMulti = true;
        });
        _checkMultiFavStatusAsync(folders);
      } else {
        final aid = await favService.getVideoAid(_tracks.first);
        final folders = await favService.getFavFolders(videoAid: aid);
        if (!mounted) return;
        final original = <int>{};
        for (final folder in folders) {
          if (folder.isFavorited) original.add(folder.id);
        }
        setState(() {
          _folders = folders;
          _originalIds = original;
          _selectedIds = Set.from(original);
          _isLoading = false;
        });
      }
    } on BilibiliFavoritesException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = t.remote.error.unknown(code: 'LOAD');
      });
    }
  }

  Future<void> _checkMultiFavStatusAsync(
    List<BilibiliFavFolder> folders,
  ) async {
    final favService = ref.read(bilibiliFavoritesServiceProvider);
    final folderIds = folders.map((folder) => folder.id).toSet();
    final favCounts = <int, int>{};

    final aids = await Future.wait(
      _tracks.map((track) async {
        try {
          return await favService.getVideoAid(track);
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;

    for (final aid in aids) {
      if (aid == null) continue;
      try {
        final trackFolders = await favService.getFavFolders(videoAid: aid);
        if (!mounted) return;
        for (final folder in trackFolders) {
          if (folder.isFavorited && folderIds.contains(folder.id)) {
            favCounts[folder.id] = (favCounts[folder.id] ?? 0) + 1;
          }
        }
      } catch (_) {
        // A single folder status lookup failure should not block the dialog.
      }
    }

    if (!mounted) return;
    final trackCount = _tracks.length;
    final original = <int>{};
    final partial = <int>{};
    for (final entry in favCounts.entries) {
      if (entry.value >= trackCount) {
        original.add(entry.key);
      } else if (entry.value > 0) {
        partial.add(entry.key);
      }
    }
    setState(() {
      _originalIds = original;
      _partialIds = partial;
      _selectedIds = Set.from(original);
      _isCheckingMulti = false;
    });
  }

  ({List<int> toAdd, List<int> toRemove}) _computeChanges() {
    final toAdd =
        _selectedIds.difference(_originalIds).difference(_partialIds).toList();
    final toRemove = [
      ..._originalIds.difference(_selectedIds),
      ..._deselectedPartialIds,
    ];
    return (toAdd: toAdd, toRemove: toRemove);
  }

  Future<void> _submit() async {
    final (:toAdd, :toRemove) = _computeChanges();

    if (toAdd.isEmpty && toRemove.isEmpty) {
      ToastService.show(context, t.remote.noChanges);
      Navigator.pop(context, false);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final favService = ref.read(bilibiliFavoritesServiceProvider);

      for (var i = 0; i < _tracks.length; i++) {
        if (!mounted) return;
        final track = _tracks[i];
        if (_isMulti) {
          setState(() => _submitProgress = '${i + 1}/${_tracks.length}');
        }
        final aid = await favService.getVideoAid(track);
        await favService.updateVideoFavorites(
          videoAid: aid,
          addFolderIds: toAdd,
          removeFolderIds: toRemove,
        );
      }

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
    } catch (_) {
      if (!mounted) return;
      ToastService.error(context, t.remote.error.unknown(code: 'UNKNOWN'));
      setState(() {
        _isSubmitting = false;
        _submitProgress = null;
      });
    }
  }

  Future<void> _syncLocalPlaylists(List<int> toAdd, List<int> toRemove) async {
    final changedFolderIds = {...toAdd, ...toRemove};
    final syncService = ref.read(remotePlaylistSyncServiceProvider);
    final matchingPlaylists = await syncService.findMatchingImportedPlaylists(
      sourceType: SourceType.bilibili,
      remotePlaylistIds: changedFolderIds.map((id) => id.toString()),
    );

    AppLogger.info(
      'Syncing local playlists: toAdd=$toAdd, toRemove=$toRemove, '
          'tracks=${_tracks.length}, matched playlists=${matchingPlaylists.length}',
      'RemoteFav',
    );

    if (toRemove.isNotEmpty) {
      final sourceIds = _tracks.map((track) => track.sourceId).toList();
      final trackRepo = ref.read(trackRepositoryProvider);
      final localTracks = await trackRepo.getBySourceIds(sourceIds);
      final playlistSvc = ref.read(playlistServiceProvider);

      for (final playlist in matchingPlaylists) {
        try {
          final matchingIds = localTracks
              .where(
                (track) =>
                    track.sourceType == SourceType.bilibili &&
                    track.belongsToPlaylist(playlist.id),
              )
              .map((track) => track.id)
              .toList();
          if (matchingIds.isEmpty) continue;
          await playlistSvc.removeTracksFromPlaylist(playlist.id, matchingIds);
          AppLogger.info(
            'Removed ${matchingIds.length} tracks from local playlist',
            'RemoteFav',
          );
        } catch (e) {
          AppLogger.error(
            'Failed to remove from local playlist: $e',
            'RemoteFav',
          );
        }
      }
    }

    await syncService.refreshMatchingImportedPlaylists(
      sourceType: SourceType.bilibili,
      remotePlaylistIds: changedFolderIds.map((id) => id.toString()),
      playlists: matchingPlaylists,
    );
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
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: AppRadius.borderRadiusXs,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    t.remote.dialogTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
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
                                      color: colorScheme.onSurfaceVariant,
                                    ),
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
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                clipBehavior: Clip.hardEdge,
                child: _buildFolderList(colorScheme, scrollController),
              ),
            ),
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              if (_submitProgress != null) ...[
                                const SizedBox(width: 8),
                                Text(_submitProgress!),
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
    ColorScheme colorScheme,
    ScrollController scrollController,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _errorMessage!,
            style: TextStyle(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
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
        final isPartial = !isSelected &&
            _partialIds.contains(folder.id) &&
            !_deselectedPartialIds.contains(folder.id);

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
          trailing: _isCheckingMulti
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : isSelected
                  ? Icon(Icons.check_circle, color: colorScheme.primary)
                  : isPartial
                      ? Icon(
                          Icons.remove_circle_outline,
                          color: colorScheme.primary,
                        )
                      : Icon(Icons.circle_outlined, color: colorScheme.outline),
          selected: isSelected || isPartial,
          selectedTileColor:
              colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusLg,
          ),
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(folder.id);
                if (_partialIds.contains(folder.id)) {
                  _deselectedPartialIds.add(folder.id);
                }
              } else if (isPartial) {
                _selectedIds.add(folder.id);
              } else if (_deselectedPartialIds.contains(folder.id)) {
                _deselectedPartialIds.remove(folder.id);
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
    final (:toAdd, :toRemove) = _computeChanges();
    if (toAdd.isEmpty && toRemove.isEmpty) return t.remote.confirm;
    if (toAdd.isNotEmpty && toRemove.isEmpty) {
      return t.remote.addToCount(count: toAdd.length.toString());
    }
    return t.remote.confirm;
  }
}
