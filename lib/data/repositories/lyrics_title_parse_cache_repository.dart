import 'package:isar/isar.dart';

import '../models/lyrics_title_parse_cache.dart';

class LyricsTitleParseCacheRepository {
  static const int durationToleranceMs = 2000;

  final Isar _isar;

  LyricsTitleParseCacheRepository(this._isar);

  Future<LyricsTitleParseCache?> getReusable({
    required String trackUniqueKey,
    required String originalTitle,
    required String? originalArtist,
    required int? durationMs,
  }) async {
    final cached = await _isar.lyricsTitleParseCaches
        .where()
        .trackUniqueKeyEqualTo(trackUniqueKey)
        .findFirst();
    if (cached == null) return null;
    if (cached.originalTitle != originalTitle) return null;
    if ((cached.originalArtist ?? '') != (originalArtist ?? '')) return null;
    final cachedDuration = cached.durationMs;
    if (cachedDuration != null && durationMs != null) {
      if ((cachedDuration - durationMs).abs() > durationToleranceMs) {
        return null;
      }
    }
    return cached;
  }

  Future<void> save({
    required String trackUniqueKey,
    required String sourceType,
    required String originalTitle,
    required String? originalArtist,
    required int? durationMs,
    required String parsedTrackName,
    required String? parsedArtistName,
    required List<String> alternativeTrackNames,
    required List<String> alternativeArtistNames,
    required double confidence,
    required String provider,
    required String model,
  }) async {
    final existing = await _isar.lyricsTitleParseCaches
        .where()
        .trackUniqueKeyEqualTo(trackUniqueKey)
        .findFirst();
    final now = DateTime.now();
    final cache = existing ?? LyricsTitleParseCache();
    cache
      ..trackUniqueKey = trackUniqueKey
      ..sourceType = sourceType
      ..originalTitle = originalTitle
      ..originalArtist = originalArtist
      ..durationMs = durationMs
      ..parsedTrackName = parsedTrackName
      ..parsedArtistName = parsedArtistName
      ..alternativeTrackNames = alternativeTrackNames
      ..alternativeArtistNames = alternativeArtistNames
      ..confidence = confidence
      ..provider = provider
      ..model = model
      ..createdAt = existing?.createdAt ?? now
      ..updatedAt = now;
    await _isar.writeTxn(() => _isar.lyricsTitleParseCaches.put(cache));
  }

  Future<void> clear() async {
    await _isar.writeTxn(() => _isar.lyricsTitleParseCaches.clear());
  }
}
