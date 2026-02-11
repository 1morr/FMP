import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/repository_providers.dart';
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
  Set<int> _selectedPlaylistIds = {};
  Set<int> _originalPlaylistIds = {};  // 原始状态：打开对话框时 track 已在的歌单
  bool _isAdding = false;
  bool _isInitialized = false;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  /// 初始化选中状态：预选已添加歌单中的歌单
  Future<void> _initializeSelection(List<Track> tracks, List<dynamic> playlists) async {
    if (_isInitialized) return;

    // 先从数据库获取最新的 track 数据（包含 playlistInfo）
    final trackRepo = ref.read(trackRepositoryProvider);
    final loadedTracks = <Track>[];
    for (final track in tracks) {
      try {
        final saved = await trackRepo.getOrCreate(track);
        loadedTracks.add(saved);
      } catch (_) {
        // 如果获取失败，使用原始 track
        loadedTracks.add(track);
      }
    }

    // 对于多个 track，只有所有 track 都在的歌单才预选
    // 对于单个 track，预选它所在的歌单
    final Set<int> preselectedIds = {};
    final manualPlaylists = playlists.where((p) => !p.isImported).toList();

    for (final playlist in manualPlaylists) {
      final playlistId = playlist.id;
      // 检查是否所有 tracks 都在这个歌单中
      final allInPlaylist = loadedTracks.every((track) => track.belongsToPlaylist(playlistId));
      if (allInPlaylist) {
        preselectedIds.add(playlistId);
      }
    }

    _originalPlaylistIds = Set.from(preselectedIds);
    _selectedPlaylistIds = Set.from(preselectedIds);
    _isInitialized = true;

    if (mounted) {
      setState(() {});  // 触发 UI 更新
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playlists = ref.watch(allPlaylistsProvider);

    // 初始化选中状态（在数据加载完成后）
    playlists.whenData((lists) {
      if (!_isInitialized && mounted) {
        _initializeSelection(widget.tracks, lists);
      }
    });

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
            // 确认按钮（始终显示，允许全部取消勾选来移出歌单）
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isAdding ? null : _updateSelectedPlaylists,
                    icon: _isAdding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_getConfirmButtonText()),
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

  /// 获取确认按钮文本
  String _getConfirmButtonText() {
    if (_isAdding) {
      return '保存中...';
    }

    // 计算变化
    final toAdd = _selectedPlaylistIds.difference(_originalPlaylistIds);
    final toRemove = _originalPlaylistIds.difference(_selectedPlaylistIds);

    if (toAdd.isEmpty && toRemove.isEmpty) {
      // 没有变化
      return '保存';
    } else if (toAdd.isNotEmpty && toRemove.isEmpty) {
      // 只添加
      return '添加到 ${toAdd.length} 个歌单';
    } else if (toRemove.isNotEmpty && toAdd.isEmpty) {
      // 只移除
      return '从 ${toRemove.length} 个歌单移出';
    } else {
      // 同时添加和移除
      return '添加 ${toAdd.length} 个，移出 ${toRemove.length} 个';
    }
  }

  /// 更新选中的歌单（同时处理添加和移除）
  Future<void> _updateSelectedPlaylists() async {
    // 计算变化
    final toAdd = _selectedPlaylistIds.difference(_originalPlaylistIds);
    final toRemove = _originalPlaylistIds.difference(_selectedPlaylistIds);

    // 没有变化，直接关闭
    if (toAdd.isEmpty && toRemove.isEmpty) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _isAdding = true;
    });

    try {
      final service = ref.read(playlistServiceProvider);
      int addSuccessCount = 0;
      int removeSuccessCount = 0;

      // 先处理移除
      for (final playlistId in toRemove) {
        try {
          for (final track in widget.tracks) {
            // 获取最新的 track ID（可能已经被保存到数据库）
            final savedTrack = await ref.read(trackRepositoryProvider).getOrCreate(track);
            await service.removeTrackFromPlaylist(playlistId, savedTrack.id);
          }
          removeSuccessCount++;
          ref.read(playlistListProvider.notifier).invalidatePlaylistProviders(playlistId);
        } catch (e) {
          // 继续处理其他歌单
        }
      }

      // 再处理添加
      for (final playlistId in toAdd) {
        try {
          for (final track in widget.tracks) {
            await service.addTrackToPlaylist(playlistId, track);
          }
          addSuccessCount++;
          ref.read(playlistListProvider.notifier).invalidatePlaylistProviders(playlistId);
        } catch (e) {
          // 继续处理其他歌单
        }
      }

      // 刷新歌单列表
      ref.invalidate(allPlaylistsProvider);
      // watch 自动更新歌单列表，无需手动刷新

      if (mounted) {
        // 根据操作结果显示不同的提示
        final totalChanged = toAdd.length + toRemove.length;
        final totalSuccess = addSuccessCount + removeSuccessCount;

        if (totalSuccess == totalChanged) {
          if (toAdd.isNotEmpty && toRemove.isNotEmpty) {
            ToastService.success(context, '已添加 $addSuccessCount 个，移出 $removeSuccessCount 个');
          } else if (toAdd.isNotEmpty) {
            ToastService.success(context, '已添加到 $addSuccessCount 个歌单');
          } else {
            ToastService.success(context, '已从 $removeSuccessCount 个歌单移出');
          }
        } else {
          ToastService.warning(context, '完成 $totalSuccess/$totalChanged 个操作');
        }
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ToastService.error(context, '操作失败: $e');
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
