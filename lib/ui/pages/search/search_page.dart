import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/ui_constants.dart';
import '../../../core/utils/number_format_utils.dart';
import '../../../i18n/strings.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../data/models/track.dart';
import '../../../data/models/video_detail.dart';
import '../../../data/sources/base_source.dart' show SearchOrder;
import '../../../providers/account/account_provider.dart';
import '../../../providers/search/search_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/radio/radio_controller.dart';
import '../../widgets/dialogs/add_to_playlist_dialog.dart';
import '../../widgets/dialogs/add_to_remote_playlist_dialog.dart';
import '../lyrics/lyrics_search_sheet.dart';
import '../../widgets/feedback/error_display.dart';
import '../../widgets/indicators/now_playing_indicator.dart';
import '../../widgets/indicators/source_badge.dart';
import '../../widgets/images/radio_cover_image.dart';
import '../../widgets/track_group/track_group.dart';
import '../../widgets/images/track_thumbnail.dart';
import '../../widgets/indicators/vip_badge.dart';
import '../../../providers/ui/selection_provider.dart';
import '../../widgets/menus/context_menu_region.dart';
import '../../widgets/app_bars/selection_mode_app_bar.dart';
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_handler.dart';
import '../../handlers/track_action_menu.dart';

/// 搜索页
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  // 分P展开状态管理
  final Set<String> _expandedVideos = {};
  final Map<String, List<VideoPage>> _loadedPages = {};
  final Set<String> _loadingPages = {};

  @override
  void initState() {
    super.initState();
    // Restore search text from provider state after tab switching
    final query = ref.read(searchProvider).query;
    if (query.isNotEmpty) {
      _searchController.text = query;
    }
    _searchController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // 触发 rebuild 以更新 close 按钮的显示状态
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.removeListener(_onTextChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final isSelectionMode = ref.watch(
      searchSelectionProvider.select((state) => state.isSelectionMode),
    );

    // 獲取所有搜索結果用於全選
    final allTracks = isSelectionMode
        ? [
            ...searchState.localResults,
            ...searchState.mixedOnlineTracks,
          ]
        : const <Track>[];

    // 多選模式下的可用操作（搜索頁不支持下載和刪除）
    const availableActions = <String>{
      selectionActionAddToQueue,
      selectionActionPlayNext,
      selectionActionAddToPlaylist,
      selectionActionAddToRemotePlaylist,
    };

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isSelectionMode) {
          ref.read(searchSelectionProvider.notifier).exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: isSelectionMode
            ? SelectionModeAppBar(
                selectionProvider: searchSelectionProvider,
                allTracks: allTracks,
                availableActions: availableActions,
              )
            : AppBar(
                toolbarHeight: kToolbarHeight + 16, // 增加頂部間隔
                centerTitle: false,
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
                  const SizedBox(width: 8),
                ],
              ),
        body: Column(
          children: [
            // 音源筛选（多選模式下隱藏）
            if (!isSelectionMode) _buildSourceFilter(context, searchState),

            // 内容区域
            Expanded(
              child: searchState.query.isEmpty
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
      decoration: InputDecoration(
        hintText: t.searchPage.hint,
        border: InputBorder.none,
        prefixIcon: const Icon(Icons.search),
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
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(t.searchPage.source.all),
                            selected: state.selectedSource == null &&
                                !state.isLiveSearchMode,
                            onSelected: (_) {
                              ref.read(searchProvider.notifier).setFilters(
                                    clearSource: true,
                                    clearLiveRoomFilter: true,
                                  );
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(t.importPlatform.bilibili),
                            selected:
                                state.selectedSource == SourceType.bilibili &&
                                    !state.isLiveSearchMode,
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
                            selected:
                                state.selectedSource == SourceType.youtube,
                            onSelected: (_) {
                              ref.read(searchProvider.notifier).setFilters(
                                    sourceType: SourceType.youtube,
                                    clearLiveRoomFilter: true,
                                  );
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(t.importPlatform.netease),
                            selected:
                                state.selectedSource == SourceType.netease,
                            onSelected: (_) {
                              ref.read(searchProvider.notifier).setFilters(
                                    sourceType: SourceType.netease,
                                    clearLiveRoomFilter: true,
                                  );
                            },
                          ),
                          const SizedBox(width: 16),
                          // 分隔线
                          Container(
                            width: 1,
                            height: 24,
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withValues(alpha: 0.3),
                          ),
                          const SizedBox(width: 16),
                          // 直播间筛选
                          ChoiceChip(
                            label: Text(t.searchPage.liveRoom.all),
                            selected:
                                state.liveRoomFilter == LiveRoomFilter.all,
                            onSelected: (_) {
                              ref.read(searchProvider.notifier).setFilters(
                                    sourceType: SourceType.bilibili,
                                    liveRoomFilter: LiveRoomFilter.all,
                                  );
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(t.searchPage.liveRoom.online),
                            selected:
                                state.liveRoomFilter == LiveRoomFilter.online,
                            onSelected: (_) {
                              ref.read(searchProvider.notifier).setFilters(
                                    sourceType: SourceType.bilibili,
                                    liveRoomFilter: LiveRoomFilter.online,
                                  );
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(t.searchPage.liveRoom.offline),
                            selected:
                                state.liveRoomFilter == LiveRoomFilter.offline,
                            onSelected: (_) {
                              ref.read(searchProvider.notifier).setFilters(
                                    sourceType: SourceType.bilibili,
                                    liveRoomFilter: LiveRoomFilter.offline,
                                  );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 排序按钮（仅在视频搜索模式下显示）
                if (!state.isLiveSearchMode) _buildSortButton(context, state),
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
        PopupMenuItem(
          value: SearchOrder.relevance,
          child: Text(t.searchPage.sort.relevance),
        ),
        PopupMenuItem(
          value: SearchOrder.playCount,
          child: Text(t.searchPage.sort.playCount),
        ),
        PopupMenuItem(
          value: SearchOrder.publishDate,
          child: Text(t.searchPage.sort.publishDate),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: AppRadius.borderRadiusXl,
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
        return t.searchPage.sort.relevanceShort;
      case SearchOrder.playCount:
        return t.searchPage.sort.playCountShort;
      case SearchOrder.publishDate:
        return t.searchPage.sort.publishDateShort;
    }
  }

  Widget _buildSearchHistory(BuildContext context) {
    final history = ref.watch(searchHistoryManagerProvider);

    if (history.isEmpty) {
      return ErrorDisplay.empty(
        icon: Icons.search,
        message: t.searchPage.searchMusic,
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
                t.searchPage.history,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(searchHistoryManagerProvider.notifier).clearAll();
                },
                child: Text(t.searchPage.clear),
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

    final mixedOnlineTracks = state.mixedOnlineTracks;

    if (state.isLoading && state.allOnlineTracks.isEmpty) {
      return const LoadingPlaceholder();
    }

    if (state.error != null && state.allOnlineTracks.isEmpty) {
      return ErrorDisplay(
        type: ErrorType.general,
        message: state.error!,
        onRetry: () => _performSearch(state.query),
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
                  t.searchPage.section
                      .inPlaylist(count: state.localResults.length),
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
                final groupedLocalResults =
                    groupTracks(uniqueTracks.values.toList());
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final group = groupedLocalResults[index];
                      return _LocalGroupTile(
                        key: ValueKey('local-group-${group.groupKey}'),
                        group: group,
                        isExpanded: _expandedVideos.contains(group.groupKey),
                        onToggleExpand: () => _toggleExpanded(group.groupKey),
                        onPlayTrack: (track) {
                          final controller =
                              ref.read(audioControllerProvider.notifier);
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

          // 在线结果（混合显示）
          if (mixedOnlineTracks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  t.searchPage.section
                      .onlineResults(count: mixedOnlineTracks.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            Builder(
              builder: (context) {
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = mixedOnlineTracks[index];
                      return Consumer(
                        builder: (context, ref, child) {
                          final selection = ref.watch(
                            searchSelectionProvider.select(
                              (state) => (
                                isSelectionMode: state.isSelectionMode,
                                isSelected: state.isSelected(track),
                              ),
                            ),
                          );
                          final selectionNotifier =
                              ref.read(searchSelectionProvider.notifier);
                          return _SearchResultTile(
                            key: ValueKey(
                                '${track.groupKey}:${track.pageNum ?? 1}'),
                            track: track,
                            isLocal: false,
                            isExpanded:
                                _expandedVideos.contains(track.sourceId),
                            isLoading: _loadingPages.contains(track.sourceId),
                            pages: _loadedPages[track.sourceId],
                            onTap: selection.isSelectionMode
                                ? () => selectionNotifier.toggleSelection(track)
                                : () => _playVideo(track),
                            onLongPress: selection.isSelectionMode
                                ? null
                                : () =>
                                    selectionNotifier.enterSelectionMode(track),
                            onToggleExpand: () =>
                                _toggleExpanded(track.sourceId),
                            onMenuAction: _handleMenuAction,
                            onPageMenuAction: (page, action) =>
                                _handlePageMenuAction(track, page, action),
                            isSelectionMode: selection.isSelectionMode,
                            isSelected: selection.isSelected,
                          );
                        },
                      );
                    },
                    childCount: mixedOnlineTracks.length,
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
                    t.searchPage.allLoaded,
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
              child: ErrorDisplay.notFound(
                message: t.searchPage.noResults(query: state.query),
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
      return const LoadingPlaceholder();
    }

    if (state.error != null && rooms.isEmpty) {
      return ErrorDisplay(
        type: ErrorType.general,
        message: state.error!,
        onRetry: () => _performSearch(state.query),
      );
    }

    if (rooms.isEmpty && !state.isLoading) {
      return ErrorDisplay.empty(
        icon: Icons.live_tv_outlined,
        message: t.searchPage.noLiveRooms(query: state.query),
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
                t.searchPage.liveRoom.title(
                    count: state.liveRoomResults?.totalCount ?? rooms.length),
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
                  key: ValueKey('live-room-${room.roomId}'),
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
                    t.searchPage.allLoaded,
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
      if (mounted) ToastService.warning(context, t.searchPage.liveRoom.notLive);
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
      if (mounted) {
        ToastService.success(context, t.searchPage.toast.addedToRadio);
      }
    } catch (e) {
      if (mounted) ToastService.error(context, e.toString());
    }
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();
    // 清空之前的分P缓存
    _expandedVideos.clear();
    _loadedPages.clear();
    _loadingPages.clear();
    ref.read(searchProvider.notifier).search(query).then((_) {
      if (mounted) {
        ref.read(searchHistoryManagerProvider.notifier).loadHistory();
      }
    });
  }

  /// 加载视频分P信息
  Future<void> _loadVideoPages(Track track) async {
    final key = track.sourceId;
    if (_loadedPages.containsKey(key) || _loadingPages.contains(key)) {
      return;
    }

    setState(() {
      _loadingPages.add(key);
    });

    try {
      final pages =
          await ref.read(searchProvider.notifier).loadVideoPagesForTrack(track);

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
        ToastService.error(context, e.toString());
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
    // 确保有分P信息
    if (!_loadedPages.containsKey(track.sourceId)) {
      await _loadVideoPages(track);
    }

    final pages = _loadedPages[track.sourceId];
    final hasMultiplePages = pages != null && pages.length > 1;

    if (hasMultiplePages) {
      switch (action) {
        case playTrackActionId:
          _playVideo(track);
          return;
        case playNextTrackActionId:
        case addToQueueTrackActionId:
        case addToPlaylistTrackActionId:
        case addToRemoteTrackActionId:
          final pageTracks = pages.map((p) => p.toTrack(track)).toList();
          if (mounted) {
            await TrackActionCoordinator.handleMulti(
              context: context,
              ref: ref,
              tracks: pageTracks,
              actionId: action,
            );
          }
          return;
        case matchLyricsTrackActionId:
          if (mounted) {
            showLyricsSearchSheet(context: context, track: track);
          }
          return;
      }
    }

    if (!mounted) return;
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
  }

  void _handlePageMenuAction(
      Track parentTrack, VideoPage page, String action) async {
    final pageTrack = page.toTrack(parentTrack);

    if (!mounted) return;
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: pageTrack,
      actionId: action,
    );
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
    super.key,
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
    final isPlayingThisVideo =
        currentTrack != null && currentTrack.sourceId == track.sourceId;
    // 检查是否正在播放这个具体的 track（单P视频或第一个分P）
    final isPlaying =
        isPlayingThisVideo && currentTrack.pageNum == track.pageNum;
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
              size: AppSizes.thumbnailMedium,
              borderRadius: 4,
              isPlaying: shouldHighlight,
            ),
            onLongPress: onLongPress,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: shouldHighlight ? colorScheme.primary : null,
                      fontWeight: shouldHighlight ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (track.isVip) ...[
                  const SizedBox(width: 4),
                  const VipBadge(),
                ],
              ],
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
                // 音源标识（播放数右边）
                const SizedBox(width: 8),
                SourceBadge(sourceType: track.sourceType),
                if (hasMultiplePages) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: AppRadius.borderRadiusSm,
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
                key: ValueKey(
                  'page-${track.sourceType.name}:${track.sourceId}:${page.page}',
                ),
                page: page,
                parentTrack: track,
                onTap: () => onPageMenuAction(page, 'play'),
                onMenuAction: (action) => onPageMenuAction(page, action),
              )),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
    );
  }
}

/// 分P列表项
class _PageTile extends ConsumerWidget {
  final VideoPage page;
  final Track parentTrack;
  final VoidCallback onTap;
  final void Function(String action) onMenuAction;

  const _PageTile({
    super.key,
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
                    borderRadius: AppRadius.borderRadiusSm,
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

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
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
    super.key,
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
    final groupKeys = group.tracks
        .map((track) => SelectionKey.fromTrack(track))
        .toList(growable: false);
    final selection = ref.watch(
      searchSelectionProvider.select((state) {
        final selectedCount =
            groupKeys.where(state.selectedKeys.contains).length;
        return (
          isSelectionMode: state.isSelectionMode,
          selectedKeys: state.selectedKeys,
          isGroupFullySelected:
              groupKeys.isNotEmpty && selectedCount == groupKeys.length,
          isGroupPartiallySelected:
              selectedCount > 0 && selectedCount < groupKeys.length,
        );
      }),
    );
    final selectionNotifier = ref.read(searchSelectionProvider.notifier);
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
            onLongPress: selection.isSelectionMode
                ? null
                : () => selectionNotifier
                    .enterSelectionModeWithTracks(group.tracks),
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
                    firstTrack.artist ?? t.general.unknownArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasMultipleParts) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: AppRadius.borderRadiusSm,
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
                if (hasMultipleParts && !selection.isSelectionMode)
                  IconButton(
                    icon: Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    onPressed: onToggleExpand,
                  ),
                // 菜单
                if (selection.isSelectionMode)
                  _SelectionGroupCheckbox(
                    isFullySelected: selection.isGroupFullySelected,
                    isPartiallySelected: selection.isGroupPartiallySelected,
                    onTap: () =>
                        selectionNotifier.toggleGroupSelection(group.tracks),
                  )
                else
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) =>
                        _handleMenuAction(context, ref, value),
                    itemBuilder: (_) => _buildMenuItems(),
                  ),
              ],
            ),
            onTap: selection.isSelectionMode
                ? () => selectionNotifier.toggleGroupSelection(group.tracks)
                : () => onPlayTrack(firstTrack),
          ),
        ),

        // 展开的分P列表
        if (isExpanded && hasMultipleParts)
          ...group.tracks.map((track) => _LocalTrackTile(
                key: ValueKey('${track.groupKey}:${track.pageNum ?? 1}'),
                track: track,
                onTap: selection.isSelectionMode
                    ? () => selectionNotifier.toggleSelection(track)
                    : () => onPlayTrack(track),
                onMenuAction: onMenuAction,
                isSelectionMode: selection.isSelectionMode,
                isSelected: selection.selectedKeys
                    .contains(SelectionKey.fromTrack(track)),
                onLongPress: () => selectionNotifier.toggleSelection(track),
              )),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(
        translations: t,
        options: const TrackActionMenuOptions(
          includeMatchLyrics: false,
        ),
      ),
    );
  }

  void _handleMenuAction(
      BuildContext context, WidgetRef ref, String action) async {
    final controller = ref.read(audioControllerProvider.notifier);

    switch (action) {
      case playTrackActionId:
        onPlayTrack(group.firstTrack);
        break;
      case playNextTrackActionId:
        bool anyAdded = false;
        for (final track in group.tracks) {
          final added = await controller.addNext(track);
          if (added) anyAdded = true;
        }
        if (anyAdded && context.mounted) {
          ToastService.success(
            context,
            group.hasMultipleParts
                ? t.searchPage.toast.addedPartsToNext(count: group.partCount)
                : t.general.addedToNext,
          );
        }
        break;
      case addToQueueTrackActionId:
        bool anyAdded = false;
        for (final track in group.tracks) {
          final added = await controller.addToQueue(track);
          if (added) anyAdded = true;
        }
        if (anyAdded && context.mounted) {
          ToastService.success(
            context,
            group.hasMultipleParts
                ? t.searchPage.toast.addedPartsToQueue(count: group.partCount)
                : t.general.addedToQueue,
          );
        }
        break;

      case addToPlaylistTrackActionId:
        showAddToPlaylistDialog(context: context, tracks: group.tracks);
        break;
      case addToRemoteTrackActionId:
        final isLoggedIn =
            ref.read(isLoggedInProvider(group.firstTrack.sourceType));
        if (!isLoggedIn) {
          if (context.mounted) {
            ToastService.show(context, t.remote.pleaseLogin);
          }
          return;
        }
        if (context.mounted) {
          showAddToRemotePlaylistDialog(
              context: context, track: group.firstTrack);
        }
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
    super.key,
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
                    borderRadius: AppRadius.borderRadiusSm,
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

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
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
    super.key,
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
          borderRadius: AppRadius.borderRadiusSm,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 封面图
                ColorFiltered(
                  colorFilter: room.isLive
                      ? const ColorFilter.mode(
                          Colors.transparent, BlendMode.multiply)
                      : kGrayscaleColorFilter,
                  child: RadioCoverImage(
                    networkUrl:
                        room.cover?.isNotEmpty == true ? room.cover : room.face,
                    placeholder: ImagePlaceholder(
                      icon: Icons.live_tv,
                      size: 48,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      iconColor: colorScheme.outline,
                    ),
                    width: 48,
                    height: 48,
                    variant: RadioCoverVariant.compact,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ),
          ),
        ),
        title: Text(
          room.title.isNotEmpty
              ? room.title
              : t.searchPage.liveRoom.userRoom(user: room.uname),
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
                  color: room.isLive
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Text(
                  room.areaName!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: room.isLive
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.outline,
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
            leading: Icon(Icons.play_arrow,
                color: room.isLive ? null : colorScheme.outline),
            title: Text(t.general.play,
                style:
                    TextStyle(color: room.isLive ? null : colorScheme.outline)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'add_to_radio',
          child: ListTile(
              leading: const Icon(Icons.radio),
              title: Text(t.searchPage.menu.addToRadio),
              contentPadding: EdgeInsets.zero),
        ),
      ];

  String _formatOnlineCount(int count) => formatCount(count);
}
