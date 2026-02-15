import '../../core/logger.dart';
import '../../data/models/lyrics_match.dart';
import '../../data/models/track.dart';
import '../../data/repositories/lyrics_repository.dart';
import 'lrclib_source.dart';
import 'lyrics_cache_service.dart';
import 'lyrics_result.dart';
import 'netease_source.dart';
import 'qqmusic_source.dart';
import 'title_parser.dart';

/// 歌词自动匹配服务
///
/// 在播放歌曲时自动搜索并匹配歌词（仅当没有已匹配的歌词时）。
/// 匹配条件：
/// - 时长差距 ≤ 10 秒
/// - 只有一个结果符合时长条件时才自动匹配
class LyricsAutoMatchService with Logging {
  final LrclibSource _lrclib;
  final NeteaseSource _netease;
  final QQMusicSource _qqmusic;
  final LyricsRepository _repo;
  final LyricsCacheService _cache;
  final TitleParser _parser;

  LyricsAutoMatchService({
    required LrclibSource lrclib,
    required NeteaseSource netease,
    required QQMusicSource qqmusic,
    required LyricsRepository repo,
    required LyricsCacheService cache,
    required TitleParser parser,
  })  : _lrclib = lrclib,
        _netease = netease,
        _qqmusic = qqmusic,
        _repo = repo,
        _cache = cache,
        _parser = parser;

  /// 尝试自动匹配歌词
  ///
  /// 返回 true 表示成功匹配，false 表示未匹配（已有匹配、无结果、多个结果等）
  Future<bool> tryAutoMatch(Track track) async {
    try {
      // 1. 检查是否已有匹配
      final existingMatch = await _repo.getByTrackKey(track.uniqueKey);
      if (existingMatch != null) {
        logDebug('Track already has lyrics match: ${track.uniqueKey}');
        return false;
      }

      // 2. 解析标题和艺术家
      final parsed = _parser.parse(track.title);
      final trackName = parsed.trackName;
      final artistName = parsed.artistName ?? track.artist ?? '';

      if (trackName.isEmpty) {
        logDebug('Cannot parse track name: ${track.title}');
        return false;
      }

      logDebug('Auto-matching: "$trackName" by "$artistName"');

      // 3. 先尝试网易云搜索
      final neteaseMatch = await _tryNeteaseMatch(
        trackName, artistName, (track.durationMs ?? 0) ~/ 1000,
      );
      if (neteaseMatch != null) {
        await _cache.put(track.uniqueKey, neteaseMatch);
        final match = LyricsMatch()
          ..trackUniqueKey = track.uniqueKey
          ..lyricsSource = 'netease'
          ..externalId = neteaseMatch.id
          ..offsetMs = 0
          ..matchedAt = DateTime.now();
        await _repo.save(match);
        logInfo('Auto-matched lyrics: ${track.title} → netease:${neteaseMatch.id}');
        return true;
      }

      // 3.5. 尝试 QQ 音乐搜索
      final qqmusicMatch = await _tryQQMusicMatch(
        trackName, artistName, (track.durationMs ?? 0) ~/ 1000,
      );
      if (qqmusicMatch != null) {
        await _cache.put(track.uniqueKey, qqmusicMatch);
        final match = LyricsMatch()
          ..trackUniqueKey = track.uniqueKey
          ..lyricsSource = 'qqmusic'
          ..externalId = 0
          ..externalStringId = qqmusicMatch.externalStringId
          ..offsetMs = 0
          ..matchedAt = DateTime.now();
        await _repo.save(match);
        logInfo('Auto-matched lyrics: ${track.title} → qqmusic:${qqmusicMatch.externalStringId}');
        return true;
      }

      // 4. Fallback 到 lrclib
      final results = await _lrclib.search(
        trackName: trackName,
        artistName: artistName.isNotEmpty ? artistName : null,
      );

      if (results.isEmpty) {
        logDebug('No lyrics found for: $trackName');
        return false;
      }

      // 5. 过滤符合时长条件的结果（±10秒）
      final trackDurationSec = (track.durationMs ?? 0) ~/ 1000;
      final matchingResults = results.where((result) {
        final diff = (result.duration - trackDurationSec).abs();
        return diff <= 10;
      }).toList();

      if (matchingResults.isEmpty) {
        logDebug('No results match duration (${trackDurationSec}s): ${results.length} total');
        return false;
      }

      // 6. 如果有多个结果，选择最相似的
      final result = matchingResults.length == 1
          ? matchingResults.first
          : _selectBestMatch(matchingResults, trackName, artistName, trackDurationSec);

      if (result == null) {
        logDebug('No confident match found among ${matchingResults.length} candidates');
        return false;
      }

      logDebug('Selected best match: "${result.trackName}" by "${result.artistName}" (score: ${_calculateScore(result, trackName, artistName, trackDurationSec).toStringAsFixed(2)})');

      // 7. 先缓存歌词内容（在保存匹配之前）
      await _cache.put(track.uniqueKey, result);

      // 8. 保存匹配记录
      final match = LyricsMatch()
        ..trackUniqueKey = track.uniqueKey
        ..lyricsSource = 'lrclib'
        ..externalId = result.id
        ..offsetMs = 0
        ..matchedAt = DateTime.now();

      await _repo.save(match);

      logInfo('Auto-matched lyrics: ${track.title} → lrclib:${result.id}');
      return true;
    } catch (e) {
      logError('Auto-match failed for ${track.uniqueKey}: $e');
      return false;
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

      // 过滤符合时长条件的结果（±10秒）
      final matching = results.where((r) {
        if (r.duration == 0) return true; // 网易云有时不返回时长
        return (r.duration - trackDurationSec).abs() <= 10;
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

      // 过滤符合时长条件的结果（±10秒）
      final matching = results.where((r) {
        if (r.duration == 0) return true;
        return (r.duration - trackDurationSec).abs() <= 10;
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
      final score = _calculateScore(result, trackName, artistName, trackDurationSec);
      return (result: result, score: score);
    }).toList();

    // 按得分降序排序
    scored.sort((a, b) => b.score.compareTo(a.score));

    // 只有当最高分 >= 0.6 时才认为是可信的匹配
    final best = scored.first;
    if (best.score >= 0.6) {
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
    final durationScore = durationDiff <= 2
        ? 1.0
        : durationDiff <= 5
            ? 0.8
            : durationDiff <= 10
                ? 0.5
                : 0.0;

    // 4. 是否有同步歌词（权重 10%）
    final syncedScore = result.syncedLyrics != null && result.syncedLyrics!.isNotEmpty
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
