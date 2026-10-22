import 'package:isar_community/isar.dart';

part 'lyrics_title_parse_cache.g.dart';

/// 舊版的 AI 標題解析快取。匯入不讀它，只為了開庫時 schema 完整。
@collection
class LyricsTitleParseCache {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String trackUniqueKey;

  late String sourceType;
  late String parsedTrackName;
  String? parsedArtistName;
  double confidence = 0;
  late String provider;
  late String model;
  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
}
