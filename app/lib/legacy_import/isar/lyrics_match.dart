import 'package:isar_community/isar.dart';

part 'lyrics_match.g.dart';

@collection
class LyricsMatch {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String trackUniqueKey;

  late String lyricsSource;
  late String externalId;
  int offsetMs = 0;
  DateTime matchedAt = DateTime.now();
}
