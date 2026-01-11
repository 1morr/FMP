import 'dart:io';

import '../../data/models/track.dart';
import '../utils/duration_formatter.dart';

/// Track 模型扩展方法
extension TrackExtensions on Track {
  /// 获取本地封面路径（如果存在）
  String? get localCoverPath {
    if (downloadedPath == null) return null;
    final dir = Directory(downloadedPath!).parent;
    final coverPath = '${dir.path}/cover.jpg';
    return File(coverPath).existsSync() ? coverPath : null;
  }

  /// 获取本地头像路径（如果存在）
  String? get localAvatarPath {
    if (downloadedPath == null) return null;
    final dir = Directory(downloadedPath!).parent;
    final avatarPath = '${dir.path}/avatar.jpg';
    return File(avatarPath).existsSync() ? avatarPath : null;
  }

  /// 格式化时长显示
  String get formattedDuration {
    if (durationMs == null) return '--:--';
    return DurationFormatter.formatMs(durationMs!);
  }

  /// 是否有本地封面
  bool get hasLocalCover => localCoverPath != null;

  /// 是否有网络封面
  bool get hasNetworkCover => thumbnailUrl != null && thumbnailUrl!.isNotEmpty;

  /// 是否有任何封面（本地或网络）
  bool get hasCover => hasLocalCover || hasNetworkCover;
}
