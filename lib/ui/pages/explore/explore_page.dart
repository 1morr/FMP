import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/popular_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_menu.dart';
import '../../widgets/context_menu_region.dart';
import '../../widgets/error_display.dart';
import '../../widgets/selection_mode_app_bar.dart';
import '../../widgets/images/track_thumbnail.dart';
import '../../widgets/vip_badge.dart';

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
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/'),
                ),
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
        cacheExtent: 500,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return RepaintBoundary(
            child: _ExploreTrackTile(
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

/// 探索頁面歌曲項目（類似搜索結果項目）
class _ExploreTrackTile extends ConsumerWidget {
  final Track track;
  final int rank;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ExploreTrackTile({
    super.key,
    required this.track,
    required this.rank,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;

    return ContextMenuRegion(
      menuBuilder: (_) => _buildMenuItems(),
      onSelected: (value) => _handleMenuAction(context, ref, value),
      child: InkWell(
        onTap: onTap ??
            () {
              ref.read(audioControllerProvider.notifier).playTemporary(track);
            },
        onLongPress: onLongPress,
        borderRadius: AppRadius.borderRadiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 16,
          ),
          child: Row(
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
              const SizedBox(width: 16),
              TrackThumbnail(
                track: track,
                size: AppSizes.thumbnailMedium,
                borderRadius: 4,
                isPlaying: isPlaying,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: isPlaying ? colorScheme.primary : null,
                                  fontWeight:
                                      isPlaying ? FontWeight.w600 : null,
                                ),
                          ),
                        ),
                        if (track.isVip) ...[
                          const SizedBox(width: 4),
                          const VipBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.artist ?? t.general.unknownArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
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
                            formatCount(track.viewCount!),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelectionMode)
                _SelectionCheckbox(
                  isSelected: isSelected,
                  onTap: onTap,
                )
              else
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) => _handleMenuAction(context, ref, value),
                  itemBuilder: (_) => _buildMenuItems(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
    );
  }

  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
  }
}

/// 圓形選擇勾選框
class _SelectionCheckbox extends StatelessWidget {
  final bool isSelected;
  final VoidCallback? onTap;

  const _SelectionCheckbox({
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? colorScheme.primary : colorScheme.outline,
      ),
      onPressed: onTap,
    );
  }
}
