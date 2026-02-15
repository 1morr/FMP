import 'package:isar/isar.dart';

part 'lyrics_match.g.dart';

/// 歌词匹配记录
///
/// 存储 Track 与 lrclib 歌词的匹配关系。
/// 不保存歌词内容，每次通过 [externalId] 在线获取。
@collection
class LyricsMatch {
  Id id = Isar.autoIncrement;

  /// Track 唯一标识（Track.uniqueKey: "sourceType:sourceId" 或 "sourceType:sourceId:cid"）
  @Index(unique: true, replace: true)
  late String trackUniqueKey;

  /// 歌词源标识（"lrclib", 未来: "netease", "qqmusic"）
  late String lyricsSource;

  /// 歌词源中的外部 ID
  late int externalId;

  /// 用户自定义偏移（毫秒）
  int offsetMs = 0;

  /// 匹配时间
  DateTime matchedAt = DateTime.now();
}
