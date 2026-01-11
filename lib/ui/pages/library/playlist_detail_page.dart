import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/track_group/track_group.dart';
import '../../widgets/track_thumbnail.dart';

/// 歌单详情页
class PlaylistDetailPage extends ConsumerStatefulWidget {
  final int playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  // 展开状态：key是groupKey
  final Set<String> _expandedGroups = {};

  // 缓存分组结果，避免每次 build 重新计算
  List<Track>? _cachedTracks;
  List<TrackGroup>? _cachedGroups;

  /// 获取分组后的 tracks，使用缓存避免重复计算
  List<TrackGroup> _getGroupedTracks(List<Track> tracks) {
    // 检查是否需要重新计算
    if (_cachedTracks != tracks || _cachedGroups == null) {
      _cachedTracks = tracks;
      _cachedGroups = groupTracks(tracks);
    }
    return _cachedGroups!;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playlistDetailProvider(widget.playlistId));
    final colorScheme = Theme.of(context).colorScheme;

    if (state.isLoading && state.playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null && state.playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(state.error!),
            ],
          ),
        ),
      );
    }

    final playlist = state.playlist!;
    final tracks = state.tracks;

    // 使用缓存的分组结果，避免每次 build 重新计算
    final groupedTracks = _getGroupedTracks(tracks);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 折叠式应用栏
          _buildSliverAppBar(context, playlist, state),

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
      ),
    );
  }

  /// 构建分组项
  Widget _buildGroupItem(BuildContext context, TrackGroup group) {
    // 如果组只有一个track，显示普通样式
    if (group.tracks.length == 1) {
      return _TrackListTile(
        track: group.tracks.first,
        playlistId: widget.playlistId,
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
          playlistId: widget.playlistId,
        ),
        // 展开的分P列表
        if (isExpanded)
          ...group.tracks.map((track) => _TrackListTile(
                track: track,
                playlistId: widget.playlistId,
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
    ToastService.show(context, '已添加 ${tracks.length} 个分P到队列');
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    dynamic playlist,
    PlaylistDetailState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverAsync = ref.watch(playlistCoverProvider(widget.playlistId));

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 封面背景
            coverAsync.when(
              data: (coverUrl) => coverUrl != null
                  ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      color: Colors.black54,
                      colorBlendMode: BlendMode.darken,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: colorScheme.primaryContainer),
                    )
                  : Container(color: colorScheme.primaryContainer),
              loading: () => Container(color: colorScheme.primaryContainer),
              error: (error, stack) =>
                  Container(color: colorScheme.primaryContainer),
            ),

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

            // 歌单信息
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
                    child: coverAsync.when(
                      data: (coverUrl) => coverUrl != null
                          ? Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                color: colorScheme.primaryContainer,
                                child: Center(
                                  child: Icon(
                                    Icons.music_note,
                                    size: 48,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: colorScheme.primaryContainer,
                              child: Center(
                                child: Icon(
                                  Icons.music_note,
                                  size: 48,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                      loading: () => Container(
                          color: colorScheme.surfaceContainerHighest),
                      error: (error, stack) => Container(
                          color: colorScheme.surfaceContainerHighest),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 歌单名称
                        Text(
                          playlist.name,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (playlist.description != null &&
                            playlist.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            playlist.description!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white70,
                                    ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${state.tracks.length} 首歌曲 · ${DurationFormatter.formatLong(state.totalDuration)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white60,
                                  ),
                        ),
                        if (playlist.isImported) ...[
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
                                  Icons.link,
                                  size: 14,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '已导入',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

  Widget _buildActionButtons(
    BuildContext context,
    List<Track> tracks,
  ) {
    final state = ref.watch(playlistDetailProvider(widget.playlistId));
    final playlist = state.playlist;
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      tracks.isEmpty ? null : () => _playAll(tracks, context),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('添加所有'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      tracks.isEmpty ? null : () => _shufflePlay(tracks, context),
                  icon: const Icon(Icons.shuffle),
                  label: const Text('随机添加'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 下载按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: tracks.isEmpty || playlist == null 
                  ? null 
                  : () => _downloadPlaylist(context, playlist),
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载全部'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '歌单暂无歌曲',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '去搜索页面添加歌曲吧',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  void _playAll(List<Track> tracks, BuildContext context) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.addAllToQueue(tracks);
    ToastService.show(context, '已添加 ${tracks.length} 首歌曲到队列');
  }

  void _shufflePlay(List<Track> tracks, BuildContext context) {
    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(tracks)..shuffle();
    controller.addAllToQueue(shuffled);
    ToastService.show(context, '已随机添加 ${tracks.length} 首歌曲到队列');
  }

  void _playTrack(Track track) {
    final controller = ref.read(audioControllerProvider.notifier);
    // 临时播放点击的歌曲，播放完成后恢复原队列位置
    controller.playTemporary(track);
  }
  
  void _downloadPlaylist(BuildContext context, dynamic playlist) async {
    final downloadService = ref.read(downloadServiceProvider);
    final result = await downloadService.addPlaylistDownload(playlist);
    
    if (context.mounted) {
      if (result != null) {
        ToastService.show(context, '已添加歌单"${playlist.name}"到下载队列');
      } else {
        ToastService.show(context, '歌单已在下载队列中或为空');
      }
    }
  }
}

/// 分组标题组件
class _GroupHeader extends ConsumerWidget {
  final TrackGroup group;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onPlayFirst;
  final VoidCallback onAddAllToQueue;
  final int playlistId;

  const _GroupHeader({
    required this.group,
    required this.isExpanded,
    required this.onToggle,
    required this.onPlayFirst,
    required this.onAddAllToQueue,
    required this.playlistId,
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
      leading: TrackThumbnail(
        track: firstTrack,
        size: 48,
        isPlaying: isPlayingThisGroup,
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
          // 检查是否所有分P都已下载
          if (group.tracks.every((t) =>
              t.downloadedPath != null &&
              File(t.downloadedPath!).existsSync())) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.download_done,
              size: 14,
              color: colorScheme.primary,
            ),
          ],
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
                value: 'download_all',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('下载全部分P'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'add_to_playlist',
                child: ListTile(
                  leading: Icon(Icons.playlist_add),
                  title: Text('添加到其他歌单'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'remove_all',
                child: ListTile(
                  leading: Icon(Icons.remove_circle_outline),
                  title: Text('从歌单移除全部'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
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
      case 'download_all':
        // 下载所有分P
        final downloadService = ref.read(downloadServiceProvider);
        int addedCount = 0;
        for (final track in group.tracks) {
          final result = await downloadService.addTrackDownload(track);
          if (result != null) addedCount++;
        }
        if (context.mounted) {
          ToastService.show(context, '已添加 $addedCount 个分P到下载队列');
        }
        break;
      case 'add_to_playlist':
        // 添加所有分P到其他歌单
        showAddToPlaylistDialog(context: context, tracks: group.tracks);
        break;
      case 'remove_all':
        // 移除所有分P
        final notifier = ref.read(playlistDetailProvider(playlistId).notifier);
        for (final track in group.tracks) {
          notifier.removeTrack(track.id);
        }
        ToastService.show(context, '已从歌单移除 ${group.tracks.length} 个分P');
        break;
    }
  }
}

/// 歌曲列表项
class _TrackListTile extends ConsumerWidget {
  final Track track;
  final int playlistId;
  final VoidCallback onTap;
  final bool isPartOfMultiPage;
  final bool indent;

  const _TrackListTile({
    required this.track,
    required this.playlistId,
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
            : TrackThumbnail(
                track: track,
                size: 48,
                isPlaying: isPlaying,
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
                    ? 'P${track.pageNum ?? 1} · ${DurationFormatter.formatMs(track.durationMs ?? 0)}'
                    : track.artist ?? '未知艺术家',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 检查歌曲是否已下载到本地
            if (track.downloadedPath != null &&
                File(track.downloadedPath!).existsSync())
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
                    DurationFormatter.formatMs(track.durationMs!),
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
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('下载'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // 分P不显示"添加到歌单"选项
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
                  value: 'remove',
                  child: ListTile(
                    leading: Icon(Icons.remove_circle_outline),
                    title: Text('从歌单移除'),
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

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    switch (action) {
      case 'play_next':
        ref.read(audioControllerProvider.notifier).addNext(track);
        ToastService.show(context, '已添加到下一首');
        break;
      case 'add_to_queue':
        ref.read(audioControllerProvider.notifier).addToQueue(track);
        ToastService.show(context, '已添加到播放队列');
        break;
      case 'download':
        final downloadService = ref.read(downloadServiceProvider);
        final result = await downloadService.addTrackDownload(track);
        if (context.mounted) {
          ToastService.show(
            context,
            result != null ? '已添加到下载队列' : '歌曲已下载或已在队列中',
          );
        }
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
      case 'remove':
        ref
            .read(playlistDetailProvider(playlistId).notifier)
            .removeTrack(track.id);
        ToastService.show(context, '已从歌单移除');
        break;
    }
  }
}
