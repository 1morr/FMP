import 'package:isar/isar.dart';
import 'dart:io';

import '../models/track.dart';
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
        .downloadPathsIsNotEmpty()
        .sortByUpdatedAtDesc()
        .findAll();
  }

  /// 监听已下载歌曲变化
  Stream<List<Track>> watchDownloaded() {
    return _isar.tracks
        .filter()
        .downloadPathsIsNotEmpty()
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  /// 清除歌曲的所有下载路径
  Future<void> clearDownloadPath(int id) async {
    final track = await getById(id);
    if (track != null) {
      track.playlistIds = [];
      track.downloadPaths = [];
      await save(track);
    }
  }

  /// 清除歌曲在指定歌单中的下载路径
  Future<void> clearDownloadPathForPlaylist(int trackId, int playlistId) async {
    final track = await getById(trackId);
    if (track != null) {
      track.removeDownloadPath(playlistId);
      await save(track);
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

  /// 清理孤儿 Track（不被任何歌单/队列引用，且本地文件不存在的）
  ///
  /// [referencedTrackIds] 被歌单或播放队列引用的 Track ID 集合
  /// 返回：删除的 Track 数量
  Future<int> cleanupOrphanTracks(Set<int> referencedTrackIds) async {
    final allTracks = await getAll();
    final toDelete = <int>[];

    for (final track in allTracks) {
      // 如果被引用，保留
      if (referencedTrackIds.contains(track.id)) {
        continue;
      }

      // 如果有任何下载路径且文件存在，保留
      bool hasExistingFile = false;
      for (final path in track.downloadPaths) {
        if (await File(path).exists()) {
          hasExistingFile = true;
          break;
        }
      }
      if (hasExistingFile) {
        continue;
      }

      // 否则标记为删除
      toDelete.add(track.id);
    }

    if (toDelete.isNotEmpty) {
      await deleteAll(toDelete);
      logDebug('Cleaned up ${toDelete.length} orphan tracks');
    }
    
    return toDelete.length;
  }
}
