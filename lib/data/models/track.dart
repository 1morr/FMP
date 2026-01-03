import 'package:isar/isar.dart';

part 'track.g.dart';

/// 音源类型枚举
enum SourceType {
  bilibili,
  youtube,
}

/// 歌曲/音频实体
@collection
class Track {
  Id id = Isar.autoIncrement;

  /// 源平台的唯一ID (如 BV号, YouTube video ID)
  @Index()
  late String sourceId;

  /// 音源类型
  @Index()
  @Enumerated(EnumType.name)
  late SourceType sourceType;

  /// 歌曲标题
  late String title;

  /// 艺术家/UP主名称
  String? artist;

  /// 时长（毫秒）
  int? durationMs;

  /// 封面图 URL
  String? thumbnailUrl;

  /// 音频 URL（可能会过期，需要重新获取）
  String? audioUrl;

  /// 音频 URL 过期时间
  DateTime? audioUrlExpiry;

  /// 是否可用
  bool isAvailable = true;

  /// 不可用原因
  String? unavailableReason;

  /// 流媒体缓存路径
  String? cachedPath;

  /// 离线下载路径
  String? downloadedPath;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 更新时间
  DateTime? updatedAt;

  /// 复合索引用于快速查找
  @Index(composite: [CompositeIndex('sourceType')])
  String get sourceKey => '${sourceType.name}:$sourceId';

  /// 检查音频 URL 是否有效
  bool get hasValidAudioUrl {
    if (audioUrl == null) return false;
    if (audioUrlExpiry == null) return true;
    return DateTime.now().isBefore(audioUrlExpiry!);
  }

  /// 是否已下载
  bool get isDownloaded => downloadedPath != null;

  /// 是否已缓存
  bool get isCached => cachedPath != null;

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
  String toString() => 'Track(id: $id, title: $title, artist: $artist, source: $sourceType)';
}
