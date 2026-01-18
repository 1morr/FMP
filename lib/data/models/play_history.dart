import 'package:isar/isar.dart';

import 'track.dart';

part 'play_history.g.dart';

/// 播放历史实体
/// 存储必要的显示信息，独立于 Track 表，以便历史记录可以独立显示
@collection
class PlayHistory {
  Id id = Isar.autoIncrement;

  /// 源平台的唯一ID (如 BV号, YouTube video ID)
  @Index()
  late String sourceId;

  /// 音源类型
  @Index()
  @Enumerated(EnumType.name)
  late SourceType sourceType;

  /// Bilibili cid（分P唯一标识）
  int? cid;

  /// 歌曲标题
  late String title;

  /// 艺术家/UP主名称
  String? artist;

  /// 时长（毫秒）
  int? durationMs;

  /// 封面图 URL
  String? thumbnailUrl;

  /// 播放时间
  @Index()
  DateTime playedAt = DateTime.now();

  /// 歌曲唯一标识（用于统计播放次数）
  String get trackKey => cid != null
      ? '${sourceType.name}:$sourceId:$cid'
      : '${sourceType.name}:$sourceId';

  /// 从 Track 创建播放历史记录
  static PlayHistory fromTrack(Track track) {
    return PlayHistory()
      ..sourceId = track.sourceId
      ..sourceType = track.sourceType
      ..cid = track.cid
      ..title = track.title
      ..artist = track.artist
      ..durationMs = track.durationMs
      ..thumbnailUrl = track.thumbnailUrl
      ..playedAt = DateTime.now();
  }

  /// 转换为临时 Track（用于播放）
  Track toTrack() {
    return Track()
      ..sourceId = sourceId
      ..sourceType = sourceType
      ..cid = cid
      ..title = title
      ..artist = artist
      ..durationMs = durationMs
      ..thumbnailUrl = thumbnailUrl;
  }

  /// 格式化时长显示
  String get formattedDuration {
    if (durationMs == null) return '--:--';
    final duration = Duration(milliseconds: durationMs!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() =>
      'PlayHistory(title: $title, artist: $artist, playedAt: $playedAt)';
}
