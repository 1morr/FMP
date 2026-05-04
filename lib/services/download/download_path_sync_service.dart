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

    // 第一步：扫描所有本地文件，收集可用于批量匹配的结果
    final scannedDownloads = <_ScannedDownload>[];
    for (final folder in folders) {
      final results = await _scanAndMatchFolder(folder);
      scannedDownloads.addAll(results.scanned);

      processed++;
      onProgress?.call(processed, total);
    }

    final existingTracks = await _trackRepo.getBySourceIdentities(
      scannedDownloads.map((download) => TrackSourceIdentity.fromTrack(
            download.scannedTrack,
          )),
    );

    for (final scannedDownload in scannedDownloads) {
      final existingTrack = existingTracks[
          TrackSourceIdentity.fromTrack(scannedDownload.scannedTrack)];
      if (existingTrack == null) continue;
      if (scannedDownload.scannedTrack.cid == null &&
          scannedDownload.scannedTrack.pageNum != null &&
          existingTrack.pageNum != null &&
          scannedDownload.scannedTrack.pageNum != existingTrack.pageNum) {
        continue;
      }

      final trackId = existingTrack.id;
      matchedTrackIds.add(trackId);

      if (!trackPathsMap.containsKey(trackId)) {
        trackPathsMap[trackId] = [];
        if (existingTrack.hasAnyDownload) {
          tracksWithExistingPaths.add(trackId);
        }
      }

      final folderName = scannedDownload.folderName;
      var playlistId = 0;
      var playlistName = folderName;

      if (existingTrack.playlistInfo.isNotEmpty) {
        final matchingInfo = existingTrack.playlistInfo
            .where((info) => info.playlistName == folderName)
            .firstOrNull;
        if (matchingInfo != null) {
          playlistId = matchingInfo.playlistId;
          playlistName = matchingInfo.playlistName;
        }
      }

      trackPathsMap[trackId]!.add(_PathInfo(
        playlistId: playlistId,
        playlistName: playlistName,
        downloadPath: scannedDownload.localPath,
      ));
    }

    final tracksToSave = <Track>[];

    // 第二步：批量更新 Track，合并所有路径
    for (final entry in trackPathsMap.entries) {
      final trackId = entry.key;
      final pathInfos = entry.value;

      final track = existingTracks.values
          .where((existingTrack) => existingTrack.id == trackId)
          .firstOrNull;
      if (track == null) continue;

      final hadExistingPaths = tracksWithExistingPaths.contains(trackId);

      // 合并策略：
      // - 歌单归属（playlistId）以 DB 为权威来源，同步不改变
      // - 下载路径以本地文件为权威来源
      // - 文件夹名不匹配时，标记为未分类（playlistId=0），让用户手动分类
      final newPlaylistInfo = <PlaylistDownloadInfo>[];
      final usedPathIndices = <int>{};

      // 1. 对已有的歌单关联，尝试匹配本地路径并更新 downloadPath
      if (track.playlistInfo.isNotEmpty) {
        for (final info in track.playlistInfo) {
          // 精确匹配 playlistName
          final matchIdx = pathInfos.indexWhere(
            (p) =>
                p.playlistName == info.playlistName &&
                !usedPathIndices.contains(pathInfos.indexOf(p)),
          );
          if (matchIdx >= 0) {
            usedPathIndices.add(matchIdx);
            newPlaylistInfo.add(PlaylistDownloadInfo()
              ..playlistId = info.playlistId
              ..playlistName = info.playlistName
              ..downloadPath = pathInfos[matchIdx].downloadPath);
          }
          // 本地没有匹配的文件夹 → 不保留这条路径（文件已不存在）
        }
      }

      // 2. 添加本地有但 DB 中没有的路径（新发现的文件夹）
      // 新发现的文件夹统一标记为未分类（playlistId=0），让用户手动分类
      // 这避免了多歌单场景下继承错误 playlistId 的问题
      for (var i = 0; i < pathInfos.length; i++) {
        if (!usedPathIndices.contains(i)) {
          final pathInfo = pathInfos[i];
          newPlaylistInfo.add(PlaylistDownloadInfo()
            ..playlistId = 0 // 新发现的文件夹统一标记为未分类
            ..playlistName = pathInfo.playlistName
            ..downloadPath = pathInfo.downloadPath);
        }
      }

      track.playlistInfo = newPlaylistInfo;
      tracksToSave.add(track);

      if (!hadExistingPaths) {
        added++;
        logDebug(
            'Added ${pathInfos.length} download path(s) for: ${track.title}');
      } else {
        logDebug(
            'Updated ${pathInfos.length} download path(s) for: ${track.title}');
      }
    }

    // 第三步：清理数据库中不在本地的路径
    final allTracks = await _trackRepo.getAllTracksWithDownloads();
    for (final track in allTracks) {
      if (!matchedTrackIds.contains(track.id)) {
        // 这个 Track 没有在本地找到匹配文件，清除其路径
        track.clearAllDownloadPaths();
        tracksToSave.add(track);
        removed++;
        logDebug('Cleared paths for track not found locally: ${track.title}');
      }
    }

    if (tracksToSave.isNotEmpty) {
      await _trackRepo.saveAll(tracksToSave);
    }

    logDebug('Sync complete: added $added, removed $removed');
    return (added, removed);
  }

  /// 扫描单个文件夹
  Future<_ScanResult> _scanAndMatchFolder(Directory folder) async {
    final scanned = <_ScannedDownload>[];

    try {
      final tracks = await DownloadScanner.scanFolderForTracks(folder.path);
      final folderName = folder.path.split(RegExp(r'[/\\]')).last;

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

        scanned.add(_ScannedDownload(
          scannedTrack: scannedTrack,
          localPath: localPath,
          folderName: folderName,
        ));
      }
    } catch (e) {
      logDebug('Error scanning folder ${folder.path}: $e');
    }

    return _ScanResult(scanned: scanned);
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
  final List<_ScannedDownload> scanned;

  _ScanResult({required this.scanned});
}

/// 扫描到的本地下载路径
class _ScannedDownload {
  final Track scannedTrack;
  final String localPath;
  final String folderName;

  _ScannedDownload({
    required this.scannedTrack,
    required this.localPath,
    required this.folderName,
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
