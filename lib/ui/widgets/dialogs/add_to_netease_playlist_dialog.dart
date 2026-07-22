import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account/account_provider.dart';
import '../../../providers/library/remote_playlist_sync_provider.dart';
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

  List<Track> get _tracks => widget.tracks;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
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
    final result = await showCreateRemotePlaylistDialog<bool>(
      context: context,
      title: t.remote.createPlaylist,
      hint: t.remote.playlistNameHint,
      initialPrivacy: false,
      privacySegments: remotePlaylistPrivacySegments(),
    );

    if (result != null && mounted) {
      try {
        final service = ref.read(neteasePlaylistServiceProvider);
        final playlistId = await service.createPlaylist(
          title: result.name,
          isPrivate: result.privacy,
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
      reportRemotePlaylistEditResult(
        context,
        result,
        onSuccess: () => Navigator.pop(context, true),
      );
      // 成功路徑已 pop；僅失敗/無變更時需重置提交狀態
      if (mounted && !result.changedRemote) {
        setState(() {
          _isSubmitting = false;
        });
      }
    } on NeteasePlaylistException catch (e) {
      if (!mounted) return;
      ToastService.error(context, e.message);
      setState(() {
        _isSubmitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      ToastService.error(context, t.remote.error.unknown(code: 'UNKNOWN'));
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RemotePlaylistSheetBody(
      title: t.remote.dialogTitleNetease,
      tracks: _tracks,
      createTitle: t.remote.createPlaylist,
      onCreate: _showCreatePlaylistDialog,
      isSubmitting: _isSubmitting,
      isLoading: _isLoading,
      onSubmit: _submit,
      buttonText: _getButtonText(),
      listBuilder: (context, scrollController) =>
          RemotePlaylistSelectionListView<NeteasePlaylistInfo>(
        isLoading: _isLoading,
        errorMessage: _errorMessage,
        items: _playlists,
        scrollController: scrollController,
        isChecking: _isCheckingMulti,
        itemImageUrl: (playlist) => playlist.thumbnailUrl,
        itemIcon: (playlist) => Icons.playlist_play,
        itemTitle: (playlist) => playlist.title,
        itemSubtitle: (playlist) => '${playlist.trackCount}',
        isSelected: (playlist) => _selectedIds.contains(playlist.playlistId),
        isPartial: (playlist) =>
            !_selectedIds.contains(playlist.playlistId) &&
            _partialIds.contains(playlist.playlistId) &&
            !_deselectedPartialIds.contains(playlist.playlistId),
        onToggle: _togglePlaylist,
      ),
    );
  }

  void _togglePlaylist(NeteasePlaylistInfo playlist) {
    final id = playlist.playlistId;
    final isSelected = _selectedIds.contains(id);
    final isPartial = !isSelected &&
        _partialIds.contains(id) &&
        !_deselectedPartialIds.contains(id);
    setState(() {
      if (isSelected) {
        _selectedIds.remove(id);
        if (_partialIds.contains(id)) {
          _deselectedPartialIds.add(id);
        }
      } else if (isPartial) {
        _selectedIds.add(id);
      } else if (_deselectedPartialIds.contains(id)) {
        _deselectedPartialIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  String _getButtonText() {
    final (:toAdd, :toRemove) = _computeChanges();
    return remotePlaylistSubmitButtonText(
      toAddCount: toAdd.length,
      toRemoveCount: toRemove.length,
    );
  }
}
