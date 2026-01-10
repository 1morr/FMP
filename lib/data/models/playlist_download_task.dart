import 'package:isar/isar.dart';

import 'download_task.dart';

part 'playlist_download_task.g.dart';

/// 歌单下载任务实体
@collection
class PlaylistDownloadTask {
  Id id = Isar.autoIncrement;

  /// 关联的歌单ID
  @Index()
  late int playlistId;

  /// 快照歌单名（防止歌单删除后显示异常）
  late String playlistName;

  /// 要下载的歌曲ID列表
  List<int> trackIds = [];

  /// 下载状态
  @Enumerated(EnumType.name)
  DownloadStatus status = DownloadStatus.pending;

  /// 排序优先级（越小越优先）
  int priority = 0;

  /// 创建时间
  DateTime createdAt = DateTime.now();

  /// 完成时间
  DateTime? completedAt;

  /// 是否正在下载
  @ignore
  bool get isDownloading => status == DownloadStatus.downloading;

  /// 是否已完成
  @ignore
  bool get isCompleted => status == DownloadStatus.completed;

  /// 是否失败
  @ignore
  bool get isFailed => status == DownloadStatus.failed;

  /// 是否等待中
  @ignore
  bool get isPending => status == DownloadStatus.pending;

  /// 是否已暂停
  @ignore
  bool get isPaused => status == DownloadStatus.paused;

  /// 歌曲总数
  @ignore
  int get totalTracks => trackIds.length;

  @override
  String toString() =>
      'PlaylistDownloadTask(playlistId: $playlistId, name: $playlistName, status: $status, tracks: ${trackIds.length})';
}
