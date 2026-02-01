import 'package:isar/isar.dart';

import 'track.dart'; // for SourceType enum

part 'radio_station.g.dart';

/// 電台/直播間實體
@collection
class RadioStation {
  Id id = Isar.autoIncrement;

  /// 原始直播間 URL
  @Index(unique: true)
  late String url;

  /// 電台名稱（自動獲取+可編輯）
  late String title;

  /// 封面圖片 URL
  String? thumbnailUrl;

  /// 主播/頻道名稱
  String? hostName;

  /// 主播頭像 URL
  String? hostAvatarUrl;

  /// 音源類型 (bilibili, youtube)
  @Index()
  @Enumerated(EnumType.name)
  late SourceType sourceType;

  /// 源平台的房間/視頻 ID (roomId for Bilibili, videoId for YouTube)
  @Index()
  late String sourceId;

  /// 排序順序（數字越小越靠前）
  @Index()
  int sortOrder = 0;

  /// 創建時間
  DateTime createdAt = DateTime.now();

  /// 最後播放時間
  DateTime? lastPlayedAt;

  /// 是否已收藏/置頂
  bool isFavorite = false;

  /// 額外備註
  String? note;

  /// 獲取唯一鍵（用於去重）
  String get uniqueKey => '${sourceType.name}:$sourceId';

  @override
  String toString() =>
      'RadioStation(id: $id, title: $title, sourceType: ${sourceType.name}, sourceId: $sourceId)';
}
