import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/lyrics_match.dart';
import '../data/repositories/lyrics_repository.dart';
import '../services/audio/audio_provider.dart';
import '../services/lyrics/lrc_parser.dart';
import '../services/lyrics/lrclib_source.dart';
import '../services/lyrics/lyrics_auto_match_service.dart';
import '../services/lyrics/lyrics_cache_service.dart';
import '../services/lyrics/lyrics_result.dart';
import '../services/lyrics/netease_source.dart';
import '../services/lyrics/qqmusic_source.dart';
import '../services/lyrics/title_parser.dart';
import 'repository_providers.dart';

// ---------------------------------------------------------------------------
// Singleton providers
// ---------------------------------------------------------------------------

/// LrclibSource 单例
final lrclibSourceProvider = Provider<LrclibSource>((ref) => LrclibSource());

/// NeteaseSource 单例
final neteaseSourceProvider = Provider<NeteaseSource>((ref) => NeteaseSource());

/// QQMusicSource 单例
final qqmusicSourceProvider = Provider<QQMusicSource>((ref) => QQMusicSource());

/// 歌词源筛选
enum LyricsSourceFilter { all, netease, qqmusic, lrclib }

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
    netease: ref.watch(neteaseSourceProvider),
    qqmusic: ref.watch(qqmusicSourceProvider),
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
    Provider.autoDispose<String?>((ref) {
  final match = ref.watch(currentLyricsMatchProvider).valueOrNull;
  return match?.externalId;
});

/// 当前歌词源标识（用于决定从哪个源获取歌词内容）
final _currentLyricsSourceProvider =
    Provider.autoDispose<String?>((ref) {
  final match = ref.watch(currentLyricsMatchProvider).valueOrNull;
  return match?.lyricsSource;
});

/// 当前播放歌曲的歌词内容（优先从缓存获取，否则在线获取）
/// 注意：只在 externalId 变化时重新加载，offset 变化不会触发重新加载
final currentLyricsContentProvider =
    FutureProvider.autoDispose<LyricsResult?>((ref) async {
  final currentTrack = ref.watch(currentTrackProvider);
  if (currentTrack == null) return null;

  final externalId = ref.watch(_currentLyricsExternalIdProvider);
  if (externalId == null) return null;

  final lyricsSource = ref.watch(_currentLyricsSourceProvider);
  final cache = ref.watch(lyricsCacheServiceProvider);

  // 1. 尝试从缓存获取
  final cached = await cache.get(currentTrack.uniqueKey);
  if (cached != null) return cached;

  // 2. 根据歌词源从对应 API 获取
  LyricsResult? result;
  if (lyricsSource == 'qqmusic') {
    final qqmusic = ref.watch(qqmusicSourceProvider);
    result = await qqmusic.getLyricsResult(externalId);
  } else if (lyricsSource == 'netease') {
    final netease = ref.watch(neteaseSourceProvider);
    result = await netease.getLyricsResult(externalId);
  } else {
    final lrclib = ref.watch(lrclibSourceProvider);
    result = await lrclib.getById(externalId);
  }

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
  final List<LyricsResult> results;
  final String? error;
  final LyricsSourceFilter filter;

  const LyricsSearchState({
    this.isLoading = false,
    this.results = const [],
    this.error,
    this.filter = LyricsSourceFilter.all,
  });

  LyricsSearchState copyWith({
    bool? isLoading,
    List<LyricsResult>? results,
    String? error,
    LyricsSourceFilter? filter,
  }) {
    return LyricsSearchState(
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: error,
      filter: filter ?? this.filter,
    );
  }
}

/// 歌词搜索 Notifier
class LyricsSearchNotifier extends StateNotifier<LyricsSearchState> {
  final LrclibSource _lrclib;
  final NeteaseSource _netease;
  final QQMusicSource _qqmusic;
  final LyricsRepository _repo;
  final LyricsCacheService _cache;

  LyricsSearchNotifier(
      this._lrclib, this._netease, this._qqmusic, this._repo, this._cache)
      : super(const LyricsSearchState());

  /// 设置筛选源
  void setFilter(LyricsSourceFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// 搜索歌词
  Future<void> search({String? query, String? trackName, String? artistName}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final filter = state.filter;
      List<LyricsResult> results;

      switch (filter) {
        case LyricsSourceFilter.lrclib:
          results = await _lrclib.search(
            q: query,
            trackName: trackName,
            artistName: artistName,
          );
        case LyricsSourceFilter.netease:
          results = await _netease.searchLyrics(
            query: query,
            trackName: trackName,
            artistName: artistName,
          );
        case LyricsSourceFilter.qqmusic:
          results = await _qqmusic.searchLyrics(
            query: query,
            trackName: trackName,
            artistName: artistName,
          );
        case LyricsSourceFilter.all:
          // 并行搜索三个源
          final futures = await Future.wait([
            _netease.searchLyrics(
              query: query,
              trackName: trackName,
              artistName: artistName,
            ).catchError((_) => <LyricsResult>[]),
            _qqmusic.searchLyrics(
              query: query,
              trackName: trackName,
              artistName: artistName,
            ).catchError((_) => <LyricsResult>[]),
            _lrclib.search(
              q: query,
              trackName: trackName,
              artistName: artistName,
            ).catchError((_) => <LyricsResult>[]),
          ]);
          // 网易云 → QQ音乐 → lrclib
          results = [...futures[0], ...futures[1], ...futures[2]];
      }

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
    required LyricsResult result,
  }) async {
    final match = LyricsMatch()
      ..trackUniqueKey = trackUniqueKey
      ..lyricsSource = result.source
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
  final netease = ref.watch(neteaseSourceProvider);
  final qqmusic = ref.watch(qqmusicSourceProvider);
  final repo = ref.watch(lyricsRepositoryProvider);
  final cache = ref.watch(lyricsCacheServiceProvider);
  return LyricsSearchNotifier(lrclib, netease, qqmusic, repo, cache);
});

/// 查询指定 track 的歌词匹配（用于菜单显示"已匹配"状态）
final lyricsMatchForTrackProvider =
    FutureProvider.autoDispose.family<LyricsMatch?, String>((ref, trackKey) {
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.getByTrackKey(trackKey);
});
