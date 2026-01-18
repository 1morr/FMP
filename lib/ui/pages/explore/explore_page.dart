import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../data/models/track.dart';
import '../../../providers/popular_provider.dart';
import '../../../services/audio/audio_provider.dart';

/// 探索页面 - 显示热门和排行榜内容
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

    // 初始加载
    Future.microtask(() {
      ref.read(popularVideosProvider.notifier).load();
      ref.read(rankingVideosProvider.notifier).loadCategory(BilibiliCategory.music);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('探索'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '热门'),
            Tab(text: '排行榜'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPopularTab(colorScheme),
          _buildRankingTab(colorScheme),
        ],
      ),
    );
  }

  Widget _buildPopularTab(ColorScheme colorScheme) {
    final state = ref.watch(popularVideosProvider);

    if (state.tracks.isEmpty && state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败: ${state.error}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(popularVideosProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(popularVideosProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: state.tracks.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.tracks.length) {
            // 加载更多
            if (!state.isLoading) {
              Future.microtask(
                () => ref.read(popularVideosProvider.notifier).loadMore(),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final track = state.tracks[index];
          return _buildTrackTile(track, colorScheme);
        },
      ),
    );
  }

  Widget _buildRankingTab(ColorScheme colorScheme) {
    final state = ref.watch(rankingVideosProvider);

    return Column(
      children: [
        // 分区选择器
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: BilibiliCategory.values.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = BilibiliCategory.values[index];
              final isSelected = category == state.selectedCategory;
              return FilterChip(
                label: Text(category.label),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    ref.read(rankingVideosProvider.notifier).loadCategory(category);
                  }
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        // 排行榜内容
        Expanded(
          child: _buildRankingContent(state, colorScheme),
        ),
      ],
    );
  }

  Widget _buildRankingContent(RankingState state, ColorScheme colorScheme) {
    if (state.isLoading && state.currentTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.currentTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败: ${state.error}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(rankingVideosProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.currentTracks.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(rankingVideosProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: state.currentTracks.length,
        itemBuilder: (context, index) {
          final track = state.currentTracks[index];
          return _buildRankingTile(track, index + 1, colorScheme);
        },
      ),
    );
  }

  Widget _buildTrackTile(Track track, ColorScheme colorScheme) {
    return ListTile(
      leading: SizedBox(
        width: 80,
        height: 60,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: track.thumbnailUrl != null
              ? ImageLoadingService.loadImage(
                  networkUrl: track.thumbnailUrl,
                  placeholder: const Icon(Icons.music_note),
                  fit: BoxFit.cover,
                )
              : Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.music_note),
                ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              track.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (track.viewCount != null)
            Text(
              _formatViewCount(track.viewCount!),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
        ],
      ),
      onTap: () {
        ref.read(audioControllerProvider.notifier).playTemporary(track);
      },
    );
  }

  Widget _buildRankingTile(Track track, int rank, ColorScheme colorScheme) {
    final rankColor = switch (rank) {
      1 => Colors.amber,
      2 => Colors.grey.shade400,
      3 => Colors.brown.shade300,
      _ => colorScheme.outline,
    };

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: rank <= 3 ? 18 : 14,
                fontWeight: rank <= 3 ? FontWeight.bold : FontWeight.normal,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            height: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: track.thumbnailUrl != null
                  ? ImageLoadingService.loadImage(
                      networkUrl: track.thumbnailUrl,
                      placeholder: const Icon(Icons.music_note),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.music_note),
                    ),
            ),
          ),
        ],
      ),
      title: Text(
        track.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              track.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (track.viewCount != null)
            Text(
              _formatViewCount(track.viewCount!),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
        ],
      ),
      onTap: () {
        ref.read(audioControllerProvider.notifier).playTemporary(track);
      },
    );
  }

  String _formatViewCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿播放';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万播放';
    }
    return '$count播放';
  }
}
