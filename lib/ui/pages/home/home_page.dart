import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../core/utils/icon_helpers.dart';
import '../../../data/models/play_history.dart';
import '../../../data/models/track.dart';
import '../../../providers/library/playlist_provider.dart';
import '../../../providers/library/play_history_provider.dart';
import '../../../providers/settings/home_ranking_settings_provider.dart';
import '../../../providers/search/popular_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../services/radio/radio_controller.dart';
import '../../router.dart';
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_handler.dart';
import '../../handlers/track_action_menu.dart';
import '../../widgets/dialogs/confirm_destructive_dialog.dart';
import '../../widgets/indicators/live_badge.dart';
import '../../widgets/indicators/now_playing_indicator.dart';
import '../../widgets/layout/horizontal_scroll_section.dart';
import '../../widgets/menus/context_menu_region.dart';
import '../../widgets/menus/playlist_card_actions.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../widgets/images/playlist_cover_image.dart';
import '../../widgets/images/radio_cover_image.dart';
import '../../widgets/images/recent_play_cover_image.dart';
import '../../widgets/images/track_thumbnail.dart';
import '../../widgets/indicators/vip_badge.dart';
import '../../../data/models/playlist.dart';
import '../../../providers/search/refresh_provider.dart';
import '../../../services/library/playlist_service.dart';
import '../library/widgets/create_playlist_dialog.dart';
import '../../../core/constants/app_constants.dart';

class HomeRankingSourcePlan {
  final String id;
  final List<Track> tracks;

  HomeRankingSourcePlan({
    required this.id,
    required List<Track> tracks,
  }) : tracks = List.unmodifiable(tracks);
}

class HomeRankingLayoutPlan {
  final Axis axis;
  final List<HomeRankingSourcePlan> sources;

  HomeRankingLayoutPlan({
    required this.axis,
    required List<HomeRankingSourcePlan> sources,
  }) : sources = List.unmodifiable(sources);
}

HomeRankingLayoutPlan buildHomeRankingLayoutPlan({
  required double maxWidth,
  required List<String> enabledSourceOrder,
  required Map<String, List<Track>> tracksBySource,
}) {
  final layoutType = Breakpoints.getLayoutType(maxWidth);
  final axis =
      layoutType == LayoutType.mobile ? Axis.vertical : Axis.horizontal;
  final maxSources = layoutType == LayoutType.desktop ? 3 : 2;

  final candidateSources = enabledSourceOrder
      .where(tracksBySource.containsKey)
      .map(
        (source) => HomeRankingSourcePlan(
          id: source,
          tracks: tracksBySource[source] ?? const <Track>[],
        ),
      )
      .toList();
  final availableSources =
      candidateSources.where((source) => source.tracks.isNotEmpty).toList();

  return HomeRankingLayoutPlan(
    axis: axis,
    sources: availableSources.take(maxSources).toList(),
  );
}

/// 首页
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    // 监听电台错误并显示 Toast（与 RadioPage 保持一致）
    ref.listen<RadioState>(radioControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ToastService.error(context, next.error!);
      }
    });

    return const Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 音樂排行榜（独立 ConsumerWidget）
            HomeRankingsSection(),

            // 我的歌单（独立 ConsumerWidget）
            _RecentPlaylistsSection(),

            // 电台（独立 ConsumerWidget）
            _RadioSection(),

            // 正在播放（独立 ConsumerWidget）
            _NowPlayingSection(),

            // 队列预览（独立 ConsumerWidget）
            _QueuePreviewSection(),

            // 最近播放历史（独立 ConsumerWidget）
            _RecentHistorySection(),

            SizedBox(height: 100), // 为迷你播放器留出空间
          ],
        ),
      ),
    );
  }
}

/// 音樂排行榜區域（独立 ConsumerWidget，避免其他 section 变化触发 rebuild）
class HomeRankingsSection extends ConsumerWidget {
  const HomeRankingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledSourceOrder = ref.watch(enabledHomeRankingSourceOrderProvider);

    if (enabledSourceOrder.isEmpty) {
      return const SizedBox.shrink();
    }

    final tracksBySource = {
      for (final source in enabledSourceOrder)
        if (_tracksForRankingSource(ref, source) case final tracks?)
          source: tracks,
    };
    if (tracksBySource.isEmpty) {
      return const SizedBox.shrink();
    }

    final isLoading = ref.watch(
      rankingCacheServiceProvider.select((state) => state.isInitialLoading),
    );

    final candidateSources = enabledSourceOrder
        .where(tracksBySource.containsKey)
        .map(
          (source) => HomeRankingSourcePlan(
            id: source,
            tracks: tracksBySource[source] ?? const <Track>[],
          ),
        )
        .toList();
    final availableSources =
        candidateSources.where((source) => source.tracks.isNotEmpty).toList();

    if (!isLoading && availableSources.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                t.home.recentTrending,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(RoutePaths.explore),
                child: Text(t.home.viewAll),
              ),
            ],
          ),
        ),
        _buildRankingContent(
          context,
          colorScheme,
          enabledSourceOrder: enabledSourceOrder,
          tracksBySource: tracksBySource,
          isLoading: isLoading,
        ),
      ],
    );
  }

  List<Track>? _tracksForRankingSource(WidgetRef ref, String source) {
    switch (source) {
      case 'bilibili':
        return ref.watch(homeBilibiliMusicRankingProvider);
      case 'youtube':
        return ref.watch(homeYouTubeMusicRankingProvider);
      case 'netease':
        return ref.watch(homeNeteaseHotRankingProvider);
      default:
        return null;
    }
  }

  Widget _buildRankingContent(
    BuildContext context,
    ColorScheme colorScheme, {
    required List<String> enabledSourceOrder,
    required Map<String, List<Track>> tracksBySource,
    required bool isLoading,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plan = buildHomeRankingLayoutPlan(
          maxWidth: constraints.maxWidth,
          enabledSourceOrder: enabledSourceOrder,
          tracksBySource: tracksBySource,
        );
        final candidateSources = enabledSourceOrder
            .where(tracksBySource.containsKey)
            .map(
              (source) => HomeRankingSourcePlan(
                id: source,
                tracks: tracksBySource[source] ?? const <Track>[],
              ),
            )
            .toList();
        final availableSources = candidateSources
            .where((source) => source.tracks.isNotEmpty)
            .toList();

        if (isLoading && availableSources.isEmpty) {
          if (candidateSources.isEmpty) return const SizedBox.shrink();
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (plan.sources.isEmpty) return const SizedBox.shrink();

        if (plan.axis == Axis.horizontal) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < plan.sources.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Expanded(
                    child: _buildRankingCard(
                      context,
                      colorScheme,
                      title: _titleForRankingSource(plan.sources[i].id),
                      tracks: plan.sources[i].tracks,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < plan.sources.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _buildRankingCard(
                  context,
                  colorScheme,
                  title: _titleForRankingSource(plan.sources[i].id),
                  tracks: plan.sources[i].tracks,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _titleForRankingSource(String source) {
    switch (source) {
      case 'bilibili':
        return t.importPlatform.bilibili;
      case 'youtube':
        return 'YouTube';
      case 'netease':
        return t.importPlatform.netease;
      default:
        return source;
    }
  }

  Widget _buildRankingCard(
    BuildContext context,
    ColorScheme colorScheme, {
    required String title,
    required List<Track> tracks,
  }) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final displayTracks =
        tracks.take(AppConstants.homeTrackPreviewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Column(
          children: [
            for (int i = 0; i < displayTracks.length; i++)
              _RankingTrackTile(
                key: ValueKey(
                  '${displayTracks[i].sourceId}_${displayTracks[i].pageNum}',
                ),
                track: displayTracks[i],
                rank: i + 1,
              ),
          ],
        ),
      ],
    );
  }
}

/// 我的歌单区域（独立 ConsumerWidget）
class _RecentPlaylistsSection extends ConsumerWidget {
  const _RecentPlaylistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(allPlaylistsProvider);
    final coverMapAsync = ref.watch(playlistCoverMapProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return playlists.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (lists) {
        final recentLists =
            lists.take(AppConstants.homeListPreviewCount).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    t.home.myPlaylists,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (lists.isNotEmpty)
                    TextButton(
                      onPressed: () => context.go(RoutePaths.library),
                      child: Text(t.home.viewAll),
                    ),
                ],
              ),
            ),
            if (lists.isEmpty)
              _buildEmptyPlaylistPlaceholder(context, colorScheme)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth =
                      (constraints.maxWidth / 4).clamp(100.0, 140.0);
                  final cardHeight = cardWidth / 0.8;

                  final playlistCards = recentLists.map((playlist) {
                    return SizedBox(
                      width: cardWidth,
                      child: _HomePlaylistCard(
                        playlist: playlist,
                        coverAsync: _coverForPlaylist(
                          coverMapAsync,
                          playlist.id,
                        ),
                      ),
                    );
                  }).toList();

                  return HorizontalScrollSection(
                    height: cardHeight,
                    itemWidth: cardWidth,
                    children: playlistCards,
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyPlaylistPlaceholder(
      BuildContext context, ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth / 4).clamp(100.0, 140.0);
        final cardHeight = cardWidth / 0.8;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.go(RoutePaths.library),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(Icons.add,
                              size: 32, color: colorScheme.outline),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        t.home.createPlaylist,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colorScheme.outline),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

AsyncValue<PlaylistCoverData> _coverForPlaylist(
  AsyncValue<Map<int, PlaylistCoverData>> coverMapAsync,
  int playlistId,
) {
  return coverMapAsync.when(
    skipLoadingOnReload: true,
    data: (coverMap) => AsyncData<PlaylistCoverData>(
      coverMap[playlistId] ?? const PlaylistCoverData(),
    ),
    loading: () => const AsyncLoading<PlaylistCoverData>(),
    error: (error, stackTrace) => AsyncError<PlaylistCoverData>(
      error,
      stackTrace,
    ),
  );
}

/// 电台区域（独立 ConsumerWidget）
class _RadioSection extends ConsumerWidget {
  const _RadioSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radioState = ref.watch(radioControllerProvider);

    if (radioState.stations.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedStations = List<RadioStation>.from(radioState.stations)
      ..sort((a, b) {
        final aLive = radioState.isStationLive(a.id) ? 0 : 1;
        final bLive = radioState.isStationLive(b.id) ? 0 : 1;
        return aLive.compareTo(bLive);
      });
    final displayStations =
        sortedStations.take(AppConstants.homeListPreviewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                t.home.radio,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(RoutePaths.radio),
                child: Text(t.home.viewAll),
              ),
            ],
          ),
        ),
        HorizontalScrollSection(
          height: 140,
          itemWidth: 120,
          children: displayStations.map((station) {
            final isLive = radioState.isStationLive(station.id);
            final isCurrentPlaying =
                radioState.currentStation?.id == station.id;
            final isPlaying = isCurrentPlaying && radioState.isPlaying;
            final isLoading = radioState.loadingStationId == station.id;

            return SizedBox(
              width: 120,
              child: ContextMenuRegion(
                menuBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete,
                          color: Theme.of(context).colorScheme.error),
                      title: Text(t.radio.deleteStation,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'delete') {
                    _showRadioDeleteConfirm(context, ref, station);
                  }
                },
                child: _HomeRadioStationCard(
                  station: station,
                  isLive: isLive,
                  isPlaying: isPlaying,
                  isLoading: isLoading,
                  onTap: () => _onRadioStationTap(
                      ref, station, isCurrentPlaying, radioState),
                  onLongPress: () =>
                      _showRadioOptionsMenu(context, ref, station),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _onRadioStationTap(WidgetRef ref, RadioStation station,
      bool isCurrentPlaying, RadioState radioState) {
    final controller = ref.read(radioControllerProvider.notifier);
    if (isCurrentPlaying) {
      if (radioState.isPlaying) {
        controller.pause();
      } else {
        controller.resume();
      }
    } else {
      controller.play(station);
    }
  }

  void _showRadioOptionsMenu(
      BuildContext context, WidgetRef ref, RadioStation station) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text(t.radio.deleteStation,
                    style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _showRadioDeleteConfirm(context, ref, station);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRadioDeleteConfirm(
      BuildContext context, WidgetRef ref, RadioStation station) async {
    final confirmed = await showConfirmDestructiveDialog(
      context,
      title: t.radio.deleteStation,
      content: t.radio.deleteConfirm(title: station.title),
      confirmLabel: t.radio.delete,
    );

    if (confirmed == true) {
      await ref
          .read(radioControllerProvider.notifier)
          .deleteStation(station.id);
      if (context.mounted) {
        ToastService.success(context, t.radio.stationDeleted);
      }
    }
  }
}

/// 最近播放历史区域（独立 ConsumerWidget）
class _RecentHistorySection extends ConsumerWidget {
  const _RecentHistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(recentPlayHistoryProvider);

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (historyList) {
        final displayList =
            historyList.take(AppConstants.homeListPreviewCount).toList();
        if (displayList.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    t.home.recentlyPlayed,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.push(RoutePaths.history),
                    child: Text(t.home.viewAll),
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth =
                    (constraints.maxWidth / 4).clamp(100.0, 140.0);
                final cardHeight = cardWidth / 0.8;

                final historyCards = displayList
                    .map((history) =>
                        _buildHistoryItem(context, ref, history, cardWidth))
                    .toList();

                return HorizontalScrollSection(
                  height: cardHeight,
                  itemWidth: cardWidth,
                  children: historyCards,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryItem(BuildContext context, WidgetRef ref,
      PlayHistory history, double cardWidth) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: cardWidth,
      child: ContextMenuRegion(
        menuBuilder: (_) => _buildHistoryMenuItems(colorScheme),
        onSelected: (value) =>
            _handleHistoryMenuAction(context, ref, history, value),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              final track = history.toTrack();
              ref.read(audioControllerProvider.notifier).playTemporary(track);
            },
            onLongPress: () => _showHistoryOptionsMenu(context, ref, history),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      history.thumbnailUrl != null
                          ? RecentPlayCoverImage(
                              networkUrl: history.thumbnailUrl,
                              placeholder: const ImagePlaceholder.track(),
                              fit: BoxFit.cover,
                              width: cardWidth,
                            )
                          : const ImagePlaceholder.track(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    history.title,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildHistoryMenuItems(
          ColorScheme colorScheme) =>
      [
        ...buildTrackActionPopupMenuEntries(
          buildCommonTrackActionMenuItems(
            translations: t,
            options: const TrackActionMenuOptions(
              includeMatchLyrics: false,
              includeAddToRemote: false,
            ),
          ),
        ),
        const PopupMenuDivider(),
        buildDestructivePopupMenuItem(
          value: 'delete',
          icon: Icons.delete_outline,
          label: t.playHistoryPage.deleteThisRecord,
          color: colorScheme.error,
        ),
        buildDestructivePopupMenuItem(
          value: 'delete_all',
          icon: Icons.delete_sweep,
          label: t.playHistoryPage.deleteAllForTrack,
          color: colorScheme.error,
        ),
      ];

  void _handleHistoryMenuAction(BuildContext context, WidgetRef ref,
      PlayHistory history, String action) async {
    final track = history.toTrack();
    final trackAction = tryParseTrackAction(action);
    if (trackAction != null) {
      await TrackActionCoordinator.handleSingle(
        context: context,
        ref: ref,
        track: track,
        actionId: action,
      );
      return;
    }

    switch (action) {
      case 'delete':
        if (!context.mounted) {
          return;
        }
        final confirmedDelete = await showConfirmDestructiveDialog(
          context,
          title: t.playHistoryPage.deleteThisRecord,
          content: t.radio.deleteConfirm(title: history.title),
          confirmLabel: t.playHistoryPage.deleteButton,
        );
        if (confirmedDelete == true && context.mounted) {
          await ref.read(playHistoryActionsProvider).delete(history.id);
          if (context.mounted) {
            ToastService.success(
                context, t.playHistoryPage.toastDeletedRecord);
          }
        }
      case 'delete_all':
        if (!context.mounted) {
          return;
        }
        final confirmed = await showConfirmDestructiveDialog(
          context,
          title: t.playHistoryPage.deleteAllTitle,
          content: t.playHistoryPage.deleteAllConfirm(title: history.title),
          confirmLabel: t.playHistoryPage.deleteButton,
        );
        if (confirmed == true && context.mounted) {
          final count = await ref
              .read(playHistoryPageProvider.notifier)
              .deleteAllForTrack(history.trackKey);
          if (context.mounted) {
            ToastService.success(
                context, t.playHistoryPage.toastDeletedCount(n: count));
          }
        }
    }
  }

  void _showHistoryOptionsMenu(
      BuildContext context, WidgetRef ref, PlayHistory history) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...buildCommonTrackActionMenuItems(
                translations: t,
                options: const TrackActionMenuOptions(
                  includeMatchLyrics: false,
                  includeAddToRemote: false,
                ),
              ).map(
                (item) => ListTile(
                  leading: Icon(item.icon),
                  title: Text(item.label),
                  onTap: () {
                    Navigator.pop(context);
                    _handleHistoryMenuAction(context, ref, history, item.id);
                  },
                ),
              ),
              const Divider(),
              ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text(t.playHistoryPage.deleteThisRecord,
                      style: TextStyle(color: colorScheme.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleHistoryMenuAction(context, ref, history, 'delete');
                  }),
              ListTile(
                  leading: Icon(Icons.delete_sweep, color: colorScheme.error),
                  title: Text(t.playHistoryPage.deleteAllForTrack,
                      style: TextStyle(color: colorScheme.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleHistoryMenuAction(
                        context, ref, history, 'delete_all');
                  }),
            ],
          ),
        ),
      ),
    );
  }
}

/// 排行榜歌曲項目（類似搜索結果項目）
class _RankingTrackTile extends ConsumerWidget {
  final Track track;
  final int rank;

  const _RankingTrackTile({super.key, required this.track, required this.rank});

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
        onTap: () {
          ref.read(audioControllerProvider.notifier).playTemporary(track);
        },
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

/// 首頁電台卡片（簡化版）
class _HomeRadioStationCard extends StatelessWidget {
  final RadioStation station;
  final bool isLive;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HomeRadioStationCard({
    required this.station,
    required this.isLive,
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppRadius.borderRadiusLg,
      child: Column(
        children: [
          // 圆形封面
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              children: [
                // 封面图
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.surfaceContainerHighest,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ColorFiltered(
                    colorFilter: isLive
                        ? const ColorFilter.mode(
                            Colors.transparent,
                            BlendMode.multiply,
                          )
                        : kGrayscaleColorFilter,
                    child: RadioCoverImage(
                      networkUrl: station.thumbnailUrl,
                      fit: BoxFit.cover,
                      width: 100,
                      height: 100,
                      variant: RadioCoverVariant.card,
                    ),
                  ),
                ),

                // 正在直播红点
                if (isLive)
                  Positioned(
                    top: LiveBadge.dotOffset(14),
                    right: LiveBadge.dotOffset(14),
                    child: const LiveBadge.dot(size: 14),
                  ),

                // 播放中指示器
                if (isPlaying || isLoading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.primary.withValues(alpha: 0.4),
                      ),
                      child: Center(
                        child: isLoading
                            ? const SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const NowPlayingIndicator(
                                color: Colors.white,
                                size: 30,
                                isPlaying: true,
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // 标题
          Text(
            station.title,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: isPlaying ? FontWeight.bold : null,
              color: isLive
                  ? (isPlaying ? colorScheme.primary : colorScheme.onSurface)
                  : colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 首頁歌單卡片（帶右鍵/長按菜單）
class _HomePlaylistCard extends ConsumerWidget {
  final Playlist playlist;
  final AsyncValue<PlaylistCoverData> coverAsync;

  const _HomePlaylistCard({
    required this.playlist,
    required this.coverAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ContextMenuRegion(
      menuBuilder: (_) => _buildContextMenuItems(context, ref),
      onSelected: (value) => _handleContextMenuAction(context, ref, value),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/library/${playlist.id}'),
          onLongPress: () => _showOptionsMenu(context, ref),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    coverAsync.when(
                      skipLoadingOnReload: true,
                      data: (coverData) => coverData.hasCover
                          ? PlaylistCoverImage(
                              localPath: coverData.localPath,
                              networkUrl: coverData.networkUrl,
                              placeholder: const ImagePlaceholder.playlist(),
                              fit: BoxFit.cover,
                              variant: PlaylistCoverVariant.card,
                            )
                          : const ImagePlaceholder.playlist(),
                      loading: () => const ImagePlaceholder.playlist(),
                      error: (e, s) => const ImagePlaceholder.playlist(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (playlist.isMix) ...[
                          Icon(
                            Icons.radio,
                            size: 12,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Mix',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                          ),
                        ] else ...[
                          if (playlist.isImported) ...[
                            Icon(
                              getImportSourceIcon(playlist.importSourceType),
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            t.library.trackCount(n: playlist.trackCount),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildContextMenuItems(
      BuildContext context, WidgetRef ref) {
    final isRefreshing = ref.read(isPlaylistRefreshingProvider(playlist.id));
    return PlaylistCardActions.buildPopupMenuEntries(
      context: context,
      items: PlaylistCardActions.buildMenuItems(
        playlist: playlist,
        isRefreshing: isRefreshing,
      ),
    );
  }

  void _handleContextMenuAction(
      BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case PlaylistCardActions.actionPlayMix:
        _playMix(context, ref);
      case PlaylistCardActions.actionAddAll:
        _addAllToQueue(context, ref);
      case PlaylistCardActions.actionShuffleAdd:
        _shuffleAddToQueue(context, ref);
      case PlaylistCardActions.actionEdit:
        _showEditDialog(context, ref);
      case PlaylistCardActions.actionRefresh:
        _refreshPlaylist(context, ref);
      case PlaylistCardActions.actionDelete:
        _showDeleteConfirm(context, ref);
    }
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    final isRefreshing = ref.read(isPlaylistRefreshingProvider(playlist.id));
    final items = PlaylistCardActions.buildMenuItems(
      playlist: playlist,
      isRefreshing: isRefreshing,
    );

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlaylistCardActions.buildBottomSheetTiles(
              context: context,
              items: items,
              onSelected: (value) =>
                  _handleContextMenuAction(context, ref, value),
            ),
          ),
        ),
      ),
    );
  }

  void _addAllToQueue(BuildContext context, WidgetRef ref) async {
    await PlaylistCardActions.addAllToQueue(context, ref, playlist);
  }

  void _shuffleAddToQueue(BuildContext context, WidgetRef ref) async {
    await PlaylistCardActions.shuffleAddToQueue(context, ref, playlist);
  }

  Future<void> _playMix(BuildContext context, WidgetRef ref) async {
    await PlaylistCardActions.playMix(context, ref, playlist);
  }

  void _refreshPlaylist(BuildContext context, WidgetRef ref) {
    ref.read(refreshManagerProvider.notifier).refreshPlaylist(playlist);
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => CreatePlaylistDialog(playlist: playlist),
    );
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDestructiveDialog(
      context,
      title: t.library.main.deletePlaylist,
      content: t.library.main.deletePlaylistConfirm(name: playlist.name),
      confirmLabel: t.general.delete,
    );
    if (confirmed == true) {
      ref.read(playlistListProvider.notifier).deletePlaylist(playlist.id);
      if (context.mounted) {
        ToastService.success(context, t.library.main.playlistDeleted);
      }
    }
  }
}

/// 正在播放区域（独立 ConsumerWidget）
class _NowPlayingSection extends ConsumerWidget {
  const _NowPlayingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // 只监听当前曲目和播放状态
    final track = ref.watch(currentTrackProvider);
    final isPlaying =
        ref.watch(audioControllerProvider.select((s) => s.isPlaying));
    final isRadioPlaying = ref.watch(isRadioPlayingProvider);
    final hasRadioContext = ref.watch(currentRadioStationProvider) != null;

    if (track == null) return const SizedBox.shrink();

    final isMusicPlaying = isPlaying && !isRadioPlaying;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            t.home.nowPlaying,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: InkWell(
              onTap: () {
                if (hasRadioContext) {
                  ref
                      .read(radioControllerProvider.notifier)
                      .returnToMusic(forcePlay: true);
                } else {
                  ref.read(audioControllerProvider.notifier).togglePlayPause();
                }
              },
              borderRadius: AppRadius.borderRadiusLg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 封面
                    TrackThumbnail(
                      track: track,
                      size: AppSizes.thumbnailLarge,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 12),
                    // 信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            track.artist ?? t.general.unknownArtist,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // 控制按钮
                    IconButton(
                      icon: Icon(
                        isMusicPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: () {
                        if (hasRadioContext) {
                          ref
                              .read(radioControllerProvider.notifier)
                              .returnToMusic(forcePlay: true);
                        } else {
                          ref
                              .read(audioControllerProvider.notifier)
                              .togglePlayPause();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 队列预览区域（独立 ConsumerWidget）
class _QueuePreviewSection extends ConsumerWidget {
  const _QueuePreviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只监听即将播放的曲目
    final upcomingTracks =
        ref.watch(audioControllerProvider.select((s) => s.upcomingTracks));
    final upNext =
        upcomingTracks.take(AppConstants.upcomingTracksPreviewCount).toList();

    if (upNext.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                t.home.upNext,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(RoutePaths.queue),
                child: Text(t.home.viewQueue),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: upNext
                .map((track) => ListTile(
                      contentPadding: const EdgeInsets.only(left: 18),
                      leading: TrackThumbnail(
                        track: track,
                        size: AppSizes.thumbnailSmall,
                        borderRadius: 4,
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist ?? t.general.unknownArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      dense: true,
                      onTap: () {
                        final playerState = ref.read(audioControllerProvider);
                        final trackIndex = playerState.queue.indexOf(track);
                        if (trackIndex >= 0) {
                          ref
                              .read(audioControllerProvider.notifier)
                              .playAt(trackIndex);
                        }
                      },
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}
