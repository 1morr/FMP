import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../track_thumbnail.dart';

/// 显示添加到歌单对话框（单个track）
Future<bool> showAddToPlaylistDialog({
  required BuildContext context,
  Track? track,
  List<Track>? tracks,
}) async {
  assert(track != null || (tracks != null && tracks.isNotEmpty),
      'Either track or tracks must be provided');
  
  final trackList = tracks ?? [track!];
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AddToPlaylistSheet(tracks: trackList),
  );
  return result ?? false;
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  final List<Track> tracks;

  const _AddToPlaylistSheet({required this.tracks});

  Track get firstTrack => tracks.first;
  bool get isMultiple => tracks.length > 1;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  final _newPlaylistController = TextEditingController();
  final Set<int> _selectedPlaylistIds = {};
  bool _isAdding = false;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playlists = ref.watch(allPlaylistsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 拖拽指示条
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '添加到歌单',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // 封面
                  TrackThumbnail(
                    track: widget.firstTrack,
                    size: 48,
                    borderRadius: 4,
                  ),
                  const SizedBox(width: 12),
                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isMultiple
                              ? '${widget.tracks.length} 首歌曲'
                              : widget.firstTrack.title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.isMultiple
                              ? widget.firstTrack.parentTitle ?? widget.firstTrack.title
                              : widget.firstTrack.artist ?? '未知艺术家',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
            // 创建新歌单
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.add,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('创建新歌单'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => _showCreatePlaylistDialog(context),
              ),
            ),
            const Divider(),
            // 多选提示
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '可多选歌单',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                  ),
                  if (_selectedPlaylistIds.isNotEmpty) ...[
                    const Spacer(),
                    Text(
                      '已选 ${_selectedPlaylistIds.length} 个',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            // 歌单列表
            Expanded(
              child: playlists.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text('加载失败: $error'),
                ),
                data: (lists) {
                  // 过滤掉导入的歌单，只显示手动创建的歌单
                  final manualPlaylists = lists.where((p) => !p.isImported).toList();
                  
                  if (manualPlaylists.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.library_music,
                            size: 48,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无歌单',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.outline,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击上方创建新歌单',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: manualPlaylists.length,
                    itemBuilder: (context, index) {
                      final playlist = manualPlaylists[index];
                      final isSelected = _selectedPlaylistIds.contains(playlist.id);
                      final coverAsync =
                          ref.watch(playlistCoverProvider(playlist.id));

                      return ListTile(
                        leading: Stack(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: colorScheme.surfaceContainerHighest,
                                border: isSelected
                                    ? Border.all(
                                        color: colorScheme.primary,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: coverAsync.when(
                                data: (coverData) => coverData.hasCover
                                    ? ImageLoadingService.loadImage(
                                        localPath: coverData.localPath,
                                        networkUrl: coverData.networkUrl,
                                        placeholder: Icon(
                                          Icons.album,
                                          color: colorScheme.outline,
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(
                                        Icons.album,
                                        color: colorScheme.outline,
                                      ),
                                loading: () => const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                error: (e, s) => Icon(
                                  Icons.album,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    size: 12,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(playlist.name),
                        subtitle: Text('${playlist.trackCount} 首歌曲'),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: colorScheme.primary,
                              )
                            : Icon(
                                Icons.circle_outlined,
                                color: colorScheme.outline,
                              ),
                        selected: isSelected,
                        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () => _togglePlaylistSelection(playlist.id),
                      );
                    },
                  );
                },
              ),
            ),
            // 确认按钮
            if (_selectedPlaylistIds.isNotEmpty)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isAdding ? null : _addToSelectedPlaylists,
                      icon: _isAdding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.playlist_add),
                      label: Text(
                        _isAdding
                            ? '添加中...'
                            : '添加到 ${_selectedPlaylistIds.length} 个歌单',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _togglePlaylistSelection(int playlistId) {
    setState(() {
      if (_selectedPlaylistIds.contains(playlistId)) {
        _selectedPlaylistIds.remove(playlistId);
      } else {
        _selectedPlaylistIds.add(playlistId);
      }
    });
  }

  Future<void> _showCreatePlaylistDialog(BuildContext dialogContext) async {
    final result = await showDialog<String>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('创建歌单'),
        content: TextField(
          controller: _newPlaylistController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '歌单名称',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = _newPlaylistController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      try {
        // 创建歌单
        final playlist = await ref
            .read(playlistListProvider.notifier)
            .createPlaylist(name: result);

        if (playlist != null && mounted) {
          // 刷新歌单列表以显示新创建的歌单（两个 provider 都要刷新）
          ref.invalidate(allPlaylistsProvider);
          // playlistListProvider 已在 createPlaylist 中自动刷新
          // 自动选中新创建的歌单
          setState(() {
            _selectedPlaylistIds.add(playlist.id);
          });
        }
      } catch (e) {
        if (mounted) {
          ToastService.error(context, '创建失败: $e');
        }
      }
    }

    _newPlaylistController.clear();
  }

  Future<void> _addToSelectedPlaylists() async {
    if (_selectedPlaylistIds.isEmpty) return;

    setState(() {
      _isAdding = true;
    });

    try {
      final service = ref.read(playlistServiceProvider);
      int successCount = 0;

      for (final playlistId in _selectedPlaylistIds) {
        try {
          // 添加所有tracks
          for (final track in widget.tracks) {
            await service.addTrackToPlaylist(playlistId, track);
          }
          successCount++;
          // 刷新该歌单详情和封面
          ref.invalidate(playlistDetailProvider(playlistId));
          ref.invalidate(playlistCoverProvider(playlistId));
        } catch (e) {
          // 继续添加到其他歌单
        }
      }

      // 刷新歌单列表（两个 provider 都要刷新）
      ref.invalidate(allPlaylistsProvider);
      await ref.read(playlistListProvider.notifier).loadPlaylists();

      if (mounted) {
        if (successCount == _selectedPlaylistIds.length) {
          ToastService.success(context, '已添加到 $successCount 个歌单');
        } else {
          ToastService.warning(context, '成功添加到 $successCount/${_selectedPlaylistIds.length} 个歌单');
        }
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ToastService.error(context, '添加失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }
}
