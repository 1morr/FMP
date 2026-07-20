import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/search/popular_provider.dart';
import '../../../providers/ui/selection_provider.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../widgets/feedback/error_display.dart';
import '../../widgets/app_bars/selection_mode_app_bar.dart';
import '../../widgets/track_tiles/ranking_track_tile.dart';

/// 探索页面 - 显示音乐排行榜
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabIndexChanged);
    // 不再需要手動加載，直接使用緩存服務的數據
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabIndexChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabIndexChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    if (_activeTabIndex == _tabController.index) return;
    setState(() {
      _activeTabIndex = _tabController.index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectionState = ref.watch(exploreSelectionProvider);

    // 獲取當前 tab 的 tracks 用於全選
    final currentTracks = switch (_activeTabIndex) {
      0 => ref.watch(cachedBilibiliRankingProvider),
      1 => ref.watch(cachedYouTubeRankingProvider),
      _ => ref.watch(cachedNeteaseRankingProvider),
    };

    // 多選模式下的可用操作（探索頁不支持下載和刪除）
    const availableActions = <String>{
      selectionActionAddToQueue,
      selectionActionPlayNext,
      selectionActionAddToPlaylist,
      selectionActionAddToRemotePlaylist,
    };

    return PopScope(
      canPop: !selectionState.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectionState.isSelectionMode) {
          ref.read(exploreSelectionProvider.notifier).exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: selectionState.isSelectionMode
            ? SelectionModeAppBar(
                selectionProvider: exploreSelectionProvider,
                allTracks: currentTracks,
                availableActions: availableActions,
                bottom: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: t.importPlatform.bilibili),
                    const Tab(text: 'YouTube'),
                    Tab(text: t.importPlatform.netease),
                  ],
                ),
              )
            : AppBar(
                title: Text(t.nav.explore),
                bottom: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: t.importPlatform.bilibili),
                    const Tab(text: 'YouTube'),
                    Tab(text: t.importPlatform.netease),
                  ],
                ),
              ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildBilibiliTab(),
            _buildYouTubeTab(),
            _buildNeteaseTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildBilibiliTab() {
    final tracks = ref.watch(cachedBilibiliRankingProvider);
    final isInitialLoading = ref.watch(
      rankingCacheServiceProvider.select((state) => state.isInitialLoading),
    );
    final error = ref.watch(
      rankingCacheServiceProvider.select((state) => state.bilibiliError),
    );
    return _buildRankingContent(
      tracks: tracks,
      isLoading: isInitialLoading && tracks.isEmpty,
      error: error,
      onRefresh: () =>
          ref.read(rankingCacheServiceProvider.notifier).refreshBilibili(),
    );
  }

  Widget _buildYouTubeTab() {
    final tracks = ref.watch(cachedYouTubeRankingProvider);
    final isInitialLoading = ref.watch(
      rankingCacheServiceProvider.select((state) => state.isInitialLoading),
    );
    final error = ref.watch(
      rankingCacheServiceProvider.select((state) => state.youtubeError),
    );
    return _buildRankingContent(
      tracks: tracks,
      isLoading: isInitialLoading && tracks.isEmpty,
      error: error,
      onRefresh: () =>
          ref.read(rankingCacheServiceProvider.notifier).refreshYouTube(),
    );
  }

  Widget _buildNeteaseTab() {
    final tracks = ref.watch(cachedNeteaseRankingProvider);
    final isInitialLoading = ref.watch(
      rankingCacheServiceProvider.select((state) => state.isInitialLoading),
    );
    final error = ref.watch(
      rankingCacheServiceProvider.select((state) => state.neteaseError),
    );
    return _buildRankingContent(
      tracks: tracks,
      isLoading: isInitialLoading && tracks.isEmpty,
      error: error,
      onRefresh: () =>
          ref.read(rankingCacheServiceProvider.notifier).refreshNetease(),
    );
  }

  Widget _buildRankingContent({
    required List<Track> tracks,
    required bool isLoading,
    required String? error,
    required Future<void> Function() onRefresh,
  }) {
    if (isLoading && tracks.isEmpty) {
      return const LoadingPlaceholder();
    }

    if (error != null && tracks.isEmpty) {
      return ErrorDisplay(
        type: ErrorType.general,
        message: t.general.loadFailed,
        onRetry: () => onRefresh(),
      );
    }

    if (tracks.isEmpty) {
      return ErrorDisplay.empty(
        message: t.databaseViewer.noData,
        icon: Icons.library_music_outlined,
        onRetry: () => onRefresh(),
      );
    }

    final selectionState = ref.watch(exploreSelectionProvider);
    final selectionNotifier = ref.read(exploreSelectionProvider.notifier);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: tracks.length,
        // 预加载视口外 500px 的项目，减少快速滚动时的空白
        scrollCacheExtent: const ScrollCacheExtent.pixels(500),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return RepaintBoundary(
            child: RankingTrackTile(
              key: ValueKey('${track.sourceId}_${track.pageNum}'),
              track: track,
              rank: index + 1,
              isSelectionMode: selectionState.isSelectionMode,
              isSelected: selectionState.isSelected(track),
              onTap: selectionState.isSelectionMode
                  ? () => selectionNotifier.toggleSelection(track)
                  : null,
              onLongPress: selectionState.isSelectionMode
                  ? null
                  : () => selectionNotifier.enterSelectionMode(track),
            ),
          );
        },
      ),
    );
  }
}
