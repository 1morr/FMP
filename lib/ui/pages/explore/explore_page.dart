import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../providers/popular_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
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
    // 不再需要手動加載，直接使用緩存服務的數據
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
    final asyncValue = ref.watch(cachedBilibiliRankingProvider);
    return asyncValue.when(
      data: (tracks) => _buildRankingContent(
        tracks: tracks,
        isLoading: false,
        error: null,
        onRefresh: () async {
          // 觸發緩存刷新
          final service = ref.read(rankingCacheServiceProvider);
          await service.refreshBilibili();
        },
      ),
      loading: () => _buildRankingContent(
        tracks: [],
        isLoading: true,
        error: null,
        onRefresh: () async {},
      ),
      error: (_, _) => _buildRankingContent(
        tracks: [],
        isLoading: false,
        error: '載入失敗',
        onRefresh: () async {
          final service = ref.read(rankingCacheServiceProvider);
          await service.refreshBilibili();
        },
      ),
    );
  }

  Widget _buildYouTubeTab() {
    final asyncValue = ref.watch(cachedYouTubeRankingProvider);
    return asyncValue.when(
      data: (tracks) => _buildRankingContent(
        tracks: tracks,
        isLoading: false,
        error: null,
        onRefresh: () async {
          // 觸發緩存刷新
          final service = ref.read(rankingCacheServiceProvider);
          await service.refreshYouTube();
        },
      ),
      loading: () => _buildRankingContent(
        tracks: [],
        isLoading: true,
        error: null,
        onRefresh: () async {},
      ),
      error: (_, _) => _buildRankingContent(
        tracks: [],
        isLoading: false,
        error: '載入失敗',
        onRefresh: () async {
          final service = ref.read(rankingCacheServiceProvider);
          await service.refreshYouTube();
        },
      ),
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

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          TrackThumbnail(
            track: track,
            size: 48,
            borderRadius: 4,
            isPlaying: isPlaying,
          ),
        ],
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
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              track.artist ?? '未知藝術家',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (track.viewCount != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.play_arrow,
              size: 14,
              color: colorScheme.outline,
            ),
            const SizedBox(width: 2),
            Text(
              _formatViewCount(track.viewCount!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
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
      onTap: () {
        ref.read(audioControllerProvider.notifier).playTemporary(track);
      },
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);

    switch (action) {
      case 'play':
        controller.playTemporary(track);
        break;
      case 'play_next':
        final added = await controller.addNext(track);
        if (added && context.mounted) {
          ToastService.show(context, '已添加到下一首');
        }
        break;
      case 'add_to_queue':
        final added = await controller.addToQueue(track);
        if (added && context.mounted) {
          ToastService.show(context, '已添加到播放隊列');
        }
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
