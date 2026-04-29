import 'package:isar/isar.dart';

part 'lyrics_title_parse_cache.g.dart';

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
