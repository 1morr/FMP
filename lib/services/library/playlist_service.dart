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
import '../download/playlist_folder_migrator.dart';

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

    // 预计算本地封面路径
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    final coverLocalPath = _computePlaylistCoverPath(baseDir, name);

    final playlist = Playlist()
      ..name = name
      ..description = description
      ..coverUrl = coverUrl
      ..coverLocalPath = coverLocalPath
      ..createdAt = DateTime.now();

    final id = await _playlistRepository.save(playlist);
    playlist.id = id;
    return playlist;
  }

  /// 更新歌单信息
  ///
  /// 返回 [PlaylistUpdateResult]，如果重命名了歌单且有已下载的文件，
  /// 结果中会包含旧文件夹路径，提示用户手动移动。
  Future<PlaylistUpdateResult> updatePlaylist({
    required int playlistId,
    String? name,
    String? description,
    String? coverUrl,
  }) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    final oldName = playlist.name;
    bool isRenaming = false;
    String? oldDownloadFolder;
    String? newDownloadFolder;

    // 检查新名称是否已存在（排除当前歌单）
    if (name != null && name != playlist.name) {
      if (await _playlistRepository.nameExists(name, excludeId: playlistId)) {
        throw PlaylistNameExistsException(name);
      }
      playlist.name = name;
      isRenaming = true;

      // 更新预计算的本地封面路径
      final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
      playlist.coverLocalPath = _computePlaylistCoverPath(baseDir, name);

      // 检查旧文件夹是否存在（有下载文件）
      final oldFolderName = DownloadPathUtils.sanitizeFileName(oldName);
      final oldFolder = Directory(p.join(baseDir, oldFolderName));
      if (await oldFolder.exists()) {
        oldDownloadFolder = oldFolder.path;
        final newFolderName = DownloadPathUtils.sanitizeFileName(name);
        newDownloadFolder = p.join(baseDir, newFolderName);
      }
    }

    if (description != null) {
      playlist.description = description;
    }
    if (coverUrl != null) {
      playlist.coverUrl = coverUrl;
    }

    await _playlistRepository.save(playlist);

    // 歌单改名时只更新预计算路径，不再自动移动文件
    if (isRenaming) {
      final migrator = PlaylistFolderMigrator(
        isar: _isar,
        settingsRepository: _settingsRepository,
      );

      // 更新所有 Track 的预计算下载路径（包括未下载的）
      try {
        final updatedCount = await migrator.updateAllTrackDownloadPaths(
          playlist: playlist,
          newName: name!,
        );
        logDebug('Updated $updatedCount track download paths');
      } catch (e, stack) {
        logError('Failed to update track download paths: $e', e, stack);
      }
    }

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
      // 移除该歌单的下载路径
      track.removeDownloadPath(playlistId);

      // 检查是否还属于其他歌单
      if (track.playlistIds.isEmpty) {
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
  /// 同时预计算并设置下载路径。
  /// 使用 getOrCreate 确保使用数据库中的最新数据，避免缓存导致的数据不同步问题。
  Future<void> addTrackToPlaylist(int playlistId, Track track) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    // 先获取数据库中最新的 track 或创建新的
    // 这避免了使用缓存的旧 track 对象导致 playlistIds/downloadPaths 数据不同步
    final existingTrack = await _trackRepository.getOrCreate(track);
    
    // 检查是否已在该歌单中
    if (existingTrack.playlistIds.contains(playlistId)) {
      logDebug('Track ${existingTrack.title} already in playlist $playlistId, skipping');
      return;
    }

    // 计算下载路径
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    final downloadPath = DownloadPathUtils.computeDownloadPath(
      baseDir: baseDir,
      playlistName: playlist.name,
      track: existingTrack,
    );

    // 设置下载路径（在数据库返回的最新对象上操作）
    existingTrack.setDownloadPath(playlistId, downloadPath);

    // 保存歌曲
    final savedTrack = await _trackRepository.save(existingTrack);
    await _playlistRepository.addTrack(playlistId, savedTrack.id);
  }

  /// 批量添加歌曲到歌单
  /// 
  /// 同时预计算并设置下载路径。
  /// 使用 getOrCreateAll 确保使用数据库中的最新数据，避免缓存导致的数据不同步问题。
  Future<void> addTracksToPlaylist(int playlistId, List<Track> tracks) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    // 先获取数据库中最新的 tracks 或创建新的
    final existingTracks = await _trackRepository.getOrCreateAll(tracks);
    
    // 过滤掉已在该歌单中的 tracks
    final tracksToAdd = existingTracks
        .where((t) => !t.playlistIds.contains(playlistId))
        .toList();
    
    if (tracksToAdd.isEmpty) {
      logDebug('All ${tracks.length} tracks already in playlist $playlistId, skipping');
      return;
    }

    // 获取下载基础目录
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);

    // 为每个歌曲计算并设置下载路径（在数据库返回的最新对象上操作）
    for (final track in tracksToAdd) {
      final downloadPath = DownloadPathUtils.computeDownloadPath(
        baseDir: baseDir,
        playlistName: playlist.name,
        track: track,
      );
      track.setDownloadPath(playlistId, downloadPath);
    }

    // 保存所有歌曲
    final savedTracks = await _trackRepository.saveAll(tracksToAdd);
    final trackIds = savedTracks.map((t) => t.id).toList();
    await _playlistRepository.addTracks(playlistId, trackIds);
    
    if (tracksToAdd.length < existingTracks.length) {
      logDebug('Added ${tracksToAdd.length}/${existingTracks.length} tracks to playlist $playlistId (${existingTracks.length - tracksToAdd.length} already existed)');
    }
  }

  /// 从歌单移除歌曲
  /// 
  /// 同时清理该歌单的下载路径，如果歌曲不属于任何歌单则删除
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await _playlistRepository.removeTrack(playlistId, trackId);

    // 移除该歌单的下载路径
    final track = await _trackRepository.getById(trackId);
    if (track != null) {
      track.removeDownloadPath(playlistId);

      if (track.playlistIds.isEmpty) {
        // 不属于任何歌单，删除歌曲记录
        await _trackRepository.delete(trackId);
        logDebug('Deleted orphan track: ${track.title}');
      } else {
        await _trackRepository.save(track);
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
    final trackId = trackIds.removeAt(oldIndex);

    // 调整插入位置
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    trackIds.insert(insertIndex, trackId);

    await _playlistRepository.reorderTracks(playlistId, trackIds);
  }

  /// 获取歌单封面数据（包含本地路径和网络 URL）
  ///
  /// 优先级：
  /// 1. 本地歌单封面（异步检查文件实际存在）
  /// 2. 第一首已下载歌曲的本地封面
  /// 3. 歌单的网络封面 URL
  /// 4. 第一首歌曲的网络封面 URL
  Future<PlaylistCoverData> getPlaylistCoverData(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return const PlaylistCoverData();

    String? localPath;
    String? networkUrl;

    // 异步检查歌单本地封面是否存在
    if (playlist.coverLocalPath != null) {
      if (await File(playlist.coverLocalPath!).exists()) {
        localPath = playlist.coverLocalPath;
      }
    }

    // 设置网络封面 URL
    networkUrl = playlist.coverUrl;

    // 如果没有歌单级别的封面，尝试使用第一首歌的封面
    if (localPath == null && networkUrl == null && playlist.trackIds.isNotEmpty) {
      final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
      if (firstTrack != null) {
        // 异步检查第一首歌的本地封面
        for (final downloadPath in firstTrack.downloadPaths) {
          final dir = Directory(downloadPath).parent;
          final coverPath = '${dir.path}/cover.jpg';
          if (await File(coverPath).exists()) {
            localPath = coverPath;
            break;
          }
        }
        // 设置网络封面
        if (firstTrack.thumbnailUrl != null) {
          networkUrl = firstTrack.thumbnailUrl;
        }
      }
    }

    return PlaylistCoverData(localPath: localPath, networkUrl: networkUrl);
  }

  /// 计算歌单封面的本地路径
  ///
  /// 路径格式: {baseDir}/{playlistName}/playlist_cover.jpg
  String _computePlaylistCoverPath(String baseDir, String playlistName) {
    final subDir = DownloadPathUtils.sanitizeFileName(playlistName);
    return p.join(baseDir, subDir, 'playlist_cover.jpg');
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

    // 计算新歌单的封面路径
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    final coverLocalPath = _computePlaylistCoverPath(baseDir, newName);

    final copy = Playlist()
      ..name = newName
      ..description = original.description
      ..coverUrl = original.coverUrl
      ..coverLocalPath = coverLocalPath
      ..trackIds = List.from(original.trackIds)
      ..createdAt = DateTime.now();

    final id = await _playlistRepository.save(copy);
    copy.id = id;
    return copy;
  }
}

/// 歌单及其歌曲
class PlaylistWithTracks {
  final Playlist playlist;
  final List<Track> tracks;

  const PlaylistWithTracks({
    required this.playlist,
    required this.tracks,
  });

  int get trackCount => tracks.length;

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
  String toString() => '歌单名称 "$name" 已存在';
}

/// 歌单未找到异常
class PlaylistNotFoundException implements Exception {
  final int playlistId;
  const PlaylistNotFoundException(this.playlistId);

  @override
  String toString() => '歌单 (id: $playlistId) 不存在';
}
