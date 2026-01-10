import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/track.dart';
import '../../../providers/download_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/now_playing_indicator.dart';

/// 已下载分类详情页面
class DownloadedCategoryPage extends ConsumerStatefulWidget {
  final DownloadedCategory category;

  const DownloadedCategoryPage({super.key, required this.category});

  @override
  ConsumerState<DownloadedCategoryPage> createState() => _DownloadedCategoryPageState();
}

class _DownloadedCategoryPageState extends ConsumerState<DownloadedCategoryPage> {
  // 展开状态：key是groupKey
  final Set<String> _expandedGroups = {};

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(downloadedCategoryTracksProvider(widget.category.folderPath));
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: tracksAsync.when(
        loading: () => CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, []),
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (error, stack) => CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, []),
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text('加载失败: $error'),
                  ],
                ),
              ),
            ),
          ],
        ),
        data: (tracks) {
          // 将tracks按groupKey分组
          final groupedTracks = _groupTracks(tracks);

          return CustomScrollView(
            slivers: [
              // 折叠式应用栏
              _buildSliverAppBar(context, tracks),

              // 操作按钮
              SliverToBoxAdapter(
                child: _buildActionButtons(context, tracks),
              ),

              // 歌曲列表
              if (tracks.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyState(context),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final group = groupedTracks[index];
                      return _buildGroupItem(context, group);
                    },
                    childCount: groupedTracks.length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, List<Track> tracks) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalDuration = _calculateTotalDuration(tracks);

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 封面背景
            _buildCoverBackground(colorScheme),

            // 渐变遮罩
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    colorScheme.surface.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),

            // 分类信息
            Positioned(
              left: 16,
              right: 16,
              bottom: 70,
              child: Row(
                children: [
                  // 封面
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildCover(colorScheme),
                  ),
                  const SizedBox(width: 16),

                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 分类名称
                        Text(
                          widget.category.displayName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.category.trackCount} 首歌曲 · ${_formatDuration(totalDuration)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white60,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.download_done,
                                size: 14,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '已下载',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverBackground(ColorScheme colorScheme) {
    if (widget.category.coverPath != null) {
      final coverFile = File(widget.category.coverPath!);
      if (coverFile.existsSync()) {
        return Image.file(
          coverFile,
          fit: BoxFit.cover,
          color: Colors.black54,
          colorBlendMode: BlendMode.darken,
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.tertiaryContainer,
          ],
        ),
      ),
    );
  }

  Widget _buildCover(ColorScheme colorScheme) {
    if (widget.category.coverPath != null) {
      final coverFile = File(widget.category.coverPath!);
      if (coverFile.existsSync()) {
        return Image.file(
          coverFile,
          fit: BoxFit.cover,
        );
      }
    }
    return Container(
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.folder,
        size: 48,
        color: colorScheme.primary,
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, List<Track> tracks) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: tracks.isEmpty ? null : () => _playAll(tracks),
              icon: const Icon(Icons.play_arrow),
              label: const Text('添加所有'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: tracks.isEmpty ? null : () => _shufflePlay(tracks),
              icon: const Icon(Icons.shuffle),
              label: const Text('随机添加'),
            ),
          ),
        ],
      ),
    );
  }

  Duration _calculateTotalDuration(List<Track> tracks) {
    int totalMs = 0;
    for (final track in tracks) {
      totalMs += track.durationMs ?? 0;
    }
    return Duration(milliseconds: totalMs);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours 小时 $minutes 分钟';
    }
    return '$minutes 分钟';
  }

  void _playAll(List<Track> tracks) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.addAllToQueue(tracks);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 ${tracks.length} 首歌曲到队列')),
    );
  }

  void _shufflePlay(List<Track> tracks) {
    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(tracks)..shuffle();
    controller.addAllToQueue(shuffled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已随机添加 ${tracks.length} 首歌曲到队列')),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '此分类下暂无歌曲',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  /// 将tracks按groupKey分组
  List<_TrackGroup> _groupTracks(List<Track> tracks) {
    final Map<String, List<Track>> grouped = {};
    final List<String> order = [];

    for (final track in tracks) {
      final key = track.groupKey;
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        order.add(key);
      }
      grouped[key]!.add(track);
    }

    return order.map((key) {
      final groupTracks = grouped[key]!;
      // 按pageNum排序
      groupTracks.sort((a, b) => (a.pageNum ?? 0).compareTo(b.pageNum ?? 0));
      return _TrackGroup(
        groupKey: key,
        tracks: groupTracks,
        parentTitle: groupTracks.first.parentTitle ?? groupTracks.first.title,
      );
    }).toList();
  }

  /// 构建分组项
  Widget _buildGroupItem(BuildContext context, _TrackGroup group) {
    // 如果组只有一个track，显示普通样式
    if (group.tracks.length == 1) {
      return _DownloadedTrackTile(
        track: group.tracks.first,
        onTap: () => _playTrack(group.tracks.first),
        isPartOfMultiPage: false,
      );
    }

    // 多P视频，显示可展开样式
    final isExpanded = _expandedGroups.contains(group.groupKey);

    return Column(
      children: [
        // 父视频标题行
        _GroupHeader(
          group: group,
          isExpanded: isExpanded,
          onToggle: () => _toggleGroup(group.groupKey),
          onPlayFirst: () => _playTrack(group.tracks.first),
          onAddAllToQueue: () => _addAllToQueue(context, group.tracks),
        ),
        // 展开的分P列表
        if (isExpanded)
          ...group.tracks.map((track) => _DownloadedTrackTile(
                track: track,
                onTap: () => _playTrack(track),
                isPartOfMultiPage: true,
                indent: true,
              )),
      ],
    );
  }

  void _toggleGroup(String groupKey) {
    setState(() {
      if (_expandedGroups.contains(groupKey)) {
        _expandedGroups.remove(groupKey);
      } else {
        _expandedGroups.add(groupKey);
      }
    });
  }

  void _addAllToQueue(BuildContext context, List<Track> tracks) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.addAllToQueue(tracks);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 ${tracks.length} 个分P到队列')),
    );
  }

  void _playTrack(Track track) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.playTemporary(track);
  }
}

/// 分组数据类
class _TrackGroup {
  final String groupKey;
  final List<Track> tracks;
  final String parentTitle;

  _TrackGroup({
    required this.groupKey,
    required this.tracks,
    required this.parentTitle,
  });
}

/// 分组标题组件
class _GroupHeader extends ConsumerWidget {
  final _TrackGroup group;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onPlayFirst;
  final VoidCallback onAddAllToQueue;

  const _GroupHeader({
    required this.group,
    required this.isExpanded,
    required this.onToggle,
    required this.onPlayFirst,
    required this.onAddAllToQueue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstTrack = group.tracks.first;
    final currentTrack = ref.watch(currentTrackProvider);
    // 检查当前播放的是否是这个组的某个分P
    final isPlayingThisGroup =
        currentTrack != null && group.tracks.any((t) => t.id == currentTrack.id);

    return ListTile(
      onTap: onToggle,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: colorScheme.surfaceContainerHighest,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              _buildThumbnail(firstTrack, colorScheme),
              if (isPlayingThisGroup)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: colorScheme.primary.withValues(alpha: 0.8),
                  ),
                  child: const Center(
                    child: NowPlayingIndicator(
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Text(
        group.parentTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlayingThisGroup ? colorScheme.primary : null,
          fontWeight: isPlayingThisGroup ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Row(
        children: [
          Text(
            firstTrack.artist ?? '未知UP主',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${group.tracks.length}P',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.download_done,
            size: 14,
            color: colorScheme.primary,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 展开/折叠按钮
          IconButton(
            icon: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onPressed: onToggle,
          ),
          // 菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleMenuAction(context, ref, value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'play_first',
                child: ListTile(
                  leading: Icon(Icons.play_arrow),
                  title: Text('播放第一个分P'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'add_all_to_queue',
                child: ListTile(
                  leading: Icon(Icons.add_to_queue),
                  title: Text('添加全部到队列'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'add_to_playlist',
                child: ListTile(
                  leading: Icon(Icons.playlist_add),
                  title: Text('添加到歌单'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete_all',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除全部下载'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(Track track, ColorScheme colorScheme) {
    // 尝试加载本地封面
    if (track.downloadedPath != null) {
      final dir = Directory(track.downloadedPath!).parent;
      final coverFile = File('${dir.path}/cover.jpg');
      if (coverFile.existsSync()) {
        return Image.file(
          coverFile,
          fit: BoxFit.cover,
          width: 48,
          height: 48,
        );
      }
    }

    // 回退到网络封面
    if (track.thumbnailUrl != null) {
      return Image.network(
        track.thumbnailUrl!,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(
            Icons.music_note,
            color: colorScheme.outline,
          ),
        ),
      );
    }

    return Center(
      child: Icon(
        Icons.music_note,
        color: colorScheme.outline,
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_first':
        onPlayFirst();
        break;
      case 'add_all_to_queue':
        onAddAllToQueue();
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, tracks: group.tracks);
        break;
      case 'delete_all':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除下载'),
            content: Text('确定要删除 ${group.tracks.length} 个分P的下载文件吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await _deleteAllDownloads(ref);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已删除 ${group.tracks.length} 个分P的下载文件')),
            );
          }
        }
        break;
    }
  }

  Future<void> _deleteAllDownloads(WidgetRef ref) async {
    final trackRepo = ref.read(trackRepositoryProvider);
    for (final track in group.tracks) {
      // 删除文件
      if (track.downloadedPath != null) {
        final file = File(track.downloadedPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      // 清除数据库中的下载路径
      await trackRepo.clearDownloadPath(track.id);
    }
  }
}

/// 已下载歌曲列表项
class _DownloadedTrackTile extends ConsumerWidget {
  final Track track;
  final VoidCallback onTap;
  final bool isPartOfMultiPage;
  final bool indent;

  const _DownloadedTrackTile({
    required this.track,
    required this.onTap,
    required this.isPartOfMultiPage,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = currentTrack?.id == track.id;

    return Padding(
      padding: EdgeInsets.only(left: indent ? 56 : 0),
      child: ListTile(
        // 分P不显示封面（因为都是一样的）
        leading: isPartOfMultiPage
            ? null
            : SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  children: [
                    // 封面
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _buildThumbnail(colorScheme),
                    ),

                    // 播放中指示
                    if (isPlaying)
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: colorScheme.primary.withValues(alpha: 0.8),
                        ),
                        child: const Center(
                          child: NowPlayingIndicator(
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        title: Row(
          children: [
            // 分P时如果正在播放，显示播放指示器
            if (isPartOfMultiPage && isPlaying) ...[
              NowPlayingIndicator(
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPlaying ? colorScheme.primary : null,
                  fontWeight: isPlaying ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                isPartOfMultiPage
                    ? 'P${track.pageNum ?? 1} · ${_formatTrackDuration(track.durationMs ?? 0)}'
                    : track.artist ?? '未知艺术家',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.download_done,
              size: 14,
              color: colorScheme.primary,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isPartOfMultiPage && track.durationMs != null)
              SizedBox(
                width: 48,
                child: Center(
                  child: Text(
                    _formatTrackDuration(track.durationMs!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                  ),
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _handleMenuAction(context, ref, value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'play_next',
                  child: ListTile(
                    leading: Icon(Icons.queue_play_next),
                    title: Text('下一首播放'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'add_to_queue',
                  child: ListTile(
                    leading: Icon(Icons.add_to_queue),
                    title: Text('添加到队列'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!isPartOfMultiPage)
                  const PopupMenuItem(
                    value: 'add_to_playlist',
                    child: ListTile(
                      leading: Icon(Icons.playlist_add),
                      title: Text('添加到歌单'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('删除下载'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme colorScheme) {
    // 尝试加载本地封面
    if (track.downloadedPath != null) {
      final dir = Directory(track.downloadedPath!).parent;
      final coverFile = File('${dir.path}/cover.jpg');
      if (coverFile.existsSync()) {
        return Image.file(
          coverFile,
          fit: BoxFit.cover,
          width: 48,
          height: 48,
        );
      }
    }

    // 回退到网络封面
    if (track.thumbnailUrl != null) {
      return Image.network(
        track.thumbnailUrl!,
        fit: BoxFit.cover,
        width: 48,
        height: 48,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(
            Icons.music_note,
            color: colorScheme.outline,
          ),
        ),
      );
    }

    return Center(
      child: Icon(
        Icons.music_note,
        color: colorScheme.outline,
      ),
    );
  }

  String _formatTrackDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_next':
        ref.read(audioControllerProvider.notifier).addNext(track);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到下一首')),
        );
        break;
      case 'add_to_queue':
        ref.read(audioControllerProvider.notifier).addToQueue(track);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到播放队列')),
        );
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除下载'),
            content: const Text('确定要删除这首歌曲的下载文件吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await _deleteDownload(ref);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已删除下载文件')),
            );
          }
        }
        break;
    }
  }

  Future<void> _deleteDownload(WidgetRef ref) async {
    final trackRepo = ref.read(trackRepositoryProvider);

    // 删除文件
    if (track.downloadedPath != null) {
      final file = File(track.downloadedPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    // 清除数据库中的下载路径
    await trackRepo.clearDownloadPath(track.id);
  }
}
