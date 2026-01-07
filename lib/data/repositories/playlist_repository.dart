import 'package:isar/isar.dart';
import '../models/playlist.dart';

/// Playlist 数据仓库
class PlaylistRepository {
  final Isar _isar;

  PlaylistRepository(this._isar);

  /// 获取所有歌单
  Future<List<Playlist>> getAll() async {
    return _isar.playlists.where().findAll();
  }

  /// 根据ID获取歌单
  Future<Playlist?> getById(int id) async {
    return _isar.playlists.get(id);
  }

  /// 根据名称获取歌单
  Future<Playlist?> getByName(String name) async {
    return _isar.playlists.where().nameEqualTo(name).findFirst();
  }

  /// 获取导入的歌单
  Future<List<Playlist>> getImported() async {
    return _isar.playlists.filter().sourceUrlIsNotNull().findAll();
  }

  /// 获取需要刷新的歌单
  Future<List<Playlist>> getNeedingRefresh() async {
    final imported = await getImported();
    return imported.where((p) => p.needsRefresh).toList();
  }

  /// 保存歌单
  Future<int> save(Playlist playlist) async {
    playlist.updatedAt = DateTime.now();
    return _isar.writeTxn(() => _isar.playlists.put(playlist));
  }

  /// 删除歌单
  Future<bool> delete(int id) async {
    return _isar.writeTxn(() => _isar.playlists.delete(id));
  }

  /// 添加歌曲到歌单
  Future<void> addTrack(int playlistId, int trackId) async {
    final playlist = await getById(playlistId);
    if (playlist != null && !playlist.trackIds.contains(trackId)) {
      // 创建可变列表副本，避免 fixed-length list 错误
      final newTrackIds = List<int>.from(playlist.trackIds);
      newTrackIds.add(trackId);
      playlist.trackIds = newTrackIds;
      await save(playlist);
    }
  }

  /// 批量添加歌曲到歌单
  Future<void> addTracks(int playlistId, List<int> trackIds) async {
    final playlist = await getById(playlistId);
    if (playlist != null) {
      // 创建可变列表副本，避免 fixed-length list 错误
      final newTrackIds = List<int>.from(playlist.trackIds);
      for (final trackId in trackIds) {
        if (!newTrackIds.contains(trackId)) {
          newTrackIds.add(trackId);
        }
      }
      playlist.trackIds = newTrackIds;
      await save(playlist);
    }
  }

  /// 从歌单移除歌曲
  Future<void> removeTrack(int playlistId, int trackId) async {
    final playlist = await getById(playlistId);
    if (playlist != null) {
      // 创建可变列表副本，避免 fixed-length list 错误
      final newTrackIds = List<int>.from(playlist.trackIds);
      newTrackIds.remove(trackId);
      playlist.trackIds = newTrackIds;
      await save(playlist);
    }
  }

  /// 更新歌单歌曲顺序
  Future<void> reorderTracks(int playlistId, List<int> newOrder) async {
    final playlist = await getById(playlistId);
    if (playlist != null) {
      playlist.trackIds = newOrder;
      await save(playlist);
    }
  }

  /// 更新刷新时间
  Future<void> updateLastRefreshed(int playlistId) async {
    final playlist = await getById(playlistId);
    if (playlist != null) {
      playlist.lastRefreshed = DateTime.now();
      await save(playlist);
    }
  }

  /// 检查名称是否存在
  Future<bool> nameExists(String name, {int? excludeId}) async {
    final existing = await getByName(name);
    if (existing == null) return false;
    if (excludeId != null && existing.id == excludeId) return false;
    return true;
  }
}
