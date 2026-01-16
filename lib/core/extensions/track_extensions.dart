import 'dart:io';

import '../../data/models/track.dart';
import '../utils/duration_formatter.dart';

/// Track 模型扩展方法
extension TrackExtensions on Track {
  /// 获取本地封面路径（仅返回存在的文件）
  ///
  /// 遍历所有下载路径，返回第一个存在 cover.jpg 的路径
  /// 如果都不存在，返回 null
  String? get localCoverPath {
    if (downloadPaths.isEmpty) return null;

    for (final downloadPath in downloadPaths) {
      final dir = Directory(downloadPath).parent;
      final coverPath = '${dir.path}/cover.jpg';
      if (File(coverPath).existsSync()) {
        return coverPath;
      }
    }
    return null;
  }

  /// 获取本地头像路径（仅返回存在的文件）
  ///
  /// 遍历所有下载路径，返回第一个存在 avatar.jpg 的路径
  /// 如果都不存在，返回 null
  String? get localAvatarPath {
    if (downloadPaths.isEmpty) return null;

    for (final downloadPath in downloadPaths) {
      final dir = Directory(downloadPath).parent;
      final avatarPath = '${dir.path}/avatar.jpg';
      if (File(avatarPath).existsSync()) {
        return avatarPath;
      }
    }
    return null;
  }

  /// 格式化时长显示
  String get formattedDuration {
    if (durationMs == null) return '--:--';
    return DurationFormatter.formatMs(durationMs!);
  }

  /// 是否有本地封面（文件实际存在）
  bool get hasLocalCover => localCoverPath != null;

  /// 是否有网络封面
  bool get hasNetworkCover => thumbnailUrl != null && thumbnailUrl!.isNotEmpty;

  /// 是否有任何封面（本地或网络）
  bool get hasCover => hasLocalCover || hasNetworkCover;

  /// 获取本地音频路径（仅返回存在的文件）
  ///
  /// 遍历所有下载路径，返回第一个实际存在的音频文件路径
  /// 如果都不存在，返回 null
  String? get localAudioPath {
    if (downloadPaths.isEmpty) return null;

    for (final downloadPath in downloadPaths) {
      if (File(downloadPath).existsSync()) {
        return downloadPath;
      }
    }
    return null;
  }

  /// 是否有本地音频文件（文件实际存在）
  bool get hasLocalAudio => localAudioPath != null;

  /// 是否已下载（任意歌单中的文件存在）
  bool get isDownloaded => hasLocalAudio;
}
