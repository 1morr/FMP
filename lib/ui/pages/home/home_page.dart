import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/breakpoints.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../core/errors/user_message.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/play_history.dart';
import '../../../data/models/track.dart';
import '../../../providers/library/playlist_provider.dart';
import '../../../providers/library/play_history_provider.dart';
import '../../../providers/settings/home_ranking_settings_provider.dart';
import '../../../providers/search/popular_provider.dart';
import '../../../providers/audio/audio_controller_provider.dart';
import '../../../providers/audio/audio_player_selectors.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../services/radio/radio_controller.dart';
import '../../router.dart';
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_handler.dart';
import '../../handlers/track_action_menu.dart';
import '../../widgets/dialogs/confirm_destructive_dialog.dart';
import '../../widgets/layout/horizontal_scroll_section.dart';
import '../../widgets/layout/playlist_card.dart';
import '../../widgets/menus/context_menu_region.dart';
import '../../widgets/menus/menu_action.dart';
import '../../widgets/menus/playlist_card_actions.dart';
import '../../widgets/radio/radio_station_card.dart';
import '../../../i18n/strings.g.dart';
import '../../widgets/feedback/error_display.dart';
import '../../widgets/images/playlist_cover_image.dart';
import '../../widgets/images/recent_play_cover_image.dart';
import '../../widgets/images/track_thumbnail.dart';
import '../../widgets/track_tiles/ranking_track_tile.dart';
import '../../../data/models/playlist.dart';
import '../../../providers/search/refresh_provider.dart';
import '../../../services/library/playlist_service.dart';
import '../library/widgets/create_playlist_dialog.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/audio/queue_state.dart';

class HomeRankingSourcePlan {
  final String id;
  final List<Track> tracks;

  HomeRankingSourcePlan({
    required this.id,
    required List<Track> tracks,
  }) : tracks = List.unmodifiable(tracks);
}

/// 首頁排行榜的版面計畫。
///
/// [rows] 永遠包含**每一個**有資料的音源。版面只決定它們怎麼排，不決定誰要不要
/// 出現 —— 這裡原本是 `sources.take(maxSources)`，於是：
///
/// - 1280dp 平板上開啟曲目詳情面板後內容區縮到約 868dp，斷點掉到 tablet，
///   使用者在設定裡開著的第三個音源整個消失（P0-1）；
/// - 手機上永遠只看得到兩個，而垂直堆疊根本沒有寬度限制。
///
/// 沒有任何設定說「最多顯示 N 個排行榜」，那個上限純粹是版面產物。放不下就換到
/// 下一列，不要把使用者自己開啟的內容藏起來。
class HomeRankingLayoutPlan {
  HomeRankingLayoutPlan({
    required this.columns,
    required this.hasCandidateSources,
    required List<List<HomeRankingSourcePlan>> rows,
  }) : rows = List.unmodifiable(
          rows.map(List<HomeRankingSourcePlan>.unmodifiable),
        );

  /// 一列放幾個。最後一列可能不滿，渲染時要補空欄位維持對齊。
  final int columns;

  /// 有沒有任何已啟用的音源（即使它們都還沒有資料）。載入中要不要顯示佔位符看
  /// 這個，看 [sources] 會在第一次載入時把整段藏起來。
  final bool hasCandidateSources;

  final List<List<HomeRankingSourcePlan>> rows;

  /// 攤平後的所有音源，順序與 `enabledSourceOrder` 一致。
  List<HomeRankingSourcePlan> get sources =>
      [for (final row in rows) ...row];
}

HomeRankingLayoutPlan buildHomeRankingLayoutPlan({
  required double maxWidth,
  required List<String> enabledSourceOrder,
  required Map<String, List<Track>> tracksBySource,
}) {
  final columns = columnsFor(maxWidth);

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

  final rows = <List<HomeRankingSourcePlan>>[
    for (var i = 0; i < availableSources.length; i += columns)
      availableSources.skip(i).take(columns).toList(),
  ];

  return HomeRankingLayoutPlan(
    columns: columns,
    hasCandidateSources: candidateSources.isNotEmpty,
    rows: rows,
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
            _HomeSettingsEntry(),

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

/// 手機上的「設定」入口。
///
/// 設定不在底部導覽裡（M3 規範是 3–5 個目的地），有導覽軌的視窗把它放在軌底
/// 部，而手機沒有軌。**HomePage 刻意沒有 AppBar**（見 `lib/ui/AGENTS.md` 的
/// Page Conventions），所以這是一列跟著內容捲動的按鈕，不是固定標題列 ——
/// 代價是往下捲之後看不到它，換到的是 dashboard 的性格不變。
class _HomeSettingsEntry extends StatelessWidget {
  const _HomeSettingsEntry();

  @override
  Widget build(BuildContext context) {
    if (WindowClass.of(MediaQuery.sizeOf(context).width) !=
        WindowClass.compact) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.xs,
        0,
      ),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.nav.settings,
            onPressed: () => context.go(RoutePaths.settings),
          ),
        ],
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
        source: ?_tracksForRankingSource(ref, source),
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
                onPressed: () => context.push(RoutePaths.explore),
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
        if (isLoading && plan.sources.isEmpty) {
          if (!plan.hasCandidateSources) return const SizedBox.shrink();
          return const SizedBox(
            height: 200,
            child: LoadingPlaceholder(),
          );
        }

        if (plan.sources.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var rowIndex = 0; rowIndex < plan.rows.length; rowIndex++)
                ...[
                if (rowIndex > 0) const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 補到 plan.columns 個欄位而不是只放這一列有的，最後一列不
                    // 滿時才不會把僅有的那個排行榜拉成整列寬、與上一列錯開。
                    for (var column = 0; column < plan.columns; column++) ...[
                      if (column > 0) const SizedBox(width: 16),
                      Expanded(
                        child: column < plan.rows[rowIndex].length
                            ? _buildRankingCard(
                                context,
                                colorScheme,
                                title: SourceIds.displayNameFor(
                                    plan.rows[rowIndex][column].id),
                                tracks: plan.rows[rowIndex][column].tracks,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
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
              RankingTrackTile(
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
      // 區塊級的失敗不能靜靜消失 —— 使用者會以為自己沒有歌單。
      error: (e, s) => ErrorDisplay(
        compact: true,
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(allPlaylistsProvider),
      ),
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
                menuBuilder: (_) => buildMenuActionPopupEntries(
                  _radioMenuActions(),
                  Theme.of(context).colorScheme.error,
                ),
                onSelected: (value) =>
                    _handleRadioMenuAction(context, ref, station, value),
                child: RadioStationCard(
                  station: station,
                  isLive: isLive,
                  isPlaying: isPlaying,
                  isLoading: isLoading,
                  coverSize: 100,
                  dense: true,
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

  List<MenuAction> _radioMenuActions() => [
        MenuAction(
          id: 'delete',
          icon: Icons.delete,
          label: t.radio.deleteStation,
          destructive: true,
        ),
      ];

  void _handleRadioMenuAction(
      BuildContext context, WidgetRef ref, RadioStation station, String value) {
    if (value == 'delete') {
      _showRadioDeleteConfirm(context, ref, station);
    }
  }

  void _showRadioOptionsMenu(
      BuildContext context, WidgetRef ref, RadioStation station) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: buildMenuActionListTiles(
              sheetContext,
              _radioMenuActions(),
              (value) => _handleRadioMenuAction(context, ref, station, value),
              colorScheme.error,
            ),
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
      error: (e, s) => ErrorDisplay(
        compact: true,
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(recentPlayHistoryProvider),
      ),
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

  List<MenuAction> _historyDestructiveActions() => [
        MenuAction(
          id: 'delete',
          icon: Icons.delete_outline,
          label: t.playHistoryPage.deleteThisRecord,
          destructive: true,
        ),
        MenuAction(
          id: 'delete_all',
          icon: Icons.delete_sweep,
          label: t.playHistoryPage.deleteAllForTrack,
          destructive: true,
        ),
      ];

  List<PopupMenuEntry<String>> _buildHistoryMenuItems(
          ColorScheme colorScheme) =>
      [
        ...buildTrackActionPopupMenuEntries(
          buildCommonTrackActionMenuItems(
            translations: t,
            options: const TrackActionMenuOptions(
              includeAddToRemote: false,
            ),
          ),
        ),
        const PopupMenuDivider(),
        ...buildMenuActionPopupEntries(
          _historyDestructiveActions(),
          colorScheme.error,
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
            ToastService.success(context, t.playHistoryPage.toastDeletedRecord);
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
              ...buildTrackActionListTiles(
                context,
                buildCommonTrackActionMenuItems(
                  translations: t,
                  options: const TrackActionMenuOptions(
                    includeAddToRemote: false,
                  ),
                ),
                (item) =>
                    _handleHistoryMenuAction(context, ref, history, item.id),
              ),
              const Divider(),
              ...buildMenuActionListTiles(
                context,
                _historyDestructiveActions(),
                (value) =>
                    _handleHistoryMenuAction(context, ref, history, value),
                colorScheme.error,
              ),
            ],
          ),
        ),
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
      child: PlaylistCard(
        playlist: playlist,
        margin: EdgeInsets.zero,
        onTap: () => context.push(RoutePaths.playlistDetailPath(playlist.id)),
        onLongPress: () => _showOptionsMenu(context, ref),
        cover: coverAsync.when(
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
                      tooltip:
                          isMusicPlaying ? t.general.pause : t.general.play,
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
    // 只監聽即將播放的曲目
    final upcomingTracks = ref.watch(upcomingTracksProvider);
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
                        final trackIndex =
                            ref.read(queueStateProvider).queue.indexOf(track);
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
