import 'package:isar_community/isar.dart';

part 'track.g.dart';

/// 歌單歸屬與下載路徑（嵌入物件）。`playlistId` 為 0 是掃描器發現的本機檔案。
@embedded
class PlaylistDownloadInfo {
  int playlistId = 0;
  String playlistName = '';

  /// 空字串＝未下載；非空是絕對路徑。
  String downloadPath = '';

  PlaylistDownloadInfo();

  /// 舊版沒標 @ignore，被存成欄位（schema 的一部分）；匯入不讀它。
  bool get isDownloaded => downloadPath.isNotEmpty;
}

@collection
class Track {
  Id id = Isar.autoIncrement;

  @Index()
  late String sourceId;

  @Index()
  late String sourceType;

  late String title;
  String? artist;
  int? ownerId;
  String? channelId;
  int? durationMs;
  String? thumbnailUrl;

  /// 過期的簽名串流網址；匯入不讀。
  String? audioUrl;
  DateTime? audioUrlExpiry;

  bool isAvailable = true;
  bool isVip = false;
  String? unavailableReason;
  List<PlaylistDownloadInfo> playlistInfo = [];

  /// 分 P 總數。
  int? pageCount;

  @Index()
  int? cid;

  int? pageNum;
  String? parentTitle;
  int? bilibiliAid;
  String? originalSongId;
  String? originalSource;
  DateTime createdAt = DateTime.now();

  @Index()
  DateTime? updatedAt;

  // 下面的 getter 在舊版沒標 @ignore，被存成欄位（schema 的一部分）；它們是
  // 推導值（有的還和時間有關），匯入不讀。
  @Index(composite: [CompositeIndex('cid')])
  String get sourcePageKey =>
      cid != null ? '$sourceType:$sourceId:$cid' : '$sourceType:$sourceId';

  bool get hasValidAudioUrl {
    if (audioUrl == null) return false;
    final expiry = audioUrlExpiry;
    if (expiry == null) return true;
    return DateTime.now().isBefore(expiry.subtract(const Duration(minutes: 5)));
  }

  bool get isPartOfMultiPage => (pageCount ?? 0) > 1;
  String get groupKey => '$sourceType:$sourceId';
  String get uniqueKey => sourcePageKey;
  String get formattedDuration => durationMs == null ? '--:--' : '$durationMs';
}
