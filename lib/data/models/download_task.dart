import 'package:isar/isar.dart';

part 'download_task.g.dart';

/// 下载状态枚举
enum DownloadStatus {
  /// 等待中
  pending,

  /// 下载中
  downloading,

  /// 已暂停
  paused,

  /// 已完成
  completed,

  /// 失败
  failed,
}

/// 下载任务实体
@collection
class DownloadTask {
  Id id = Isar.autoIncrement;

  /// 关联的歌曲ID
  @Index()
  late int trackId;

  /// 所属歌单下载任务ID（null=独立单曲任务）
  @Index()
  int? playlistDownloadTaskId;

  /// 下载状态
  @Enumerated(EnumType.name)
  DownloadStatus status = DownloadStatus.pending;

  /// 下载进度 (0.0 - 1.0)
  double progress = 0.0;

  /// 已下载字节数
  int downloadedBytes = 0;

  /// 总字节数
  int? totalBytes;

  /// 错误信息
  String? errorMessage;

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

  /// 是否是歌单任务中的一部分
  @ignore
  bool get isPartOfPlaylist => playlistDownloadTaskId != null;

  /// 格式化进度显示
  @ignore
  String get formattedProgress => '${(progress * 100).toStringAsFixed(1)}%';

  @override
  String toString() =>
      'DownloadTask(trackId: $trackId, status: $status, progress: $formattedProgress)';
}
