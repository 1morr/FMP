import 'dart:io';

import 'package:fmp/i18n/strings.g.dart';

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

  /// 同步本地文件到数据库（C3: REPLACE 模式）
  ///
  /// 扫描下载目录，匹配 Track 并**替换**所有下载路径
  /// C1: 跳过没有有效 metadata 的文件
  /// C2: 本地文件添加 playlistId=0
  /// C3: 本地文件是权威来源 - 替换所有 DB 路径
  /// 返回 (新增路径数量, 移除路径数量)
  Future<(int added, int removed)> syncLocalFiles({
    void Function(int current, int total)? onProgress,
  }) async {
    final basePath = await _pathManager.getCurrentDownloadPath();
    if (basePath == null) {
      throw Exception(t.download.pathNotConfigured);
    }

    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      return (0, 0);
    }

    int added = 0;
    int removed = 0;
    int processed = 0;

    // 收集所有匹配的 Track ID（用于清理不存在的路径）
    final matchedTrackIds = <int>{};
    final tracksToUpdate = <Track>[];
    // 记录哪些 track 在同步前已有下载路径
    final tracksWithExistingPaths = <int>{};

    // 获取所有子文件夹
    final folders = <Directory>[];
    await for (final entity in baseDir.list()) {
      if (entity is Directory) {
        folders.add(entity);
      }
    }
    final total = folders.length;

    logDebug('Starting sync: found $total folders to scan');

    // 第一步：扫描所有本地文件，收集匹配结果
    for (final folder in folders) {
      final results = await _scanAndMatchFolder(folder);

      for (final result in results.matched) {
        matchedTrackIds.add(result.track.id);
        tracksToUpdate.add(result.track);
        if (result.hadExistingPaths) {
          tracksWithExistingPaths.add(result.track.id);
        }
      }

      processed++;
      onProgress?.call(processed, total);
    }

    // 第二步：批量更新 Track（C3: 替换所有路径）
    for (final track in tracksToUpdate) {
      await _trackRepo.save(track);
      // 如果之前没有下载路径，则计为新增
      if (!tracksWithExistingPaths.contains(track.id)) {
        added++;
        logDebug('Added download path for: ${track.title}');
      } else {
        logDebug('Replaced download paths for: ${track.title}');
      }
    }

    // 第三步：清理数据库中不在本地的路径
    final allTracks = await _trackRepo.getAllTracksWithDownloads();
    for (final track in allTracks) {
      if (!matchedTrackIds.contains(track.id)) {
        // 这个 Track 没有在本地找到匹配文件，清除其路径
        track.clearAllDownloadPaths();
        await _trackRepo.save(track);
        removed++;
        logDebug('Cleared paths for track not found locally: ${track.title}');
      }
    }

    logDebug('Sync complete: added $added, removed $removed');
    return (added, removed);
  }

  /// 扫描并匹配单个文件夹
  Future<_ScanResult> _scanAndMatchFolder(Directory folder) async {
    final matched = <_MatchedTrack>[];

    try {
      final tracks = await DownloadScanner.scanFolderForTracks(folder.path);

      for (final scannedTrack in tracks) {
        // C1: 跳过没有有效 metadata 的文件
        if (scannedTrack.sourceId.isEmpty) {
          logDebug('Skipping file without valid sourceId: ${folder.path}');
          continue;
        }

        final localPath = scannedTrack.allDownloadPaths.firstOrNull;
        if (localPath == null) {
          continue;
        }

        final existingTrack = await _findMatchingTrack(scannedTrack);

        if (existingTrack != null) {
          // 记录同步前是否已有下载路径
          final hadExistingPaths = existingTrack.hasAnyDownload;

          // 保留原有的歌单关联，只更新下载路径
          // 如果 Track 已经属于某个歌单，保留该关联
          if (existingTrack.playlistInfo.isNotEmpty) {
            // 更新所有歌单关联的下载路径
            for (final info in existingTrack.playlistInfo) {
              info.downloadPath = localPath;
            }
          } else {
            // 如果没有歌单关联，添加为未分类（playlistId = 0）
            final folderName = folder.path.split(RegExp(r'[/\\]')).last;
            existingTrack.playlistInfo = [
              PlaylistDownloadInfo()
                ..playlistId = 0
                ..playlistName = folderName
                ..downloadPath = localPath,
            ];
          }

          matched.add(_MatchedTrack(
            track: existingTrack,
            localPath: localPath,
            hadExistingPaths: hadExistingPaths,
          ));
        }
      }
    } catch (e) {
      logDebug('Error scanning folder ${folder.path}: $e');
    }

    return _ScanResult(matched: matched);
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
}

/// 扫描结果
class _ScanResult {
  final List<_MatchedTrack> matched;

  _ScanResult({required this.matched});
}

/// 匹配的 Track 和本地路径
class _MatchedTrack {
  final Track track;
  final String localPath;
  final bool hadExistingPaths;

  _MatchedTrack({
    required this.track,
    required this.localPath,
    required this.hadExistingPaths,
  });
}
