import 'package:isar_community/isar.dart';

part 'download_task.g.dart';

/// 下載狀態；磁碟上存 `name`（字串）。
enum DownloadStatus { pending, downloading, paused, completed, failed }

@collection
class DownloadTask {
  Id id = Isar.autoIncrement;

  @Index()
  late int trackId;

  int? playlistId;
  String? playlistName;

  @Index()
  String? savePath;

  @Index()
  @Enumerated(EnumType.name)
  DownloadStatus status = DownloadStatus.pending;

  double progress = 0.0;
  int downloadedBytes = 0;
  int? totalBytes;
  String? errorMessage;
  String? tempFilePath;

  @Index()
  int priority = 0;

  DateTime createdAt = DateTime.now();
  DateTime? completedAt;
}
