import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../data/models/track.dart';
export '../data/models/track.dart' show SourceType;
import '../data/models/search_history.dart';
import '../data/sources/base_source.dart';
import '../data/sources/source_provider.dart';
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
  final Set<SourceType> enabledSources;
  final Map<SourceType, int> currentPages;
  final SearchOrder searchOrder;

  const SearchState({
    this.query = '',
    this.localResults = const [],
    this.onlineResults = const {},
    this.isLoading = false,
    this.error,
    this.enabledSources = const {SourceType.bilibili, SourceType.youtube},
    this.currentPages = const {},
    this.searchOrder = SearchOrder.relevance,
  });

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
  bool get hasResults => localResults.isNotEmpty || allOnlineTracks.isNotEmpty;

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
    Set<SourceType>? enabledSources,
    Map<SourceType, int>? currentPages,
    SearchOrder? searchOrder,
  }) {
    return SearchState(
      query: query ?? this.query,
      localResults: localResults ?? this.localResults,
      onlineResults: onlineResults ?? this.onlineResults,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      enabledSources: enabledSources ?? this.enabledSources,
      currentPages: currentPages ?? this.currentPages,
      searchOrder: searchOrder ?? this.searchOrder,
    );
  }

  @override
  List<Object?> get props => [
        query,
        localResults,
        onlineResults,
        isLoading,
        error,
        enabledSources,
        currentPages,
        searchOrder,
      ];
}

/// 搜索控制器
class SearchNotifier extends StateNotifier<SearchState> {
  final SearchService _service;

  SearchNotifier(this._service) : super(const SearchState());

  /// 执行搜索
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = const SearchState();
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

  /// 切换音源筛选
  void toggleSource(SourceType sourceType) {
    final sources = Set<SourceType>.from(state.enabledSources);
    if (sources.contains(sourceType)) {
      sources.remove(sourceType);
    } else {
      sources.add(sourceType);
    }
    state = state.copyWith(enabledSources: sources);

    // 如果有查询，重新搜索
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }

  /// 设置启用的音源
  void setEnabledSources(Set<SourceType> sources) {
    state = state.copyWith(enabledSources: sources);
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
      enabledSources: const {SourceType.bilibili},
      searchOrder: state.searchOrder, // 保留排序设置
    );
  }
}

/// 搜索 Provider
final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final service = ref.watch(searchServiceProvider);
  return SearchNotifier(service);
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
