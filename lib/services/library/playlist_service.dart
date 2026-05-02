import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

import '../../core/logger.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../download/download_path_utils.dart';
import 'playlist_exceptions.dart';
import 'playlist_mutation_service.dart';

export 'playlist_exceptions.dart';

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
  final PlaylistMutationService _mutationService;

  PlaylistService({
    required PlaylistRepository playlistRepository,
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
    required Isar isar,
    PlaylistMutationService? mutationService,
  })  : _playlistRepository = playlistRepository,
        _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _isar = isar,
        _mutationService =
            mutationService ?? PlaylistMutationService(isar: isar);

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
  Future<void> deletePlaylist(int playlistId) async {
    await _mutationService.deletePlaylist(playlistId);
  }

  /// 添加歌曲到歌单
  ///
  /// 在单个事务中解析或创建 Track，并同时写入 Playlist.trackIds 和
  /// Track.playlistInfo，避免关系事务前先写入孤立 Track。
  /// 注意：下载路径不再预计算，将在实际下载完成时由 DownloadService 设置。
  Future<void> addTrackToPlaylist(int playlistId, Track track) async {
    await _mutationService.addTrack(playlistId, track);
  }

  /// 批量添加歌曲到歌单
  ///
  /// 在单个事务中解析或创建 Track，并同时写入 Playlist.trackIds 和
  /// Track.playlistInfo，避免关系事务前先写入孤立 Track。
  /// 注意：下载路径不再预计算，将在实际下载完成时由 DownloadService 设置。
  Future<void> addTracksToPlaylist(int playlistId, List<Track> tracks) async {
    final result = await _mutationService.addTracks(playlistId, tracks);
    if (result.addedCount == 0 && result.repairedCount == 0) {
      logDebug(
          'All ${tracks.length} tracks already in playlist $playlistId, skipping');
    } else if (result.addedCount + result.repairedCount < tracks.length) {
      logDebug(
          'Added or repaired ${result.addedCount + result.repairedCount}/${tracks.length} tracks in playlist $playlistId');
    }
  }

  /// 从歌单移除歌曲
  ///
  /// 同时清理该歌单的下载路径，如果歌曲不属于任何歌单则删除
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await _mutationService.removeTrack(playlistId, trackId);
  }

  /// 批量从歌单移除歌曲
  Future<void> removeTracksFromPlaylist(
      int playlistId, List<int> trackIds) async {
    await _mutationService.removeTracks(playlistId, trackIds);
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
    final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    trackIds.insert(insertIndex, trackId);

    await _mutationService.reorderTracks(playlistId, trackIds);
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
          final coverPath = p.join(dir.path, 'cover.jpg');
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

    return _mutationService.duplicatePlaylist(playlistId, copy);
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
