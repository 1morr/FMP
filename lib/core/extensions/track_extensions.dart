import 'dart:io';

import '../../data/models/track.dart';
import '../utils/duration_formatter.dart';

/// Track 模型扩展方法
extension TrackExtensions on Track {
  /// 获取本地封面路径（遍历所有下载路径查找）
  ///
  /// 返回第一个存在 cover.jpg 的目录路径
  String? get localCoverPath {
    if (downloadPaths.isEmpty) return null;
    
    for (final downloadPath in downloadPaths) {
      final dir = Directory(downloadPath).parent;
      final coverPath = '${dir.path}/cover.jpg';
      if (File(coverPath).existsSync()) {
        return coverPath;
      }
    }
    
    // 如果都不存在，返回第一个路径的封面路径（由 ImageLoadingService 处理回退）
    final firstDir = Directory(downloadPaths.first).parent;
    return '${firstDir.path}/cover.jpg';
  }

  /// 获取本地头像路径（遍历所有下载路径查找）
  ///
  /// 返回第一个存在 avatar.jpg 的目录路径
  String? get localAvatarPath {
    if (downloadPaths.isEmpty) return null;
    
    for (final downloadPath in downloadPaths) {
      final dir = Directory(downloadPath).parent;
      final avatarPath = '${dir.path}/avatar.jpg';
      if (File(avatarPath).existsSync()) {
        return avatarPath;
      }
    }
    
    // 如果都不存在，返回第一个路径的头像路径（由 ImageLoadingService 处理回退）
    final firstDir = Directory(downloadPaths.first).parent;
    return '${firstDir.path}/avatar.jpg';
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
