import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/remote_playlist_sync_provider.dart';
import '../../../services/account/netease_playlist_service.dart';
import '../../../services/library/remote_playlist_selection_changes.dart';
import 'remote_playlist_dialog_widgets.dart';

Future<bool> showAddToNeteasePlaylistDialog({
  required BuildContext context,
  required List<Track> tracks,
}) async {
  if (tracks.isEmpty) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _NeteasePlaylistSheet(tracks: tracks),
  );
  return result ?? false;
}

class _NeteasePlaylistSheet extends ConsumerStatefulWidget {
  final List<Track> tracks;
  const _NeteasePlaylistSheet({required this.tracks});

  @override
  ConsumerState<_NeteasePlaylistSheet> createState() =>
      _NeteasePlaylistSheetState();
}

class _NeteasePlaylistSheetState extends ConsumerState<_NeteasePlaylistSheet> {
  List<NeteasePlaylistInfo>? _playlists;
  final Set<String> _selectedIds = {};
  final Set<String> _originalIds = {};
  final Set<String> _partialIds = {};
  final Set<String> _deselectedPartialIds = {};
  final Map<String, Set<String>> _existingTrackIdsByPlaylist = {};
  bool _isLoading = true;
  bool _isCheckingMulti = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _submitProgress;
  final _newPlaylistController = TextEditingController();

  List<Track> get _tracks => widget.tracks;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaylists() async {
    try {
      final service = ref.read(neteasePlaylistServiceProvider);
      final playlists = await service.getWritablePlaylists();

      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });

      if (playlists.isNotEmpty) {
        setState(() => _isCheckingMulti = true);
        _checkMembershipAsync(playlists);
      }
    } on NeteasePlaylistException catch (e) {
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

  Future<void> _checkMembershipAsync(
    List<NeteasePlaylistInfo> playlists,
  ) async {
    final service = ref.read(neteasePlaylistServiceProvider);
    final trackIds = _tracks.map((track) => track.sourceId).toSet();
    final membershipCounts = <String, int>{};
    const batchSize = 4;

    for (var start = 0; start < playlists.length; start += batchSize) {
      final batch = playlists.skip(start).take(batchSize).toList();
      final membershipEntries = await Future.wait(
        batch.map((playlist) async {
          try {
            final existingTrackIds = await service.getTrackIdsInPlaylist(
              playlist.playlistId,
              targetTrackIds: trackIds,
            );
            if (existingTrackIds.isEmpty) {
              return null;
            }
            _existingTrackIdsByPlaylist[playlist.playlistId] = existingTrackIds;
            return MapEntry(playlist.playlistId, existingTrackIds.length);
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted) return;

      for (final entry
          in membershipEntries.whereType<MapEntry<String, int>>()) {
        membershipCounts[entry.key] = entry.value;
      }
    }

    if (!mounted) return;
    final totalTracks = trackIds.length;
    setState(() {
      for (final entry in membershipCounts.entries) {
        if (entry.value >= totalTracks) {
          _originalIds.add(entry.key);
          _selectedIds.add(entry.key);
        } else if (entry.value > 0) {
          _partialIds.add(entry.key);
        }
      }
      _isCheckingMulti = false;
    });
  }

  Future<void> _showCreatePlaylistDialog() async {
    bool isPrivate = false;
    final result = await showDialog<({String name, bool isPrivate})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t.remote.createPlaylist),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _newPlaylistController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: t.remote.playlistNameHint,
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
                onSelectionChanged: (values) {
                  setDialogState(() => isPrivate = values.first);
                },
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
                final name = _newPlaylistController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(
                    context,
                    (name: name, isPrivate: isPrivate),
                  );
                }
              },
              child: Text(t.general.confirm),
            ),
          ],
        ),
      ),
    );

    _newPlaylistController.clear();

    if (result != null && mounted) {
      try {
        final service = ref.read(neteasePlaylistServiceProvider);
        final playlistId = await service.createPlaylist(
          title: result.name,
          isPrivate: result.isPrivate,
        );
        if (!mounted) return;
        setState(() {
          final newPlaylist = NeteasePlaylistInfo(
            playlistId: playlistId,
            title: result.name,
            trackCount: 0,
            isMine: true,
          );
          _playlists?.insert(0, newPlaylist);
          _selectedIds.add(playlistId);
        });
      } on NeteasePlaylistException catch (e) {
        if (!mounted) return;
        ToastService.error(context, e.message);
      } catch (_) {
        if (!mounted) return;
        ToastService.error(context, t.remote.error.unknown(code: 'UNKNOWN'));
      }
    }
  }

  ({List<String> toAdd, List<String> toRemove}) _computeChanges() {
    return computeRemotePlaylistSelectionChanges(
      selectedIds: _selectedIds,
      originalIds: _originalIds,
      deselectedPartialIds: _deselectedPartialIds,
    );
  }

  Future<void> _submit() async {
    final (:toAdd, :toRemove) = _computeChanges();

    if (toAdd.isEmpty && toRemove.isEmpty) {
      ToastService.show(context, t.remote.noChanges);
      Navigator.pop(context, false);
      return;
    }

    setState(() {
      _isSubmitting = true;
      if (toAdd.length + toRemove.length > 1) {
        final total = toAdd.length + toRemove.length;
        _submitProgress = '$total/$total';
      }
    });
    try {
      final result = await ref
          .read(remotePlaylistEditControllerProvider)
          .submitSelectionEdit(
            sourceType: SourceType.netease,
            tracks: _tracks,
            selectedPlaylistIds: _selectedIds,
            originalPlaylistIds: _originalIds,
            deselectedPartialPlaylistIds: _deselectedPartialIds,
            existingTrackSourceIdsByPlaylist: _existingTrackIdsByPlaylist,
          );

      if (!mounted) return;
      if (result.changedRemote && result.hasFailures) {
        final summary = result.summary;
        final successCount =
            summary.addedTrackCount + summary.removedTrackCount;
        final totalCount = successCount + summary.failedTrackCount;
        ToastService.warning(
          context,
          t.addToPlaylistDialog.partiallyCompleted(
            success: successCount,
            total: totalCount,
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      if (result.changedRemote) {
        ToastService.success(context, t.remote.updated);
        Navigator.pop(context, true);
        return;
      }
      if (result.hasFailures) {
        ToastService.error(context, result.failures.first.error.toString());
      } else {
        ToastService.show(context, t.remote.noChanges);
      }
      setState(() {
        _isSubmitting = false;
        _submitProgress = null;
      });
    } on NeteasePlaylistException catch (e) {
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
            RemotePlaylistDialogHeader(
              title: t.remote.dialogTitleNetease,
              onClose: () => Navigator.pop(context, false),
            ),
            RemotePlaylistTrackSummary(tracks: _tracks),
            const SizedBox(height: 8),
            RemotePlaylistCreateTile(
              title: t.remote.createPlaylist,
              onTap: _isSubmitting ? null : _showCreatePlaylistDialog,
            ),
            const Divider(),
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                clipBehavior: Clip.hardEdge,
                child: _buildPlaylistList(colorScheme, scrollController),
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

  Widget _buildPlaylistList(
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
    final playlists = _playlists;
    if (playlists == null || playlists.isEmpty) {
      return Center(child: Text(t.remote.loading));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final isSelected = _selectedIds.contains(playlist.playlistId);
        final isPartial = !isSelected &&
            _partialIds.contains(playlist.playlistId) &&
            !_deselectedPartialIds.contains(playlist.playlistId);

        return RemotePlaylistListTile(
          imageUrl: playlist.thumbnailUrl,
          fallbackIcon: Icons.playlist_play,
          title: playlist.title,
          subtitle: '${playlist.trackCount}',
          isSelected: isSelected,
          isPartial: isPartial,
          isChecking: _isCheckingMulti,
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(playlist.playlistId);
                if (_partialIds.contains(playlist.playlistId)) {
                  _deselectedPartialIds.add(playlist.playlistId);
                }
              } else if (isPartial) {
                _selectedIds.add(playlist.playlistId);
              } else if (_deselectedPartialIds.contains(playlist.playlistId)) {
                _deselectedPartialIds.remove(playlist.playlistId);
              } else {
                _selectedIds.add(playlist.playlistId);
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
