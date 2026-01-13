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

  /// 离线下载路径（已废弃，保留用于数据迁移）
  /// 新系统使用 downloadedPlaylistIds + downloadedPaths
  @Deprecated('Use getDownloadedPath(playlistId) instead')
  String? downloadedPath;

  // ========== 多路径下载支持 ==========

  /// 已下载的歌单ID列表（与 downloadedPaths 并行）
  List<int> downloadedPlaylistIds = [];

  /// 已下载的路径列表（与 downloadedPlaylistIds 并行）
  List<String> downloadedPaths = [];

  /// 获取指定歌单的下载路径
  String? getDownloadedPath(int playlistId) {
    final index = downloadedPlaylistIds.indexOf(playlistId);
    return index >= 0 ? downloadedPaths[index] : null;
  }

  /// 设置指定歌单的下载路径
  void setDownloadedPath(int playlistId, String path) {
    final index = downloadedPlaylistIds.indexOf(playlistId);
    if (index >= 0) {
      downloadedPaths[index] = path;
    } else {
      downloadedPlaylistIds = List.from(downloadedPlaylistIds)..add(playlistId);
      downloadedPaths = List.from(downloadedPaths)..add(path);
    }
  }

  /// 移除指定歌单的下载路径
  void removeDownloadedPath(int playlistId) {
    final index = downloadedPlaylistIds.indexOf(playlistId);
    if (index >= 0) {
      downloadedPlaylistIds = List.from(downloadedPlaylistIds)..removeAt(index);
      downloadedPaths = List.from(downloadedPaths)..removeAt(index);
    }
  }

  /// 检查指定歌单是否已下载
  bool isDownloadedInPlaylist(int playlistId) {
    return downloadedPlaylistIds.contains(playlistId);
  }

  /// 检查是否有任何下载
  @ignore
  bool get hasAnyDownload => downloadedPaths.isNotEmpty;

  /// 获取第一个有效的下载路径（用于播放）
  @ignore
  String? get firstDownloadedPath =>
      downloadedPaths.isNotEmpty ? downloadedPaths.first : null;

  /// 播放量/观看数（仅用于搜索结果显示，不持久化）
  @ignore
  int? viewCount;

  /// 分P总数（仅用于导入时判断是否需要展开，不持久化）
  @ignore
  int? pageCount;

  /// 在歌单中的顺序（仅用于已下载页面排序，不持久化）
  @ignore
  int? order;

  // ========== 分P相关字段 ==========

  /// Bilibili cid（分P唯一标识）
  int? cid;

  /// 分P序号 (1, 2, 3...)，null表示单P或未获取分P信息
  int? pageNum;

  /// 父视频标题（用于分组显示时的标题）
  String? parentTitle;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 更新时间
  DateTime? updatedAt;

  /// 复合索引用于快速查找
  @Index(composite: [CompositeIndex('sourceType')])
  String get sourceKey => '${sourceType.name}:$sourceId';

  /// 分P唯一索引（用于查找特定分P）
  @Index(composite: [CompositeIndex('cid')])
  String get sourcePageKey => cid != null
      ? '${sourceType.name}:$sourceId:$cid'
      : '${sourceType.name}:$sourceId';

  /// 检查音频 URL 是否有效
  bool get hasValidAudioUrl {
    if (audioUrl == null) return false;
    if (audioUrlExpiry == null) return true;
    return DateTime.now().isBefore(audioUrlExpiry!);
  }

  /// 是否已下载（兼容旧代码，检查是否有任何下载）
  @Deprecated('Use isDownloadedInPlaylist(playlistId) or hasAnyDownload instead')
  bool get isDownloaded => hasAnyDownload || downloadedPath != null;

  /// 是否已缓存
  bool get isCached => cachedPath != null;

  /// 是否是多P视频中的一个分P
  bool get isPartOfMultiPage => pageNum != null && pageNum! > 0;

  /// 用于分组的key（同一视频的分P有相同的key）
  String get groupKey => '${sourceType.name}:$sourceId';

  /// 唯一标识（包含cid用于区分分P）
  String get uniqueKey => cid != null
      ? '${sourceType.name}:$sourceId:$cid'
      : '${sourceType.name}:$sourceId';

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

  /// 创建用于添加到队列的副本（重置id，确保每次添加都创建新记录）
  Track copyForQueue() {
    return Track()
      ..sourceId = sourceId
      ..sourceType = sourceType
      ..title = title
      ..artist = artist
      ..durationMs = durationMs
      ..thumbnailUrl = thumbnailUrl
      ..audioUrl = audioUrl
      ..audioUrlExpiry = audioUrlExpiry
      ..isAvailable = isAvailable
      ..unavailableReason = unavailableReason
      ..cachedPath = cachedPath
      // ignore: deprecated_member_use_from_same_package
      ..downloadedPath = downloadedPath
      ..downloadedPlaylistIds = List.from(downloadedPlaylistIds)
      ..downloadedPaths = List.from(downloadedPaths)
      ..cid = cid
      ..pageNum = pageNum
      ..parentTitle = parentTitle
      ..createdAt = DateTime.now();
  }

  @override
  String toString() => 'Track(id: $id, title: $title, artist: $artist, source: $sourceType)';
}
