import 'package:isar_community/isar.dart';

part 'radio_station.g.dart';

@collection
class RadioStation {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String url;

  late String title;
  String? thumbnailUrl;
  String? hostName;
  String? hostAvatarUrl;
  int? hostUid;

  @Index()
  late String sourceType;

  @Index()
  late String sourceId;

  @Index()
  int sortOrder = 0;

  DateTime createdAt = DateTime.now();
  DateTime? lastPlayedAt;

  @Index()
  bool isFavorite = false;

  /// 舊版沒標 @ignore，被存成欄位（schema 的一部分）；匯入不讀它。
  String get uniqueKey => '$sourceType:$sourceId';
}
