import 'package:isar/isar.dart';

import '../models/lyrics_title_parse_cache.dart';

class LyricsTitleParseCacheRepository {
  final Isar _isar;

  LyricsTitleParseCacheRepository(this._isar);

  Future<LyricsTitleParseCache?> getReusable({
    required String trackUniqueKey,
  }) {
    return _isar.lyricsTitleParseCaches
        .where()
        .trackUniqueKeyEqualTo(trackUniqueKey)
        .findFirst();
  }

  Future<void> save({
    required String trackUniqueKey,
    required String sourceType,
    required String parsedTrackName,
    required String? parsedArtistName,
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
      ..parsedTrackName = parsedTrackName
      ..parsedArtistName = parsedArtistName
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
