import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../data/models/play_history.dart';
import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/play_history_provider.dart';
import '../../../providers/popular_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';
import '../../widgets/track_thumbnail.dart';

/// 首页
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // 热门推荐
              _buildPopularPreview(context, colorScheme),

              // 我的歌单
              _buildRecentPlaylists(context, colorScheme),

              // 最近播放历史
              _buildRecentHistory(context, colorScheme),

              // 队列预览
              if (playerState.queue.isNotEmpty)
                _buildQueuePreview(context, playerState, colorScheme),

              const SizedBox(height: 100), // 为迷你播放器留出空间
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopularPreview(BuildContext context, ColorScheme colorScheme) {
    final popularAsync = ref.watch(homePopularPreviewProvider);

    return popularAsync.when(
      loading: () => _buildSectionLoading(context, '热门推荐'),
      error: (e, s) => const SizedBox.shrink(),
      data: (tracks) {
        if (tracks.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    '热门推荐',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Bilibili',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go(RoutePaths.explore),
                    child: const Text('更多'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tracks.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return _buildPopularItem(context, track, colorScheme);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPopularItem(
    BuildContext context,
    Track track,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      width: 120,
      height: 160,
      child: InkWell(
        onTap: () {
          ref.read(audioControllerProvider.notifier).playTemporary(track);
        },
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.surfaceContainerHighest,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  track.thumbnailUrl != null
                      ? ImageLoadingService.loadImage(
                          networkUrl: track.thumbnailUrl,
                          placeholder: Icon(
                            Icons.local_fire_department,
                            size: 40,
                            color: colorScheme.outline,
                          ),
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          Icons.local_fire_department,
                          size: 40,
                          color: colorScheme.outline,
                        ),
                  // 播放量标签
                  if (track.viewCount != null)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_arrow,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _formatViewCount(track.viewCount!),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // 标题
            Text(
              track.title,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLoading(BuildContext context, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(
          height: 160,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }

  String _formatViewCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  Widget _buildRecentPlaylists(BuildContext context, ColorScheme colorScheme) {
    final playlists = ref.watch(allPlaylistsProvider);

    return playlists.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (lists) {
        if (lists.isEmpty) return const SizedBox.shrink();

        // 根据屏幕宽度响应式计算显示数量
        final screenWidth = MediaQuery.of(context).size.width;
        final itemWidth = 120.0 + 12.0; // 卡片宽度 + 间距
        final padding = 32.0; // 左右内边距
        final availableWidth = screenWidth - padding;
        final calculatedItems = (availableWidth / itemWidth).floor();
        final maxItems = calculatedItems.clamp(1, lists.length);
        final recentLists = lists.take(maxItems).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    '我的歌单',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go(RoutePaths.library),
                    child: const Text('查看全部'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 152,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recentLists.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final playlist = recentLists[index];
                  final coverAsync =
                      ref.watch(playlistCoverProvider(playlist.id));

                  // 預加載歌單詳情數據
                  ref.read(playlistDetailProvider(playlist.id));

                  return SizedBox(
                    width: 120,
                    child: InkWell(
                      onTap: () => context.go('/library/${playlist.id}'),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 封面
                          AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: colorScheme.surfaceContainerHighest,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: coverAsync.when(
                                skipLoadingOnReload: true,
                                data: (coverData) => coverData.hasCover
                                    ? ImageLoadingService.loadImage(
                                        localPath: coverData.localPath,
                                        networkUrl: coverData.networkUrl,
                                        placeholder: Icon(
                                          Icons.album,
                                          size: 40,
                                          color: colorScheme.outline,
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : Icon(
                                        Icons.album,
                                        size: 40,
                                        color: colorScheme.outline,
                                      ),
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (e, s) => Icon(
                                  Icons.album,
                                  size: 40,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 名称
                          Text(
                            playlist.name,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentHistory(BuildContext context, ColorScheme colorScheme) {
    final historyAsync = ref.watch(recentPlayHistoryProvider);

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (historyList) {
        if (historyList.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    '最近播放',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  // TODO: 查看全部历史页面
                ],
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: historyList.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final history = historyList[index];
                  return _buildHistoryItem(context, history, colorScheme);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    PlayHistory history,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      width: 120,
      height: 160,
      child: InkWell(
        onTap: () {
          // 将历史记录转换为 Track 并播放
          final track = history.toTrack();
          ref.read(audioControllerProvider.notifier).playTemporary(track);
        },
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面 (120x120)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.surfaceContainerHighest,
              ),
              clipBehavior: Clip.antiAlias,
              child: history.thumbnailUrl != null
                  ? ImageLoadingService.loadImage(
                      networkUrl: history.thumbnailUrl,
                      placeholder: Icon(
                        Icons.music_note,
                        size: 40,
                        color: colorScheme.outline,
                      ),
                      fit: BoxFit.cover,
                    )
                  : Icon(
                      Icons.music_note,
                      size: 40,
                      color: colorScheme.outline,
                    ),
            ),
            const SizedBox(height: 4),
            // 标题 (剩余 36px 空间，约2行文本)
            Text(
              history.title,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueuePreview(
    BuildContext context,
    PlayerState playerState,
    ColorScheme colorScheme,
  ) {
    // 使用 upcomingTracks 获取接下来要播放的歌曲（已考虑 shuffle 模式）
    final upNext = playerState.upcomingTracks.take(3).toList();
    if (upNext.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                '接下来播放',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(RoutePaths.queue),
                child: const Text('查看队列'),
              ),
            ],
          ),
        ),
        ...upNext.map((track) => ListTile(
              leading: TrackThumbnail(
                track: track,
                size: 40,
                borderRadius: 4,
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.artist ?? '未知艺术家',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              dense: true,
              onTap: () {
                final trackIndex = playerState.queue.indexOf(track);
                if (trackIndex >= 0) {
                  ref.read(audioControllerProvider.notifier).playAt(trackIndex);
                }
              },
            )),
      ],
    );
  }
}
