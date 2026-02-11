import 'package:isar/isar.dart';

part 'track.g.dart';

/// 音源类型枚举
enum SourceType {
  bilibili,
  youtube,
}

/// 歌单归属与下载路径信息（嵌入式对象）
@embedded
class PlaylistDownloadInfo {
  /// 所属歌单ID
  int playlistId = 0;

  /// 所属歌单名称（用于下载路径匹配，歌单重命名时需同步更新）
  String playlistName = '';

  /// 下载路径（空字符串表示未下载）
  String downloadPath = '';

  PlaylistDownloadInfo();

  /// 是否已下载
  bool get isDownloaded => downloadPath.isNotEmpty;

  @override
  String toString() =>
      'PlaylistDownloadInfo(playlistId: $playlistId, name: $playlistName, downloadPath: $downloadPath)';
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

  /// Bilibili UP主 ID（用於頭像查找）
  int? ownerId;

  /// YouTube 頻道 ID（用於頭像查找）
  String? channelId;

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

  // ========== 歌单归属与下载路径（使用 @embedded PlaylistDownloadInfo）==========

  /// 歌单归属与下载信息列表
  List<PlaylistDownloadInfo> playlistInfo = [];

  // ========== 新的辅助方法 ==========

  /// 获取指定歌单的下载路径（优先按名称匹配，兼容旧数据按ID匹配）
  String? getDownloadPath(int playlistId, {String? playlistName}) {
    // 优先按名称匹配
    if (playlistName != null && playlistName.isNotEmpty) {
      for (final info in playlistInfo) {
        if (info.playlistName == playlistName && info.downloadPath.isNotEmpty) {
          return info.downloadPath;
        }
      }
    }
    // 降级按 ID 匹配（兼容旧数据）
    for (final info in playlistInfo) {
      if (info.playlistId == playlistId && info.downloadPath.isNotEmpty) {
        return info.downloadPath;
      }
    }
    return null;
  }

  /// 设置指定歌单的下载路径
  ///
  /// 注意：必须创建新的列表和对象，否则 Isar 无法检测到 @embedded 对象的变更
  void setDownloadPath(int playlistId, String path, {String? playlistName}) {
    final newInfos = <PlaylistDownloadInfo>[];
    bool found = false;

    for (final info in playlistInfo) {
      if (info.playlistId == playlistId) {
        // 创建新对象以确保 Isar 检测到变更
        newInfos.add(PlaylistDownloadInfo()
          ..playlistId = playlistId
          ..playlistName = playlistName ?? info.playlistName
          ..downloadPath = path);
        found = true;
      } else {
        // 复制现有对象
        newInfos.add(PlaylistDownloadInfo()
          ..playlistId = info.playlistId
          ..playlistName = info.playlistName
          ..downloadPath = info.downloadPath);
      }
    }

    if (!found) {
      // 如果不在任何歌单中，添加新条目
      newInfos.add(PlaylistDownloadInfo()
        ..playlistId = playlistId
        ..playlistName = playlistName ?? ''
        ..downloadPath = path);
    }

    playlistInfo = newInfos;
  }

  /// 从歌单中移除（同时移除下载路径关联）
  void removeFromPlaylist(int playlistId) {
    playlistInfo =
        List.from(playlistInfo)..removeWhere((i) => i.playlistId == playlistId);
  }

  /// 检查是否属于指定歌单
  bool belongsToPlaylist(int playlistId) {
    return playlistInfo.any((i) => i.playlistId == playlistId);
  }

  /// 添加到歌单（不影响下载路径）
  void addToPlaylist(int playlistId, {String? playlistName}) {
    if (!belongsToPlaylist(playlistId)) {
      playlistInfo = List.from(playlistInfo)
        ..add(PlaylistDownloadInfo()
          ..playlistId = playlistId
          ..playlistName = playlistName ?? '');
    }
  }

  /// 检查是否已为指定歌单下载（优先按名称匹配，兼容旧数据按ID匹配）
  bool isDownloadedForPlaylist(int playlistId, {String? playlistName}) {
    // 优先按名称匹配
    if (playlistName != null && playlistName.isNotEmpty) {
      final byName = playlistInfo.where((i) => i.playlistName == playlistName).firstOrNull;
      if (byName != null && byName.downloadPath.isNotEmpty) {
        return true;
      }
    }
    // 降级按 ID 匹配（兼容旧数据）
    final byId = playlistInfo.where((i) => i.playlistId == playlistId).firstOrNull;
    return byId != null && byId.downloadPath.isNotEmpty;
  }

  /// 清除所有下载路径（保留歌单关联）
  ///
  /// 注意：必须创建新的列表和对象，否则 Isar 无法检测到 @embedded 对象的变更
  void clearAllDownloadPaths() {
    playlistInfo = playlistInfo
        .map((info) => PlaylistDownloadInfo()
          ..playlistId = info.playlistId
          ..playlistName = info.playlistName
          ..downloadPath = '')
        .toList();
  }

  /// 清除指定歌单的下载路径（保留歌单关联）
  ///
  /// 注意：必须创建新的列表和对象，否则 Isar 无法检测到 @embedded 对象的变更
  void clearDownloadPathForPlaylist(int playlistId) {
    playlistInfo = playlistInfo
        .map((info) => PlaylistDownloadInfo()
          ..playlistId = info.playlistId
          ..playlistName = info.playlistName
          ..downloadPath = info.playlistId == playlistId ? '' : info.downloadPath)
        .toList();
  }

  // ========== @ignore 便捷 getters ==========

  /// 所有歌单ID列表
  @ignore
  List<int> get allPlaylistIds => playlistInfo.map((i) => i.playlistId).toList();

  /// 所有下载路径列表（不含空字符串）
  @ignore
  List<String> get allDownloadPaths =>
      playlistInfo.map((i) => i.downloadPath).where((p) => p.isNotEmpty).toList();

  /// 是否有任何下载
  @ignore
  bool get hasAnyDownload => playlistInfo.any((i) => i.downloadPath.isNotEmpty);

  /// 播放量/观看数（仅用于搜索结果显示，不持久化）
  @ignore
  int? viewCount;

  /// 分P总数（用于判断是否是多P视频）
  int? pageCount;

  // ========== 分P相关字段 ==========

  /// Bilibili cid（分P唯一标识）
  int? cid;

  /// 分P序号 (1, 2, 3...)，null表示单P或未获取分P信息
  int? pageNum;

  /// 父视频标题（用于分组显示时的标题）
  String? parentTitle;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 更新时间（添加索引用于已下载排序查询优化）
  @Index()
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

  /// 是否是多P视频中的一个分P
  ///
  /// 判断依据是 pageCount > 1，而非 pageNum != null
  /// 因为单P视频也可能有 pageNum = 1（为了保持一致性）
  bool get isPartOfMultiPage => (pageCount ?? 0) > 1;

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

  @override
  String toString() => 'Track(id: $id, title: $title, artist: $artist, source: $sourceType)';
}