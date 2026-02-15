import '../../core/logger.dart';
import '../../data/models/lyrics_match.dart';
import '../../data/models/track.dart';
import '../../data/repositories/lyrics_repository.dart';
import 'lrclib_source.dart';
import 'lyrics_cache_service.dart';
import 'title_parser.dart';

/// 歌词自动匹配服务
///
/// 在播放歌曲时自动搜索并匹配歌词（仅当没有已匹配的歌词时）。
/// 匹配条件：
/// - 时长差距 ≤ 10 秒
/// - 只有一个结果符合时长条件时才自动匹配
class LyricsAutoMatchService with Logging {
  final LrclibSource _lrclib;
  final LyricsRepository _repo;
  final LyricsCacheService _cache;
  final TitleParser _parser;

  LyricsAutoMatchService({
    required LrclibSource lrclib,
    required LyricsRepository repo,
    required LyricsCacheService cache,
    required TitleParser parser,
  })  : _lrclib = lrclib,
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

      // 3. 搜索歌词
      final results = await _lrclib.search(
        trackName: trackName,
        artistName: artistName.isNotEmpty ? artistName : null,
      );

      if (results.isEmpty) {
        logDebug('No lyrics found for: $trackName');
        return false;
      }

      // 4. 过滤符合时长条件的结果（±10秒）
      final trackDurationSec = (track.durationMs ?? 0) ~/ 1000;
      final matchingResults = results.where((result) {
        final diff = (result.duration - trackDurationSec).abs();
        return diff <= 10;
      }).toList();

      if (matchingResults.isEmpty) {
        logDebug('No results match duration (${trackDurationSec}s): ${results.length} total');
        return false;
      }

      if (matchingResults.length > 1) {
        logDebug('Multiple results match duration: ${matchingResults.length}, skipping auto-match');
        return false;
      }

      // 5. 只有一个结果符合条件，自动匹配
      final result = matchingResults.first;
      final match = LyricsMatch()
        ..trackUniqueKey = track.uniqueKey
        ..lyricsSource = 'lrclib'
        ..externalId = result.id
        ..offsetMs = 0
        ..matchedAt = DateTime.now();

      await _repo.save(match);

      // 6. 立即缓存歌词内容
      await _cache.put(track.uniqueKey, result);

      logInfo('Auto-matched lyrics: ${track.title} → lrclib:${result.id}');
      return true;
    } catch (e) {
      logError('Auto-match failed for ${track.uniqueKey}: $e');
      return false;
    }
  }
}
