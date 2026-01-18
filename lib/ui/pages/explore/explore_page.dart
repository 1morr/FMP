import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../providers/popular_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/track_thumbnail.dart';

/// 探索页面 - 显示音乐排行榜
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 初始加载音乐分类
    Future.microtask(() {
      ref.read(rankingVideosProvider.notifier).loadCategory(BilibiliCategory.music);
      ref.read(youtubeTrendingProvider.notifier).loadCategory(YouTubeCategory.music);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('探索'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Bilibili'),
            Tab(text: 'YouTube'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBilibiliTab(),
          _buildYouTubeTab(),
        ],
      ),
    );
  }

  Widget _buildBilibiliTab() {
    final state = ref.watch(rankingVideosProvider);
    return _buildRankingContent(
      tracks: state.currentTracks,
      isLoading: state.isLoading,
      error: state.error,
      onRefresh: () => ref.read(rankingVideosProvider.notifier).refresh(),
    );
  }

  Widget _buildYouTubeTab() {
    final state = ref.watch(youtubeTrendingProvider);
    return _buildRankingContent(
      tracks: state.currentTracks,
      isLoading: state.isLoading,
      error: state.error,
      onRefresh: () => ref.read(youtubeTrendingProvider.notifier).refresh(),
    );
  }

  Widget _buildRankingContent({
    required List<Track> tracks,
    required bool isLoading,
    required String? error,
    required Future<void> Function() onRefresh,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isLoading && tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              '載入失敗',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRefresh,
              child: const Text('重試'),
            ),
          ],
        ),
      );
    }

    if (tracks.isEmpty) {
      return const Center(child: Text('暫無數據'));
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _ExploreTrackTile(track: track, rank: index + 1);
        },
      ),
    );
  }
}

/// 探索頁面歌曲項目（類似搜索結果項目）
class _ExploreTrackTile extends ConsumerWidget {
  final Track track;
  final int rank;

  const _ExploreTrackTile({required this.track, required this.rank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;

    return InkWell(
      onTap: () {
        ref.read(audioControllerProvider.notifier).playTemporary(track);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 排名數字
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            // 封面或播放指示器
            SizedBox(
              width: 48,
              height: 48,
              child: isPlaying
                  ? Center(
                      child: NowPlayingIndicator(
                        size: 28,
                        color: colorScheme.primary,
                      ),
                    )
                  : TrackThumbnail(
                      track: track,
                      size: 48,
                      borderRadius: 4,
                    ),
            ),
            const SizedBox(width: 16),
            // 標題和副標題
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: isPlaying ? colorScheme.primary : null,
                          fontWeight: isPlaying ? FontWeight.w600 : null,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          track.artist ?? '未知藝術家',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                        ),
                      ),
                      if (track.viewCount != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatViewCount(track.viewCount!),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // 菜單按鈕
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: colorScheme.onSurfaceVariant,
              ),
              onSelected: (value) => _handleMenuAction(context, ref, value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'play',
                  child: ListTile(
                    leading: Icon(Icons.play_arrow),
                    title: Text('播放'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
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
                    title: Text('添加到隊列'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'add_to_playlist',
                  child: ListTile(
                    leading: Icon(Icons.playlist_add),
                    title: Text('添加到歌單'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
    final controller = ref.read(audioControllerProvider.notifier);

    switch (action) {
      case 'play':
        controller.playTemporary(track);
        break;
      case 'play_next':
        controller.addNext(track);
        ToastService.show(context, '已添加到下一首');
        break;
      case 'add_to_queue':
        controller.addToQueue(track);
        ToastService.show(context, '已添加到播放隊列');
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
    }
  }

  String _formatViewCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}億';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}萬';
    }
    return count.toString();
  }
}
