import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account/account_provider.dart';
import '../../../providers/library/remote_playlist_sync_provider.dart';
import '../../../services/account/bilibili_favorites_service.dart';
import '../../../services/library/remote_playlist_selection_changes.dart';
import 'remote_playlist_dialog_widgets.dart';

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
  final Map<int, Set<String>> _existingTrackIdsByFolder = {};
  bool _isLoading = true;
  bool _isCheckingMulti = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<Track> get _tracks => widget.tracks;
  bool get _isMulti => _tracks.length > 1;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _showCreateFolderDialog() async {
    final result = await showCreateRemotePlaylistDialog<bool>(
      context: context,
      title: t.remote.createFolder,
      hint: t.remote.folderNameHint,
      initialPrivacy: false,
      privacySegments: remotePlaylistPrivacySegments(),
    );

    if (result != null && mounted) {
      try {
        final favService = ref.read(bilibiliFavoritesServiceProvider);
        final folder = await favService.createFavFolder(
          title: result.name,
          isPrivate: result.privacy,
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

    final aidEntries = await Future.wait(
      _tracks.map((track) async {
        try {
          return (track.sourceId, await favService.getVideoAid(track));
        } catch (_) {
          return null;
        }
      }),
    );
    if (!mounted) return;

    for (final aidEntry in aidEntries) {
      if (aidEntry == null) continue;
      final (sourceId, aid) = aidEntry;
      try {
        final trackFolders = await favService.getFavFolders(videoAid: aid);
        if (!mounted) return;
        for (final folder in trackFolders) {
          if (folder.isFavorited && folderIds.contains(folder.id)) {
            favCounts[folder.id] = (favCounts[folder.id] ?? 0) + 1;
            (_existingTrackIdsByFolder[folder.id] ??= {}).add(sourceId);
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
            sourceType: SourceType.bilibili,
            tracks: _tracks,
            selectedPlaylistIds:
                _selectedIds.map((id) => id.toString()).toSet(),
            originalPlaylistIds:
                _originalIds.map((id) => id.toString()).toSet(),
            deselectedPartialPlaylistIds:
                _deselectedPartialIds.map((id) => id.toString()).toSet(),
            existingTrackSourceIdsByPlaylist:
                _existingTrackIdsByFolder.map((folderId, trackIds) {
              return MapEntry(folderId.toString(), trackIds);
            }),
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
    } on BilibiliFavoritesException catch (e) {
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
      title: t.remote.dialogTitle,
      tracks: _tracks,
      createTitle: t.remote.createFolder,
      onCreate: _showCreateFolderDialog,
      isSubmitting: _isSubmitting,
      isLoading: _isLoading,
      onSubmit: _submit,
      buttonText: _getButtonText(),
      listBuilder: (context, scrollController) =>
          RemotePlaylistSelectionListView<BilibiliFavFolder>(
        isLoading: _isLoading,
        errorMessage: _errorMessage,
        items: _folders,
        scrollController: scrollController,
        isChecking: _isCheckingMulti,
        itemImageUrl: (folder) => folder.coverUrl,
        itemIcon: (folder) =>
            folder.isDefault ? Icons.star : Icons.folder_outlined,
        itemTitle: (folder) => folder.title,
        itemSubtitle: (folder) => '${folder.mediaCount}',
        isSelected: (folder) => _selectedIds.contains(folder.id),
        isPartial: (folder) =>
            !_selectedIds.contains(folder.id) &&
            _partialIds.contains(folder.id) &&
            !_deselectedPartialIds.contains(folder.id),
        onToggle: _toggleFolder,
      ),
    );
  }

  void _toggleFolder(BilibiliFavFolder folder) {
    final isSelected = _selectedIds.contains(folder.id);
    final isPartial = !isSelected &&
        _partialIds.contains(folder.id) &&
        !_deselectedPartialIds.contains(folder.id);
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
  }

  String _getButtonText() {
    final (:toAdd, :toRemove) = _computeChanges();
    return remotePlaylistSubmitButtonText(
      toAddCount: toAdd.length,
      toRemoveCount: toRemove.length,
    );
  }
}
