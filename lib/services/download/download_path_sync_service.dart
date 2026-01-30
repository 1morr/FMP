import 'dart:io';

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/repositories/track_repository.dart';
import '../../providers/download/download_scanner.dart';
import 'download_path_manager.dart';

/// 下载路径同步服务
///
/// 负责扫描本地文件并同步到数据库
class DownloadPathSyncService with Logging {
  final TrackRepository _trackRepo;
  final DownloadPathManager _pathManager;

  DownloadPathSyncService(this._trackRepo, this._pathManager);

  /// 同步本地文件到数据库
  ///
  /// 扫描下载目录，匹配 Track 并更新下载路径
  /// 返回 (更新数量, 孤儿文件数量)
  Future<(int updated, int orphans)> syncLocalFiles({
    void Function(int current, int total)? onProgress,
  }) async {
    final basePath = await _pathManager.getCurrentDownloadPath();
    if (basePath == null) {
      throw Exception('下载路径未配置');
    }

    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      return (0, 0);
    }

    int updated = 0;
    int orphans = 0;
    int processed = 0;

    // 获取所有子文件夹
    final folders = <Directory>[];
    await for (final entity in baseDir.list()) {
      if (entity is Directory) {
        folders.add(entity);
      }
    }
    final total = folders.length;

    logDebug('Starting sync: found $total folders to scan');

    for (final folder in folders) {
      final result = await _syncFolder(folder);
      updated += result.$1;
      orphans += result.$2;

      processed++;
      onProgress?.call(processed, total);
    }

    logDebug('Sync complete: updated $updated, orphans $orphans');
    return (updated, orphans);
  }

  /// 同步单个文件夹
  Future<(int updated, int orphans)> _syncFolder(Directory folder) async {
    try {
      final tracks = await DownloadScanner.scanFolderForTracks(folder.path);
      int updated = 0;
      int orphans = 0;

      for (final scannedTrack in tracks) {
        final existingTrack = await _findMatchingTrack(scannedTrack);

        if (existingTrack != null) {
          final path = scannedTrack.downloadPaths.firstOrNull;
          if (path != null && !existingTrack.downloadPaths.contains(path)) {
            await _trackRepo.addDownloadPath(
              existingTrack.id,
              scannedTrack.playlistIds.firstOrNull,
              path,
            );
            updated++;
            logDebug('Updated download path for: ${existingTrack.title}');
          }
        } else {
          orphans++;
        }
      }

      return (updated, orphans);
    } catch (e) {
      logDebug('Error syncing folder ${folder.path}: $e');
      return (0, 0);
    }
  }

  /// 查找匹配的 Track
  ///
  /// 匹配规则：sourceId + sourceType + cid (+ pageNum for multi-part videos)
  Future<Track?> _findMatchingTrack(Track scannedTrack) async {
    // 使用精确匹配：sourceId + sourceType + cid
    final track = await _trackRepo.getBySourceIdAndCid(
      scannedTrack.sourceId,
      scannedTrack.sourceType,
      cid: scannedTrack.cid,
    );

    if (track != null) {
      // 如果有 cid 匹配，直接返回
      if (scannedTrack.cid != null) {
        return track;
      }

      // 如果没有 cid，检查 pageNum 是否匹配（多P视频兼容）
      if (scannedTrack.pageNum != null && track.pageNum != null) {
        if (scannedTrack.pageNum == track.pageNum) {
          return track;
        }
        // pageNum 不匹配，尝试查找其他 Track
        return null;
      }

      return track;
    }

    return null;
  }

  /// 清理无效的下载路径
  Future<int> cleanupInvalidPaths() async {
    logDebug('Cleaning up invalid paths...');
    final cleaned = await _trackRepo.cleanupInvalidDownloadPaths();
    logDebug('Cleaned $cleaned tracks with invalid paths');
    return cleaned;
  }

  /// 获取孤儿文件列表
  ///
  /// 返回本地存在但数据库中没有匹配的文件信息
  Future<List<OrphanFileInfo>> getOrphanFiles() async {
    final basePath = await _pathManager.getCurrentDownloadPath();
    if (basePath == null) return [];

    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) return [];

    final orphans = <OrphanFileInfo>[];

    await for (final entity in baseDir.list()) {
      if (entity is Directory) {
        final tracks = await DownloadScanner.scanFolderForTracks(entity.path);
        for (final track in tracks) {
          final existingTrack = await _findMatchingTrack(track);
          if (existingTrack == null) {
            orphans.add(OrphanFileInfo(
              title: track.title,
              path: track.downloadPaths.firstOrNull,
              sourceId: track.sourceId,
              sourceType: track.sourceType,
            ));
          }
        }
      }
    }

    return orphans;
  }
}

/// 孤儿文件信息
class OrphanFileInfo {
  final String title;
  final String? path;
  final String sourceId;
  final SourceType sourceType;

  OrphanFileInfo({
    required this.title,
    this.path,
    required this.sourceId,
    required this.sourceType,
  });
}
