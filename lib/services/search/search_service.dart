import 'dart:async';

import 'package:fmp/i18n/strings.g.dart';

import 'package:fmp/core/errors/user_message.dart';
import 'package:fmp/data/models/search_history.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';

/// 搜索结果（包含多个音源）
class MultiSourceSearchResult {
  final Map<String, SearchResult> results;
  final String query;
  final bool isLoading;
  final String? error;

  const MultiSourceSearchResult({
    this.results = const {},
    this.query = '',
    this.isLoading = false,
    this.error,
  });

  /// 获取所有歌曲（合并所有音源结果）
  List<Track> get allTracks {
    final tracks = <Track>[];
    for (final result in results.values) {
      tracks.addAll(result.tracks);
    }
    return tracks;
  }

  /// 获取总结果数
  int get totalCount {
    int count = 0;
    for (final result in results.values) {
      count += result.totalCount;
    }
    return count;
  }

  /// 是否有更多结果
  bool hasMoreFor(String sourceType) {
    return results[sourceType]?.hasMore ?? false;
  }

  MultiSourceSearchResult copyWith({
    Map<String, SearchResult>? results,
    String? query,
    bool? isLoading,
    String? error,
  }) {
    return MultiSourceSearchResult(
      results: results ?? this.results,
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 多源搜索服务
class SearchService {
  final SourceManager _sourceManager;
  final TrackRepository _trackRepository;
  final SearchHistoryRepository _searchHistoryRepository;

  SearchService({
    required SourceManager sourceManager,
    required TrackRepository trackRepository,
    required SearchHistoryRepository searchHistoryRepository,
  }) : _sourceManager = sourceManager,
       _trackRepository = trackRepository,
       _searchHistoryRepository = searchHistoryRepository;

  /// 在线搜索。
  ///
  /// 呼叫端可传入 chips 对应的 [sourceTypes]；未传入时使用所有已注册的
  /// direct sources。
  Future<MultiSourceSearchResult> searchOnline(
    String query, {
    List<String>? sourceTypes,
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    if (query.trim().isEmpty) {
      return const MultiSourceSearchResult();
    }

    final sources = sourceTypes ?? _sourceManager.registeredSourceTypes;
    final results = <String, SearchResult>{};
    final errors = <String>[];

    // 并行搜索所有音源
    await Future.wait(
      sources.map((type) async {
        try {
          final source = _sourceManager.searchSource(type);
          if (source != null) {
            final result = await source.search(
              query,
              page: page,
              pageSize: pageSize,
              order: order,
            );
            results[type] = result;
          }
        } catch (e, stack) {
          // 這一行的產物會整段畫進搜尋頁的 ErrorDisplay，所以不能是例外原文
          // —— 實機上它曾經顯示一整條含 URL 的 ClientException。
          final reason = failureMessage(
            e,
            stack,
            'Searching $type failed',
            tag: 'Search',
          );
          errors.add('$type: $reason');
        }
      }),
    );

    // 保存搜索历史
    await _saveSearchHistory(query);

    return MultiSourceSearchResult(
      results: results,
      query: query,
      error: errors.isNotEmpty ? errors.join('\n') : null,
    );
  }

  /// 搜索单个音源（用于加载更多）
  Future<SearchResult> searchSource(
    String sourceType,
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    final source = _sourceManager.searchSource(sourceType);
    if (source == null) {
      throw SearchException(t.error.sourceUnavailable(source: sourceType));
    }

    return source.search(query, page: page, pageSize: pageSize, order: order);
  }

  /// 加载具备 PagedVideoSource 能力音源的视频分P信息；不具备该能力的音源返回空列表。
  Future<List<VideoPage>> loadVideoPagesForTrack(Track track) async {
    final source = _sourceManager.pagedVideoSource(track.sourceType);
    if (source == null) {
      return const [];
    }

    return source.getVideoPages(track.sourceId);
  }

  /// 本地搜索（已保存的歌曲）
  Future<List<Track>> searchLocal(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    return _trackRepository.search(query);
  }

  /// 混合搜索（本地 + 在线）
  Future<MixedSearchResult> searchMixed(
    String query, {
    List<String>? sourceTypes,
    int pageSize = 20,
  }) async {
    if (query.trim().isEmpty) {
      return const MixedSearchResult();
    }

    // 并行执行本地和在线搜索
    final localFuture = searchLocal(query);
    final onlineFuture = searchOnline(
      query,
      sourceTypes: sourceTypes,
      pageSize: pageSize,
    );

    final results = await Future.wait([localFuture, onlineFuture]);
    final localTracks = results[0] as List<Track>;
    final onlineResult = results[1] as MultiSourceSearchResult;

    return MixedSearchResult(
      localTracks: localTracks,
      onlineResult: onlineResult,
      query: query,
    );
  }

  /// 获取搜索历史
  Future<List<SearchHistory>> getSearchHistory({int limit = 20}) async {
    return _searchHistoryRepository.getRecent(limit: limit);
  }

  /// 删除单条搜索历史
  Future<void> deleteSearchHistory(int id) async {
    await _searchHistoryRepository.deleteById(id);
  }

  /// 清空搜索历史
  Future<void> clearSearchHistory() async {
    await _searchHistoryRepository.clear();
  }

  /// 保存搜索历史
  Future<void> _saveSearchHistory(String query) async {
    await _searchHistoryRepository.saveQuery(query);
  }

  /// 获取搜索建议
  Future<List<String>> getSearchSuggestions(String prefix) async {
    return _searchHistoryRepository.searchByPrefix(prefix);
  }
}

/// 混合搜索结果
class MixedSearchResult {
  final List<Track> localTracks;
  final MultiSourceSearchResult onlineResult;
  final String query;

  const MixedSearchResult({
    this.localTracks = const [],
    this.onlineResult = const MultiSourceSearchResult(),
    this.query = '',
  });

  bool get hasLocalResults => localTracks.isNotEmpty;
  bool get hasOnlineResults => onlineResult.allTracks.isNotEmpty;
  bool get isEmpty => !hasLocalResults && !hasOnlineResults;
}

/// 搜索异常
class SearchException implements Exception {
  final String message;
  const SearchException(this.message);

  @override
  String toString() => message;
}
