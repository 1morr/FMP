import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/popular_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/context_menu_region.dart';
import '../../widgets/error_display.dart';
import '../../widgets/selection_mode_app_bar.dart';
import '../../widgets/track_tile.dart';
import '../lyrics/lyrics_search_sheet.dart';

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
    final selectionState = ref.watch(exploreSelectionProvider);
    
    // 獲取當前 tab 的 tracks 用於全選
    final bilibiliTracks = ref.watch(cachedBilibiliRankingProvider).valueOrNull ?? [];
    final youtubeTracks = ref.watch(cachedYouTubeRankingProvider).valueOrNull ?? [];
    final currentTracks = _tabController.index == 0 ? bilibiliTracks : youtubeTracks;

    // 多選模式下的可用操作（探索頁不支持下載和刪除）
    const availableActions = <SelectionAction>{
      SelectionAction.addToQueue,
      SelectionAction.playNext,
      SelectionAction.addToPlaylist,
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
                  tabs: const [
                    Tab(text: 'Bilibili'),
                    Tab(text: 'YouTube'),
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
      error: (error, stack) {
        debugPrint('Failed to load Bilibili ranking: $error');
        return _buildRankingContent(
          tracks: [],
          isLoading: false,
          error: t.general.loadFailed,
          onRefresh: () async {
            final service = ref.read(rankingCacheServiceProvider);
            await service.refreshBilibili();
          },
        );
      },
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
      error: (error, stack) {
        debugPrint('Failed to load YouTube ranking: $error');
        return _buildRankingContent(
          tracks: [],
          isLoading: false,
          error: t.general.loadFailed,
          onRefresh: () async {
            final service = ref.read(rankingCacheServiceProvider);
            await service.refreshYouTube();
          },
        );
      },
    );
  }

  Widget _buildRankingContent({
    required List<Track> tracks,
    required bool isLoading,
    required String? error,
    required Future<void> Function() onRefresh,
  }) {
    if (isLoading && tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && tracks.isEmpty) {
      return ErrorDisplay(
        type: ErrorType.general,
        message: t.general.loadFailed,
        onRetry: onRefresh,
      );
    }

    if (tracks.isEmpty) {
      return Center(child: Text(t.databaseViewer.noData));
    }

    final selectionState = ref.watch(exploreSelectionProvider);
    final selectionNotifier = ref.read(exploreSelectionProvider.notifier);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _ExploreTrackTile(
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
      child: TrackTile(
        track: track,
        rank: rank,
        isPlaying: isPlaying,
        onTap: onTap ?? () {
          ref.read(audioControllerProvider.notifier).playTemporary(track);
        },
        onLongPress: onLongPress,
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                track.artist ?? t.general.unknownArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            ],
          ],
        ),
        trailing: isSelectionMode
            ? _SelectionCheckbox(
                isSelected: isSelected,
                onTap: onTap,
              )
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) => _handleMenuAction(context, ref, value),
                itemBuilder: (_) => _buildMenuItems(),
              ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() => [
    PopupMenuItem(
      value: 'play',
      child: ListTile(leading: const Icon(Icons.play_arrow), title: Text(t.searchPage.menu.play), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'play_next',
      child: ListTile(leading: const Icon(Icons.queue_play_next), title: Text(t.searchPage.menu.playNext), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'add_to_queue',
      child: ListTile(leading: const Icon(Icons.add_to_queue), title: Text(t.searchPage.menu.addToQueue), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'add_to_playlist',
      child: ListTile(leading: const Icon(Icons.playlist_add), title: Text(t.searchPage.menu.addToPlaylist), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'matchLyrics',
      child: ListTile(leading: const Icon(Icons.lyrics_outlined), title: Text(t.lyrics.matchLyrics), contentPadding: EdgeInsets.zero),
    ),
  ];

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);

    switch (action) {
      case 'play':
        controller.playTemporary(track);
        break;
      case 'play_next':
        final added = await controller.addNext(track);
        if (added && context.mounted) {
          ToastService.success(context, t.searchPage.toast.addedToNext);
        }
        break;
      case 'add_to_queue':
        final added = await controller.addToQueue(track);
        if (added && context.mounted) {
          ToastService.success(context, t.searchPage.toast.addedToQueue);
        }
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
      case 'matchLyrics':
        showLyricsSearchSheet(context: context, track: track);
        break;
    }
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
