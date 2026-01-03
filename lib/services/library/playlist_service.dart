import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/track_repository.dart';

/// 歌单管理服务
class PlaylistService {
  final PlaylistRepository _playlistRepository;
  final TrackRepository _trackRepository;

  PlaylistService({
    required PlaylistRepository playlistRepository,
    required TrackRepository trackRepository,
  })  : _playlistRepository = playlistRepository,
        _trackRepository = trackRepository;

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

  /// 获取歌单封面（使用第一首歌的封面或自定义封面）
  Future<String?> getPlaylistCover(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) return null;

    // 优先使用自定义封面
    if (playlist.coverUrl != null) {
      return playlist.coverUrl;
    }

    // 使用本地封面
    if (playlist.coverLocalPath != null) {
      return playlist.coverLocalPath;
    }

    // 使用第一首歌的封面
    if (playlist.trackIds.isNotEmpty) {
      final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
      return firstTrack?.thumbnailUrl;
    }

    return null;
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
