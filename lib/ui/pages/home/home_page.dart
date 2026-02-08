import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    // 监听电台错误并显示 Toast（与 RadioPage 保持一致）
    ref.listen<RadioState>(radioControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ToastService.show(context, next.error!);
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

            // 正在播放
            if (playerState.hasCurrentTrack)
              _buildNowPlaying(context, playerState, colorScheme),

            // 队列预览
            if (playerState.queue.isNotEmpty)
              _buildQueuePreview(context, playerState, colorScheme),

            // 电台
            _buildRadioSection(context, colorScheme),

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
                '近期熱門',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(RoutePaths.explore),
                child: const Text('查看全部'),
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
                '載入失敗',
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
          ),
          data: (tracks) {
            if (tracks.isEmpty) {
              return const SizedBox.shrink();
            }
            final displayTracks = tracks.take(5).toList();
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
        final recentLists = lists.take(20).toList();

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
                  if (lists.isNotEmpty)
                    TextButton(
                      onPressed: () => context.go(RoutePaths.library),
                      child: const Text('查看全部'),
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
                  final coverAsync =
                      ref.watch(playlistCoverProvider(playlist.id));

                  // 預加載歌單詳情數據
                  ref.read(playlistDetailProvider(playlist.id));

                  return SizedBox(
                    width: cardWidth,
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.go('/library/${playlist.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 封面 - 使用 Expanded 与音乐库一致
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
                                            placeholder:
                                                const ImagePlaceholder
                                                    .playlist(),
                                            fit: BoxFit.cover,
                                          )
                                        : const ImagePlaceholder.playlist(),
                                    loading: () =>
                                        const ImagePlaceholder.playlist(),
                                    error: (e, s) =>
                                        const ImagePlaceholder.playlist(),
                                  ),
                                ],
                              ),
                            ),
                            // 名称
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                playlist.name,
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
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
                        '创建歌单',
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
        final displayList = historyList.take(20).toList();

        if (displayList.isEmpty) return const SizedBox.shrink();

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
                  TextButton(
                    onPressed: () => context.push(RoutePaths.history),
                    child: const Text('查看全部'),
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
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            // 将历史记录转换为 Track 并播放
            final track = history.toTrack();
            ref.read(audioControllerProvider.notifier).playTemporary(track);
          },
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
            '正在播放',
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
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 封面
                    TrackThumbnail(
                      track: track,
                      size: 56,
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
                            track.artist ?? '未知艺术家',
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: upNext.map((track) => ListTile(
              contentPadding: const EdgeInsets.only(left: 18),
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
    final displayStations = sortedStations.take(20).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                '電台',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(RoutePaths.radio),
                child: const Text('查看全部'),
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
              child: _HomeRadioStationCard(
                station: station,
                isLive: isLive,
                isPlaying: isPlaying,
                isLoading: isLoading,
                onTap: () => _onRadioStationTap(station, isCurrentPlaying, radioState),
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

    return ListTile(
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

  String _formatViewCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}億';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}萬';
    }
    return count.toString();
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
}

/// 首頁電台卡片（簡化版）
class _HomeRadioStationCard extends StatelessWidget {
  final RadioStation station;
  final bool isLive;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onTap;

  const _HomeRadioStationCard({
    required this.station,
    required this.isLive,
    required this.isPlaying,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
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
