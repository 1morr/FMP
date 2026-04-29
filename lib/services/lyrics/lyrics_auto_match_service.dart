import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/lyrics_match.dart';
import '../../data/models/lyrics_title_parse_cache.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../data/repositories/lyrics_repository.dart';
import '../../data/repositories/lyrics_title_parse_cache_repository.dart';
import 'ai_title_parser.dart';
import 'lrclib_source.dart';
import 'lyrics_ai_config_service.dart';
import 'lyrics_cache_service.dart';
import 'lyrics_result.dart';
import 'netease_source.dart';
import 'qqmusic_source.dart';
import 'title_parser.dart';

/// 歌词自动匹配服务
///
/// 在播放歌曲时自动搜索并匹配歌词（仅当没有已匹配的歌词时）。
/// 匹配条件：
/// - 时长差距 ≤ 20 秒
/// - 只有一个结果符合时长条件时才自动匹配
class LyricsAutoMatchService with Logging {
  final LrclibSource _lrclib;
  final NeteaseSource _netease;
  final QQMusicSource _qqmusic;
  final LyricsRepository _repo;
  final LyricsCacheService _cache;
  final TitleParser _parser;
  final AiTitleParser? _aiTitleParser;
  final Future<LyricsAiConfig> Function()? _aiConfigLoader;
  final LyricsTitleParseCacheRepository? _titleParseCacheRepo;

  LyricsAutoMatchService({
    required LrclibSource lrclib,
    required NeteaseSource netease,
    required QQMusicSource qqmusic,
    required LyricsRepository repo,
    required LyricsCacheService cache,
    required TitleParser parser,
    AiTitleParser? aiTitleParser,
    Future<LyricsAiConfig> Function()? aiConfigLoader,
    LyricsTitleParseCacheRepository? titleParseCacheRepo,
  })  : _lrclib = lrclib,
        _netease = netease,
        _qqmusic = qqmusic,
        _repo = repo,
        _cache = cache,
        _parser = parser,
        _aiTitleParser = aiTitleParser,
        _aiConfigLoader = aiConfigLoader,
        _titleParseCacheRepo = titleParseCacheRepo;

  /// 正在匹配中的 track key 集合，防止同一首歌并发匹配
  final Set<String> _matchingKeys = {};

  /// 尝试自动匹配歌词
  ///
  /// [enabledSources] 按优先级排序的启用歌词源列表（如 ['netease', 'qqmusic', 'lrclib']）。
  /// 如果为 null，使用默认顺序。
  /// 返回 true 表示成功匹配，false 表示未匹配（已有匹配、无结果、多个结果等）
  Future<bool> tryAutoMatch(Track track, {List<String>? enabledSources}) async {
    // 防止同一首歌并发匹配
    final key = track.uniqueKey;
    if (_matchingKeys.contains(key)) {
      logDebug('Already matching lyrics for: $key');
      return false;
    }
    _matchingKeys.add(key);

    try {
      // 1. 检查是否已有匹配
      final existingMatch = await _repo.getByTrackKey(track.uniqueKey);
      if (existingMatch != null) {
        logDebug('Track already has lyrics match: ${track.uniqueKey}');
        return false;
      }

      // 1.5a. 网易云歌曲直接用 sourceId 获取歌词（跳过搜索）
      if (track.sourceType == SourceType.netease) {
        try {
          final result = await _netease
              .getLyricsResult(track.sourceId)
              .timeout(AppConstants.networkReceiveTimeout);
          if (result != null && result.hasSyncedLyrics) {
            await _saveMatch(track, result, 'netease', track.sourceId);
            logInfo(
                'Auto-matched lyrics via netease sourceId: ${track.sourceId}');
            return true;
          }
        } catch (e) {
          logDebug(
              'Direct lyrics fetch failed for netease ${track.sourceId}: $e');
          // 降级到搜索匹配
        }
      }

      // 1.5b. 如果有原平台 ID，直接获取歌词（跳过搜索）
      if (track.originalSongId != null && track.originalSource != null) {
        final result =
            await _tryDirectFetch(track.originalSongId!, track.originalSource!);
        if (result != null) {
          await _saveMatch(
              track, result, track.originalSource!, track.originalSongId!);
          logInfo(
              'Auto-matched lyrics via direct ID: ${track.title} → ${track.originalSource}:${track.originalSongId}');
          return true;
        }
        // 直接获取失败，fallback 到搜索流程
      }

      final sources = enabledSources ?? ['netease', 'qqmusic', 'lrclib'];
      final aiConfig = await _loadAiConfigSafely();
      final shouldTryAi = _shouldTryAi(aiConfig);

      if (shouldTryAi && aiConfig!.mode == LyricsAiTitleParsingMode.alwaysAi) {
        final aiParsed = await _loadOrParseAiTitle(track, aiConfig);
        if (aiParsed != null) {
          final aiMatched = await _matchAiParsedTitle(track, aiParsed, sources);
          if (aiMatched) return true;
        }
      }

      final regexMatched = await _matchRegexParsedTitle(track, sources);
      if (regexMatched) return true;

      if (shouldTryAi &&
          aiConfig!.mode == LyricsAiTitleParsingMode.fallbackAfterRules) {
        final aiParsed = await _loadOrParseAiTitle(track, aiConfig);
        if (aiParsed != null) {
          final aiMatched = await _matchAiParsedTitle(track, aiParsed, sources);
          if (aiMatched) return true;
        }
      }

      logDebug('No lyrics matched for: ${track.title}');
      return false;
    } catch (e) {
      logError('Auto-match failed for ${track.uniqueKey}: $e');
      return false;
    } finally {
      _matchingKeys.remove(key);
    }
  }

  Future<LyricsAiConfig?> _loadAiConfigSafely() async {
    final aiConfigLoader = _aiConfigLoader;
    if (aiConfigLoader == null) return null;
    try {
      return await aiConfigLoader();
    } catch (e) {
      logWarning('Failed to load lyrics AI config: $e');
      return null;
    }
  }

  bool _shouldTryAi(LyricsAiConfig? config) {
    return _aiTitleParser != null &&
        _titleParseCacheRepo != null &&
        config != null &&
        config.isAvailable;
  }

  Future<bool> _matchRegexParsedTitle(Track track, List<String> sources) async {
    final parsed = _parser.parse(track.title);
    final trackName = parsed.trackName;
    final artistName = parsed.artistName ?? track.artist ?? '';

    if (trackName.isEmpty) {
      logDebug('Cannot parse track name: ${track.title}');
      return false;
    }

    logDebug('Auto-matching: "$trackName" by "$artistName"');
    return _matchQueryPairs(
      track,
      [(trackName: trackName, artistName: artistName)],
      sources,
    );
  }

  Future<bool> _matchAiParsedTitle(
    Track track,
    AiParsedTitle parsed,
    List<String> sources,
  ) {
    return _matchQueryPairs(track, _buildAiQueryPairs(parsed), sources);
  }

  Future<bool> _matchQueryPairs(
    Track track,
    List<({String trackName, String artistName})> queryPairs,
    List<String> sources,
  ) async {
    final trackDurationSec = (track.durationMs ?? 0) ~/ 1000;
    for (final source in sources) {
      for (final query in queryPairs) {
        LyricsResult? result;
        switch (source) {
          case 'netease':
            result = await _tryNeteaseMatch(
              query.trackName,
              query.artistName,
              trackDurationSec,
            );
          case 'qqmusic':
            result = await _tryQQMusicMatch(
              query.trackName,
              query.artistName,
              trackDurationSec,
            );
          case 'lrclib':
            result = await _tryLrclibMatch(
              query.trackName,
              query.artistName,
              trackDurationSec,
            );
        }
        if (result != null) {
          await _saveMatch(track, result, source, result.id);
          logInfo('Auto-matched lyrics: ${track.title} → $source:${result.id}');
          return true;
        }
      }
    }
    return false;
  }

  List<({String trackName, String artistName})> _buildAiQueryPairs(
    AiParsedTitle parsed,
  ) {
    final trackName = parsed.trackName.trim();
    if (trackName.isEmpty) return const [];
    final artistName = parsed.artistName?.trim();
    if (artistName != null && artistName.isNotEmpty) {
      return [
        (trackName: trackName, artistName: artistName),
        (trackName: trackName, artistName: ''),
      ];
    }
    return [(trackName: trackName, artistName: '')];
  }

  Future<AiParsedTitle?> _loadOrParseAiTitle(
    Track track,
    LyricsAiConfig config,
  ) async {
    final titleParseCacheRepo = _titleParseCacheRepo;
    final aiTitleParser = _aiTitleParser;
    if (titleParseCacheRepo == null || aiTitleParser == null) return null;

    try {
      final cached = await titleParseCacheRepo.getReusable(
        trackUniqueKey: track.uniqueKey,
      );
      if (cached != null) {
        final parsed = _cacheEntryToAiParsedTitle(cached);
        if (_isValidAiParsedTitle(parsed)) {
          return parsed;
        }
        logDebug(
            'Ignoring invalid cached AI title parse for ${track.uniqueKey}');
      }

      logInfo('Calling AI title parser for ${track.uniqueKey}: ${track.title}');
      final parsed = await aiTitleParser.parse(
        endpoint: config.endpoint,
        apiKey: config.apiKey,
        model: config.model,
        title: track.title,
        timeoutSeconds: config.timeoutSeconds,
      );
      if (parsed == null) return null;
      if (!_isValidAiParsedTitle(parsed)) {
        logDebug('Ignoring invalid AI title parse for ${track.uniqueKey}');
        return null;
      }

      await titleParseCacheRepo.save(
        trackUniqueKey: track.uniqueKey,
        sourceType: track.sourceType.name,
        parsedTrackName: parsed.trackName,
        parsedArtistName: parsed.artistName,
        confidence: parsed.artistConfidence,
        provider: 'openai-compatible',
        model: config.model,
      );
      return parsed;
    } catch (e) {
      logWarning('AI title parsing failed for ${track.uniqueKey}: $e');
      return null;
    }
  }

  bool _isValidAiParsedTitle(AiParsedTitle parsed) {
    return parsed.trackName.trim().isNotEmpty;
  }

  AiParsedTitle _cacheEntryToAiParsedTitle(LyricsTitleParseCache cached) {
    final artistName = cached.parsedArtistName?.trim();
    final artistConfidence = cached.confidence;
    return AiParsedTitle(
      trackName: cached.parsedTrackName,
      artistName: artistName != null &&
              artistName.isNotEmpty &&
              artistConfidence >= AiTitleParser.minArtistConfidence
          ? artistName
          : null,
      artistConfidence: artistConfidence,
    );
  }

  /// 保存匹配结果到缓存和数据库
  Future<void> _saveMatch(Track track, LyricsResult result, String source,
      String externalId) async {
    await _cache.put(track.uniqueKey, result);
    final match = LyricsMatch()
      ..trackUniqueKey = track.uniqueKey
      ..lyricsSource = source
      ..externalId = externalId
      ..offsetMs = 0
      ..matchedAt = DateTime.now();
    await _repo.save(match);
  }

  /// 通过原平台 ID 直接获取歌词（不需要搜索）
  ///
  /// 仅支持网易云和 QQ 音乐（Spotify 无歌词 API）
  Future<LyricsResult?> _tryDirectFetch(String songId, String source) async {
    try {
      LyricsResult? result;
      if (source == 'netease') {
        result = await _netease
            .getLyricsResult(songId)
            .timeout(AppConstants.networkReceiveTimeout);
      } else if (source == 'qqmusic') {
        result = await _qqmusic
            .getLyricsResult(songId)
            .timeout(AppConstants.networkReceiveTimeout);
      } else {
        return null; // Spotify 等不支持直接获取
      }

      // 只返回有同步歌词的结果
      if (result != null && result.hasSyncedLyrics) {
        return result;
      }
      return null;
    } catch (e) {
      logWarning('Direct lyrics fetch failed for $source:$songId: $e');
      return null;
    }
  }

  /// 尝试从网易云匹配歌词
  ///
  /// 返回匹配的 LyricsResult，或 null 表示未找到合适匹配
  Future<LyricsResult?> _tryNeteaseMatch(
    String trackName,
    String artistName,
    int trackDurationSec,
  ) async {
    try {
      final results = await _netease.searchLyrics(
        query: [trackName, artistName].where((s) => s.isNotEmpty).join(' '),
        limit: 5,
      );

      if (results.isEmpty) return null;

      // 过滤符合时长条件的结果（±20秒）
      final matching = results.where((r) {
        if (r.duration == 0) return true; // 网易云有时不返回时长
        return (r.duration - trackDurationSec).abs() <=
            AppConstants.lyricsDurationToleranceSec;
      }).toList();

      if (matching.isEmpty) return null;

      // 选择最佳匹配（优先有同步歌词的）
      final best = matching.length == 1
          ? matching.first
          : _selectBestMatch(matching, trackName, artistName, trackDurationSec);

      if (best != null && best.hasSyncedLyrics) {
        return best;
      }

      return null;
    } catch (e) {
      logWarning('Netease auto-match failed: $e');
      return null;
    }
  }

  /// 尝试从 QQ 音乐匹配歌词
  ///
  /// 返回匹配的 LyricsResult，或 null 表示未找到合适匹配
  Future<LyricsResult?> _tryQQMusicMatch(
    String trackName,
    String artistName,
    int trackDurationSec,
  ) async {
    try {
      final results = await _qqmusic.searchLyrics(
        query: [trackName, artistName].where((s) => s.isNotEmpty).join(' '),
        limit: 5,
      );

      if (results.isEmpty) return null;

      // 过滤符合时长条件的结果（±20秒）
      final matching = results.where((r) {
        if (r.duration == 0) return true;
        return (r.duration - trackDurationSec).abs() <=
            AppConstants.lyricsDurationToleranceSec;
      }).toList();

      if (matching.isEmpty) return null;

      // 选择最佳匹配（优先有同步歌词的）
      final best = matching.length == 1
          ? matching.first
          : _selectBestMatch(matching, trackName, artistName, trackDurationSec);

      if (best != null && best.hasSyncedLyrics) {
        return best;
      }

      return null;
    } catch (e) {
      logWarning('QQMusic auto-match failed: $e');
      return null;
    }
  }

  /// 尝试从 lrclib 匹配歌词
  ///
  /// 返回匹配的 LyricsResult，或 null 表示未找到合适匹配
  Future<LyricsResult?> _tryLrclibMatch(
    String trackName,
    String artistName,
    int trackDurationSec,
  ) async {
    try {
      final results = await _lrclib.search(
        trackName: trackName,
        artistName: artistName.isNotEmpty ? artistName : null,
      );

      if (results.isEmpty) return null;

      // 过滤符合时长条件的结果（±20秒）
      final matchingResults = results.where((result) {
        final diff = (result.duration - trackDurationSec).abs();
        return diff <= AppConstants.lyricsDurationToleranceSec;
      }).toList();

      if (matchingResults.isEmpty) return null;

      // 如果有多个结果，选择最相似的
      final result = matchingResults.length == 1
          ? matchingResults.first
          : _selectBestMatch(
              matchingResults, trackName, artistName, trackDurationSec);

      if (result == null) return null;

      // 与 netease/qqmusic 一致，只返回有同步歌词的结果
      if (!result.hasSyncedLyrics) return null;

      logDebug(
          'Selected best lrclib match: "${result.trackName}" by "${result.artistName}" (score: ${_calculateScore(result, trackName, artistName, trackDurationSec).toStringAsFixed(2)})');
      return result;
    } catch (e) {
      logWarning('lrclib auto-match failed: $e');
      return null;
    }
  }

  /// 从多个候选结果中选择最佳匹配
  ///
  /// 评分标准：
  /// - 标题相似度（权重 40%）
  /// - 艺术家相似度（权重 30%）
  /// - 时长差距（权重 20%）
  /// - 是否有同步歌词（权重 10%）
  LyricsResult? _selectBestMatch(
    List<LyricsResult> candidates,
    String trackName,
    String artistName,
    int trackDurationSec,
  ) {
    if (candidates.isEmpty) return null;

    // 计算每个候选的得分
    final scored = candidates.map((result) {
      final score =
          _calculateScore(result, trackName, artistName, trackDurationSec);
      return (result: result, score: score);
    }).toList();

    // 按得分降序排序
    scored.sort((a, b) => b.score.compareTo(a.score));

    // 只有当最高分 >= 0.6 时才认为是可信的匹配
    final best = scored.first;
    if (best.score >= AppConstants.lyricsMatchScoreThreshold) {
      return best.result;
    }

    return null;
  }

  /// 计算匹配得分（0.0 - 1.0）
  double _calculateScore(
    LyricsResult result,
    String trackName,
    String artistName,
    int trackDurationSec,
  ) {
    // 1. 标题相似度（权重 40%）
    final titleSimilarity = _stringSimilarity(
      trackName.toLowerCase(),
      result.trackName.toLowerCase(),
    );

    // 2. 艺术家相似度（权重 30%）
    final artistSimilarity = artistName.isEmpty
        ? 0.5 // 如果没有艺术家信息，给中等分
        : _stringSimilarity(
            artistName.toLowerCase(),
            result.artistName.toLowerCase(),
          );

    // 3. 时长匹配度（权重 20%）
    final durationDiff = (result.duration - trackDurationSec).abs();
    final durationScore = durationDiff <= 3
        ? 1.0
        : durationDiff <= 10
            ? 0.8
            : durationDiff <= AppConstants.lyricsDurationToleranceSec
                ? 0.5
                : 0.0;

    // 4. 是否有同步歌词（权重 10%）
    final syncedScore =
        result.syncedLyrics != null && result.syncedLyrics!.isNotEmpty
            ? 1.0
            : 0.0;

    // 加权总分
    final totalScore = titleSimilarity * 0.4 +
        artistSimilarity * 0.3 +
        durationScore * 0.2 +
        syncedScore * 0.1;

    return totalScore;
  }

  /// 计算两个字符串的相似度（Levenshtein 距离）
  ///
  /// 返回值范围 0.0 - 1.0，1.0 表示完全相同
  double _stringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final len1 = s1.length;
    final len2 = s2.length;
    final maxLen = len1 > len2 ? len1 : len2;

    // 使用 Levenshtein 距离算法
    final distance = _levenshteinDistance(s1, s2);

    // 转换为相似度（0.0 - 1.0）
    return 1.0 - (distance / maxLen);
  }

  /// Levenshtein 距离算法（编辑距离）
  int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    // 创建距离矩阵
    final matrix = List.generate(
      len1 + 1,
      (i) => List.filled(len2 + 1, 0),
    );

    // 初始化第一行和第一列
    for (var i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }

    // 填充矩阵
    for (var i = 1; i <= len1; i++) {
      for (var j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // 删除
          matrix[i][j - 1] + 1, // 插入
          matrix[i - 1][j - 1] + cost, // 替换
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[len1][len2];
  }
}
