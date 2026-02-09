import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../data/models/live_room.dart';
import '../data/models/track.dart';
export '../data/models/track.dart' show SourceType;
export '../data/models/live_room.dart' show LiveRoomFilter, LiveRoom, LiveSearchResult;
import '../data/models/search_history.dart';
import '../data/sources/base_source.dart';
import '../data/sources/bilibili_source.dart';
import '../data/sources/source_provider.dart' show sourceManagerProvider, bilibiliSourceProvider;
import '../services/search/search_service.dart';
import 'database_provider.dart';
import 'repository_providers.dart';

/// SearchService Provider
final searchServiceProvider = Provider<SearchService>((ref) {
  final sourceManager = ref.watch(sourceManagerProvider);
  final trackRepo = ref.watch(trackRepositoryProvider);
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  return SearchService(
    sourceManager: sourceManager,
    trackRepository: trackRepo,
    isar: db,
  );
});

/// 搜索状态
class SearchState extends Equatable {
  final String query;
  final List<Track> localResults;
  final Map<SourceType, SearchResult> onlineResults;
  final bool isLoading;
  final String? error;
  final SourceType? selectedSource; // null = 全部音源
  final Map<SourceType, int> currentPages;
  final SearchOrder searchOrder;
  // 直播间搜索相关
  final LiveRoomFilter? liveRoomFilter; // null = 视频搜索模式, 非null = 直播间搜索模式
  final LiveSearchResult? liveRoomResults;
  final int liveRoomPage;

  const SearchState({
    this.query = '',
    this.localResults = const [],
    this.onlineResults = const {},
    this.isLoading = false,
    this.error,
    this.selectedSource, // null = 全部音源
    this.currentPages = const {},
    this.searchOrder = SearchOrder.relevance,
    this.liveRoomFilter,
    this.liveRoomResults,
    this.liveRoomPage = 1,
  });

  /// 是否为直播间搜索模式
  bool get isLiveSearchMode => liveRoomFilter != null;

  /// 获取启用的音源列表
  Set<SourceType> get enabledSources => selectedSource == null
      ? const {SourceType.bilibili, SourceType.youtube}
      : {selectedSource!};

  /// 获取所有在线结果（未排序）
  List<Track> get allOnlineTracks {
    final tracks = <Track>[];
    for (final result in onlineResults.values) {
      tracks.addAll(result.tracks);
    }
    return tracks;
  }

  /// 获取混合排序后的在线结果
  /// - 综合排序：交替显示不同音源
  /// - 播放量排序：按播放数降序
  /// - 发布时间：保持原顺序（各音源已按发布时间排序）
  List<Track> get mixedOnlineTracks {
    if (onlineResults.isEmpty) return [];

    switch (searchOrder) {
      case SearchOrder.relevance:
        // 交替排序：轮流从各音源取一个
        return _interleaveResults();
      case SearchOrder.playCount:
        // 按播放量降序
        final tracks = allOnlineTracks;
        tracks.sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));
        return tracks;
      case SearchOrder.publishDate:
        // 发布时间排序：交替显示（各音源已按时间排序）
        return _interleaveResults();
    }
  }

  /// 交替排序：轮流从各音源取结果
  List<Track> _interleaveResults() {
    final sourceTypes = onlineResults.keys.toList();
    if (sourceTypes.isEmpty) return [];
    if (sourceTypes.length == 1) {
      return onlineResults[sourceTypes.first]?.tracks ?? [];
    }

    final result = <Track>[];
    final iterators = <SourceType, int>{};
    for (final type in sourceTypes) {
      iterators[type] = 0;
    }

    // 轮流从各音源取结果
    bool hasMore = true;
    while (hasMore) {
      hasMore = false;
      for (final type in sourceTypes) {
        final tracks = onlineResults[type]?.tracks ?? [];
        final index = iterators[type]!;
        if (index < tracks.length) {
          result.add(tracks[index]);
          iterators[type] = index + 1;
          hasMore = true;
        }
      }
    }
    return result;
  }

  /// 是否有结果
  bool get hasResults => localResults.isNotEmpty || allOnlineTracks.isNotEmpty || (liveRoomResults?.rooms.isNotEmpty ?? false);

  /// 是否有更多直播间结果
  bool get hasMoreLiveRooms => liveRoomResults?.hasMore ?? false;

  /// 是否有更多结果
  bool hasMoreFor(SourceType sourceType) {
    return onlineResults[sourceType]?.hasMore ?? false;
  }

  SearchState copyWith({
    String? query,
    List<Track>? localResults,
    Map<SourceType, SearchResult>? onlineResults,
    bool? isLoading,
    String? error,
    SourceType? selectedSource,
    Map<SourceType, int>? currentPages,
    SearchOrder? searchOrder,
    bool clearSelectedSource = false,
    LiveRoomFilter? liveRoomFilter,
    bool clearLiveRoomFilter = false,
    LiveSearchResult? liveRoomResults,
    bool clearLiveRoomResults = false,
    int? liveRoomPage,
  }) {
    return SearchState(
      query: query ?? this.query,
      localResults: localResults ?? this.localResults,
      onlineResults: onlineResults ?? this.onlineResults,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      selectedSource: clearSelectedSource ? null : (selectedSource ?? this.selectedSource),
      currentPages: currentPages ?? this.currentPages,
      searchOrder: searchOrder ?? this.searchOrder,
      liveRoomFilter: clearLiveRoomFilter ? null : (liveRoomFilter ?? this.liveRoomFilter),
      liveRoomResults: clearLiveRoomResults ? null : (liveRoomResults ?? this.liveRoomResults),
      liveRoomPage: liveRoomPage ?? this.liveRoomPage,
    );
  }

  @override
  List<Object?> get props => [
        query,
        localResults,
        onlineResults,
        isLoading,
        error,
        selectedSource,
        currentPages,
        searchOrder,
        liveRoomFilter,
        liveRoomResults,
        liveRoomPage,
      ];
}

/// 搜索控制器
class SearchNotifier extends StateNotifier<SearchState> {
  final SearchService _service;
  final BilibiliSource _bilibiliSource;

  SearchNotifier(this._service, this._bilibiliSource) : super(const SearchState());

  /// 执行搜索（根据当前模式自动选择视频或直播间搜索）
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    // 如果是直播间搜索模式，执行直播间搜索
    if (state.isLiveSearchMode) {
      await searchLiveRooms(query);
      return;
    }

    state = state.copyWith(
      query: query,
      isLoading: true,
      error: null,
      currentPages: {},
      onlineResults: {}, // 清空之前的结果
    );

    try {
      // 并行搜索本地和在线
      final localFuture = _service.searchLocal(query);
      final onlineFuture = _service.searchOnline(
        query,
        sourceTypes: state.enabledSources.toList(),
        order: state.searchOrder,
      );

      final results = await Future.wait([localFuture, onlineFuture]);
      final localTracks = results[0] as List<Track>;
      final onlineResult = results[1] as MultiSourceSearchResult;

      // 初始化页码
      final pages = <SourceType, int>{};
      for (final type in state.enabledSources) {
        pages[type] = 1;
      }

      state = state.copyWith(
        localResults: localTracks,
        onlineResults: onlineResult.results,
        isLoading: false,
        currentPages: pages,
        error: onlineResult.error,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 加载更多（特定音源）
  Future<void> loadMore(SourceType sourceType) async {
    if (!state.hasMoreFor(sourceType) || state.isLoading) return;

    final currentPage = state.currentPages[sourceType] ?? 1;
    final nextPage = currentPage + 1;

    state = state.copyWith(isLoading: true);

    try {
      final result = await _service.searchSource(
        sourceType,
        state.query,
        page: nextPage,
        order: state.searchOrder,
      );

      // 合并结果
      final existingResult = state.onlineResults[sourceType];
      final mergedTracks = <Track>[
        ...existingResult?.tracks ?? [],
        ...result.tracks,
      ];

      final mergedResult = SearchResult(
        tracks: mergedTracks,
        totalCount: result.totalCount,
        page: nextPage,
        pageSize: result.pageSize,
        hasMore: result.hasMore,
      );

      final updatedResults =
          Map<SourceType, SearchResult>.from(state.onlineResults);
      updatedResults[sourceType] = mergedResult;

      final updatedPages = Map<SourceType, int>.from(state.currentPages);
      updatedPages[sourceType] = nextPage;

      state = state.copyWith(
        onlineResults: updatedResults,
        currentPages: updatedPages,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 加载更多（所有有更多结果的音源同时加载）
  Future<void> loadMoreAll() async {
    if (state.isLoading) return;

    // 找出所有有更多结果的音源
    final sourcesToLoad = <SourceType>[];
    for (final entry in state.onlineResults.entries) {
      if (entry.value.hasMore) {
        sourcesToLoad.add(entry.key);
      }
    }

    if (sourcesToLoad.isEmpty) return;

    state = state.copyWith(isLoading: true);

    try {
      // 并行加载所有音源的下一页
      final futures = <Future<(SourceType, SearchResult)>>[];
      for (final sourceType in sourcesToLoad) {
        final currentPage = state.currentPages[sourceType] ?? 1;
        final nextPage = currentPage + 1;
        futures.add(
          _service
              .searchSource(
                sourceType,
                state.query,
                page: nextPage,
                order: state.searchOrder,
              )
              .then((result) => (sourceType, result)),
        );
      }

      final results = await Future.wait(futures);

      // 合并结果
      final updatedResults =
          Map<SourceType, SearchResult>.from(state.onlineResults);
      final updatedPages = Map<SourceType, int>.from(state.currentPages);

      for (final (sourceType, result) in results) {
        final existingResult = state.onlineResults[sourceType];
        final mergedTracks = <Track>[
          ...existingResult?.tracks ?? [],
          ...result.tracks,
        ];

        updatedResults[sourceType] = SearchResult(
          tracks: mergedTracks,
          totalCount: result.totalCount,
          page: result.page,
          pageSize: result.pageSize,
          hasMore: result.hasMore,
        );

        updatedPages[sourceType] = result.page;
      }

      state = state.copyWith(
        onlineResults: updatedResults,
        currentPages: updatedPages,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 设置音源筛选（null = 全部）
  /// [autoSearch] 是否自动触发搜索，默认为 true
  void setSource(SourceType? sourceType, {bool autoSearch = true}) {
    state = state.copyWith(
      selectedSource: sourceType,
      clearSelectedSource: sourceType == null,
    );

    // 如果有查询，重新搜索
    if (autoSearch && state.query.isNotEmpty) {
      search(state.query);
    }
  }

  /// 设置排序方式
  void setSearchOrder(SearchOrder order) {
    if (state.searchOrder == order) return;
    
    state = state.copyWith(searchOrder: order);
    
    // 如果有查询，重新搜索
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }

  /// 清除搜索
  void clear() {
    state = SearchState(
      selectedSource: state.selectedSource, // 保留音源筛选
      searchOrder: state.searchOrder, // 保留排序设置
      liveRoomFilter: state.liveRoomFilter, // 保留直播间筛选
    );
  }

  // ========== 直播间搜索相关方法 ==========

  /// 设置直播间筛选（null = 退出直播间搜索模式）
  /// [autoSearch] 是否自动触发搜索，默认为 true
  void setLiveRoomFilter(LiveRoomFilter? filter, {bool autoSearch = true}) {
    state = state.copyWith(
      liveRoomFilter: filter,
      clearLiveRoomFilter: filter == null,
      liveRoomResults: null, // 清空之前的直播间结果
      liveRoomPage: 1,
    );

    // 如果有查询，重新搜索
    if (autoSearch && state.query.isNotEmpty) {
      search(state.query);
    }
  }

  /// 同时设置音源和直播间筛选，只触发一次搜索
  /// 用于避免连续调用 setSource 和 setLiveRoomFilter 导致的竞态条件
  void setFilters({
    SourceType? sourceType,
    bool clearSource = false,
    LiveRoomFilter? liveRoomFilter,
    bool clearLiveRoomFilter = false,
  }) {
    // 判断是否进入/切换直播间筛选模式
    final isEnteringLiveMode = liveRoomFilter != null;
    // 判断是否退出直播间筛选模式
    final isExitingLiveMode = clearLiveRoomFilter;
    // 需要清空直播间结果的情况
    final shouldClearLiveResults = isEnteringLiveMode || isExitingLiveMode;
    
    state = state.copyWith(
      selectedSource: sourceType,
      clearSelectedSource: clearSource,
      liveRoomFilter: liveRoomFilter,
      clearLiveRoomFilter: clearLiveRoomFilter,
      // 进入/切换直播间筛选时清空直播间结果，退出时也清空
      clearLiveRoomResults: shouldClearLiveResults,
      liveRoomPage: shouldClearLiveResults ? 1 : state.liveRoomPage,
      // 退出直播间模式时清空视频结果
      onlineResults: isExitingLiveMode ? {} : state.onlineResults,
      // 有查询时显示加载状态
      isLoading: state.query.isNotEmpty,
    );

    // 如果有查询，重新搜索
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }

  /// 搜索直播间
  Future<void> searchLiveRooms(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(
        query: '',
        liveRoomResults: null,
        liveRoomPage: 1,
      );
      return;
    }

    state = state.copyWith(
      query: query,
      isLoading: true,
      error: null,
      liveRoomResults: null,
      liveRoomPage: 1,
    );

    try {
      final result = await _bilibiliSource.searchLiveRooms(
        query,
        page: 1,
        filter: state.liveRoomFilter ?? LiveRoomFilter.all,
      );

      state = state.copyWith(
        liveRoomResults: result,
        liveRoomPage: 1,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 加载更多直播间
  Future<void> loadMoreLiveRooms() async {
    if (!state.hasMoreLiveRooms || state.isLoading) return;

    final nextPage = state.liveRoomPage + 1;

    state = state.copyWith(isLoading: true);

    try {
      final result = await _bilibiliSource.searchLiveRooms(
        state.query,
        page: nextPage,
        filter: state.liveRoomFilter ?? LiveRoomFilter.all,
      );

      // 合并结果
      final existingRooms = state.liveRoomResults?.rooms ?? [];
      final mergedResult = LiveSearchResult(
        rooms: [...existingRooms, ...result.rooms],
        totalCount: result.totalCount,
        page: nextPage,
        pageSize: result.pageSize,
        hasMore: result.hasMore,
      );

      state = state.copyWith(
        liveRoomResults: mergedResult,
        liveRoomPage: nextPage,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 获取直播流地址
  Future<String?> getLiveStreamUrl(int roomId) async {
    return await _bilibiliSource.getLiveStreamUrl(roomId);
  }
}

/// 搜索 Provider
final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final service = ref.watch(searchServiceProvider);
  final bilibiliSource = ref.watch(bilibiliSourceProvider);
  return SearchNotifier(service, bilibiliSource);
});

/// 搜索历史 Provider
final searchHistoryProvider =
    FutureProvider<List<SearchHistory>>((ref) async {
  final service = ref.watch(searchServiceProvider);
  return service.getSearchHistory();
});

/// 搜索建议 Provider
final searchSuggestionsProvider =
    FutureProvider.family<List<String>, String>((ref, prefix) async {
  final service = ref.watch(searchServiceProvider);
  return service.getSearchSuggestions(prefix);
});

/// 搜索历史管理器
class SearchHistoryNotifier extends StateNotifier<List<SearchHistory>> {
  final SearchService _service;

  SearchHistoryNotifier(this._service) : super([]) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    final history = await _service.getSearchHistory();
    state = history;
  }

  Future<void> deleteItem(int id) async {
    await _service.deleteSearchHistory(id);
    await loadHistory();
  }

  Future<void> clearAll() async {
    await _service.clearSearchHistory();
    state = [];
  }
}

/// 搜索历史管理 Provider
final searchHistoryManagerProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<SearchHistory>>((ref) {
  final service = ref.watch(searchServiceProvider);
  return SearchHistoryNotifier(service);
});
