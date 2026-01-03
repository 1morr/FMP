import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../../../services/audio/audio_provider.dart';

/// 歌单详情页
class PlaylistDetailPage extends ConsumerWidget {
  final int playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playlistDetailProvider(playlistId));
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 折叠式应用栏
          _buildSliverAppBar(context, ref, playlist, state),

          // 操作按钮
          SliverToBoxAdapter(
            child: _buildActionButtons(context, ref, tracks),
          ),

          // 歌曲列表
          if (tracks.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(context),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _TrackListTile(
                  track: tracks[index],
                  index: index,
                  playlistId: playlistId,
                  onTap: () => _playTrack(ref, tracks, index),
                ),
                childCount: tracks.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    WidgetRef ref,
    dynamic playlist,
    PlaylistDetailState state,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverAsync = ref.watch(playlistCoverProvider(playlistId));

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          playlist.name,
          style: const TextStyle(fontSize: 18),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 封面背景
            coverAsync.when(
              data: (coverUrl) => coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      color: Colors.black54,
                      colorBlendMode: BlendMode.darken,
                    )
                  : Container(color: colorScheme.primaryContainer),
              loading: () => Container(color: colorScheme.primaryContainer),
              error: (error, stack) => Container(color: colorScheme.primaryContainer),
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
                          ? CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: colorScheme.primaryContainer,
                              child: Icon(
                                Icons.album,
                                size: 48,
                                color: colorScheme.primary,
                              ),
                            ),
                      loading: () =>
                          Container(color: colorScheme.surfaceContainerHighest),
                      error: (error, stack) =>
                          Container(color: colorScheme.surfaceContainerHighest),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (playlist.description != null &&
                            playlist.description!.isNotEmpty)
                          Text(
                            playlist.description!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white70,
                                    ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '${state.tracks.length} 首歌曲 · ${_formatDuration(state.totalDuration)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white60,
                                  ),
                        ),
                        if (playlist.isImported) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.link,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '已导入',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colorScheme.primary,
                                    ),
                              ),
                            ],
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
    WidgetRef ref,
    List<Track> tracks,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: tracks.isEmpty ? null : () => _playAll(ref, tracks),
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放全部'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  tracks.isEmpty ? null : () => _shufflePlay(ref, tracks),
              icon: const Icon(Icons.shuffle),
              label: const Text('随机播放'),
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours 小时 $minutes 分钟';
    }
    return '$minutes 分钟';
  }

  void _playAll(WidgetRef ref, List<Track> tracks) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.playPlaylist(tracks, startIndex: 0);
  }

  void _shufflePlay(WidgetRef ref, List<Track> tracks) {
    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(tracks)..shuffle();
    controller.playPlaylist(shuffled, startIndex: 0);
  }

  void _playTrack(WidgetRef ref, List<Track> tracks, int index) {
    final controller = ref.read(audioControllerProvider.notifier);
    controller.playPlaylist(tracks, startIndex: index);
  }
}

/// 歌曲列表项
class _TrackListTile extends ConsumerWidget {
  final Track track;
  final int index;
  final int playlistId;
  final VoidCallback onTap;

  const _TrackListTile({
    required this.track,
    required this.index,
    required this.playlistId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = currentTrack?.id == track.id;

    return ListTile(
      leading: SizedBox(
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
              child: track.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: track.thumbnailUrl!,
                      fit: BoxFit.cover,
                      width: 48,
                      height: 48,
                    )
                  : Icon(
                      Icons.music_note,
                      color: colorScheme.outline,
                    ),
            ),

            // 播放中指示
            if (isPlaying)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: colorScheme.primary.withValues(alpha: 0.8),
                ),
                child: const Center(
                  child: Icon(
                    Icons.equalizer,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlaying ? colorScheme.primary : null,
          fontWeight: isPlaying ? FontWeight.w600 : null,
        ),
      ),
      subtitle: Text(
        track.artist ?? '未知艺术家',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.durationMs != null)
            Text(
              _formatTrackDuration(track.durationMs!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
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
    );
  }

  String _formatTrackDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'play_next':
        // TODO: 实现下一首播放
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到下一首')),
        );
        break;
      case 'add_to_queue':
        // TODO: 实现添加到队列
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加到播放队列')),
        );
        break;
      case 'remove':
        ref
            .read(playlistDetailProvider(playlistId).notifier)
            .removeTrack(track.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已从歌单移除')),
        );
        break;
    }
  }
}
