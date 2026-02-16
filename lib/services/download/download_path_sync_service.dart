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
    // 使用 Map 收集每个 Track 的所有路径信息
    final trackPathsMap = <int, List<_PathInfo>>{};
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
        final trackId = result.track.id;
        matchedTrackIds.add(trackId);
        
        // 收集路径信息
        if (!trackPathsMap.containsKey(trackId)) {
          trackPathsMap[trackId] = [];
          if (result.hadExistingPaths) {
            tracksWithExistingPaths.add(trackId);
          }
        }
        
        trackPathsMap[trackId]!.add(_PathInfo(
          playlistId: result.playlistId,
          playlistName: result.playlistName,
          downloadPath: result.localPath,
        ));
      }

      processed++;
      onProgress?.call(processed, total);
    }

    // 第二步：批量更新 Track，合并所有路径
    for (final entry in trackPathsMap.entries) {
      final trackId = entry.key;
      final pathInfos = entry.value;
      
      // 从数据库重新获取 Track（避免使用扫描的临时对象）
      final track = await _trackRepo.getById(trackId);
      if (track == null) continue;
      
      final hadExistingPaths = tracksWithExistingPaths.contains(trackId);
      
      // 合并策略：以扫描到的本地路径为权威来源
      // 每个 pathInfo 代表一个本地文件夹中的匹配结果
      final newPlaylistInfo = <PlaylistDownloadInfo>[];
      final usedPathIndices = <int>{};

      // 1. 对已有的歌单关联，尝试匹配本地路径并更新 downloadPath
      if (track.playlistInfo.isNotEmpty) {
        for (final info in track.playlistInfo) {
          // 精确匹配 playlistName
          final matchIdx = pathInfos.indexWhere(
            (p) => p.playlistName == info.playlistName && !usedPathIndices.contains(pathInfos.indexOf(p)),
          );
          if (matchIdx >= 0) {
            usedPathIndices.add(matchIdx);
            newPlaylistInfo.add(PlaylistDownloadInfo()
              ..playlistId = info.playlistId
              ..playlistName = info.playlistName
              ..downloadPath = pathInfos[matchIdx].downloadPath);
          } else {
            // 本地没有这个歌单的文件，不保留（本地是权威来源）
          }
        }
      }

      // 2. 添加本地有但 DB 中没有的路径（新发现的文件夹）
      for (var i = 0; i < pathInfos.length; i++) {
        if (!usedPathIndices.contains(i)) {
          final pathInfo = pathInfos[i];
          newPlaylistInfo.add(PlaylistDownloadInfo()
            ..playlistId = pathInfo.playlistId
            ..playlistName = pathInfo.playlistName
            ..downloadPath = pathInfo.downloadPath);
        }
      }

      track.playlistInfo = newPlaylistInfo;
      
      await _trackRepo.save(track);
      
      if (!hadExistingPaths) {
        added++;
        logDebug('Added ${pathInfos.length} download path(s) for: ${track.title}');
      } else {
        logDebug('Updated ${pathInfos.length} download path(s) for: ${track.title}');
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

          // 从文件夹名提取歌单信息
          final folderName = folder.path.split(RegExp(r'[/\\]')).last;

          // 尝试从现有的 playlistInfo 中找到匹配的歌单
          int playlistId = 0;
          String playlistName = folderName;

          // 如果 Track 已经有歌单关联，尝试根据文件夹名匹配
          if (existingTrack.playlistInfo.isNotEmpty) {
            final matchingInfo = existingTrack.playlistInfo
                .where((info) => info.playlistName == folderName)
                .firstOrNull;
            if (matchingInfo != null) {
              playlistId = matchingInfo.playlistId;
              playlistName = matchingInfo.playlistName;
            }
            // 不匹配时保持 playlistId=0, playlistName=folderName
          }

          matched.add(_MatchedTrack(
            track: existingTrack,
            localPath: localPath,
            hadExistingPaths: hadExistingPaths,
            playlistId: playlistId,
            playlistName: playlistName,
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
  final int playlistId;
  final String playlistName;

  _MatchedTrack({
    required this.track,
    required this.localPath,
    required this.hadExistingPaths,
    required this.playlistId,
    required this.playlistName,
  });
}

/// 路径信息
class _PathInfo {
  final int playlistId;
  final String playlistName;
  final String downloadPath;

  _PathInfo({
    required this.playlistId,
    required this.playlistName,
    required this.downloadPath,
  });
}
