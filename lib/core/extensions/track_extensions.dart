import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/track.dart';
import '../../providers/download/file_exists_cache.dart';
import '../utils/duration_formatter.dart';

/// Track 模型扩展方法
extension TrackExtensions on Track {
  /// 简化逻辑：有路径就认为已下载
  ///
  /// 注意：这假设路径有效。使用时如果文件不存在会自动清空。
  bool get isDownloaded => hasAnyDownload;

  /// 获取本地音频路径
  ///
  /// 尝试使用第一个有效路径，如果都不存在返回 null
  String? get localAudioPath {
    if (!hasAnyDownload) return null;

    for (final downloadPath in allDownloadPaths) {
      try {
        if (File(downloadPath).existsSync()) {
          return downloadPath;
        }
      } catch (_) {
        // 路径无效，继续检查下一个
      }
    }
    return null;
  }

  /// 清理无效的下载路径
  ///
  /// 检查所有路径，移除不存在的
  /// 返回清理后的路径列表
  List<String> get validDownloadPaths {
    final valid = <String>[];
    for (final path in allDownloadPaths) {
      try {
        if (File(path).existsSync()) {
          valid.add(path);
        }
      } catch (_) {
        // 路径无效，跳过
      }
    }
    return valid;
  }

  /// 获取本地封面路径（使用缓存，适用于 UI 组件）
  ///
  /// 遍历所有下载路径，返回第一个存在 cover.jpg 的路径
  /// 如果都不存在，返回 null
  ///
  /// [cache] FileExistsCache 实例，从 ref.read(fileExistsCacheProvider.notifier) 获取
  String? getLocalCoverPath(FileExistsCache cache) {
    if (!hasAnyDownload) return null;

    final coverPaths = allDownloadPaths.map((p) {
      final dir = Directory(p).parent;
      return '${dir.path}/cover.jpg';
    }).toList();

    return cache.getFirstExisting(coverPaths);
  }

  /// 获取本地封面路径（不使用缓存）
  ///
  /// 遍历所有下载路径，返回第一个存在 cover.jpg 的路径
  String? getLocalCoverPathSync() {
    if (!hasAnyDownload) return null;

    for (final path in allDownloadPaths) {
      try {
        final dir = Directory(path).parent;
        final coverFile = File(p.join(dir.path, 'cover.jpg'));
        if (coverFile.existsSync()) {
          return coverFile.path;
        }
      } catch (_) {
        // 路径无效，继续
      }
    }
    return null;
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

  /// 是否有本地音频文件（文件实际存在）
  bool get hasLocalAudio => localAudioPath != null;
}
