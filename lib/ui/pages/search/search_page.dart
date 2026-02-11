import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../data/models/video_detail.dart';
import '../../../data/sources/base_source.dart' show SearchOrder;
import '../../../data/sources/bilibili_source.dart';
import '../../../data/sources/source_provider.dart';
import '../../../providers/search_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/now_playing_indicator.dart';
import '../../widgets/track_group/track_group.dart';
import '../../widgets/track_thumbnail.dart';
import '../../../providers/selection_provider.dart';
import '../../widgets/context_menu_region.dart';
import '../../widgets/selection_mode_app_bar.dart';

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
    final selectionState = ref.watch(searchSelectionProvider);

    // 獲取所有搜索結果用於全選
    final allTracks = [...searchState.localResults, ...searchState.mixedOnlineTracks];

    // 多選模式下的可用操作（搜索頁不支持下載和刪除）
    const availableActions = <SelectionAction>{
      SelectionAction.addToQueue,
      SelectionAction.playNext,
      SelectionAction.addToPlaylist,
    };

    return PopScope(
      canPop: !selectionState.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectionState.isSelectionMode) {
          ref.read(searchSelectionProvider.notifier).exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: selectionState.isSelectionMode
            ? SelectionModeAppBar(
                selectionProvider: searchSelectionProvider,
                allTracks: allTracks,
                availableActions: availableActions,
              )
            : AppBar(
                toolbarHeight: kToolbarHeight + 16, // 增加頂部間隔
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
            // 音源筛选（多選模式下隱藏）
            if (!selectionState.isSelectionMode)
              _buildSourceFilter(context, searchState),

            // 内容区域
            Expanded(
              child: _showHistory && searchState.query.isEmpty
                  ? _buildSearchHistory(context)
                  : _buildSearchResults(context, searchState),
            ),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：音源筛选 + 排序按钮
          SizedBox(
            height: 40,
            child: Row(
              children: [
                // 音源筛选（可滚动）
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('全部音源'),
                          selected: state.selectedSource == null && !state.isLiveSearchMode,
                          onSelected: (_) {
                            ref.read(searchProvider.notifier).setFilters(
                              clearSource: true,
                              clearLiveRoomFilter: true,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Bilibili'),
                          selected: state.selectedSource == SourceType.bilibili && !state.isLiveSearchMode,
                          onSelected: (_) {
                            ref.read(searchProvider.notifier).setFilters(
                              sourceType: SourceType.bilibili,
                              clearLiveRoomFilter: true,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('YouTube'),
                          selected: state.selectedSource == SourceType.youtube,
                          onSelected: (_) {
                            ref.read(searchProvider.notifier).setFilters(
                              sourceType: SourceType.youtube,
                              clearLiveRoomFilter: true,
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        // 分隔线
                        Container(
                          width: 1,
                          height: 24,
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 16),
                        // 直播间筛选
                        ChoiceChip(
                          label: const Text('全部直播间'),
                          selected: state.liveRoomFilter == LiveRoomFilter.all,
                          onSelected: (_) {
                            ref.read(searchProvider.notifier).setFilters(
                              sourceType: SourceType.bilibili,
                              liveRoomFilter: LiveRoomFilter.all,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('未开播'),
                          selected: state.liveRoomFilter == LiveRoomFilter.offline,
                          onSelected: (_) {
                            ref.read(searchProvider.notifier).setFilters(
                              sourceType: SourceType.bilibili,
                              liveRoomFilter: LiveRoomFilter.offline,
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('已开播'),
                          selected: state.liveRoomFilter == LiveRoomFilter.online,
                          onSelected: (_) {
                            ref.read(searchProvider.notifier).setFilters(
                              sourceType: SourceType.bilibili,
                              liveRoomFilter: LiveRoomFilter.online,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 排序按钮（仅在视频搜索模式下显示）
                if (!state.isLiveSearchMode)
                  _buildSortButton(context, state),
              ],
            ),
          ),
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
    }
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
    // 直播间搜索模式
    if (state.isLiveSearchMode) {
      return _buildLiveRoomResults(context, state);
    }

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
        // 当滚动到底部附近时自动加载更多（所有音源同时加载）
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 200) {
            if (!state.isLoading) {
              ref.read(searchProvider.notifier).loadMoreAll();
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
                final selectionState = ref.watch(searchSelectionProvider);
                final selectionNotifier = ref.read(searchSelectionProvider.notifier);
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
                        onPlayTrack: selectionState.isSelectionMode
                            ? (track) => selectionNotifier.toggleSelection(track)
                            : (track) {
                                final controller = ref.read(audioControllerProvider.notifier);
                                controller.playTemporary(track);
                              },
                        onMenuAction: _handleMenuAction,
                        isSelectionMode: selectionState.isSelectionMode,
                        isGroupFullySelected: selectionNotifier.isGroupFullySelected(group.tracks),
                        isGroupPartiallySelected: selectionNotifier.isGroupPartiallySelected(group.tracks),
                        onLongPress: selectionState.isSelectionMode
                            ? () => selectionNotifier.toggleGroupSelection(group.tracks)
                            : () => selectionNotifier.enterSelectionModeWithTracks(group.tracks),
                        isTrackSelected: (track) => selectionState.isSelected(track),
                        onTrackLongPress: (track) => selectionNotifier.toggleSelection(track),
                      );
                    },
                    childCount: groupedLocalResults.length,
                  ),
                );
              },
            ),
          ],

          // 在线结果（混合显示）
          if (state.mixedOnlineTracks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '在线结果 (${state.mixedOnlineTracks.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            Builder(
              builder: (context) {
                final selectionState = ref.watch(searchSelectionProvider);
                final selectionNotifier = ref.read(searchSelectionProvider.notifier);
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = state.mixedOnlineTracks[index];
                      return _SearchResultTile(
                        track: track,
                        isLocal: false,
                        isExpanded: _expandedVideos.contains(track.sourceId),
                        isLoading: _loadingPages.contains(track.sourceId),
                        pages: _loadedPages[track.sourceId],
                        onTap: selectionState.isSelectionMode
                            ? () => selectionNotifier.toggleSelection(track)
                            : () => _playVideo(track),
                        onLongPress: selectionState.isSelectionMode
                            ? null
                            : () => selectionNotifier.enterSelectionMode(track),
                        onToggleExpand: () => _toggleExpanded(track.sourceId),
                        onMenuAction: _handleMenuAction,
                        onPageMenuAction: (page, action) => _handlePageMenuAction(track, page, action),
                        isSelectionMode: selectionState.isSelectionMode,
                        isSelected: selectionState.isSelected(track),
                      );
                    },
                    childCount: state.mixedOnlineTracks.length,
                  ),
                );
              },
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
    // 直播间搜索模式
    if (state.isLiveSearchMode) {
      return state.hasMoreLiveRooms;
    }
    // 视频搜索模式
    for (final entry in state.onlineResults.entries) {
      if (entry.value.hasMore) return true;
    }
    return false;
  }

  /// 构建直播间搜索结果
  Widget _buildLiveRoomResults(BuildContext context, SearchState state) {
    final rooms = state.liveRoomResults?.rooms ?? [];

    if (state.isLoading && rooms.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && rooms.isEmpty) {
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

    if (rooms.isEmpty && !state.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.live_tv_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '未找到 "${state.query}" 相关直播间',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          final metrics = notification.metrics;
          if (metrics.pixels >= metrics.maxScrollExtent - 200) {
            if (!state.isLoading && state.hasMoreLiveRooms) {
              ref.read(searchProvider.notifier).loadMoreLiveRooms();
            }
          }
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          // 直播间结果标题
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '直播间 (${state.liveRoomResults?.totalCount ?? rooms.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),

          // 直播间列表
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final room = rooms[index];
                return _LiveRoomTile(
                  room: room,
                  onTap: () => _openLiveRoom(room),
                  onMenuAction: _onLiveRoomMenuAction,
                );
              },
              childCount: rooms.length,
            ),
          ),

          // 加载更多指示器
          if (state.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          // 已加载全部
          if (!state.isLoading && rooms.isNotEmpty && !state.hasMoreLiveRooms)
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
        ],
      ),
    );
  }

  /// 打开直播间
  Future<void> _openLiveRoom(LiveRoom room) async {
    if (!room.isLive) {
      if (mounted) ToastService.show(context, '主播未开播');
      return;
    }

    // 转换为 RadioStation 并使用 RadioController 播放
    final station = room.toRadioStation();
    await ref.read(radioControllerProvider.notifier).play(station);
  }

  /// 直播间菜单操作
  Future<void> _onLiveRoomMenuAction(LiveRoom room, String action) async {
    switch (action) {
      case 'play':
        await _openLiveRoom(room);
        break;
      case 'add_to_radio':
        await _addLiveRoomToRadio(room);
        break;
    }
  }

  /// 添加直播间到电台列表
  Future<void> _addLiveRoomToRadio(LiveRoom room) async {
    try {
      final url = 'https://live.bilibili.com/${room.roomId}';
      await ref.read(radioControllerProvider.notifier).addStation(url);
      if (mounted) ToastService.show(context, '已添加到电台');
    } catch (e) {
      if (mounted) ToastService.show(context, e.toString());
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
          bool anyAdded = false;
          for (final page in pages) {
            final added = await controller.addNext(page.toTrack(track));
            if (added) anyAdded = true;
          }
          if (anyAdded && mounted) {
            ToastService.show(context, '已添加${pages.length}个分P到下一首');
          }
        } else {
          final added = await controller.addNext(track);
          if (added && mounted) {
            ToastService.show(context, '已添加到下一首');
          }
        }
        break;
      case 'add_to_queue':
        if (hasMultiplePages) {
          // 多P视频：添加所有分P
          bool anyAdded = false;
          for (final page in pages) {
            final added = await controller.addToQueue(page.toTrack(track));
            if (added) anyAdded = true;
          }
          if (anyAdded && mounted) {
            ToastService.show(context, '已添加${pages.length}个分P到播放队列');
          }
        } else {
          final added = await controller.addToQueue(track);
          if (added && mounted) {
            ToastService.show(context, '已添加到播放队列');
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
        final added = await controller.addNext(pageTrack);
        if (added && mounted) {
          ToastService.show(context, '已添加到下一首');
        }
        break;
      case 'add_to_queue':
        final added = await controller.addToQueue(pageTrack);
        if (added && mounted) {
          ToastService.show(context, '已添加到播放队列');
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
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;

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
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
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
        ContextMenuRegion(
          menuBuilder: (_) => _buildMenuItems(),
          onSelected: (value) => onMenuAction(track, value),
          child: ListTile(
          leading: TrackThumbnail(
            track: track,
            size: 48,
            borderRadius: 4,
            isPlaying: shouldHighlight,
          ),
          onLongPress: onLongPress,
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
              // 音源标识（播放数右边）
              const SizedBox(width: 8),
              _SourceBadge(sourceType: track.sourceType),
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
                SizedBox(
                  width: 48,
                  child: Text(
                    DurationFormatter.formatMs(track.durationMs!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                    textAlign: TextAlign.center,
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
              else if (hasMultiplePages && !isSelectionMode)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: onToggleExpand,
                ),
              if (isSelectionMode)
                _SelectionCheckbox(
                  isSelected: isSelected,
                  onTap: onLongPress,
                )
              else
                PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) => onMenuAction(track, value),
                itemBuilder: (_) => _buildMenuItems(),
              ),
            ],
          ),
          onTap: onTap,
        ),
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

  List<PopupMenuEntry<String>> _buildMenuItems() => const [
    PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'play_next', child: ListTile(leading: Icon(Icons.queue_play_next), title: Text('下一首播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'add_to_queue', child: ListTile(leading: Icon(Icons.add_to_queue), title: Text('添加到队列'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'add_to_playlist', child: ListTile(leading: Icon(Icons.playlist_add), title: Text('添加到歌单'), contentPadding: EdgeInsets.zero)),
  ];

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

    return ContextMenuRegion(
      menuBuilder: (_) => _buildMenuItems(),
      onSelected: onMenuAction,
      child: Padding(
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
                itemBuilder: (_) => _buildMenuItems(),
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() => const [
    PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'play_next', child: ListTile(leading: Icon(Icons.queue_play_next), title: Text('下一首播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'add_to_queue', child: ListTile(leading: Icon(Icons.add_to_queue), title: Text('添加到队列'), contentPadding: EdgeInsets.zero)),
    // 注意：分P没有"添加到歌单"选项
  ];
}

/// 本地搜索结果分组组件
class _LocalGroupTile extends ConsumerWidget {
  final TrackGroup group;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final void Function(Track track) onPlayTrack;
  final void Function(Track track, String action) onMenuAction;
  final bool isSelectionMode;
  final bool isGroupFullySelected;
  final bool isGroupPartiallySelected;
  final VoidCallback? onLongPress;
  final bool Function(Track track)? isTrackSelected;
  final void Function(Track track)? onTrackLongPress;

  const _LocalGroupTile({
    required this.group,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onPlayTrack,
    required this.onMenuAction,
    this.isSelectionMode = false,
    this.isGroupFullySelected = false,
    this.isGroupPartiallySelected = false,
    this.onLongPress,
    this.isTrackSelected,
    this.onTrackLongPress,
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
        ContextMenuRegion(
          menuBuilder: (_) => _buildMenuItems(),
          onSelected: (value) => _handleMenuAction(context, ref, value),
          child: ListTile(
          leading: TrackThumbnail(
            track: firstTrack,
            size: 48,
            borderRadius: 4,
            isPlaying: isPlayingThisGroup,
          ),
          onLongPress: onLongPress,
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
              // 展开/折叠按钮 - 与音乐库页面对齐
              if (hasMultipleParts && !isSelectionMode)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: onToggleExpand,
                ),
              // 菜单
              if (isSelectionMode)
                _SelectionGroupCheckbox(
                  isFullySelected: isGroupFullySelected,
                  isPartiallySelected: isGroupPartiallySelected,
                  onTap: onLongPress,
                )
              else
                PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) => _handleMenuAction(context, ref, value),
                itemBuilder: (_) => _buildMenuItems(),
              ),
            ],
          ),
          onTap: () => onPlayTrack(firstTrack),
        ),
        ),

        // 展开的分P列表
        if (isExpanded && hasMultipleParts)
          ...group.tracks.map((track) => _LocalTrackTile(
                track: track,
                onTap: () => onPlayTrack(track),
                onMenuAction: onMenuAction,
                isSelectionMode: isSelectionMode,
                isSelected: isTrackSelected?.call(track) ?? false,
                onLongPress: onTrackLongPress != null
                    ? () => onTrackLongPress!(track)
                    : null,
              )),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() => const [
    PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'play_next', child: ListTile(leading: Icon(Icons.queue_play_next), title: Text('下一首播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'add_to_queue', child: ListTile(leading: Icon(Icons.add_to_queue), title: Text('添加到队列'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'add_to_playlist', child: ListTile(leading: Icon(Icons.playlist_add), title: Text('添加到歌单'), contentPadding: EdgeInsets.zero)),
  ];

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);

    switch (action) {
      case 'play':
        onPlayTrack(group.firstTrack);
        break;
      case 'play_next':
        bool anyAdded = false;
        for (final track in group.tracks) {
          final added = await controller.addNext(track);
          if (added) anyAdded = true;
        }
        if (anyAdded && context.mounted) {
          ToastService.show(
            context,
            group.hasMultipleParts
                ? '已添加${group.partCount}个分P到下一首'
                : '已添加到下一首',
          );
        }
        break;
      case 'add_to_queue':
        bool anyAdded = false;
        for (final track in group.tracks) {
          final added = await controller.addToQueue(track);
          if (added) anyAdded = true;
        }
        if (anyAdded && context.mounted) {
          ToastService.show(
            context,
            group.hasMultipleParts
                ? '已添加${group.partCount}个分P到播放队列'
                : '已添加到播放队列',
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
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;

  const _LocalTrackTile({
    required this.track,
    required this.onTap,
    required this.onMenuAction,
    this.isSelectionMode = false,
    this.isSelected = false,
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
      onSelected: (value) => onMenuAction(track, value),
      child: Padding(
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
        onLongPress: onLongPress,
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
              SizedBox(
                width: 48, // 与 IconButton 宽度对齐
                child: Text(
                  DurationFormatter.formatMs(track.durationMs!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (isSelectionMode)
              _SelectionCheckbox(
                isSelected: isSelected,
                onTap: onLongPress,
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) => onMenuAction(track, value),
                itemBuilder: (_) => _buildMenuItems(),
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() => const [
    PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'play_next', child: ListTile(leading: Icon(Icons.queue_play_next), title: Text('下一首播放'), contentPadding: EdgeInsets.zero)),
    PopupMenuItem(value: 'add_to_queue', child: ListTile(leading: Icon(Icons.add_to_queue), title: Text('添加到队列'), contentPadding: EdgeInsets.zero)),
  ];
}

/// 音源标识徽章
class _SourceBadge extends StatelessWidget {
  final SourceType sourceType;

  const _SourceBadge({required this.sourceType});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (sourceType) {
      SourceType.bilibili => SimpleIcons.bilibili,
      SourceType.youtube => SimpleIcons.youtube,
    };

    return Icon(
      icon,
      size: 14,
      color: colorScheme.outline,
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

/// 組選擇勾選框（支持部分選擇狀態）
class _SelectionGroupCheckbox extends StatelessWidget {
  final bool isFullySelected;
  final bool isPartiallySelected;
  final VoidCallback? onTap;

  const _SelectionGroupCheckbox({
    required this.isFullySelected,
    required this.isPartiallySelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final IconData icon;
    final Color color;

    if (isFullySelected) {
      icon = Icons.check_circle;
      color = colorScheme.primary;
    } else if (isPartiallySelected) {
      icon = Icons.remove_circle_outline;
      color = colorScheme.primary;
    } else {
      icon = Icons.radio_button_unchecked;
      color = colorScheme.outline;
    }

    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onTap,
    );
  }
}

/// 直播间列表项
class _LiveRoomTile extends StatelessWidget {
  final LiveRoom room;
  final VoidCallback onTap;
  final void Function(LiveRoom room, String action) onMenuAction;

  const _LiveRoomTile({
    required this.room,
    required this.onTap,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ContextMenuRegion(
      menuBuilder: (_) => _buildMenuItems(colorScheme),
      onSelected: (value) => onMenuAction(room, value),
      child: ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 封面图
              ColorFiltered(
                colorFilter: room.isLive
                    ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                    : const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0, 0, 0, 1, 0,
                      ]),
                child: ImageLoadingService.loadImage(
                  networkUrl: room.cover?.isNotEmpty == true
                      ? room.cover
                      : room.face,
                  placeholder: ImagePlaceholder(
                    icon: Icons.live_tv,
                    size: 48,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    iconColor: colorScheme.outline,
                  ),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),

            ],
          ),
        ),
      ),
      title: Text(
        room.title.isNotEmpty ? room.title : '${room.uname}的直播间',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: room.isLive ? null : colorScheme.outline,
        ),
      ),
      subtitle: Row(
        children: [
          // 主播名
          Flexible(
            child: Text(
              room.uname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 在线人数
          if (room.isLive && (room.online ?? 0) > 0) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.visibility,
              size: 14,
              color: colorScheme.outline,
            ),
            const SizedBox(width: 2),
            Text(
              _formatOnlineCount(room.online!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
          ],
          // 分区标签
          if (room.areaName?.isNotEmpty ?? false) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: room.isLive ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                room.areaName!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: room.isLive ? colorScheme.onPrimaryContainer : colorScheme.outline,
                    ),
              ),
            ),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) => onMenuAction(room, value),
        itemBuilder: (_) => _buildMenuItems(colorScheme),
      ),
      onTap: onTap,
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(ColorScheme colorScheme) => [
    PopupMenuItem(
      value: 'play',
      enabled: room.isLive,
      child: ListTile(
        leading: Icon(Icons.play_arrow, color: room.isLive ? null : colorScheme.outline),
        title: Text('播放', style: TextStyle(color: room.isLive ? null : colorScheme.outline)),
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuItem(
      value: 'add_to_radio',
      child: ListTile(leading: Icon(Icons.radio), title: Text('添加到电台'), contentPadding: EdgeInsets.zero),
    ),
  ];

  String _formatOnlineCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }
}
