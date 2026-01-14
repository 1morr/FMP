import 'dart:io';

import '../../data/models/track.dart';
import '../utils/duration_formatter.dart';

/// Track 模型扩展方法
extension TrackExtensions on Track {
  /// 获取本地封面路径（基于第一个下载路径计算）
  ///
  /// 注意：此方法不检查文件是否存在，由 ImageLoadingService 处理回退逻辑
  String? get localCoverPath {
    if (firstDownloadPath == null) return null;
    final dir = Directory(firstDownloadPath!).parent;
    return '${dir.path}/cover.jpg';
  }

  /// 获取本地头像路径（基于第一个下载路径计算）
  ///
  /// 注意：此方法不检查文件是否存在，由 ImageLoadingService 处理回退逻辑
  String? get localAvatarPath {
    if (firstDownloadPath == null) return null;
    final dir = Directory(firstDownloadPath!).parent;
    return '${dir.path}/avatar.jpg';
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
