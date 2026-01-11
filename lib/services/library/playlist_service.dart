import '../../data/models/playlist.dart';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/extensions/track_extensions.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';

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
class PlaylistService {
  final PlaylistRepository _playlistRepository;
  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;

  PlaylistService({
    required PlaylistRepository playlistRepository,
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
  })  : _playlistRepository = playlistRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository;

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

    final playlist = Playlist()
      ..name = name
      ..description = description
      ..coverUrl = coverUrl
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

    // 检查新名称是否已存在（排除当前歌单）
    if (name != null && name != playlist.name) {
      if (await _playlistRepository.nameExists(name, excludeId: playlistId)) {
        throw PlaylistNameExistsException(name);
      }
      playlist.name = name;
    }

    if (description != null) {
      playlist.description = description;
    }
    if (coverUrl != null) {
      playlist.coverUrl = coverUrl;
    }

    await _playlistRepository.save(playlist);
    return playlist;
  }

  /// 删除歌单
  Future<void> deletePlaylist(int playlistId) async {
    await _playlistRepository.delete(playlistId);
  }

  /// 添加歌曲到歌单
  Future<void> addTrackToPlaylist(int playlistId, Track track) async {
    // 确保歌曲已保存到数据库
    final savedTrack = await _trackRepository.save(track);
    await _playlistRepository.addTrack(playlistId, savedTrack.id);
  }

  /// 批量添加歌曲到歌单
  Future<void> addTracksToPlaylist(int playlistId, List<Track> tracks) async {
    // 保存所有歌曲
    final savedTracks = await _trackRepository.saveAll(tracks);
    final trackIds = savedTracks.map((t) => t.id).toList();
    await _playlistRepository.addTracks(playlistId, trackIds);
  }

  /// 从歌单移除歌曲
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await _playlistRepository.removeTrack(playlistId, trackId);
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
  /// 1. 本地已下载的歌单封面（playlist_cover.jpg）
  /// 2. 第一首已下载歌曲的本地封面
  /// 3. 歌单的网络封面 URL
  /// 4. 第一首歌曲的网络封面 URL
  Future<PlaylistCoverData> getPlaylistCoverData(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return const PlaylistCoverData();

    String? localPath;
    String? networkUrl;

    // 检查下载目录中的歌单封面
    final playlistLocalCover = await _findPlaylistLocalCover(playlist);
    if (playlistLocalCover != null) {
      localPath = playlistLocalCover;
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

  /// 查找歌单的本地封面文件
  Future<String?> _findPlaylistLocalCover(Playlist playlist) async {
    try {
      final settings = await _settingsRepository.get();
      String baseDir;

      if (settings.customDownloadDir != null && settings.customDownloadDir!.isNotEmpty) {
        baseDir = settings.customDownloadDir!;
      } else {
        if (Platform.isAndroid) {
          final dirs = await getExternalStorageDirectories(type: StorageDirectory.music);
          baseDir = dirs?.first.path ?? (await getApplicationDocumentsDirectory()).path;
        } else {
          baseDir = (await getDownloadsDirectory())?.path ?? 
                    (await getApplicationDocumentsDirectory()).path;
        }
        baseDir = p.join(baseDir, 'FMP');
      }

      // 歌单文件夹名称格式：歌单名_ID
      final subDir = _sanitizeFileName('${playlist.name}_${playlist.id}');
      final coverPath = p.join(baseDir, subDir, 'playlist_cover.jpg');
      final coverFile = File(coverPath);

      if (await coverFile.exists()) {
        return coverPath;
      }
    } catch (e) {
      // 忽略错误，返回 null
    }
    return null;
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
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

    final copy = Playlist()
      ..name = newName
      ..description = original.description
      ..coverUrl = original.coverUrl
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
