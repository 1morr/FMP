import 'package:isar/isar.dart';
import 'dart:io';

import '../models/track.dart';
import '../models/playlist.dart';
import '../models/play_queue.dart';
import '../../core/logger.dart';

/// Track 数据仓库
class TrackRepository with Logging {
  final Isar _isar;

  TrackRepository(this._isar);

  /// 获取所有歌曲
  Future<List<Track>> getAll() async {
    return _isar.tracks.where().findAll();
  }

  /// 根据ID获取歌曲
  Future<Track?> getById(int id) async {
    return _isar.tracks.get(id);
  }

  /// 根据ID列表获取歌曲（保持顺序）
  Future<List<Track>> getByIds(List<int> ids) async {
    logDebug('Getting tracks by ids: $ids');
    final tracks = await _isar.tracks.getAll(ids);
    // 过滤null并保持顺序
    final result = <Track>[];
    for (final id in ids) {
      final index = ids.indexOf(id);
      if (index < tracks.length && tracks[index] != null) {
        result.add(tracks[index]!);
      }
    }
    logDebug('Found ${result.length}/${ids.length} tracks');
    return result;
  }

  /// 根据源ID和类型获取歌曲
  Future<Track?> getBySourceId(String sourceId, SourceType sourceType) async {
    return _isar.tracks
        .where()
        .sourceIdEqualTo(sourceId)
        .filter()
        .sourceTypeEqualTo(sourceType)
        .findFirst();
  }

  /// 根据源ID、类型和cid获取歌曲（支持分P唯一性检查）
  Future<Track?> getBySourceIdAndCid(
    String sourceId,
    SourceType sourceType, {
    int? cid,
  }) async {
    if (cid == null) {
      // 没有cid，使用传统方式查找
      return getBySourceId(sourceId, sourceType);
    }
    
    // 有cid，精确匹配分P
    return _isar.tracks
        .where()
        .sourceIdEqualTo(sourceId)
        .filter()
        .sourceTypeEqualTo(sourceType)
        .and()
        .cidEqualTo(cid)
        .findFirst();
  }

  /// 保存歌曲并返回更新后的歌曲
  Future<Track> save(Track track) async {
    logDebug('Saving track: ${track.title} (id: ${track.id}, sourceId: ${track.sourceId})');
    logDebug('  playlistInfo: ${track.playlistInfo.map((i) => "playlist=${i.playlistId}:path=${i.downloadPath.isNotEmpty ? "HAS_PATH" : "EMPTY"}").join(", ")}');
    // 打印调用栈以找出谁在调用 save
    logDebug('  caller: ${StackTrace.current.toString().split('\n').take(5).join(' -> ')}');
    track.updatedAt = DateTime.now();
    final id = await _isar.writeTxn(() => _isar.tracks.put(track));
    track.id = id;
    logDebug('Track saved with id: $id');
    return track;
  }

  /// 批量保存歌曲并返回更新后的歌曲列表
  Future<List<Track>> saveAll(List<Track> tracks) async {
    logDebug('Saving ${tracks.length} tracks');
    final now = DateTime.now();
    for (final track in tracks) {
      track.updatedAt = now;
    }
    final ids = await _isar.writeTxn(() => _isar.tracks.putAll(tracks));
    for (var i = 0; i < tracks.length; i++) {
      tracks[i].id = ids[i];
    }
    logDebug('Saved ${tracks.length} tracks with ids: $ids');
    return tracks;
  }

  /// 删除歌曲
  Future<bool> delete(int id) async {
    return _isar.writeTxn(() => _isar.tracks.delete(id));
  }

  /// 批量删除歌曲
  Future<int> deleteAll(List<int> ids) async {
    return _isar.writeTxn(() => _isar.tracks.deleteAll(ids));
  }

  /// 搜索歌曲（本地）
  Future<List<Track>> search(String query) async {
    if (query.isEmpty) return [];
    return _isar.tracks
        .filter()
        .titleContains(query, caseSensitive: false)
        .or()
        .artistContains(query, caseSensitive: false)
        .findAll();
  }

  /// 获取所有已下载的歌曲
  Future<List<Track>> getDownloaded() async {
    return _isar.tracks
        .filter()
        .playlistInfoElement((q) => q.downloadPathIsNotEmpty())
        .sortByUpdatedAtDesc()
        .findAll();
  }

  /// 监听已下载歌曲变化
  Stream<List<Track>> watchDownloaded() {
    return _isar.tracks
        .filter()
        .playlistInfoElement((q) => q.downloadPathIsNotEmpty())
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  /// 获取所有有下载路径的 Track（用于同步服务）
  Future<List<Track>> getAllTracksWithDownloads() async {
    return _isar.tracks
        .filter()
        .playlistInfoElement((q) => q.downloadPathIsNotEmpty())
        .findAll();
  }

  /// 清除歌曲的所有下载路径（保留歌单关联）
  Future<void> clearDownloadPath(int id) async {
    final track = await getById(id);
    if (track != null) {
      track.clearAllDownloadPaths();
      await save(track);
    }
  }

  /// 清除歌曲在指定歌单中的下载路径（保留歌单关联）
  Future<void> clearDownloadPathForPlaylist(int trackId, int playlistId) async {
    final track = await getById(trackId);
    if (track != null) {
      track.clearDownloadPathForPlaylist(playlistId);
      await save(track);
    }
  }

  /// 添加下载路径
  ///
  /// [trackId] Track ID
  /// [playlistId] 歌单 ID，null 表示添加到通用列表 (playlistId = 0)
  /// [playlistName] 歌单名称（用于下载路径匹配）
  /// [path] 下载路径
  Future<void> addDownloadPath(int trackId, int? playlistId, String? playlistName, String path) async {
    final track = await getById(trackId);
    if (track == null) {
      logWarning('addDownloadPath: track $trackId not found!');
      return;
    }

    final effectivePlaylistId = playlistId ?? 0;
    logDebug('addDownloadPath: BEFORE setDownloadPath - playlistInfo: ${track.playlistInfo.map((i) => "playlist=${i.playlistId}(${i.playlistName}):path=${i.downloadPath.isNotEmpty}").join(", ")}');
    track.setDownloadPath(effectivePlaylistId, path, playlistName: playlistName);
    logDebug('addDownloadPath: AFTER setDownloadPath - playlistInfo: ${track.playlistInfo.map((i) => "playlist=${i.playlistId}(${i.playlistName}):path=${i.downloadPath.isNotEmpty}").join(", ")}');
    await save(track);
    logDebug('Added download path for track $trackId: $path');
  }

  /// 清除所有 Track 的下载路径（保留歌单关联）
  Future<void> clearAllDownloadPaths() async {
    logDebug('clearAllDownloadPaths: Starting');
    try {
      await _isar.writeTxn(() async {
        logDebug('clearAllDownloadPaths: Inside transaction, querying tracks');
        final tracks = await _isar.tracks
            .filter()
            .playlistInfoElement((q) => q.downloadPathIsNotEmpty())
            .findAll();
        logDebug('clearAllDownloadPaths: Found ${tracks.length} tracks with download paths');
        
        if (tracks.isEmpty) {
          logDebug('clearAllDownloadPaths: No tracks to clear');
          return;
        }
        
        for (final track in tracks) {
          track.clearAllDownloadPaths();
        }
        
        logDebug('clearAllDownloadPaths: Saving ${tracks.length} tracks');
        await _isar.tracks.putAll(tracks);
        logDebug('clearAllDownloadPaths: Done');
      });
      logDebug('clearAllDownloadPaths: Transaction completed');
    } catch (e, stackTrace) {
      logDebug('clearAllDownloadPaths: ERROR - $e');
      logDebug('clearAllDownloadPaths: StackTrace - $stackTrace');
      rethrow;
    }
  }

  /// 标记歌曲为不可用
  Future<void> markUnavailable(int id, String reason) async {
    final track = await getById(id);
    if (track != null) {
      track.isAvailable = false;
      track.unavailableReason = reason;
      await save(track);
    }
  }

  /// 更新音频 URL
  Future<void> updateAudioUrl(int id, String audioUrl, Duration expiry) async {
    final track = await getById(id);
    if (track != null) {
      track.audioUrl = audioUrl;
      track.audioUrlExpiry = DateTime.now().add(expiry);
      await save(track);
    }
  }

  // ============================================================
  // Track 引用模式支持方法
  // ============================================================

  /// 比较两个 Track 的数据完整性
  bool _hasMoreCompleteData(Track a, Track b) {
    int scoreA = 0, scoreB = 0;
    if (a.audioUrl != null && a.audioUrl!.isNotEmpty) scoreA += 10;
    if (b.audioUrl != null && b.audioUrl!.isNotEmpty) scoreB += 10;
    if (a.thumbnailUrl != null) scoreA += 5;
    if (b.thumbnailUrl != null) scoreB += 5;
    if (a.durationMs != null && a.durationMs! > 0) scoreA += 3;
    if (b.durationMs != null && b.durationMs! > 0) scoreB += 3;
    if (a.artist != null && a.artist!.isNotEmpty) scoreA += 2;
    if (b.artist != null && b.artist!.isNotEmpty) scoreB += 2;
    return scoreA > scoreB;
  }

  /// 获取或创建 Track（去重模式）
  ///
  /// 根据 sourceId + sourceType + cid 查找现有 Track：
  /// - 如果存在：更新可能过期的字段（audioUrl 等），返回现有记录
  /// - 如果不存在：创建新记录
  ///
  /// 这是防止 Track 重复的核心方法。
  Future<Track> getOrCreate(Track track) async {
    // 查找现有 Track
    final existing = await getBySourceIdAndCid(
      track.sourceId,
      track.sourceType,
      cid: track.cid,
    );

    if (existing != null) {
      logDebug('Found existing track: ${existing.title} (id: ${existing.id})');

      bool needsUpdate = false;

      // 更新 audioUrl（如果新的更新或现有的已过期）
      if (track.audioUrl != null && track.audioUrl!.isNotEmpty) {
        if (existing.audioUrl == null ||
            existing.audioUrl!.isEmpty ||
            !existing.hasValidAudioUrl) {
          existing.audioUrl = track.audioUrl;
          existing.audioUrlExpiry = track.audioUrlExpiry;
          needsUpdate = true;
        }
      }

      // 更新缺失的元数据
      if (existing.thumbnailUrl == null && track.thumbnailUrl != null) {
        existing.thumbnailUrl = track.thumbnailUrl;
        needsUpdate = true;
      }
      if (existing.durationMs == null && track.durationMs != null) {
        existing.durationMs = track.durationMs;
        needsUpdate = true;
      }
      if (existing.artist == null && track.artist != null) {
        existing.artist = track.artist;
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        logDebug('Updating existing track with new data');
        return save(existing);
      }

      return existing;
    }

    // 不存在，创建新 Track
    logDebug('Creating new track: ${track.title}');
    return save(track);
  }

  /// 批量获取或创建 Track（去重模式）
  ///
  /// 对输入列表进行去重，避免同一批次中有重复。
  /// 返回的列表顺序与输入顺序一致。
  Future<List<Track>> getOrCreateAll(List<Track> tracks) async {
    if (tracks.isEmpty) return [];

    logDebug('getOrCreateAll: processing ${tracks.length} tracks');

    // 使用 Map 按 uniqueKey 去重，保持顺序
    final Map<String, int> keyToIndex = {};
    final List<Track> uniqueTracks = [];

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final key = track.uniqueKey;

      if (!keyToIndex.containsKey(key)) {
        keyToIndex[key] = uniqueTracks.length;
        uniqueTracks.add(track);
      } else {
        // 如果已存在，检查是否有更完整的数据
        final existingIndex = keyToIndex[key]!;
        if (_hasMoreCompleteData(track, uniqueTracks[existingIndex])) {
          uniqueTracks[existingIndex] = track;
        }
      }
    }

    // 批量处理去重后的 Track
    final results = <Track>[];
    for (final track in uniqueTracks) {
      results.add(await getOrCreate(track));
    }

    // 重建原始顺序的结果列表（处理输入中的重复）
    final finalResults = <Track>[];
    for (final track in tracks) {
      final key = track.uniqueKey;
      final index = keyToIndex[key]!;
      finalResults.add(results[index]);
    }

    logDebug('getOrCreateAll: returned ${finalResults.length} tracks (${results.length} unique)');
    return finalResults;
  }

  /// 检查 Track 是否被引用（歌单或队列）
  ///
  /// 注意：此方法需要遍历所有歌单和队列，性能敏感操作请谨慎使用。
  Future<bool> isReferenced(int trackId) async {
    // 检查歌单
    final playlists = await _isar.playlists.where().findAll();
    for (final playlist in playlists) {
      if (playlist.trackIds.contains(trackId)) {
        return true;
      }
    }

    // 检查播放队列
    final queues = await _isar.playQueues.where().findAll();
    for (final queue in queues) {
      if (queue.trackIds.contains(trackId)) {
        return true;
      }
    }

    return false;
  }

  /// 检查 Track 是否有已下载的文件
  Future<bool> hasDownloadedFiles(Track track) async {
    for (final path in track.allDownloadPaths) {
      if (await File(path).exists()) {
        return true;
      }
    }
    return false;
  }

  /// 清理无效的下载路径
  ///
  /// 检查数据库中的所有下载路径，移除不存在的文件路径
  /// 保留歌单关联，仅清除无效的 downloadPath
  /// 返回清理的 Track 数量
  Future<int> cleanupInvalidDownloadPaths() async {
    logDebug('Cleaning up invalid download paths...');
    int cleaned = 0;

    await _isar.writeTxn(() async {
      final tracks = await _isar.tracks
          .filter()
          .playlistInfoElement((q) => q.downloadPathIsNotEmpty())
          .findAll();
      
      for (final track in tracks) {
        bool hasChanges = false;

        // 检查哪些路径需要清除
        for (final info in track.playlistInfo) {
          if (info.downloadPath.isNotEmpty) {
            try {
              if (!File(info.downloadPath).existsSync()) {
                hasChanges = true;
                break;
              }
            } catch (_) {
              hasChanges = true;
              break;
            }
          }
        }

        if (hasChanges) {
          // 创建新的列表，确保 Isar 检测到变更
          track.playlistInfo = track.playlistInfo
              .map((info) {
                if (info.downloadPath.isEmpty) {
                  return PlaylistDownloadInfo()
                    ..playlistId = info.playlistId
                    ..downloadPath = '';
                }
                try {
                  if (File(info.downloadPath).existsSync()) {
                    return PlaylistDownloadInfo()
                      ..playlistId = info.playlistId
                      ..downloadPath = info.downloadPath;
                  }
                } catch (_) {}
                return PlaylistDownloadInfo()
                  ..playlistId = info.playlistId
                  ..downloadPath = '';
              })
              .toList();
          await _isar.tracks.put(track);
          cleaned++;
        }
      }
    });

    logDebug('Cleaned up invalid download paths for $cleaned tracks');
    return cleaned;
  }

  /// 删除孤立的 Track 记录
  ///
  /// 孤立 Track 的定义：
  /// - 不在当前播放队列中（通过 excludeTrackIds 排除）
  /// - 不属于任何歌单（playlistInfo 中没有 playlistId > 0 的条目）
  ///
  /// 注意：不检查 downloadPath。playlistId=0 的下载路径只是 scanner 扫描发现的，
  /// 下次打开已下载页面时 scanner 会重新创建。删除数据库记录不影响本地文件。
  ///
  /// 返回删除的 Track 数量
  Future<int> deleteOrphanTracks({List<int> excludeTrackIds = const []}) async {
    logDebug('Deleting orphan tracks (excluding ${excludeTrackIds.length} queue tracks)...');

    final excludeSet = excludeTrackIds.toSet();
    final toDelete = <int>[];

    // 获取所有 tracks
    final allTracks = await _isar.tracks.where().findAll();

    for (final track in allTracks) {
      // 跳过当前队列中的 tracks
      if (excludeSet.contains(track.id)) {
        continue;
      }

      // 检查是否属于任何歌单（playlistId > 0）
      final belongsToPlaylist = track.playlistInfo.any(
        (info) => info.playlistId > 0,
      );
      if (belongsToPlaylist) {
        continue;
      }

      // 这是一个孤立的 track，标记为删除
      toDelete.add(track.id);
    }

    if (toDelete.isEmpty) {
      logDebug('No orphan tracks to delete');
      return 0;
    }

    // 批量删除
    await _isar.writeTxn(() async {
      await _isar.tracks.deleteAll(toDelete);
    });

    logInfo('Deleted ${toDelete.length} orphan tracks');
    return toDelete.length;
  }
}
