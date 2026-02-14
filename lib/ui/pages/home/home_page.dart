import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/play_history.dart';
import '../../../data/models/track.dart';
import '../../../providers/playlist_provider.dart';
import '../../../providers/play_history_provider.dart';
import '../../../providers/popular_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/cache/ranking_cache_service.dart';
import '../../../data/models/radio_station.dart';
import '../../../services/radio/radio_controller.dart';
import '../../router.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/horizontal_scroll_section.dart';
import '../../widgets/context_menu_region.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../widgets/track_thumbnail.dart';
import '../../../data/models/playlist.dart';
import '../../../providers/refresh_provider.dart';
import '../../../data/sources/source_provider.dart';
import '../library/widgets/create_playlist_dialog.dart';
import '../../../core/constants/app_constants.dart';

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

    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 音樂排行榜
            _buildMusicRankings(context, colorScheme),

            // 我的歌单
            _buildRecentPlaylists(context, colorScheme),

            // 电台
            _buildRadioSection(context, colorScheme),

            // 正在播放
            if (playerState.hasCurrentTrack)
              _buildNowPlaying(context, playerState, colorScheme),

            // 队列预览
            if (playerState.queue.isNotEmpty)
              _buildQueuePreview(context, playerState, colorScheme),

            // 最近播放历史
            _buildRecentHistory(context, colorScheme),

            const SizedBox(height: 100), // 为迷你播放器留出空间
          ],
        ),
      ),
    );
  }

  /// 構建音樂排行榜區域（響應式佈局）
  Widget _buildMusicRankings(BuildContext context, ColorScheme colorScheme) {
    final bilibiliAsync = ref.watch(homeBilibiliMusicRankingProvider);
    final youtubeAsync = ref.watch(homeYouTubeMusicRankingProvider);
    final cacheService = ref.watch(rankingCacheServiceProvider);

    // 判斷是否有數據
    final hasBilibiliData = bilibiliAsync.valueOrNull?.isNotEmpty ?? false;
    final hasYoutubeData = youtubeAsync.valueOrNull?.isNotEmpty ?? false;
    final isLoading = cacheService.isInitialLoading;

    // 如果不在初始加載且沒有任何緩存數據，隱藏整個區域
    if (!isLoading && !hasBilibiliData && !hasYoutubeData) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 區域標題
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
        // 排行榜內容
        _buildRankingContent(
          context,
          colorScheme,
          bilibiliAsync: bilibiliAsync,
          youtubeAsync: youtubeAsync,
          isLoading: isLoading,
          hasBilibiliData: hasBilibiliData,
          hasYoutubeData: hasYoutubeData,
        ),
      ],
    );
  }

  /// 構建排行榜內容區域（根據屏幕寬度和數據狀態調整佈局）
  Widget _buildRankingContent(
    BuildContext context,
    ColorScheme colorScheme, {
    required AsyncValue<List<Track>> bilibiliAsync,
    required AsyncValue<List<Track>> youtubeAsync,
    required bool isLoading,
    required bool hasBilibiliData,
    required bool hasYoutubeData,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 600;

        // 初始加載時顯示 loading
        if (isLoading) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (isWideScreen) {
          // 寬屏：並排顯示
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasBilibiliData)
                  Expanded(
                    child: _buildRankingCard(
                      context,
                      colorScheme,
                      title: 'Bilibili',
                      asyncValue: bilibiliAsync,
                    ),
                  ),
                if (hasBilibiliData && hasYoutubeData) const SizedBox(width: 16),
                if (hasYoutubeData)
                  Expanded(
                    child: _buildRankingCard(
                      context,
                      colorScheme,
                      title: 'YouTube',
                      asyncValue: youtubeAsync,
                    ),
                  ),
              ],
            ),
          );
        } else {
          // 窄屏：堆疊顯示
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (hasBilibiliData)
                  _buildRankingCard(
                    context,
                    colorScheme,
                    title: 'Bilibili',
                    asyncValue: bilibiliAsync,
                  ),
                if (hasBilibiliData && hasYoutubeData) const SizedBox(height: 12),
                if (hasYoutubeData)
                  _buildRankingCard(
                    context,
                    colorScheme,
                    title: 'YouTube',
                    asyncValue: youtubeAsync,
                  ),
              ],
            ),
          );
        }
      },
    );
  }

  /// 構建單個排行榜卡片（只在有數據時調用）
  Widget _buildRankingCard(
    BuildContext context,
    ColorScheme colorScheme, {
    required String title,
    required AsyncValue<List<Track>> asyncValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 簡單的標題
        Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        // 排行列表（直接使用 data，loading/error 由外層處理）
        asyncValue.when(
          loading: () => const SizedBox.shrink(),
          error: (e, s) => SizedBox(
            height: 100,
            child: Center(
              child: Text(
                t.home.loadFailed,
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
          ),
          data: (tracks) {
            if (tracks.isEmpty) {
              return const SizedBox.shrink();
            }
            final displayTracks = tracks.take(AppConstants.homeTrackPreviewCount).toList();
            return Column(
              children: [
                for (int i = 0; i < displayTracks.length; i++)
                  _RankingTrackTile(track: displayTracks[i], rank: i + 1),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecentPlaylists(BuildContext context, ColorScheme colorScheme) {
    final playlists = ref.watch(allPlaylistsProvider);

    return playlists.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (lists) {
        // 最多显示 20 个歌单
        final recentLists = lists.take(AppConstants.homeListPreviewCount).toList();

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
            // 歌单为空时显示占位卡片
            if (lists.isEmpty)
              _buildEmptyPlaylistPlaceholder(context, colorScheme)
            else
              LayoutBuilder(
              builder: (context, constraints) {
                // 根据窗口宽度计算卡片大小，平滑缩放
                final cardWidth =
                    (constraints.maxWidth / 4).clamp(100.0, 140.0);
                final cardHeight = cardWidth / 0.8; // 保持 0.8 的宽高比

                // 构建歌单卡片列表
                final playlistCards = recentLists.map((playlist) {
                  return SizedBox(
                    width: cardWidth,
                    child: _HomePlaylistCard(playlist: playlist),
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
    BuildContext context,
    ColorScheme colorScheme,
  ) {
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
                    // 封面区域 - 与普通歌单卡片结构一致
                    Expanded(
                      child: Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.add,
                            size: 32,
                            color: colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    // 标题区域 - 与普通歌单卡片结构一致
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        t.home.createPlaylist,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
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

  Widget _buildRecentHistory(BuildContext context, ColorScheme colorScheme) {
    final historyAsync = ref.watch(recentPlayHistoryProvider);

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (historyList) {
        // 最多显示 20 个
        final displayList = historyList.take(AppConstants.homeListPreviewCount).toList();

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
                // 根据窗口宽度计算卡片大小，平滑缩放
                final cardWidth =
                    (constraints.maxWidth / 4).clamp(100.0, 140.0);
                final cardHeight = cardWidth / 0.8; // 保持 0.8 的宽高比

                // 构建历史卡片列表
                final historyCards = displayList
                    .map((history) =>
                        _buildHistoryItem(context, history, colorScheme, cardWidth))
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

  Widget _buildHistoryItem(
    BuildContext context,
    PlayHistory history,
    ColorScheme colorScheme,
    double cardWidth,
  ) {
    return SizedBox(
      width: cardWidth,
      child: ContextMenuRegion(
        menuBuilder: (_) => _buildHistoryMenuItems(colorScheme),
        onSelected: (value) => _handleHistoryMenuAction(context, history, value),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              // 将历史记录转换为 Track 并播放
              final track = history.toTrack();
              ref.read(audioControllerProvider.notifier).playTemporary(track);
            },
            onLongPress: () => _showHistoryOptionsMenu(context, history),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面 - 使用 Expanded 与音乐库一致
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      history.thumbnailUrl != null
                          ? ImageLoadingService.loadImage(
                              networkUrl: history.thumbnailUrl,
                              placeholder: const ImagePlaceholder.track(),
                              fit: BoxFit.cover,
                            )
                          : const ImagePlaceholder.track(),
                    ],
                  ),
                ),
                // 标题
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

  List<PopupMenuEntry<String>> _buildHistoryMenuItems(ColorScheme colorScheme) => [
    PopupMenuItem(
      value: 'play',
      child: ListTile(leading: const Icon(Icons.play_arrow), title: Text(t.playHistoryPage.play), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'play_next',
      child: ListTile(leading: const Icon(Icons.queue_play_next), title: Text(t.playHistoryPage.playNext), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'add_to_queue',
      child: ListTile(leading: const Icon(Icons.add_to_queue), title: Text(t.playHistoryPage.addToQueue), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'add_to_playlist',
      child: ListTile(leading: const Icon(Icons.playlist_add), title: Text(t.playHistoryPage.addToPlaylist), contentPadding: EdgeInsets.zero),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'delete',
      child: ListTile(
        leading: Icon(Icons.delete_outline, color: colorScheme.error),
        title: Text(t.playHistoryPage.deleteThisRecord, style: TextStyle(color: colorScheme.error)),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'delete_all',
      child: ListTile(
        leading: Icon(Icons.delete_sweep, color: colorScheme.error),
        title: Text(t.playHistoryPage.deleteAllForTrack, style: TextStyle(color: colorScheme.error)),
        contentPadding: EdgeInsets.zero,
      ),
    ),
  ];

  void _handleHistoryMenuAction(BuildContext context, PlayHistory history, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final track = history.toTrack();

    switch (action) {
      case 'play':
        controller.playTemporary(track);
      case 'play_next':
        final added = await controller.addNext(track);
        if (added && context.mounted) {
          ToastService.success(context, t.playHistoryPage.toastAddedToNext);
        }
      case 'add_to_queue':
        final added = await controller.addToQueue(track);
        if (added && context.mounted) {
          ToastService.success(context, t.playHistoryPage.toastAddedToQueue);
        }
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
      case 'delete':
        await ref.read(playHistoryActionsProvider).delete(history.id);
        if (context.mounted) {
          ToastService.success(context, t.playHistoryPage.toastDeletedRecord);
        }
      case 'delete_all':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t.playHistoryPage.deleteAllTitle),
            content: Text(t.playHistoryPage.deleteAllConfirm(title: history.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.general.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t.playHistoryPage.deleteButton),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          final count = await ref
              .read(playHistoryPageProvider.notifier)
              .deleteAllForTrack(history.trackKey);
          if (context.mounted) {
            ToastService.success(context, t.playHistoryPage.toastDeletedCount(n: count));
          }
        }
    }
  }

  void _showHistoryOptionsMenu(BuildContext context, PlayHistory history) {
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
                leading: const Icon(Icons.play_arrow),
                title: Text(t.playHistoryPage.play),
                onTap: () {
                  Navigator.pop(context);
                  _handleHistoryMenuAction(context, history, 'play');
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_play_next),
                title: Text(t.playHistoryPage.playNext),
                onTap: () {
                  Navigator.pop(context);
                  _handleHistoryMenuAction(context, history, 'play_next');
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_to_queue),
                title: Text(t.playHistoryPage.addToQueue),
                onTap: () {
                  Navigator.pop(context);
                  _handleHistoryMenuAction(context, history, 'add_to_queue');
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: Text(t.playHistoryPage.addToPlaylist),
                onTap: () {
                  Navigator.pop(context);
                  _handleHistoryMenuAction(context, history, 'add_to_playlist');
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text(t.playHistoryPage.deleteThisRecord, style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _handleHistoryMenuAction(context, history, 'delete');
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_sweep, color: colorScheme.error),
                title: Text(t.playHistoryPage.deleteAllForTrack, style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _handleHistoryMenuAction(context, history, 'delete_all');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNowPlaying(
    BuildContext context,
    PlayerState playerState,
    ColorScheme colorScheme,
  ) {
    final track = playerState.currentTrack!;
    // 檢查電台是否正在播放
    final isRadioPlaying = ref.watch(isRadioPlayingProvider);
    // 音樂實際播放狀態：電台播放時，音樂處於暫停狀態
    final isMusicPlaying = playerState.isPlaying && !isRadioPlaying;

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
                if (isRadioPlaying) {
                          // 電台播放中，點擊播放音樂（會自動停止電台）
                          final index = playerState.currentIndex;
                          if (index != null && index >= 0) {
                            ref.read(audioControllerProvider.notifier).playAt(index);
                          }
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
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            track.artist ?? t.general.unknownArtist,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                        if (isRadioPlaying) {
                          // 電台播放中，點擊播放音樂（會自動停止電台）
                          final index = playerState.currentIndex;
                          if (index != null && index >= 0) {
                            ref.read(audioControllerProvider.notifier).playAt(index);
                          }
                        } else {
                          ref.read(audioControllerProvider.notifier).togglePlayPause();
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

    Widget _buildQueuePreview(
    BuildContext context,
    PlayerState playerState,
    ColorScheme colorScheme,
  ) {
    // 使用 upcomingTracks 获取接下来要播放的歌曲（已考虑 shuffle 模式）
    final upNext = playerState.upcomingTracks.take(AppConstants.upcomingTracksPreviewCount).toList();
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
            children: upNext.map((track) => ListTile(
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
                final trackIndex = playerState.queue.indexOf(track);
                if (trackIndex >= 0) {
                  ref.read(audioControllerProvider.notifier).playAt(trackIndex);
                }
              },
            )).toList(),
          ),
        ),
      ],
    );
  }

  /// 構建電台區域
  Widget _buildRadioSection(BuildContext context, ColorScheme colorScheme) {
    final radioState = ref.watch(radioControllerProvider);

    if (radioState.stations.isEmpty) {
      return const SizedBox.shrink();
    }

    // 排序：正在直播的排前面
    final sortedStations = List<RadioStation>.from(radioState.stations)
      ..sort((a, b) {
        final aLive = radioState.isStationLive(a.id) ? 0 : 1;
        final bLive = radioState.isStationLive(b.id) ? 0 : 1;
        return aLive.compareTo(bLive);
      });
    // 最多显示 20 个
    final displayStations = sortedStations.take(AppConstants.homeListPreviewCount).toList();

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
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 12),
                        Text(t.radio.deleteStation, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'delete') _showRadioDeleteConfirm(context, station);
                },
                child: _HomeRadioStationCard(
                  station: station,
                  isLive: isLive,
                  isPlaying: isPlaying,
                  isLoading: isLoading,
                  onTap: () => _onRadioStationTap(station, isCurrentPlaying, radioState),
                  onLongPress: () => _showRadioOptionsMenu(context, station),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 電台卡片點擊處理
  void _onRadioStationTap(
    RadioStation station,
    bool isCurrentPlaying,
    RadioState radioState,
  ) {
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

  /// 電台長按菜單（移動端）
  void _showRadioOptionsMenu(BuildContext context, RadioStation station) {
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
                title: Text(t.radio.deleteStation, style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _showRadioDeleteConfirm(context, station);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 電台刪除確認對話框
  Future<void> _showRadioDeleteConfirm(BuildContext context, RadioStation station) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.radio.deleteStation),
        content: Text(t.radio.deleteConfirm(title: station.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.radio.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(radioControllerProvider.notifier).deleteStation(station.id);
      if (context.mounted) {
        ToastService.success(context, t.radio.stationDeleted);
      }
    }
  }
}

/// 排行榜歌曲項目（類似搜索結果項目）
class _RankingTrackTile extends ConsumerWidget {
  final Track track;
  final int rank;

  const _RankingTrackTile({required this.track, required this.rank});

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
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
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
              size: AppSizes.thumbnailMedium,
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
                track.artist ?? t.general.unknownArtist,
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
                formatCount(track.viewCount!),
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
          itemBuilder: (_) => _buildMenuItems(),
        ),
        onTap: () {
          ref.read(audioControllerProvider.notifier).playTemporary(track);
        },
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() => [
    PopupMenuItem(
      value: 'play',
      child: ListTile(leading: const Icon(Icons.play_arrow), title: Text(t.home.play), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'play_next',
      child: ListTile(leading: const Icon(Icons.queue_play_next), title: Text(t.home.playNext), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'add_to_queue',
      child: ListTile(leading: const Icon(Icons.add_to_queue), title: Text(t.home.addToQueue), contentPadding: EdgeInsets.zero),
    ),
    PopupMenuItem(
      value: 'add_to_playlist',
      child: ListTile(leading: const Icon(Icons.playlist_add), title: Text(t.home.addToPlaylist), contentPadding: EdgeInsets.zero),
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
          ToastService.success(context, t.home.addedToNext);
        }
        break;
      case 'add_to_queue':
        final added = await controller.addToQueue(track);
        if (added && context.mounted) {
          ToastService.success(context, t.home.addedToQueue);
        }
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, track: track);
        break;
    }
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
                        : const ColorFilter.matrix(<double>[
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0, 0, 0, 1, 0,
                          ]),
                    child: ImageLoadingService.loadImage(
                      networkUrl: station.thumbnailUrl,
                      placeholder: _buildPlaceholder(colorScheme),
                      fit: BoxFit.cover,
                      width: 100,
                      height: 100,
                    ),
                  ),
                ),

                // 正在直播红点
                if (isLive)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.5),
                            blurRadius: 3,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
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

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.radio,
        size: 40,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

/// 首頁歌單卡片（帶右鍵/長按菜單）
class _HomePlaylistCard extends ConsumerWidget {
  final Playlist playlist;

  const _HomePlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverAsync = ref.watch(playlistCoverProvider(playlist.id));

    // 預加載歌單詳情數據
    ref.read(playlistDetailProvider(playlist.id));

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
                          ? ImageLoadingService.loadImage(
                              localPath: coverData.localPath,
                              networkUrl: coverData.networkUrl,
                              placeholder: const ImagePlaceholder.playlist(),
                              fit: BoxFit.cover,
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
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                          ),
                        ] else ...[
                          if (playlist.isImported) ...[
                            Icon(
                              Icons.link,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            t.library.trackCount(n: playlist.trackCount),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

  List<PopupMenuEntry<String>> _buildContextMenuItems(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRefreshing = ref.read(isPlaylistRefreshingProvider(playlist.id));

    return [
      if (playlist.isMix) ...[
        PopupMenuItem(
          value: 'play_mix',
          child: Row(
            children: [const Icon(Icons.play_arrow, size: 20), const SizedBox(width: 12), Text(t.library.main.playMix)],
          ),
        ),
      ] else ...[
        PopupMenuItem(
          value: 'add_all',
          child: Row(
            children: [const Icon(Icons.play_arrow, size: 20), const SizedBox(width: 12), Text(t.library.addAll)],
          ),
        ),
        PopupMenuItem(
          value: 'shuffle_add',
          child: Row(
            children: [const Icon(Icons.shuffle, size: 20), const SizedBox(width: 12), Text(t.library.shuffleAdd)],
          ),
        ),
      ],
      PopupMenuItem(
        value: 'edit',
        child: Row(
          children: [const Icon(Icons.edit, size: 20), const SizedBox(width: 12), Text(t.library.main.editPlaylist)],
        ),
      ),
      if (playlist.isImported && !playlist.isMix)
        PopupMenuItem(
          value: 'refresh',
          enabled: !isRefreshing,
          child: Row(
            children: [
              Icon(isRefreshing ? Icons.hourglass_empty : Icons.refresh, size: 20),
              const SizedBox(width: 12),
              Text(isRefreshing ? t.library.main.refreshing : t.library.main.refreshPlaylist),
            ],
          ),
        ),
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete, size: 20, color: colorScheme.error),
            const SizedBox(width: 12),
            Text(t.library.main.deletePlaylist, style: TextStyle(color: colorScheme.error)),
          ],
        ),
      ),
    ];
  }

  void _handleContextMenuAction(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case 'play_mix':
        _playMix(context, ref);
      case 'add_all':
        _addAllToQueue(context, ref);
      case 'shuffle_add':
        _shuffleAddToQueue(context, ref);
      case 'edit':
        _showEditDialog(context, ref);
      case 'refresh':
        _refreshPlaylist(context, ref);
      case 'delete':
        _showDeleteConfirm(context, ref);
    }
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRefreshing = ref.read(isPlaylistRefreshingProvider(playlist.id));

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (playlist.isMix) ...[
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(t.library.main.playMix),
                  onTap: () {
                    Navigator.pop(context);
                    _playMix(context, ref);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(t.library.addAll),
                  onTap: () {
                    Navigator.pop(context);
                    _addAllToQueue(context, ref);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shuffle),
                  title: Text(t.library.shuffleAdd),
                  onTap: () {
                    Navigator.pop(context);
                    _shuffleAddToQueue(context, ref);
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(t.library.main.editPlaylist),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(context, ref);
                },
              ),
              if (playlist.isImported && !playlist.isMix)
                ListTile(
                  leading: isRefreshing
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                          ),
                        )
                      : const Icon(Icons.refresh),
                  title: Text(isRefreshing ? t.library.main.refreshing : t.library.main.refreshPlaylist),
                  enabled: !isRefreshing,
                  onTap: isRefreshing
                      ? null
                      : () {
                          Navigator.pop(context);
                          _refreshPlaylist(context, ref);
                        },
                ),
              ListTile(
                leading: Icon(Icons.delete, color: colorScheme.error),
                title: Text(t.library.main.deletePlaylist, style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirm(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addAllToQueue(BuildContext context, WidgetRef ref) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ToastService.warning(context, t.library.main.playlistEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final added = await controller.addAllToQueue(result.tracks);

    if (added && context.mounted) {
      ToastService.success(context, t.library.addedToQueue(n: result.tracks.length));
    }
  }

  void _shuffleAddToQueue(BuildContext context, WidgetRef ref) async {
    final service = ref.read(playlistServiceProvider);
    final result = await service.getPlaylistWithTracks(playlist.id);

    if (result == null || result.tracks.isEmpty) {
      if (context.mounted) {
        ToastService.warning(context, t.library.main.playlistEmpty);
      }
      return;
    }

    final controller = ref.read(audioControllerProvider.notifier);
    final shuffled = List<Track>.from(result.tracks)..shuffle();
    final added = await controller.addAllToQueue(shuffled);

    if (added && context.mounted) {
      ToastService.success(context, t.library.shuffledAddedToQueue(n: result.tracks.length));
    }
  }

  Future<void> _playMix(BuildContext context, WidgetRef ref) async {
    if (playlist.mixPlaylistId == null || playlist.mixSeedVideoId == null) {
      ToastService.error(context, t.library.main.mixInfoIncomplete);
      return;
    }

    try {
      final youtubeSource = ref.read(youtubeSourceProvider);
      final result = await youtubeSource.fetchMixTracks(
        playlistId: playlist.mixPlaylistId!,
        currentVideoId: playlist.mixSeedVideoId!,
      );

      if (result.tracks.isEmpty) {
        if (context.mounted) {
          ToastService.error(context, t.library.main.cannotLoadMix);
        }
        return;
      }

      final controller = ref.read(audioControllerProvider.notifier);
      await controller.playMixPlaylist(
        playlistId: playlist.mixPlaylistId!,
        seedVideoId: playlist.mixSeedVideoId!,
        title: playlist.name,
        tracks: result.tracks,
      );
    } catch (e) {
      if (context.mounted) {
        ToastService.error(context, '${t.library.main.playMixFailed}: $e');
      }
    }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.library.main.deletePlaylist),
        content: Text(t.library.main.deletePlaylistConfirm(name: playlist.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(t.general.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(playlistListProvider.notifier).deletePlaylist(playlist.id);
      if (context.mounted) {
        ToastService.success(context, t.library.main.playlistDeleted);
      }
    }
  }
}
