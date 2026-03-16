import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../services/account/youtube_playlist_service.dart';
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
  // 每個 playlist 的 containsVideo 檢查狀態
  final Map<String, bool?> _containsStatus = {}; // null = loading
  bool _isLoading = true;
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
      if (!_isMulti && playlists.isNotEmpty) {
        _checkContainsVideoAsync(playlists);
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
        _errorMessage = e.toString();
      });
    }
  }

  /// 異步逐個檢查每個播放列表是否包含當前視頻
  Future<void> _checkContainsVideoAsync(List<YouTubePlaylistInfo> playlists) async {
    final service = ref.read(youtubePlaylistServiceProvider);
    final videoId = _tracks.first.sourceId;

    // 初始化所有為 loading 狀態
    for (final p in playlists) {
      _containsStatus[p.playlistId] = null;
    }

    for (final playlist in playlists) {
      if (!mounted) return;
      try {
        final contains = await service.checkVideoInPlaylist(
          playlist.playlistId,
          videoId,
        );
        if (!mounted) return;
        setState(() {
          _containsStatus[playlist.playlistId] = contains;
          if (contains) {
            _originalIds.add(playlist.playlistId);
            _selectedIds.add(playlist.playlistId);
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _containsStatus[playlist.playlistId] = false;
        });
      }
    }
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
                    Navigator.pop(context,
                        (name: value.trim(), isPrivate: isPrivate));
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.remote.privateFolder),
                value: isPrivate,
                onChanged: (v) => setDialogState(() => isPrivate = v),
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

    _newPlaylistController.clear();

    if (result != null && mounted) {
      try {
        final service = ref.read(youtubePlaylistServiceProvider);
        final playlistId = await service.createPlaylist(
          title: result.name,
          isPrivate: result.isPrivate,
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
        });
      } on YouTubePlaylistException catch (e) {
        if (!mounted) return;
        ToastService.error(context, e.message);
      } catch (e) {
        if (!mounted) return;
        ToastService.error(context, e.toString());
      }
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
      final service = ref.read(youtubePlaylistServiceProvider);

      for (var i = 0; i < _tracks.length; i++) {
        final track = _tracks[i];
        if (_isMulti && mounted) {
          setState(() {
            _submitProgress = '${i + 1}/${_tracks.length}';
          });
        }

        // 添加到選中的播放列表
        for (final playlistId in toAdd) {
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
      ToastService.error(context, e.toString());
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
            Expanded(child: _buildPlaylistList(colorScheme, scrollController)),
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
        final containsStatus = _containsStatus[playlist.playlistId];

        return ListTile(
          leading: const Icon(Icons.playlist_play),
          title: Text(playlist.title),
          subtitle: Text('${playlist.videoCount}'),
          trailing: _buildTrailing(
            colorScheme,
            isSelected,
            containsStatus,
          ),
          selected: isSelected,
          selectedTileColor:
              colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusLg),
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(playlist.playlistId);
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
    bool? containsStatus,
  ) {
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
    return Icon(Icons.circle_outlined, color: colorScheme.outline);
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
