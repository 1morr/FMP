import '../../data/models/playlist.dart';
import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

import '../../core/extensions/track_extensions.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../download/download_path_utils.dart';
import '../download/playlist_folder_migrator.dart';

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
  Future<Playlist> updatePlaylist({
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
    }

    if (description != null) {
      playlist.description = description;
    }
    if (coverUrl != null) {
      playlist.coverUrl = coverUrl;
    }

    await _playlistRepository.save(playlist);

    // 歌单改名时迁移下载文件夹
    if (isRenaming) {
      try {
        final migrator = PlaylistFolderMigrator(
          isar: _isar,
          settingsRepository: _settingsRepository,
        );
        final migratedCount = await migrator.migratePlaylistFolder(
          playlist: playlist,
          oldName: oldName,
          newName: name!,
        );
        logDebug('Migrated $migratedCount files after playlist rename');
      } catch (e, stack) {
        logError('Failed to migrate playlist folder: $e', e, stack);
        // 不抛出异常，文件夹迁移失败不影响歌单重命名
      }
    }

    return playlist;
  }

  /// 删除歌单
  /// 
  /// 同时清理不被其他歌单引用的孤立歌曲
  Future<void> deletePlaylist(int playlistId) async {
    // 获取歌单信息
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return;

    final trackIds = playlist.trackIds;

    // 删除歌单
    await _playlistRepository.delete(playlistId);

    // 清理孤立歌曲：移除该歌单的下载路径，如果歌曲不属于任何歌单则删除
    for (final trackId in trackIds) {
      final track = await _trackRepository.getById(trackId);
      if (track == null) continue;

      // 移除该歌单的下载路径
      track.removeDownloadPath(playlistId);

      // 检查是否还属于其他歌单
      if (track.playlistIds.isEmpty) {
        // 不属于任何歌单，删除歌曲记录
        await _trackRepository.delete(trackId);
        logDebug('Deleted orphan track: ${track.title}');
      } else {
        // 还属于其他歌单，保存更新
        await _trackRepository.save(track);
      }
    }
  }

  /// 添加歌曲到歌单
  /// 
  /// 同时预计算并设置下载路径
  Future<void> addTrackToPlaylist(int playlistId, Track track) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    // 计算下载路径
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);
    final downloadPath = DownloadPathUtils.computeDownloadPath(
      baseDir: baseDir,
      playlistName: playlist.name,
      track: track,
    );

    // 设置下载路径
    track.setDownloadPath(playlistId, downloadPath);

    // 保存歌曲
    final savedTrack = await _trackRepository.save(track);
    await _playlistRepository.addTrack(playlistId, savedTrack.id);
  }

  /// 批量添加歌曲到歌单
  /// 
  /// 同时预计算并设置下载路径
  Future<void> addTracksToPlaylist(int playlistId, List<Track> tracks) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    // 获取下载基础目录
    final baseDir = await DownloadPathUtils.getDefaultBaseDir(_settingsRepository);

    // 为每个歌曲计算并设置下载路径
    for (final track in tracks) {
      final downloadPath = DownloadPathUtils.computeDownloadPath(
        baseDir: baseDir,
        playlistName: playlist.name,
        track: track,
      );
      track.setDownloadPath(playlistId, downloadPath);
    }

    // 保存所有歌曲
    final savedTracks = await _trackRepository.saveAll(tracks);
    final trackIds = savedTracks.map((t) => t.id).toList();
    await _playlistRepository.addTracks(playlistId, trackIds);
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
  /// 1. 预计算的本地歌单封面路径（playlist.coverLocalPath）
  /// 2. 第一首已下载歌曲的本地封面
  /// 3. 歌单的网络封面 URL
  /// 4. 第一首歌曲的网络封面 URL
  Future<PlaylistCoverData> getPlaylistCoverData(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return const PlaylistCoverData();

    String? localPath;
    String? networkUrl;

    // 使用预计算的本地封面路径
    if (playlist.coverLocalPath != null) {
      localPath = playlist.coverLocalPath;
    }

    // 设置网络封面 URL
    if (playlist.coverUrl != null) {
      networkUrl = playlist.coverUrl;
    }

    // 如果没有歌单级别的封面，尝试使用第一首歌的封面
    if (localPath == null && networkUrl == null && playlist.trackIds.isNotEmpty) {
      final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
      if (firstTrack != null) {
        // 检查第一首歌的本地封面
        final trackLocalCover = firstTrack.localCoverPath;
        if (trackLocalCover != null) {
          localPath = trackLocalCover;
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
