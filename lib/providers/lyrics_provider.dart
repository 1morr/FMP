import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/lyrics_match.dart';
import '../data/models/settings.dart';
import '../data/repositories/lyrics_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../services/audio/audio_provider.dart';
import '../services/lyrics/lrc_parser.dart';
import '../services/lyrics/lrclib_source.dart';
import '../services/lyrics/lyrics_auto_match_service.dart';
import '../services/lyrics/lyrics_cache_service.dart';
import '../services/lyrics/lyrics_result.dart';
import '../services/lyrics/netease_source.dart';
import '../services/lyrics/qqmusic_source.dart';
import '../services/lyrics/title_parser.dart';
import 'audio_settings_provider.dart';
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
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final service = LyricsCacheService();
  service.initialize(
    initialMaxCacheFiles: () async {
      final settings = await settingsRepo.get();
      return settings.maxLyricsCacheFiles;
    },
  );
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

/// 歌词自动匹配是否正在进行中（用于 UI 显示加载动画）
final lyricsAutoMatchingProvider = StateProvider<bool>((ref) => false);

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

/// 歌词显示模式 Provider（持久化到 Settings）
final lyricsDisplayModeProvider =
    StateNotifierProvider<LyricsDisplayModeNotifier, LyricsDisplayMode>((ref) {
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return LyricsDisplayModeNotifier(settingsRepo);
});

/// 歌词显示模式管理器
class LyricsDisplayModeNotifier extends StateNotifier<LyricsDisplayMode> {
  final SettingsRepository _settingsRepository;
  Settings? _settings;

  LyricsDisplayModeNotifier(this._settingsRepository)
      : super(LyricsDisplayMode.original) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _settings = await _settingsRepository.get();
    if (!mounted) return;
    state = _settings!.lyricsDisplayMode;
  }

  Future<void> setMode(LyricsDisplayMode mode) async {
    if (_settings == null) return;
    await _settingsRepository.update((s) => s.lyricsDisplayMode = mode);
    _settings!.lyricsDisplayMode = mode;
    state = mode;
  }
}

/// 根据显示模式选择附加歌词文本（翻译/罗马音）
///
/// 返回 null 表示不显示附加文本（原文模式或无可用附加歌词）。
/// 优先级：
/// - preferTranslated: translatedLyrics → romajiLyrics → null
/// - preferRomaji: romajiLyrics → translatedLyrics → null
/// - original: null
String? _selectSubLyricsText(LyricsResult content, LyricsDisplayMode mode) {
  switch (mode) {
    case LyricsDisplayMode.preferTranslated:
      if (content.hasTranslatedLyrics) return content.translatedLyrics;
      if (content.hasRomajiLyrics) return content.romajiLyrics;
      return null;
    case LyricsDisplayMode.preferRomaji:
      if (content.hasRomajiLyrics) return content.romajiLyrics;
      if (content.hasTranslatedLyrics) return content.translatedLyrics;
      return null;
    case LyricsDisplayMode.original:
      return null;
  }
}

/// 解析后的歌词（缓存解析结果，避免每次 position 变化都重新解析）
///
/// 始终解析原文歌词，根据 lyricsDisplayMode 合并附加文本（翻译/罗马音）到每行的 subText。
final parsedLyricsProvider = Provider.autoDispose<ParsedLyrics?>((ref) {
  final content = ref.watch(currentLyricsContentProvider).valueOrNull;
  if (content == null) return null;

  // 始终解析原文
  final parsed = LrcParser.parse(content.syncedLyrics, content.plainLyrics);
  if (parsed == null) return null;

  // 根据显示模式合并附加歌词
  final mode = ref.watch(lyricsDisplayModeProvider);
  final subText = _selectSubLyricsText(content, mode);
  if (subText == null) return parsed;

  return LrcParser.mergeSubLyrics(parsed, subText);
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
  final List<String> _sourceOrder;
  final Set<String> _disabledSources;

  int _searchRequestId = 0;

  LyricsSearchNotifier(
    this._lrclib,
    this._netease,
    this._qqmusic,
    this._repo,
    this._cache, {
    List<String> sourceOrder = const ['netease', 'qqmusic', 'lrclib'],
    Set<String> disabledSources = const {},
  })  : _sourceOrder = sourceOrder,
        _disabledSources = disabledSources,
        super(const LyricsSearchState());

  /// 设置筛选源
  void setFilter(LyricsSourceFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// 搜索歌词
  Future<void> search({String? query, String? trackName, String? artistName}) async {
    // 取消之前的搜索
    final requestId = ++_searchRequestId;
    
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
          // 按用户配置的优先级并行搜索启用的源
          final enabledSources = _sourceOrder
              .where((s) => !_disabledSources.contains(s))
              .toList();
          final sourceResults = <String, List<LyricsResult>>{};
          final searchFutures = <Future<void>>[];

          for (final source in enabledSources) {
            switch (source) {
              case 'netease':
                searchFutures.add(
                  _netease.searchLyrics(
                    query: query,
                    trackName: trackName,
                    artistName: artistName,
                  ).then((r) => sourceResults['netease'] = r)
                   .catchError((_) => sourceResults['netease'] = <LyricsResult>[]),
                );
              case 'qqmusic':
                searchFutures.add(
                  _qqmusic.searchLyrics(
                    query: query,
                    trackName: trackName,
                    artistName: artistName,
                  ).then((r) => sourceResults['qqmusic'] = r)
                   .catchError((_) => sourceResults['qqmusic'] = <LyricsResult>[]),
                );
              case 'lrclib':
                searchFutures.add(
                  _lrclib.search(
                    q: query,
                    trackName: trackName,
                    artistName: artistName,
                  ).then((r) => sourceResults['lrclib'] = r)
                   .catchError((_) => sourceResults['lrclib'] = <LyricsResult>[]),
                );
            }
          }

          await Future.wait(searchFutures);

          // 按用户优先级顺序拼接结果
          results = [];
          for (final source in enabledSources) {
            results.addAll(sourceResults[source] ?? []);
          }
      }

      // 检查是否被新的搜索取代
      if (!mounted || requestId != _searchRequestId) return;
      state = state.copyWith(isLoading: false, results: results);
    } catch (e) {
      // 检查是否被新的搜索取代
      if (!mounted || requestId != _searchRequestId) return;
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
    
    // 先删除旧缓存再写入新内容，确保重新匹配后不会返回旧歌词
    await _cache.remove(trackUniqueKey);
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
  final audioSettings = ref.watch(audioSettingsProvider);
  return LyricsSearchNotifier(
    lrclib,
    netease,
    qqmusic,
    repo,
    cache,
    sourceOrder: audioSettings.lyricsSourceOrder,
    disabledSources: audioSettings.disabledLyricsSources,
  );
});

/// 查询指定 track 的歌词匹配（用于菜单显示"已匹配"状态）
final lyricsMatchForTrackProvider =
    FutureProvider.autoDispose.family<LyricsMatch?, String>((ref, trackKey) {
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.getByTrackKey(trackKey);
});
