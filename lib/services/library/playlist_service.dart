import 'dart:io';

import '../../data/models/playlist.dart';

import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../download/download_path_utils.dart';
import 'package:fmp/i18n/strings.g.dart';

/// 歌单更新结果
class PlaylistUpdateResult {
  /// 更新后的歌单
  final Playlist playlist;

  /// 如果重命名了歌单且有已下载的文件，这里会是旧文件夹路径
  /// 为 null 表示无需手动移动文件
  final String? oldDownloadFolder;

  /// 新文件夹路径（仅当 oldDownloadFolder 不为空时有值）
  final String? newDownloadFolder;

  const PlaylistUpdateResult({
    required this.playlist,
    this.oldDownloadFolder,
    this.newDownloadFolder,
  });

  /// 是否需要用户手动移动下载文件夹
  bool get needsManualFileMigration => oldDownloadFolder != null;
}

/// 歌单封面数据
class PlaylistCoverData {
  /// 本地封面路径（已下载的封面）
  final String? localPath;

  /// 网络封面 URL
  final String? networkUrl;

  const PlaylistCoverData({this.localPath, this.networkUrl});

  /// 是否有可用的封面
  bool get hasCover => localPath != null || networkUrl != null;
}

/// 歌单管理服务
class PlaylistService with Logging {
  final PlaylistRepository _playlistRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final Isar _isar;

  PlaylistService({
    required PlaylistRepository playlistRepository,
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
    required Isar isar,
  })  : _playlistRepository = playlistRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _isar = isar;

  /// 获取所有歌单
  Future<List<Playlist>> getAllPlaylists() async {
    return _playlistRepository.getAll();
  }

  /// 获取歌单（包含歌曲信息）
  Future<PlaylistWithTracks?> getPlaylistWithTracks(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return null;

    final tracks = await _trackRepository.getByIds(playlist.trackIds);
    return PlaylistWithTracks(playlist: playlist, tracks: tracks);
  }

  /// 获取歌单及分页歌曲
  Future<PlaylistWithTracks?> getPlaylistWithTracksPage(
    int playlistId, {
    int offset = 0,
    int limit = 100,
  }) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return null;

    final trackIds = playlist.trackIds;
    final pageIds = trackIds.skip(offset).take(limit).toList();
    final tracks = await _trackRepository.getByIds(pageIds);

    return PlaylistWithTracks(
      playlist: playlist,
      tracks: tracks,
      totalTrackCount: trackIds.length,
      hasMore: offset + limit < trackIds.length,
    );
  }

  /// 创建新歌单
  Future<Playlist> createPlaylist({
    required String name,
    String? description,
    String? coverUrl,
  }) async {
    // 检查名称是否已存在
    if (await _playlistRepository.nameExists(name)) {
      throw PlaylistNameExistsException(name);
    }

    // 獲取下一個排序順序
    final nextSortOrder = await _playlistRepository.getNextSortOrder();

    final playlist = Playlist()
      ..name = name
      ..description = description
      ..coverUrl = coverUrl
      ..hasCustomCover = coverUrl != null
      ..sortOrder = nextSortOrder
      ..createdAt = DateTime.now();

    final id = await _playlistRepository.save(playlist);
    playlist.id = id;
    return playlist;
  }

  /// 更新歌单信息
  ///
  /// 返回 [PlaylistUpdateResult]，如果重命名了歌单且有已下载的文件：
  /// 1. 清除该歌单下所有歌曲的下载路径
  /// 2. 结果中包含旧/新文件夹路径，提示用户手动移动
  /// 3. 用户移动文件后需从已下载页面点击同步重新关联
  Future<PlaylistUpdateResult> updatePlaylist({
    required int playlistId,
    String? name,
    String? description,
    String? coverUrl,
    int? refreshIntervalHours,
    bool? useAuthForRefresh,
  }) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    final oldName = playlist.name;
    String? oldDownloadFolder;
    String? newDownloadFolder;

    // 检查新名称是否已存在（排除当前歌单）
    if (name != null && name != playlist.name) {
      if (await _playlistRepository.nameExists(name, excludeId: playlistId)) {
        throw PlaylistNameExistsException(name);
      }
      playlist.name = name;

      // 检查旧文件夹是否存在（有下载文件）
      final baseDir =
          await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
      final oldFolderName = DownloadPathUtils.sanitizeFileName(oldName);
      final oldFolder = Directory(p.join(baseDir, oldFolderName));
      if (await oldFolder.exists()) {
        oldDownloadFolder = oldFolder.path;
        final newFolderName = DownloadPathUtils.sanitizeFileName(name);
        newDownloadFolder = p.join(baseDir, newFolderName);

        // 清除该歌单下所有歌曲的下载路径
        // 用户需要手动移动文件夹后从已下载页面点击同步
        final tracks = await _trackRepository.getByIds(playlist.trackIds);
        for (final track in tracks) {
          track.clearDownloadPathForPlaylist(playlistId);
        }
        if (tracks.isNotEmpty) {
          await _trackRepository.saveAll(tracks);
          logDebug(
              'Cleared download paths for ${tracks.length} tracks in renamed playlist');
        }
      }
    }

    if (description != null) {
      playlist.description = description;
    }
    // coverUrl: null 表示不修改，空字符串表示清除（恢復默認），其他值表示設置新封面
    if (coverUrl != null) {
      if (coverUrl.isEmpty) {
        // 清除自定義封面，恢復使用默認封面（第一首歌曲的縮略圖）
        playlist.coverUrl = null;
        playlist.hasCustomCover = false;
      } else {
        // 設置自定義封面
        playlist.coverUrl = coverUrl;
        playlist.hasCustomCover = true;
      }
    }

    // 更新自動刷新設置
    if (refreshIntervalHours != null) {
      playlist.refreshIntervalHours =
          refreshIntervalHours > 0 ? refreshIntervalHours : null;
    }

    // 更新使用登入狀態刷新
    if (useAuthForRefresh != null) {
      playlist.useAuthForRefresh = useAuthForRefresh;
    }

    await _playlistRepository.save(playlist);

    // 注：歌单改名不再需要更新预计算路径
    // 新架构下，下载路径在下载完成时保存到 Track.playlistInfo

    return PlaylistUpdateResult(
      playlist: playlist,
      oldDownloadFolder: oldDownloadFolder,
      newDownloadFolder: newDownloadFolder,
    );
  }

  /// 删除歌单
  ///
  /// 同时清理不被其他歌单引用的孤立歌曲。
  /// 使用批量操作优化性能，避免逐个查询和保存。
  Future<void> deletePlaylist(int playlistId) async {
    // 获取歌单信息
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return;

    final trackIds = playlist.trackIds;

    if (trackIds.isEmpty) {
      // 没有歌曲，直接删除歌单
      await _playlistRepository.delete(playlistId);
      return;
    }

    // 批量获取所有 tracks（一次数据库查询）
    final tracks = await _trackRepository.getByIds(trackIds);

    // 分类处理
    final toDelete = <int>[];
    final toUpdate = <Track>[];

    for (final track in tracks) {
      // 移除该歌单的关联
      track.removeFromPlaylist(playlistId);

      // 检查是否还属于其他歌单
      if (track.playlistInfo.isEmpty) {
        toDelete.add(track.id);
      } else {
        toUpdate.add(track);
      }
    }

    // 使用单个事务批量操作（大幅提升性能）
    await _isar.writeTxn(() async {
      // 删除歌单
      await _isar.playlists.delete(playlistId);

      // 批量删除孤儿 tracks
      if (toDelete.isNotEmpty) {
        await _isar.tracks.deleteAll(toDelete);
        logDebug('Batch deleted ${toDelete.length} orphan tracks');
      }

      // 批量更新其他 tracks
      if (toUpdate.isNotEmpty) {
        for (final track in toUpdate) {
          track.updatedAt = DateTime.now();
        }
        await _isar.tracks.putAll(toUpdate);
        logDebug('Batch updated ${toUpdate.length} tracks');
      }
    });
  }

  /// 添加歌曲到歌单
  ///
  /// 在单个事务中解析或创建 Track，并同时写入 Playlist.trackIds 和
  /// Track.playlistInfo，避免关系事务前先写入孤立 Track。
  /// 注意：下载路径不再预计算，将在实际下载完成时由 DownloadService 设置。
  Future<void> addTrackToPlaylist(int playlistId, Track track) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    await _isar.writeTxn(() async {
      final freshPlaylist = await _isar.playlists.get(playlistId);
      if (freshPlaylist == null) {
        throw PlaylistNotFoundException(playlistId);
      }

      final freshTrack = await _findTrackByIdentity(track);
      final trackToUpdate = freshTrack ?? track;
      final metadataChanged =
          freshTrack != null && _mergeTrackMetadataIfNeeded(freshTrack, track);
      final trackLinked = trackToUpdate.belongsToPlaylist(playlistId);
      final playlistLinked = freshTrack != null &&
          freshPlaylist.trackIds.contains(trackToUpdate.id);

      if (freshTrack != null &&
          trackLinked &&
          playlistLinked &&
          !metadataChanged) {
        logDebug(
            'Track ${trackToUpdate.title} already in playlist $playlistId, skipping');
        return;
      }

      final now = DateTime.now();
      if (!trackLinked) {
        trackToUpdate.addToPlaylist(
          playlistId,
          playlistName: freshPlaylist.name,
        );
      }
      if (freshTrack == null || !trackLinked || metadataChanged) {
        trackToUpdate.updatedAt = now;
        trackToUpdate.id = await _isar.tracks.put(trackToUpdate);
      }

      var playlistChanged = false;
      final wasEmpty = freshPlaylist.trackIds.isEmpty;
      if (!playlistLinked) {
        freshPlaylist.trackIds = [...freshPlaylist.trackIds, trackToUpdate.id];
        playlistChanged = true;
      }
      if (wasEmpty && !freshPlaylist.hasCustomCover && playlistChanged) {
        freshPlaylist.coverUrl = trackToUpdate.thumbnailUrl;
      }
      if (playlistChanged) {
        freshPlaylist.updatedAt = now;
        await _isar.playlists.put(freshPlaylist);
      }
    });
  }

  /// 批量添加歌曲到歌单
  ///
  /// 在单个事务中解析或创建 Track，并同时写入 Playlist.trackIds 和
  /// Track.playlistInfo，避免关系事务前先写入孤立 Track。
  /// 注意：下载路径不再预计算，将在实际下载完成时由 DownloadService 设置。
  Future<void> addTracksToPlaylist(int playlistId, List<Track> tracks) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    final candidateTracks = _dedupeTracksByUniqueKey(tracks);
    if (candidateTracks.isEmpty) {
      return;
    }
    final duplicateInputCount = tracks.length - candidateTracks.length;

    var alreadyFullyLinkedCount = 0;
    var changedCount = 0;
    await _isar.writeTxn(() async {
      final freshPlaylist = await _isar.playlists.get(playlistId);
      if (freshPlaylist == null) {
        throw PlaylistNotFoundException(playlistId);
      }

      final now = DateTime.now();
      final trackIds = List<int>.from(freshPlaylist.trackIds);
      final existingTrackIds = trackIds.toSet();
      final wasEmpty = trackIds.isEmpty;
      Track? firstNewPlaylistTrack;
      var playlistChanged = false;

      for (final inputTrack in candidateTracks) {
        final freshTrack = await _findTrackByIdentity(inputTrack);
        final trackToUpdate = freshTrack ?? inputTrack;
        final metadataChanged = freshTrack != null &&
            _mergeTrackMetadataIfNeeded(freshTrack, inputTrack);
        final trackLinked = trackToUpdate.belongsToPlaylist(playlistId);
        final playlistLinked =
            freshTrack != null && existingTrackIds.contains(trackToUpdate.id);

        if (freshTrack != null &&
            trackLinked &&
            playlistLinked &&
            !metadataChanged) {
          alreadyFullyLinkedCount++;
          continue;
        }

        if (!trackLinked) {
          trackToUpdate.addToPlaylist(
            playlistId,
            playlistName: freshPlaylist.name,
          );
        }
        if (freshTrack == null || !trackLinked || metadataChanged) {
          trackToUpdate.updatedAt = now;
          trackToUpdate.id = await _isar.tracks.put(trackToUpdate);
        }
        if (!playlistLinked && existingTrackIds.add(trackToUpdate.id)) {
          trackIds.add(trackToUpdate.id);
          firstNewPlaylistTrack ??= trackToUpdate;
          playlistChanged = true;
        }
        changedCount++;
      }

      if (changedCount == 0) {
        return;
      }

      if (playlistChanged) {
        freshPlaylist.trackIds = trackIds;
        if (wasEmpty && !freshPlaylist.hasCustomCover) {
          freshPlaylist.coverUrl = firstNewPlaylistTrack?.thumbnailUrl;
        }
        freshPlaylist.updatedAt = now;
        await _isar.playlists.put(freshPlaylist);
      }
    });

    if (changedCount == 0) {
      logDebug(
          'All ${tracks.length} tracks already in playlist $playlistId, skipping');
    } else if (changedCount < tracks.length) {
      logDebug(
          'Added or repaired $changedCount/${tracks.length} tracks in playlist $playlistId ($alreadyFullyLinkedCount already linked, $duplicateInputCount duplicate inputs)');
    }
  }

  Future<Track?> _findTrackByIdentity(Track track) {
    if (track.cid == null) {
      return _isar.tracks
          .where()
          .sourceIdEqualTo(track.sourceId)
          .filter()
          .sourceTypeEqualTo(track.sourceType)
          .findFirst();
    }

    return _isar.tracks
        .where()
        .sourceIdEqualTo(track.sourceId)
        .filter()
        .sourceTypeEqualTo(track.sourceType)
        .and()
        .cidEqualTo(track.cid)
        .findFirst();
  }

  List<Track> _dedupeTracksByUniqueKey(List<Track> tracks) {
    final keyToIndex = <String, int>{};
    final uniqueTracks = <Track>[];

    for (final track in tracks) {
      final key = track.uniqueKey;
      final existingIndex = keyToIndex[key];
      if (existingIndex == null) {
        keyToIndex[key] = uniqueTracks.length;
        uniqueTracks.add(track);
      } else if (_hasMoreCompleteTrackData(
          track, uniqueTracks[existingIndex])) {
        uniqueTracks[existingIndex] = track;
      }
    }

    return uniqueTracks;
  }

  bool _hasMoreCompleteTrackData(Track a, Track b) {
    return _trackCompletenessScore(a) > _trackCompletenessScore(b);
  }

  int _trackCompletenessScore(Track track) {
    var score = 0;
    if (track.audioUrl != null && track.audioUrl!.isNotEmpty) score += 10;
    if (track.thumbnailUrl != null) score += 5;
    if (track.durationMs != null && track.durationMs! > 0) score += 3;
    if (track.artist != null && track.artist!.isNotEmpty) score += 2;
    return score;
  }

  bool _mergeTrackMetadataIfNeeded(Track target, Track incoming) {
    var changed = false;

    if (incoming.audioUrl != null && incoming.audioUrl!.isNotEmpty) {
      if (target.audioUrl == null ||
          target.audioUrl!.isEmpty ||
          !target.hasValidAudioUrl) {
        target.audioUrl = incoming.audioUrl;
        target.audioUrlExpiry = incoming.audioUrlExpiry;
        changed = true;
      }
    }
    if (target.thumbnailUrl == null && incoming.thumbnailUrl != null) {
      target.thumbnailUrl = incoming.thumbnailUrl;
      changed = true;
    }
    if (target.durationMs == null && incoming.durationMs != null) {
      target.durationMs = incoming.durationMs;
      changed = true;
    }
    if (target.artist == null && incoming.artist != null) {
      target.artist = incoming.artist;
      changed = true;
    }

    return changed;
  }

  /// 从歌单移除歌曲
  ///
  /// 同时清理该歌单的下载路径，如果歌曲不属于任何歌单则删除
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    // 先获取歌单，检查被移除的是否是第一首歌
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return;

    final wasFirstTrack =
        playlist.trackIds.isNotEmpty && playlist.trackIds.first == trackId;

    await _isar.writeTxn(() async {
      playlist.trackIds = List<int>.from(playlist.trackIds)..remove(trackId);
      playlist.updatedAt = DateTime.now();
      await _isar.playlists.put(playlist);

      final track = await _isar.tracks.get(trackId);
      if (track == null) return;

      track.removeFromPlaylist(playlistId);

      if (track.playlistInfo.isEmpty) {
        // 不属于任何歌单，删除歌曲记录
        await _isar.tracks.delete(trackId);
        logDebug('Deleted orphan track: ${track.title}');
      } else {
        track.updatedAt = DateTime.now();
        await _isar.tracks.put(track);
      }
    });

    // 如果移除的是第一首歌，更新非 Bilibili 歌单的封面
    if (wasFirstTrack) {
      final updatedPlaylist = await _playlistRepository.getById(playlistId);
      if (updatedPlaylist != null) {
        await _updateDefaultCover(updatedPlaylist);
      }
    }
  }

  /// 批量从歌单移除歌曲
  Future<void> removeTracksFromPlaylist(
      int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) return;

    // 先获取歌单，检查第一首歌是否会被移除
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return;

    final trackIdsToRemove = trackIds.toSet();
    final wasFirstTrackRemoved = playlist.trackIds.isNotEmpty &&
        trackIdsToRemove.contains(playlist.trackIds.first);

    await _isar.writeTxn(() async {
      playlist.trackIds = List<int>.from(playlist.trackIds)
        ..removeWhere(trackIdsToRemove.contains);
      playlist.updatedAt = DateTime.now();
      await _isar.playlists.put(playlist);

      final tracks =
          (await _isar.tracks.getAll(trackIds)).whereType<Track>().toList();

      final toDelete = <int>[];
      final toUpdate = <Track>[];

      for (final track in tracks) {
        track.removeFromPlaylist(playlistId);
        if (track.playlistInfo.isEmpty) {
          toDelete.add(track.id);
          logDebug('Will delete orphan track: ${track.title}');
        } else {
          track.updatedAt = DateTime.now();
          toUpdate.add(track);
        }
      }

      if (toDelete.isNotEmpty) {
        await _isar.tracks.deleteAll(toDelete);
      }
      if (toUpdate.isNotEmpty) {
        await _isar.tracks.putAll(toUpdate);
      }
    });

    // 如果移除的包含第一首歌，更新封面
    if (wasFirstTrackRemoved) {
      final updatedPlaylist = await _playlistRepository.getById(playlistId);
      if (updatedPlaylist != null) {
        await _updateDefaultCover(updatedPlaylist);
      }
    }
  }

  /// 重新排序歌单中的歌曲
  Future<void> reorderPlaylistTracks(
    int playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return;

    final trackIds = List<int>.from(playlist.trackIds);
    final originalFirstTrackId = trackIds.isNotEmpty ? trackIds.first : null;

    final trackId = trackIds.removeAt(oldIndex);

    // 调整插入位置
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    trackIds.insert(insertIndex, trackId);

    await _playlistRepository.reorderTracks(playlistId, trackIds);

    // 检查第一首歌是否改变，如果改变则更新非 Bilibili 歌单的封面
    final newFirstTrackId = trackIds.isNotEmpty ? trackIds.first : null;
    if (originalFirstTrackId != newFirstTrackId) {
      // 重新获取歌单
      final updatedPlaylist = await _playlistRepository.getById(playlistId);
      if (updatedPlaylist != null) {
        await _updateDefaultCover(updatedPlaylist);
      }
    }
  }

  /// 获取歌单封面数据（包含本地路径和网络 URL）
  ///
  /// 优先级：
  /// 1. 第一首已下载歌曲的本地封面
  /// 2. 歌单的网络封面 URL
  /// 3. 第一首歌曲的网络封面 URL
  Future<PlaylistCoverData> getPlaylistCoverData(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return const PlaylistCoverData();

    String? localPath;
    String? networkUrl;

    // 设置网络封面 URL
    networkUrl = playlist.coverUrl;

    // 如果没有网络封面或需要本地封面，尝试使用第一首歌的封面
    if (playlist.trackIds.isNotEmpty) {
      final firstTrack =
          await _trackRepository.getById(playlist.trackIds.first);
      if (firstTrack != null) {
        // 异步检查第一首歌的本地封面
        for (final downloadPath in firstTrack.allDownloadPaths) {
          final dir = Directory(downloadPath).parent;
          final coverPath = '${dir.path}/cover.jpg';
          if (await File(coverPath).exists()) {
            localPath = coverPath;
            break;
          }
        }
        // 如果没有网络封面，使用第一首歌的网络封面
        if (networkUrl == null && firstTrack.thumbnailUrl != null) {
          networkUrl = firstTrack.thumbnailUrl;
        }
      }
    }

    return PlaylistCoverData(localPath: localPath, networkUrl: networkUrl);
  }

  /// 更新歌單的默認封面（使用第一首歌曲的縮略圖）
  ///
  /// 當歌單中的歌曲順序發生變化時調用此方法。
  /// 如果用戶已手動設置封面（hasCustomCover = true），則不會更新。
  Future<void> _updateDefaultCover(Playlist playlist) async {
    // 用戶手動設置的封面不會被自動更新
    if (playlist.hasCustomCover) {
      return;
    }

    String? newCoverUrl;
    if (playlist.trackIds.isNotEmpty) {
      final firstTrack =
          await _trackRepository.getById(playlist.trackIds.first);
      newCoverUrl = firstTrack?.thumbnailUrl;
    }

    // 只有當封面確實變化時才更新
    if (playlist.coverUrl != newCoverUrl) {
      playlist.coverUrl = newCoverUrl;
      await _playlistRepository.save(playlist);
      logDebug(
          'Updated playlist cover for "${playlist.name}" to: $newCoverUrl');
    }
  }

  /// 获取歌单封面（使用第一首歌的封面或自定义封面）
  /// @deprecated 使用 [getPlaylistCoverData] 替代
  Future<String?> getPlaylistCover(int playlistId) async {
    final coverData = await getPlaylistCoverData(playlistId);
    return coverData.localPath ?? coverData.networkUrl;
  }

  /// 复制歌单
  Future<Playlist> duplicatePlaylist(int playlistId, String newName) async {
    final original = await _playlistRepository.getById(playlistId);
    if (original == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    // 检查名称是否已存在
    if (await _playlistRepository.nameExists(newName)) {
      throw PlaylistNameExistsException(newName);
    }

    // 獲取下一個排序順序
    final nextSortOrder = await _playlistRepository.getNextSortOrder();

    final copy = Playlist()
      ..name = newName
      ..sortOrder = nextSortOrder
      ..createdAt = DateTime.now();

    await _isar.writeTxn(() async {
      final freshOriginal = await _isar.playlists.get(playlistId);
      if (freshOriginal == null) {
        throw PlaylistNotFoundException(playlistId);
      }

      copy
        ..description = freshOriginal.description
        ..coverUrl = freshOriginal.coverUrl
        ..hasCustomCover = freshOriginal.hasCustomCover
        ..trackIds = List.from(freshOriginal.trackIds)
        ..updatedAt = DateTime.now();
      final id = await _isar.playlists.put(copy);
      copy.id = id;

      final copiedTracks = (await _isar.tracks.getAll(copy.trackIds))
          .whereType<Track>()
          .toList();
      for (final track in copiedTracks) {
        track.addToPlaylist(copy.id, playlistName: copy.name);
        track.updatedAt = DateTime.now();
      }
      if (copiedTracks.isNotEmpty) {
        await _isar.tracks.putAll(copiedTracks);
      }
    });
    return copy;
  }

  /// 重新排序歌單列表
  ///
  /// [playlists] 是按新順序排列的歌單列表
  Future<void> reorderPlaylists(List<Playlist> playlists) async {
    await _playlistRepository.updateSortOrders(playlists);
  }
}

/// 歌单及其歌曲
class PlaylistWithTracks {
  final Playlist playlist;
  final List<Track> tracks;
  final int totalTrackCount;
  final bool hasMore;

  const PlaylistWithTracks({
    required this.playlist,
    required this.tracks,
    int? totalTrackCount,
    this.hasMore = false,
  }) : totalTrackCount = totalTrackCount ?? tracks.length;

  int get trackCount => totalTrackCount;

  Duration get totalDuration {
    int totalMs = 0;
    for (final track in tracks) {
      totalMs += track.durationMs ?? 0;
    }
    return Duration(milliseconds: totalMs);
  }
}

/// 歌单名称已存在异常
class PlaylistNameExistsException implements Exception {
  final String name;
  const PlaylistNameExistsException(this.name);

  @override
  String toString() => t.importSource.playlistNameExists(name: name);
}

/// 歌单未找到异常
class PlaylistNotFoundException implements Exception {
  final int playlistId;
  const PlaylistNotFoundException(this.playlistId);

  @override
  String toString() =>
      t.importSource.playlistIdNotFound(id: playlistId.toString());
}
