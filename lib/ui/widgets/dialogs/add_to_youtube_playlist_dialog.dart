import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/remote_playlist_sync_provider.dart';
import '../../../services/account/youtube_playlist_service.dart';
import '../../../services/library/remote_playlist_selection_changes.dart';
import '../track_thumbnail.dart';

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
  String? _submitProgress;
  final _newPlaylistController = TextEditingController();

  List<Track> get _tracks => widget.tracks;
  bool get _isMulti => _tracks.length > 1;

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
    String privacyStatus = 'UNLISTED';
    final result = await showDialog<({String name, String privacyStatus})>(
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
                    Navigator.pop(context,
                        (name: value.trim(), privacyStatus: privacyStatus));
                  }
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: [
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
                selected: {privacyStatus},
                onSelectionChanged: (v) =>
                    setDialogState(() => privacyStatus = v.first),
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
                      context, (name: name, privacyStatus: privacyStatus));
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
        final service = ref.read(youtubePlaylistServiceProvider);
        final playlistId = await service.createPlaylist(
          title: result.name,
          privacyStatus: result.privacyStatus,
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

    setState(() => _isSubmitting = true);
    try {
      final service = ref.read(youtubePlaylistServiceProvider);

      for (var i = 0; i < _tracks.length; i++) {
        if (!mounted) return;
        final track = _tracks[i];
        if (_isMulti) {
          setState(() {
            _submitProgress = '${i + 1}/${_tracks.length}';
          });
        }

        for (final playlistId in toAdd) {
          final existingTrackIds = _existingTrackIdsByPlaylist[playlistId];
          if (existingTrackIds?.contains(track.sourceId) ?? false) continue;
          await service.addToPlaylist(playlistId, track.sourceId);
        }

        // 從取消選中的播放列表移除
        for (final playlistId in toRemove) {
          final setVideoId = await service.getSetVideoId(
            playlistId,
            track.sourceId,
          );
          if (setVideoId != null) {
            await service.removeFromPlaylist(
              playlistId,
              track.sourceId,
              setVideoId,
            );
          }
        }
      }

      try {
        await ref
            .read(remotePlaylistSyncServiceProvider)
            .refreshMatchingImportedPlaylists(
          sourceType: SourceType.youtube,
          remotePlaylistIds: [...toAdd, ...toRemove],
        );
      } catch (_) {
        // Local refresh trigger is best-effort; remote playlist update already succeeded.
      }

      if (!mounted) return;
      ToastService.success(context, t.remote.updated);
      Navigator.pop(context, true);
    } on YouTubePlaylistException catch (e) {
      if (!mounted) return;
      ToastService.error(context, e.message);
      setState(() {
        _isSubmitting = false;
        _submitProgress = null;
      });
    } catch (e) {
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
                  Text(t.remote.dialogTitleYoutube,
                      style: Theme.of(context).textTheme.titleLarge),
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
            // 新建播放列表
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
                title: Text(t.remote.createPlaylist),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusLg,
                ),
                onTap: _isSubmitting ? null : _showCreatePlaylistDialog,
              ),
            ),
            const Divider(),
            // 播放列表列表
            Expanded(
              child: Material(
                type: MaterialType.transparency,
                clipBehavior: Clip.hardEdge,
                child: _buildPlaylistList(colorScheme, scrollController),
              ),
            ),
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
        final containsStatus = _containsStatus[playlist.playlistId];

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusMd,
              color: colorScheme.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: playlist.thumbnailUrl != null
                ? ImageLoadingService.loadImage(
                    networkUrl: playlist.thumbnailUrl,
                    placeholder:
                        Icon(Icons.playlist_play, color: colorScheme.outline),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    targetDisplaySize: 40,
                  )
                : Icon(Icons.playlist_play, color: colorScheme.outline),
          ),
          title: Text(playlist.title),
          subtitle: Text('${playlist.videoCount}'),
          trailing: _buildTrailing(
            colorScheme,
            isSelected,
            isPartial,
            containsStatus,
          ),
          selected: isSelected || isPartial,
          selectedTileColor:
              colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
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

  Widget _buildTrailing(
    ColorScheme colorScheme,
    bool isSelected,
    bool isPartial,
    bool? containsStatus,
  ) {
    // 多選模式正在檢查中
    if (_isCheckingMulti) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    // 單曲模式且正在檢查中
    if (!_isMulti && containsStatus == null && _playlists != null) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isSelected) {
      return Icon(Icons.check_circle, color: colorScheme.primary);
    }
    if (isPartial) {
      return Icon(Icons.remove_circle_outline, color: colorScheme.primary);
    }
    return Icon(Icons.circle_outlined, color: colorScheme.outline);
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
