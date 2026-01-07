import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';

/// 显示添加到歌单对话框
Future<bool> showAddToPlaylistDialog({
  required BuildContext context,
  required Track track,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AddToPlaylistSheet(track: track),
  );
  return result ?? false;
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  final Track track;

  const _AddToPlaylistSheet({required this.track});

  @override
  ConsumerState<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  final _newPlaylistController = TextEditingController();

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
      initialChildSize: 0.6,
      minChildSize: 0.4,
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
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: colorScheme.surface,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.track.thumbnailUrl != null
                        ? CachedNetworkImage(
                            imageUrl: widget.track.thumbnailUrl!,
                            fit: BoxFit.cover,
                          )
                        : Icon(
                            Icons.music_note,
                            color: colorScheme.primary,
                          ),
                  ),
                  const SizedBox(width: 12),
                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.track.title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.track.artist ?? '未知艺术家',
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
                      final coverAsync =
                          ref.watch(playlistCoverProvider(playlist.id));

                      return ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: coverAsync.when(
                            data: (url) => url != null
                                ? CachedNetworkImage(
                                    imageUrl: url,
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
                        title: Text(playlist.name),
                        subtitle: Text('${playlist.trackCount} 首歌曲'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () => _addToPlaylist(playlist.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
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
          // 添加歌曲到新歌单
          await _addToPlaylist(playlist.id);
        }
      } catch (e) {
        // Error handled in _addToPlaylist
      }
    }

    _newPlaylistController.clear();
  }

  Future<void> _addToPlaylist(int playlistId) async {
    try {
      final service = ref.read(playlistServiceProvider);
      await service.addTrackToPlaylist(playlistId, widget.track);

      // 刷新歌单列表
      ref.invalidate(allPlaylistsProvider);
      ref.invalidate(playlistDetailProvider(playlistId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到歌单')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }
}
