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
/// 混合來源時按平台分組，依次顯示對應平台的對話框
Future<bool> showAddToRemotePlaylistDialogMulti({
  required BuildContext context,
  required List<Track> tracks,
}) async {
  if (tracks.isEmpty) return false;

  // 按平台分組
  final bilibiliTracks = tracks.where((t) => t.sourceType == SourceType.bilibili).toList();
  final youtubeTracks = tracks.where((t) => t.sourceType == SourceType.youtube).toList();

  // 提前捕獲 navigator，避免調用方 widget dispose 後 context 失效
  final navigator = Navigator.of(context);
  final overlay = navigator.overlay;

  bool anySuccess = false;

  // 先處理 Bilibili
  if (bilibiliTracks.isNotEmpty && overlay != null && overlay.mounted) {
    final result = await _showBilibiliSheet(overlay.context, bilibiliTracks);
    if (result) anySuccess = true;
  }

  // 再處理 YouTube
  if (youtubeTracks.isNotEmpty && overlay != null && overlay.mounted) {
    final result = await showAddToYouTubePlaylistDialog(context: overlay.context, tracks: youtubeTracks);
    if (result) anySuccess = true;
  }

  return anySuccess;
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
  Set<int> _originalIds = {};              // 全部 tracks 都在的收藏夾（不可變）
  Set<int> _partialIds = {};               // 部分 tracks 在的收藏夾（不可變）
  final Set<int> _deselectedPartialIds = {};  // 用戶明確取消的半選收藏夾
  bool _isLoading = true;
  bool _isCheckingMulti = false;    // 多選時異步檢查收藏狀態
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

      if (_isMulti) {
        // 多選：先不帶 videoAid 拿收藏夾列表，再異步檢查每首歌的收藏狀態
        final folders = await favService.getFavFolders();
        if (!mounted) return;
        setState(() {
          _folders = folders;
          _isLoading = false;
          _isCheckingMulti = true;
        });
        _checkMultiFavStatusAsync(folders);
      } else {
        // 單曲：帶 videoAid 查詢
        final aid = await favService.getVideoAid(_tracks.first);
        final folders = await favService.getFavFolders(videoAid: aid);
        if (!mounted) return;
        final original = <int>{};
        for (final f in folders) {
          if (f.isFavorited) original.add(f.id);
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// 多選時異步檢查每首歌在各收藏夾的收藏狀態
  Future<void> _checkMultiFavStatusAsync(List<BilibiliFavFolder> folders) async {
    final favService = ref.read(bilibiliFavoritesServiceProvider);
    final folderIds = folders.map((f) => f.id).toSet();
    // folderId → 已收藏的 track 數量
    final favCounts = <int, int>{};

    for (final track in _tracks) {
      try {
        final aid = await favService.getVideoAid(track);
        final trackFolders = await favService.getFavFolders(videoAid: aid);
        if (!mounted) return;
        for (final f in trackFolders) {
          if (f.isFavorited && folderIds.contains(f.id)) {
            favCounts[f.id] = (favCounts[f.id] ?? 0) + 1;
          }
        }
      } catch (_) {
        // 單首查詢失敗不影響整體
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

  Future<void> _submit() async {
    final toAdd = _selectedIds.difference(_originalIds).difference(_partialIds).toList();
    // 移除：原本全選但被取消的 + 明確取消的半選
    final toRemove = [
      ..._originalIds.difference(_selectedIds),
      ..._deselectedPartialIds,
    ];

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
                      ? Icon(Icons.remove_circle_outline, color: colorScheme.primary)
                      : Icon(Icons.circle_outlined, color: colorScheme.outline),
          selected: isSelected || isPartial,
          selectedTileColor:
              colorScheme.primaryContainer.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusLg),
          onTap: () {
            setState(() {
              if (isSelected) {
                // 全選 → 取消
                _selectedIds.remove(folder.id);
                // 如果原本是半選提升上來的，標記為明確取消
                if (_partialIds.contains(folder.id)) {
                  _deselectedPartialIds.add(folder.id);
                }
              } else if (isPartial) {
                // 半選 → 全選（添加所有 tracks）
                _selectedIds.add(folder.id);
              } else if (_deselectedPartialIds.contains(folder.id)) {
                // 已取消的半選 → 恢復半選（不做任何操作）
                _deselectedPartialIds.remove(folder.id);
              } else {
                // 未選 → 全選
                _selectedIds.add(folder.id);
              }
            });
          },
        );
      },
    );
  }

  String _getButtonText() {
    final toAdd = _selectedIds.difference(_originalIds).difference(_partialIds);
    final toRemove = _originalIds.difference(_selectedIds).union(_deselectedPartialIds);
    if (toAdd.isEmpty && toRemove.isEmpty) return t.remote.confirm;
    if (toAdd.isNotEmpty && toRemove.isEmpty) {
      return t.remote.addToCount(count: toAdd.length.toString());
    }
    return t.remote.confirm;
  }
}
