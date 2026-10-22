import 'package:isar_community/isar.dart';

part 'playlist.g.dart';

@collection
class Playlist {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String name;

  String? description;
  String? coverUrl;
  bool hasCustomCover = false;
  String? sourceUrl;
  String? importSourceType;
  int? refreshIntervalHours;
  DateTime? lastRefreshed;
  bool notifyOnUpdate = true;
  String? ownerName;
  String? ownerUserId;
  bool useAuthForRefresh = false;
  bool isMix = false;
  String? mixPlaylistId;
  String? mixSeedVideoId;

  /// 有序的 `Track.id`。
  List<int> trackIds = [];

  DateTime createdAt = DateTime.now();
  DateTime? updatedAt;

  @Index()
  int sortOrder = 0;

  // 下面三個 getter 在舊版沒標 @ignore，被存成欄位（schema 的一部分）；
  // 匯入不讀它們。
  bool get isImported => sourceUrl != null;
  int get trackCount => trackIds.length;
  bool get needsRefresh {
    if (!isImported || refreshIntervalHours == null) return false;
    if (lastRefreshed == null) return true;
    return DateTime.now().isAfter(
      lastRefreshed!.add(Duration(hours: refreshIntervalHours!)),
    );
  }
}
