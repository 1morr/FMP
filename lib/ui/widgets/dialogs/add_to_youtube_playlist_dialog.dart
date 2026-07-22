import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account/account_provider.dart';
import '../../../providers/library/remote_playlist_sync_provider.dart';
import '../../../services/account/youtube_playlist_service.dart';
import '../../../services/library/remote_playlist_selection_changes.dart';
import 'remote_playlist_dialog_widgets.dart';

/// 顯示添加到 YouTube 播放列表對話框
Future<bool> showAddToYouTubePlaylistDialog({
  required BuildContext context,
  required List<Track> tracks,
}) async {
  if (tracks.isEmpty) return false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _YouTubePlaylistSheet(tracks: tracks),
  );
  return result ?? false;
}

class _YouTubePlaylistSheet extends ConsumerStatefulWidget {
  final List<Track> tracks;
  const _YouTubePlaylistSheet({required this.tracks});

  @override
  ConsumerState<_YouTubePlaylistSheet> createState() =>
      _YouTubePlaylistSheetState();
}

class _YouTubePlaylistSheetState extends ConsumerState<_YouTubePlaylistSheet> {
  List<YouTubePlaylistInfo>? _playlists;
  final Set<String> _selectedIds = {};
  final Set<String> _originalIds = {};
  final Set<String> _partialIds = {}; // 部分 tracks 在的播放列表（不可變）
  final Set<String> _deselectedPartialIds = {}; // 用戶明確取消的半選播放列表
  final Map<String, Set<String>> _existingTrackIdsByPlaylist = {};
  // 每個 playlist 的 containsVideo 檢查狀態
  final Map<String, bool?> _containsStatus = {}; // null = loading
  bool _isLoading = true;
  bool _isCheckingMulti = false; // 多選時異步檢查狀態
  bool _isSubmitting = false;
  String? _errorMessage;

  List<Track> get _tracks => widget.tracks;
  bool get _isMulti => _tracks.length > 1;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    try {
      final service = ref.read(youtubePlaylistServiceProvider);
      final playlists = await service.getPlaylists();

      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });

      // 單曲模式：異步逐個檢查 containsVideo
      // 多選模式：異步檢查每首歌在各播放列表的狀態
      if (playlists.isNotEmpty) {
        if (_isMulti) {
          setState(() => _isCheckingMulti = true);
          _checkMultiContainsAsync(playlists);
        } else {
          _checkContainsVideoAsync(playlists);
        }
      }
    } on YouTubePlaylistException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = t.remote.error.unknown(code: 'LOAD');
      });
    }
  }

  /// 並行檢查每個播放列表是否包含當前視頻
  Future<void> _checkContainsVideoAsync(
      List<YouTubePlaylistInfo> playlists) async {
    final service = ref.read(youtubePlaylistServiceProvider);
    final videoId = _tracks.first.sourceId;

    // 初始化所有為 loading 狀態
    for (final p in playlists) {
      _containsStatus[p.playlistId] = null;
    }

    final results = await Future.wait(
      playlists.map((playlist) async {
        try {
          final contains = await service.checkVideoInPlaylist(
            playlist.playlistId,
            videoId,
          );
          return (playlist.playlistId, contains);
        } catch (_) {
          return (playlist.playlistId, false);
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      for (final (playlistId, contains) in results) {
        _containsStatus[playlistId] = contains;
        if (contains) {
          _originalIds.add(playlistId);
          _selectedIds.add(playlistId);
        }
      }
    });
  }

  /// 多選時異步檢查每首歌在各播放列表的收藏狀態
  ///
  /// 優化：每個播放列表只 browse 一次，收集所有 videoId，再批量比對
  Future<void> _checkMultiContainsAsync(
      List<YouTubePlaylistInfo> playlists) async {
    final service = ref.read(youtubePlaylistServiceProvider);
    final trackVideoIds = _tracks.map((t) => t.sourceId).toSet();
    // playlistId → 已包含的 track 數量
    final containsCounts = <String, int>{};

    for (final playlist in playlists) {
      try {
        final videoIds = await service.getVideoIdsInPlaylist(
          playlist.playlistId,
          targetVideoIds: trackVideoIds,
        );
        if (!mounted) return;
        final matchingVideoIds = trackVideoIds.intersection(videoIds);
        if (matchingVideoIds.isNotEmpty) {
          containsCounts[playlist.playlistId] = matchingVideoIds.length;
          _existingTrackIdsByPlaylist[playlist.playlistId] = matchingVideoIds;
        }
      } catch (_) {
        // 單個播放列表查詢失敗不影響整體
      }
    }

    if (!mounted) return;
    final trackCount = _tracks.length;
    setState(() {
      for (final entry in containsCounts.entries) {
        if (entry.value >= trackCount) {
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
    final result = await showCreateRemotePlaylistDialog<String>(
      context: context,
      title: t.remote.createPlaylist,
      hint: t.remote.playlistNameHint,
      initialPrivacy: 'UNLISTED',
      privacySegments: [
        ButtonSegment(
          value: 'PUBLIC',
          label: Text(t.remote.privacyPublic),
          icon: const Icon(Icons.public, size: 18),
        ),
        ButtonSegment(
          value: 'UNLISTED',
          label: Text(t.remote.privacyUnlisted),
          icon: const Icon(Icons.link, size: 18),
        ),
        ButtonSegment(
          value: 'PRIVATE',
          label: Text(t.remote.privacyPrivate),
          icon: const Icon(Icons.lock, size: 18),
        ),
      ],
    );

    if (result != null && mounted) {
      try {
        final service = ref.read(youtubePlaylistServiceProvider);
        final playlistId = await service.createPlaylist(
          title: result.name,
          privacyStatus: result.privacy,
        );
        if (!mounted || playlistId == null) return;
        setState(() {
          final newPlaylist = YouTubePlaylistInfo(
            playlistId: playlistId,
            title: result.name,
            videoCount: 0,
          );
          _playlists?.insert(0, newPlaylist);
          _selectedIds.add(playlistId);
          _containsStatus[playlistId] = false;
        });
      } on YouTubePlaylistException catch (e) {
        if (!mounted) return;
        ToastService.error(context, e.message);
      } catch (e) {
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
            sourceType: SourceType.youtube,
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
    } on YouTubePlaylistException catch (e) {
      if (!mounted) return;
      ToastService.error(context, e.message);
      setState(() {
        _isSubmitting = false;
      });
    } catch (e) {
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
      title: t.remote.dialogTitleYoutube,
      tracks: _tracks,
      createTitle: t.remote.createPlaylist,
      onCreate: _showCreatePlaylistDialog,
      isSubmitting: _isSubmitting,
      isLoading: _isLoading,
      onSubmit: _submit,
      buttonText: _getButtonText(),
      listBuilder: (context, scrollController) =>
          RemotePlaylistSelectionListView<YouTubePlaylistInfo>(
        isLoading: _isLoading,
        errorMessage: _errorMessage,
        items: _playlists,
        scrollController: scrollController,
        isChecking: _isCheckingMulti,
        itemImageUrl: (playlist) => playlist.thumbnailUrl,
        itemIcon: (playlist) => Icons.playlist_play,
        itemTitle: (playlist) => playlist.title,
        itemSubtitle: (playlist) => '${playlist.videoCount}',
        isSelected: (playlist) => _selectedIds.contains(playlist.playlistId),
        isPartial: (playlist) =>
            !_selectedIds.contains(playlist.playlistId) &&
            _partialIds.contains(playlist.playlistId) &&
            !_deselectedPartialIds.contains(playlist.playlistId),
        onToggle: _togglePlaylist,
        // 單曲模式：逐筆確認 containsVideo，尚未回應的播放清單顯示載入指示
        isCheckingItem: (playlist) =>
            !_isMulti &&
            _playlists != null &&
            _containsStatus[playlist.playlistId] == null,
      ),
    );
  }

  void _togglePlaylist(YouTubePlaylistInfo playlist) {
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
