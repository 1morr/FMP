import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../data/models/video_detail.dart';
import '../../../data/sources/base_source.dart' show SearchOrder;
import '../../../data/sources/bilibili_source.dart';
import '../../../data/sources/source_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/track_group/track_group.dart';
import '../../widgets/track_thumbnail.dart';

/// 搜索页
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showHistory = true;

  // 分P展开状态管理
  final Set<String> _expandedVideos = {};
  final Map<String, List<VideoPage>> _loadedPages = {};
  final Set<String> _loadingPages = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    setState(() {
      _showHistory = _searchController.text.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(
        title: _buildSearchField(context),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchController.clear();
                ref.read(searchProvider.notifier).clear();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // 音源筛选
          _buildSourceFilter(context, searchState),

          // 内容区域
          Expanded(
            child: _showHistory && searchState.query.isEmpty
                ? _buildSearchHistory(context)
                : _buildSearchResults(context, searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      decoration: const InputDecoration(
        hintText: '搜索歌曲、艺术家...',
        border: InputBorder.none,
        prefixIcon: Icon(Icons.search),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: _performSearch,
    );
  }

  Widget _buildSourceFilter(BuildContext context, SearchState state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '音源:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(width: 8),
          _buildSourceChip(
            context,
            SourceType.bilibili,
            'Bilibili',
            state.enabledSources.contains(SourceType.bilibili),
          ),
          const Spacer(),
          // 排序按钮
          _buildSortButton(context, state),
        ],
      ),
    );
  }

  Widget _buildSortButton(BuildContext context, SearchState state) {
    return PopupMenuButton<SearchOrder>(
      initialValue: state.searchOrder,
      onSelected: (order) {
        ref.read(searchProvider.notifier).setSearchOrder(order);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: SearchOrder.relevance,
          child: Text('综合排序'),
        ),
        const PopupMenuItem(
          value: SearchOrder.playCount,
          child: Text('最多播放'),
        ),
        const PopupMenuItem(
          value: SearchOrder.publishDate,
          child: Text('最新发布'),
        ),
        const PopupMenuItem(
          value: SearchOrder.danmakuCount,
          child: Text('最多弹幕'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              _getOrderName(state.searchOrder),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _getOrderName(SearchOrder order) {
    switch (order) {
      case SearchOrder.relevance:
        return '综合';
      case SearchOrder.playCount:
        return '播放量';
      case SearchOrder.publishDate:
        return '最新';
      case SearchOrder.danmakuCount:
        return '弹幕';
    }
  }

  Widget _buildSourceChip(
    BuildContext context,
    SourceType sourceType,
    String label,
    bool isSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          ref.read(searchProvider.notifier).toggleSource(sourceType);
        },
      ),
    );
  }

  Widget _buildSearchHistory(BuildContext context) {
    final history = ref.watch(searchHistoryManagerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '搜索你喜欢的音乐',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '搜索历史',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(searchHistoryManagerProvider.notifier).clearAll();
                },
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(item.query),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    ref
                        .read(searchHistoryManagerProvider.notifier)
                        .deleteItem(item.id);
                  },
                ),
                onTap: () {
                  _searchController.text = item.query;
                  _performSearch(item.query);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context, SearchState state) {
    if (state.isLoading && state.allOnlineTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.allOnlineTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(state.error!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _performSearch(state.query),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 当滚动到底部附近时自动加载更多
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 200) {
            // 对每个有更多内容的音源加载更多
            for (final entry in state.onlineResults.entries) {
              if (entry.value.hasMore && !state.isLoading) {
                ref.read(searchProvider.notifier).loadMore(entry.key);
                break; // 一次只加载一个音源
              }
            }
          }
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          // 歌单中的结果（按视频分组显示）
          if (state.localResults.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '歌单中 (${state.localResults.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            Builder(
              builder: (context) {
                // 先按 sourceId + pageNum 去重，避免同一首歌在多个歌单中重复显示
                final uniqueTracks = <String, Track>{};
                for (final track in state.localResults) {
                  final key = '${track.sourceId}:${track.pageNum ?? 1}';
                  // 只保留第一个出现的（或者可以保留最新的）
                  uniqueTracks.putIfAbsent(key, () => track);
                }
                // 然后按视频分组
                final groupedLocalResults = groupTracks(uniqueTracks.values.toList());
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final group = groupedLocalResults[index];
                      return _LocalGroupTile(
                        group: group,
                        isExpanded: _expandedVideos.contains(group.groupKey),
                        onToggleExpand: () => _toggleExpanded(group.groupKey),
                        onPlayTrack: (track) {
                          final controller = ref.read(audioControllerProvider.notifier);
                          controller.playTemporary(track);
                        },
                        onMenuAction: _handleMenuAction,
                      );
                    },
                    childCount: groupedLocalResults.length,
                  ),
                );
              },
            ),
          ],

          // 在线结果（按音源分组）
          for (final entry in state.onlineResults.entries) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _getSourceName(entry.key),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = entry.value.tracks[index];
                  return _SearchResultTile(
                    track: track,
                    isLocal: false,
                    isExpanded: _expandedVideos.contains(track.sourceId),
                    isLoading: _loadingPages.contains(track.sourceId),
                    pages: _loadedPages[track.sourceId],
                    onTap: () => _playVideo(track),
                    onToggleExpand: () => _toggleExpanded(track.sourceId),
                    onMenuAction: _handleMenuAction,
                    onPageMenuAction: (page, action) => _handlePageMenuAction(track, page, action),
                  );
                },
                childCount: entry.value.tracks.length,
              ),
            ),
          ],

          // 加载更多指示器
          if (state.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          // 已加载全部
          if (!state.isLoading && state.hasResults && !_hasMoreResults(state))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    '已加载全部',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ),
            ),

          // 无结果
          if (!state.hasResults && !state.isLoading)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '未找到 "${state.query}" 相关结果',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasMoreResults(SearchState state) {
    for (final entry in state.onlineResults.entries) {
      if (entry.value.hasMore) return true;
    }
    return false;
  }

  String _getSourceName(SourceType type) {
    switch (type) {
      case SourceType.bilibili:
        return 'Bilibili';
      case SourceType.youtube:
        return 'YouTube';
    }
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();
    // 清空之前的分P缓存
    _expandedVideos.clear();
    _loadedPages.clear();
    _loadingPages.clear();
    ref.read(searchProvider.notifier).search(query);
  }

  /// 加载视频分P信息
  Future<void> _loadVideoPages(Track track) async {
    final key = track.sourceId;
    if (_loadedPages.containsKey(key) || _loadingPages.contains(key)) {
      return;
    }

    if (track.sourceType != SourceType.bilibili) {
      return;
    }

    setState(() {
      _loadingPages.add(key);
    });

    try {
      final sourceManager = ref.read(sourceManagerProvider);
      final source = sourceManager.getSource(SourceType.bilibili) as BilibiliSource;
      final pages = await source.getVideoPages(track.sourceId);

      if (mounted) {
        setState(() {
          _loadedPages[key] = pages;
          _loadingPages.remove(key);
          if (pages.length > 1) {
            _expandedVideos.add(key);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPages.remove(key);
        });
      }
    }
  }

  /// 切换视频展开状态
  void _toggleExpanded(String sourceId) {
    setState(() {
      if (_expandedVideos.contains(sourceId)) {
        _expandedVideos.remove(sourceId);
      } else {
        _expandedVideos.add(sourceId);
      }
    });
  }

  /// 播放视频（自动获取分P并播放第一个）
  Future<void> _playVideo(Track track) async {
    final controller = ref.read(audioControllerProvider.notifier);

    // 如果已有分P信息
    if (_loadedPages.containsKey(track.sourceId)) {
      final pages = _loadedPages[track.sourceId]!;
      if (pages.isNotEmpty) {
        // 播放第一个分P
        final firstPage = pages.first;
        final pageTrack = firstPage.toTrack(track);
        controller.playTemporary(pageTrack);
      } else {
        controller.playTemporary(track);
      }
    } else {
      // 先播放原始track，同时加载分P信息
      controller.playTemporary(track);
      await _loadVideoPages(track);
    }
  }

  /// 处理视频菜单操作
  void _handleMenuAction(Track track, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);

    // 确保有分P信息
    if (!_loadedPages.containsKey(track.sourceId)) {
      await _loadVideoPages(track);
    }

    final pages = _loadedPages[track.sourceId];
    final hasMultiplePages = pages != null && pages.length > 1;

    switch (action) {
      case 'play':
        _playVideo(track);
        break;
      case 'play_next':
        if (hasMultiplePages) {
          // 多P视频：添加所有分P
          for (final page in pages) {
            controller.addNext(page.toTrack(track));
          }
          if (mounted) {
            ToastService.show(context, '已添加${pages.length}个分P到下一首');
          }
        } else {
          controller.addNext(track);
          if (mounted) {
            ToastService.show(context, '已添加到下一首');
          }
        }
        break;
      case 'add_to_queue':
        if (hasMultiplePages) {
          // 多P视频：添加所有分P
          for (final page in pages) {
            controller.addToQueue(page.toTrack(track));
          }
          if (mounted) {
            ToastService.show(context, '已添加${pages.length}个分P到播放队列');
          }
        } else {
          controller.addToQueue(track);
          if (mounted) {
            ToastService.show(context, '已添加到播放队列');
          }
        }
        break;
      case 'download':
        final downloadService = ref.read(downloadServiceProvider);
        if (hasMultiplePages) {
          // 多P视频：下载所有分P
          int addedCount = 0;
          for (final page in pages) {
            final pageTrack = page.toTrack(track);
            final result = await downloadService.addTrackDownload(pageTrack);
            if (result != null) addedCount++;
          }
          if (mounted) {
            ToastService.show(context, '已添加 $addedCount 个分P到下载队列');
          }
        } else {
          final result = await downloadService.addTrackDownload(track);
          if (mounted) {
            ToastService.show(
              context,
              result != null ? '已添加到下载队列' : '歌曲已下载或已在队列中',
            );
          }
        }
        break;
      case 'add_to_playlist':
        if (hasMultiplePages) {
          // 多P视频：添加所有分P到歌单
          final pageTracks = pages.map((p) => p.toTrack(track)).toList();
          if (mounted) {
            showAddToPlaylistDialog(context: context, tracks: pageTracks);
          }
        } else {
          if (mounted) {
            showAddToPlaylistDialog(context: context, track: track);
          }
        }
        break;
    }
  }

  /// 处理分P菜单操作
  void _handlePageMenuAction(Track parentTrack, VideoPage page, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);
    final pageTrack = page.toTrack(parentTrack);

    switch (action) {
      case 'play':
        controller.playTemporary(pageTrack);
        break;
      case 'play_next':
        controller.addNext(pageTrack);
        ToastService.show(context, '已添加到下一首');
        break;
      case 'add_to_queue':
        controller.addToQueue(pageTrack);
        ToastService.show(context, '已添加到播放队列');
        break;
      case 'download':
        final downloadService = ref.read(downloadServiceProvider);
        final result = await downloadService.addTrackDownload(pageTrack);
        if (mounted) {
          ToastService.show(
            context,
            result != null ? '已添加到下载队列' : '分P已下载或已在队列中',
          );
        }
        break;
    }
  }
}

/// 搜索结果列表项（支持分P展开）
class _SearchResultTile extends ConsumerWidget {
  final Track track;
  final bool isLocal;
  final bool isExpanded;
  final bool isLoading;
  final List<VideoPage>? pages;
  final VoidCallback onTap;
  final VoidCallback? onToggleExpand;
  final void Function(Track track, String action) onMenuAction;
  final void Function(VideoPage page, String action) onPageMenuAction;

  const _SearchResultTile({
    required this.track,
    required this.isLocal,
    required this.isExpanded,
    required this.isLoading,
    required this.pages,
    required this.onTap,
    required this.onToggleExpand,
    required this.onMenuAction,
    required this.onPageMenuAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMultiplePages = pages != null && pages!.length > 1;
    final currentTrack = ref.watch(currentTrackProvider);

    // 检查当前播放的是否是这个视频的某个分P
    final isPlayingThisVideo = currentTrack != null &&
        currentTrack.sourceId == track.sourceId;
    // 检查是否正在播放这个具体的 track（单P视频或第一个分P）
    final isPlaying = isPlayingThisVideo &&
        currentTrack.pageNum == track.pageNum;
    // 多P视频高亮整个视频，单P视频高亮具体匹配
    final shouldHighlight = hasMultiplePages ? isPlayingThisVideo : isPlaying;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主视频行
        ListTile(
          leading: TrackThumbnail(
            track: track,
            size: 48,
            borderRadius: 4,
            isPlaying: shouldHighlight,
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: shouldHighlight ? colorScheme.primary : null,
              fontWeight: shouldHighlight ? FontWeight.w600 : null,
            ),
          ),
          subtitle: Row(
            children: [
              if (isLocal) ...[
                Icon(
                  Icons.check_circle,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  track.artist ?? '未知艺术家',
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
              if (hasMultiplePages) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${pages!.length}P',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (track.durationMs != null)
                Text(
                  DurationFormatter.formatMs(track.durationMs!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (hasMultiplePages)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: onToggleExpand,
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) => onMenuAction(track, value),
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
                      title: Text('添加到队列'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download',
                    child: ListTile(
                      leading: Icon(Icons.download_outlined),
                      title: Text('下载'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add_to_playlist',
                    child: ListTile(
                      leading: Icon(Icons.playlist_add),
                      title: Text('添加到歌单'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: onTap,
        ),

        // 分P列表（展开时显示）
        if (isExpanded && pages != null && pages!.length > 1)
          ...pages!.map((page) => _PageTile(
                page: page,
                parentTrack: track,
                onTap: () => onPageMenuAction(page, 'play'),
                onMenuAction: (action) => onPageMenuAction(page, action),
              )),
      ],
    );
  }

  String _formatViewCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    } else {
      return count.toString();
    }
  }
}

/// 分P列表项
class _PageTile extends ConsumerWidget {
  final VideoPage page;
  final Track parentTrack;
  final VoidCallback onTap;
  final void Function(String action) onMenuAction;

  const _PageTile({
    required this.page,
    required this.parentTrack,
    required this.onTap,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    // 检查是否正在播放这个分P
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == parentTrack.sourceId &&
        currentTrack.pageNum == page.page;

    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: ListTile(
        leading: isPlaying
            ? NowPlayingIndicator(
                size: 24,
                color: colorScheme.primary,
              )
            : Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  'P${page.page}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
              ),
        title: Text(
          page.part,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isPlaying ? colorScheme.primary : null,
            fontWeight: isPlaying ? FontWeight.w600 : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              page.formattedDuration,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: onMenuAction,
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
                    title: Text('添加到队列'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('下载'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                // 注意：分P没有"添加到歌单"选项
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// 本地搜索结果分组组件
class _LocalGroupTile extends ConsumerWidget {
  final TrackGroup group;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final void Function(Track track) onPlayTrack;
  final void Function(Track track, String action) onMenuAction;

  const _LocalGroupTile({
    required this.group,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onPlayTrack,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final firstTrack = group.firstTrack;
    final hasMultipleParts = group.hasMultipleParts;

    // 检查当前播放的是否是这个组的某个分P
    final isPlayingThisGroup = currentTrack != null &&
        group.tracks.any((t) =>
            t.sourceId == currentTrack.sourceId &&
            t.pageNum == currentTrack.pageNum);

    return Column(
      children: [
        // 主视频行
        ListTile(
          leading: TrackThumbnail(
            track: firstTrack,
            size: 48,
            borderRadius: 4,
            isPlaying: isPlayingThisGroup,
          ),
          title: Text(
            group.parentTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isPlayingThisGroup ? colorScheme.primary : null,
              fontWeight: isPlayingThisGroup ? FontWeight.w600 : null,
            ),
          ),
          subtitle: Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  firstTrack.artist ?? '未知艺术家',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasMultipleParts) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${group.partCount}P',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                  ),
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (firstTrack.durationMs != null && !hasMultipleParts)
                Text(
                  DurationFormatter.formatMs(firstTrack.durationMs!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
              if (hasMultipleParts)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: onToggleExpand,
                ),
              PopupMenuButton<String>(
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
                      title: Text('添加到队列'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download',
                    child: ListTile(
                      leading: Icon(Icons.download_outlined),
                      title: Text('下载'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'add_to_playlist',
                    child: ListTile(
                      leading: Icon(Icons.playlist_add),
                      title: Text('添加到歌单'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => onPlayTrack(firstTrack),
        ),

        // 展开的分P列表
        if (isExpanded && hasMultipleParts)
          ...group.tracks.map((track) => _LocalTrackTile(
                track: track,
                onTap: () => onPlayTrack(track),
                onMenuAction: onMenuAction,
              )),
      ],
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);

    switch (action) {
      case 'play':
        onPlayTrack(group.firstTrack);
        break;
      case 'play_next':
        for (final track in group.tracks) {
          controller.addNext(track);
        }
        ToastService.show(
          context,
          group.hasMultipleParts
              ? '已添加${group.partCount}个分P到下一首'
              : '已添加到下一首',
        );
        break;
      case 'add_to_queue':
        for (final track in group.tracks) {
          controller.addToQueue(track);
        }
        ToastService.show(
          context,
          group.hasMultipleParts
              ? '已添加${group.partCount}个分P到播放队列'
              : '已添加到播放队列',
        );
        break;
      case 'download':
        final downloadService = ref.read(downloadServiceProvider);
        int addedCount = 0;
        for (final track in group.tracks) {
          final result = await downloadService.addTrackDownload(track);
          if (result != null) addedCount++;
        }
        if (context.mounted) {
          ToastService.show(
            context,
            addedCount > 0 ? '已添加 $addedCount 首到下载队列' : '歌曲已下载或已在队列中',
          );
        }
        break;
      case 'add_to_playlist':
        showAddToPlaylistDialog(context: context, tracks: group.tracks);
        break;
    }
  }
}

/// 本地搜索结果的单个歌曲项（分P展开时显示）
class _LocalTrackTile extends ConsumerWidget {
  final Track track;
  final VoidCallback onTap;
  final void Function(Track track, String action) onMenuAction;

  const _LocalTrackTile({
    required this.track,
    required this.onTap,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = currentTrack != null &&
        currentTrack.sourceId == track.sourceId &&
        currentTrack.pageNum == track.pageNum;

    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: ListTile(
        leading: isPlaying
            ? NowPlayingIndicator(
                size: 24,
                color: colorScheme.primary,
              )
            : Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  'P${track.pageNum ?? 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (track.durationMs != null)
              Text(
                DurationFormatter.formatMs(track.durationMs!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (value) => onMenuAction(track, value),
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
                    title: Text('添加到队列'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('下载'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
