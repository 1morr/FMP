import 'package:isar_community/isar.dart';

part 'play_history.g.dart';

@collection
class PlayHistory {
  Id id = Isar.autoIncrement;

  @Index()
  late String sourceId;

  @Index()
  late String sourceType;

  int? cid;
  late String title;
  String? artist;
  int? durationMs;
  String? thumbnailUrl;

  @Index()
  DateTime playedAt = DateTime.now();

  /// 舊版把這個 getter 存成欄位並建索引（schema 的一部分）；匯入不讀它，由
  /// `sourceType`／`sourceId`／`cid` 重算。
  @Index()
  String get trackKey =>
      cid != null ? '$sourceType:$sourceId:$cid' : '$sourceType:$sourceId';
}
