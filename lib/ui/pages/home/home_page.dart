import 'package:flutter/material.dart';
import 'dart:ui';

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
import '../../router.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

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

              // 最近播放历史
              _buildRecentHistory(context, colorScheme),

              const SizedBox(height: 100), // 为迷你播放器留出空间
            ],
          ),
        ),
      ),
    );
  }

  /// 構建音樂排行榜區域（響應式佈局）
  Widget _buildMusicRankings(BuildContext context, ColorScheme colorScheme) {
    final bilibiliAsync = ref.watch(homeBilibiliMusicRankingProvider);
    final youtubeAsync = ref.watch(homeYouTubeMusicRankingProvider);

    // 判斷是否有數據
    final hasBilibiliData = bilibiliAsync.valueOrNull?.isNotEmpty ?? false;
    final hasYoutubeData = youtubeAsync.valueOrNull?.isNotEmpty ?? false;
    final isLoading = bilibiliAsync.isLoading || youtubeAsync.isLoading;

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
                child: const Text('更多'),
              ),
            ],
          ),
        ),
        // 排行榜內容
        LayoutBuilder(
          builder: (context, constraints) {
            final isWideScreen = constraints.maxWidth > 600;

            if (isWideScreen) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildRankingCard(
                        context,
                        colorScheme,
                        title: 'Bilibili',
                        asyncValue: bilibiliAsync,
                      ),
                    ),
                    const SizedBox(width: 16),
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
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildRankingCard(
                      context,
                      colorScheme,
                      title: 'Bilibili',
                      asyncValue: bilibiliAsync,
                    ),
                    const SizedBox(height: 12),
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
        ),
      ],
    );
  }

  /// 構建單個排行榜卡片
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
        // 排行列表
        asyncValue.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
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
              return SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    '暫無數據',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                ),
              );
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
        // 最多显示 10 个歌单
        final recentLists = lists.take(10).toList();

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

                return SizedBox(
                  height: cardHeight,
                  child: ScrollConfiguration(
                    // 允许鼠标拖拽滚动（桌面端支持）
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: recentLists.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final playlist = recentLists[index];
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
                              onTap: () =>
                                  context.go('/library/${playlist.id}'),
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
                                          data: (coverData) =>
                                              coverData.hasCover
                                                  ? ImageLoadingService
                                                      .loadImage(
                                                      localPath:
                                                          coverData.localPath,
                                                      networkUrl:
                                                          coverData.networkUrl,
                                                      placeholder:
                                                          const ImagePlaceholder
                                                              .playlist(),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const ImagePlaceholder
                                                      .playlist(),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
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
    final currentTrack = ref.watch(audioControllerProvider).currentTrack;

    return historyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (historyList) {
        // 过滤掉当前正在播放的歌曲
        final filteredList = currentTrack != null
            ? historyList
                .where((h) =>
                    h.sourceId != currentTrack.sourceId ||
                    h.sourceType != currentTrack.sourceType)
                .toList()
            : historyList;

        if (filteredList.isEmpty) return const SizedBox.shrink();

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
                  // TODO: 查看全部历史页面
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                // 根据窗口宽度计算卡片大小，平滑缩放
                final cardWidth =
                    (constraints.maxWidth / 4).clamp(100.0, 140.0);
                final cardHeight = cardWidth / 0.8; // 保持 0.8 的宽高比

                return SizedBox(
                  height: cardHeight,
                  child: ScrollConfiguration(
                    // 允许鼠标拖拽滚动（桌面端支持）
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredList.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final history = filteredList[index];
                        return _buildHistoryItem(
                            context, history, colorScheme, cardWidth);
                      },
                    ),
                  ),
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
              onTap: () => ref.read(audioControllerProvider.notifier).togglePlayPause(),
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
                        playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: () =>
                          ref.read(audioControllerProvider.notifier).togglePlayPause(),
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
