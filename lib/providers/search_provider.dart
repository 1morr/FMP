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

  const SearchState({
    this.query = '',
    this.localResults = const [],
    this.onlineResults = const {},
    this.isLoading = false,
    this.error,
    this.enabledSources = const {SourceType.bilibili},
    this.currentPages = const {},
  });

  /// 获取所有在线结果
  List<Track> get allOnlineTracks {
    final tracks = <Track>[];
    for (final result in onlineResults.values) {
      tracks.addAll(result.tracks);
    }
    return tracks;
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
  }) {
    return SearchState(
      query: query ?? this.query,
      localResults: localResults ?? this.localResults,
      onlineResults: onlineResults ?? this.onlineResults,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      enabledSources: enabledSources ?? this.enabledSources,
      currentPages: currentPages ?? this.currentPages,
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
    );

    try {
      // 并行搜索本地和在线
      final localFuture = _service.searchLocal(query);
      final onlineFuture = _service.searchOnline(
        query,
        sourceTypes: state.enabledSources.toList(),
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

  /// 清除搜索
  void clear() {
    state = const SearchState(
      enabledSources: {SourceType.bilibili},
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
