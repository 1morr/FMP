import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/track.dart';
import '../../providers/download/file_exists_cache.dart';
import '../utils/duration_formatter.dart';

/// Track 模型扩展方法
extension TrackExtensions on Track {
  /// 获取本地封面路径（使用缓存，适用于 UI 组件）
  ///
  /// 遍历所有下载路径，返回第一个存在 cover.jpg 的路径
  /// 如果都不存在，返回 null
  ///
  /// [cache] FileExistsCache 实例，从 ref.read(fileExistsCacheProvider.notifier) 获取
  String? getLocalCoverPath(FileExistsCache cache) {
    if (downloadPaths.isEmpty) return null;

    final coverPaths = downloadPaths.map((p) {
      final dir = Directory(p).parent;
      return '${dir.path}/cover.jpg';
    }).toList();

    return cache.getFirstExisting(coverPaths);
  }

  /// 獲取本地頭像路徑（使用集中式頭像文件夾）
  ///
  /// 頭像存儲在 {baseDir}/avatars/{platform}/{creatorId}.jpg
  /// - Bilibili: avatars/bilibili/{ownerId}.jpg
  /// - YouTube: avatars/youtube/{channelId}.jpg
  ///
  /// [cache] FileExistsCache 實例
  /// [baseDir] 下載基礎目錄，從 downloadBaseDirProvider 獲取
  String? getLocalAvatarPath(FileExistsCache cache, {String? baseDir}) {
    if (baseDir == null) return null;

    // 獲取創作者 ID
    final creatorId = sourceType == SourceType.bilibili
        ? ownerId?.toString()
        : channelId;

    // 如果沒有創作者 ID，無法查找頭像
    if (creatorId == null || creatorId.isEmpty || creatorId == '0') {
      return null;
    }

    // 構建集中式頭像路徑
    final platform = sourceType == SourceType.bilibili ? 'bilibili' : 'youtube';
    final avatarPath = p.join(baseDir, 'avatars', platform, '$creatorId.jpg');

    // 使用緩存檢查文件是否存在
    return cache.exists(avatarPath) ? avatarPath : null;
  }

  /// 格式化时长显示
  String get formattedDuration {
    if (durationMs == null) return '--:--';
    return DurationFormatter.formatMs(durationMs!);
  }

  /// 是否有网络封面
  bool get hasNetworkCover => thumbnailUrl != null && thumbnailUrl!.isNotEmpty;

  /// 获取本地音频路径（仅返回存在的文件）
  ///
  /// 遍历所有下载路径，返回第一个实际存在的音频文件路径
  /// 如果都不存在，返回 null
  ///
  /// 注意：此方法可以在服务层使用（如 QueueManager），
  /// 因为音频路径检查通常不在 UI build 上下文中。
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
