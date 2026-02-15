import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/lyrics_match.dart';
import '../data/repositories/lyrics_repository.dart';
import '../services/audio/audio_provider.dart';
import '../services/lyrics/lrc_parser.dart';
import '../services/lyrics/lrclib_source.dart';
import '../services/lyrics/lyrics_auto_match_service.dart';
import '../services/lyrics/lyrics_cache_service.dart';
import '../services/lyrics/title_parser.dart';
import 'repository_providers.dart';

// ---------------------------------------------------------------------------
// Singleton providers
// ---------------------------------------------------------------------------

/// LrclibSource 单例
final lrclibSourceProvider = Provider<LrclibSource>((ref) => LrclibSource());

/// TitleParser 单例
final titleParserProvider = Provider<TitleParser>((ref) => RegexTitleParser());

/// LyricsCacheService 单例
final lyricsCacheServiceProvider = Provider<LyricsCacheService>((ref) {
  final service = LyricsCacheService();
  service.initialize();
  return service;
});

/// LyricsAutoMatchService 单例
final lyricsAutoMatchServiceProvider = Provider<LyricsAutoMatchService>((ref) {
  return LyricsAutoMatchService(
    lrclib: ref.watch(lrclibSourceProvider),
    repo: ref.watch(lyricsRepositoryProvider),
    cache: ref.watch(lyricsCacheServiceProvider),
    parser: ref.watch(titleParserProvider),
  );
});

// ---------------------------------------------------------------------------
// 当前播放歌曲的歌词匹配
// ---------------------------------------------------------------------------

/// 当前播放歌曲的歌词匹配信息（实时监听数据库变化）
final currentLyricsMatchProvider =
    StreamProvider.autoDispose<LyricsMatch?>((ref) {
  final currentTrack = ref.watch(currentTrackProvider);
  if (currentTrack == null) return Stream.value(null);
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.watchByTrackKey(currentTrack.uniqueKey);
});

/// 当前歌词的 externalId（用于触发内容加载，避免 offset 变化时重新加载）
final _currentLyricsExternalIdProvider =
    Provider.autoDispose<int?>((ref) {
  final match = ref.watch(currentLyricsMatchProvider).valueOrNull;
  return match?.externalId;
});

/// 当前播放歌曲的歌词内容（优先从缓存获取，否则在线获取）
/// 注意：只在 externalId 变化时重新加载，offset 变化不会触发重新加载
final currentLyricsContentProvider =
    FutureProvider.autoDispose<LrclibResult?>((ref) async {
  final currentTrack = ref.watch(currentTrackProvider);
  if (currentTrack == null) return null;

  // 只监听 externalId，不监听整个 match 对象
  final externalId = ref.watch(_currentLyricsExternalIdProvider);
  if (externalId == null) return null;

  final cache = ref.watch(lyricsCacheServiceProvider);
  final lrclib = ref.watch(lrclibSourceProvider);

  // 1. 尝试从缓存获取
  final cached = await cache.get(currentTrack.uniqueKey);
  if (cached != null) return cached;

  // 2. 从 API 获取
  final result = await lrclib.getById(externalId);
  if (result != null) {
    // 3. 保存到缓存
    await cache.put(currentTrack.uniqueKey, result);
  }

  return result;
});

/// 解析后的歌词（缓存解析结果，避免每次 position 变化都重新解析）
final parsedLyricsProvider = Provider.autoDispose<ParsedLyrics?>((ref) {
  final content = ref.watch(currentLyricsContentProvider).valueOrNull;
  if (content == null) return null;
  return LrcParser.parse(content.syncedLyrics, content.plainLyrics);
});

// ---------------------------------------------------------------------------
// 歌词搜索
// ---------------------------------------------------------------------------

/// 歌词搜索状态
class LyricsSearchState {
  final bool isLoading;
  final List<LrclibResult> results;
  final String? error;

  const LyricsSearchState({
    this.isLoading = false,
    this.results = const [],
    this.error,
  });

  LyricsSearchState copyWith({
    bool? isLoading,
    List<LrclibResult>? results,
    String? error,
  }) {
    return LyricsSearchState(
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: error,
    );
  }
}

/// 歌词搜索 Notifier
class LyricsSearchNotifier extends StateNotifier<LyricsSearchState> {
  final LrclibSource _lrclib;
  final LyricsRepository _repo;
  final LyricsCacheService _cache;

  LyricsSearchNotifier(this._lrclib, this._repo, this._cache)
      : super(const LyricsSearchState());

  /// 搜索歌词
  Future<void> search({String? query, String? trackName, String? artistName}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await _lrclib.search(
        q: query,
        trackName: trackName,
        artistName: artistName,
      );
      if (!mounted) return;
      state = state.copyWith(isLoading: false, results: results);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 保存匹配
  Future<void> saveMatch({
    required String trackUniqueKey,
    required LrclibResult result,
  }) async {
    final match = LyricsMatch()
      ..trackUniqueKey = trackUniqueKey
      ..lyricsSource = 'lrclib'
      ..externalId = result.id
      ..offsetMs = 0
      ..matchedAt = DateTime.now();
    await _repo.save(match);
    
    // 立即缓存歌词内容
    await _cache.put(trackUniqueKey, result);
  }

  /// 删除匹配
  Future<void> removeMatch(String trackUniqueKey) async {
    await _repo.delete(trackUniqueKey);
  }

  /// 更新偏移
  Future<void> updateOffset(String trackUniqueKey, int offsetMs) async {
    await _repo.updateOffset(trackUniqueKey, offsetMs);
  }

  /// 重置搜索状态
  void reset() {
    state = const LyricsSearchState();
  }
}

/// 歌词搜索 Provider
final lyricsSearchProvider =
    StateNotifierProvider.autoDispose<LyricsSearchNotifier, LyricsSearchState>(
        (ref) {
  final lrclib = ref.watch(lrclibSourceProvider);
  final repo = ref.watch(lyricsRepositoryProvider);
  final cache = ref.watch(lyricsCacheServiceProvider);
  return LyricsSearchNotifier(lrclib, repo, cache);
});

/// 查询指定 track 的歌词匹配（用于菜单显示"已匹配"状态）
final lyricsMatchForTrackProvider =
    FutureProvider.autoDispose.family<LyricsMatch?, String>((ref, trackKey) {
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.getByTrackKey(trackKey);
});
