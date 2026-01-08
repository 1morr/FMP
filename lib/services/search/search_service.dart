import 'dart:async';

import 'package:isar/isar.dart';
import '../../data/models/track.dart';
import '../../data/models/search_history.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_provider.dart';
import '../../data/repositories/track_repository.dart';

/// 搜索结果（包含多个音源）
class MultiSourceSearchResult {
  final Map<SourceType, SearchResult> results;
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
  bool hasMoreFor(SourceType sourceType) {
    return results[sourceType]?.hasMore ?? false;
  }

  MultiSourceSearchResult copyWith({
    Map<SourceType, SearchResult>? results,
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
  final Isar _isar;

  SearchService({
    required SourceManager sourceManager,
    required TrackRepository trackRepository,
    required Isar isar,
  })  : _sourceManager = sourceManager,
        _trackRepository = trackRepository,
        _isar = isar;

  /// 在线搜索（所有启用的音源）
  Future<MultiSourceSearchResult> searchOnline(
    String query, {
    List<SourceType>? sourceTypes,
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    if (query.trim().isEmpty) {
      return const MultiSourceSearchResult();
    }

    final sources = sourceTypes ?? _sourceManager.enabledSourceTypes;
    final results = <SourceType, SearchResult>{};
    final errors = <String>[];

    // 并行搜索所有音源
    await Future.wait(
      sources.map((type) async {
        try {
          final source = _sourceManager.getSource(type);
          if (source != null) {
            final result = await source.search(
              query,
              page: page,
              pageSize: pageSize,
              order: order,
            );
            results[type] = result;
          }
        } catch (e) {
          errors.add('${type.name}: ${e.toString()}');
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
    SourceType sourceType,
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    final source = _sourceManager.getSource(sourceType);
    if (source == null) {
      throw SearchException('音源 ${sourceType.name} 不可用');
    }

    return source.search(query, page: page, pageSize: pageSize, order: order);
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
    List<SourceType>? sourceTypes,
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
    return _isar.searchHistorys
        .filter()
        .queryIsNotEmpty()
        .sortByTimestampDesc()
        .limit(limit)
        .findAll();
  }

  /// 删除单条搜索历史
  Future<void> deleteSearchHistory(int id) async {
    await _isar.writeTxn(() => _isar.searchHistorys.delete(id));
  }

  /// 清空搜索历史
  Future<void> clearSearchHistory() async {
    await _isar.writeTxn(() => _isar.searchHistorys.clear());
  }

  /// 保存搜索历史
  Future<void> _saveSearchHistory(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    // 删除相同的旧记录
    final existing = await _isar.searchHistorys
        .filter()
        .queryEqualTo(trimmedQuery)
        .findAll();

    await _isar.writeTxn(() async {
      // 删除旧记录
      for (final history in existing) {
        await _isar.searchHistorys.delete(history.id);
      }

      // 添加新记录
      final newHistory = SearchHistory()
        ..query = trimmedQuery
        ..timestamp = DateTime.now();
      await _isar.searchHistorys.put(newHistory);

      // 保留最近 100 条
      final allHistory = await _isar.searchHistorys
          .filter()
          .queryIsNotEmpty()
          .sortByTimestampDesc()
          .findAll();

      if (allHistory.length > 100) {
        final toDelete = allHistory.sublist(100);
        for (final history in toDelete) {
          await _isar.searchHistorys.delete(history.id);
        }
      }
    });
  }

  /// 获取搜索建议
  Future<List<String>> getSearchSuggestions(String prefix) async {
    if (prefix.trim().isEmpty) {
      // 返回最近搜索
      final history = await getSearchHistory(limit: 5);
      return history.map((h) => h.query).toList();
    }

    // 从历史记录中匹配
    final history = await _isar.searchHistorys
        .filter()
        .queryContains(prefix, caseSensitive: false)
        .sortByTimestampDesc()
        .limit(10)
        .findAll();

    return history.map((h) => h.query).toList();
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
