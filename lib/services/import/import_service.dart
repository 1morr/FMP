import 'dart:async';

import 'package:isar/isar.dart';

import '../../core/logger.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/sources/source_provider.dart';
import '../../data/sources/youtube_source.dart';
import 'package:fmp/i18n/strings.g.dart';

/// 导入进度
class ImportProgress {
  final int current;
  final int total;
  final String? currentItem;
  final ImportStatus status;
  final String? error;

  const ImportProgress({
    this.current = 0,
    this.total = 0,
    this.currentItem,
    this.status = ImportStatus.idle,
    this.error,
  });

  double get percentage => total > 0 ? current / total : 0;

  ImportProgress copyWith({
    int? current,
    int? total,
    String? currentItem,
    ImportStatus? status,
    String? error,
  }) {
    return ImportProgress(
      current: current ?? this.current,
      total: total ?? this.total,
      currentItem: currentItem ?? this.currentItem,
      status: status ?? this.status,
      error: error,
    );
  }
}

enum ImportStatus {
  idle,
  parsing,
  importing,
  completed,
  failed,
}

/// 导入结果
class ImportResult {
  final Playlist playlist;
  final int addedCount;
  final int skippedCount;
  final int removedCount;
  final List<String> errors;

  const ImportResult({
    required this.playlist,
    required this.addedCount,
    required this.skippedCount,
    this.removedCount = 0,
    required this.errors,
  });
}

/// 外部导入服务
class ImportService with Logging {
  final SourceManager _sourceManager;
  final PlaylistRepository _playlistRepository;
  final TrackRepository _trackRepository;
  final Isar _isar;

  // 导入进度流
  final _progressController = StreamController<ImportProgress>.broadcast();
  Stream<ImportProgress> get progressStream => _progressController.stream;

  ImportProgress _currentProgress = const ImportProgress();

  /// 取消标记
  bool _isCancelled = false;

  /// 取消导入后需要清理的歌单 ID
  int? _cancelledPlaylistId;

  /// 取消当前导入
  void cancelImport() {
    _isCancelled = true;
  }

  /// 清理取消导入后残留的歌单（在导入完全停止后调用）
  Future<void> cleanupCancelledImport() async {
    final playlistId = _cancelledPlaylistId;
    _cancelledPlaylistId = null;
    if (playlistId != null) {
      try {
        await _playlistRepository.delete(playlistId);
      } catch (_) {
        // 清理失败不影响功能
      }
    }
  }

  ImportService({
    required SourceManager sourceManager,
    required PlaylistRepository playlistRepository,
    required TrackRepository trackRepository,
    required Isar isar,
  })  : _sourceManager = sourceManager,
        _playlistRepository = playlistRepository,
        _trackRepository = trackRepository,
        _isar = isar;

  /// 从 URL 导入歌单/收藏夹
  Future<ImportResult> importFromUrl(
    String url, {
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
  }) async {
    _isCancelled = false;
    _cancelledPlaylistId = null;
    _updateProgress(status: ImportStatus.parsing, currentItem: t.importSource.parsingUrl);

    try {
      // 识别音源类型
      final source = _sourceManager.detectSource(url);
      if (source == null) {
        throw ImportException(t.importSource.unrecognizedUrlFormat);
      }

      // 檢測是否為 YouTube Mix 播放列表（RD 開頭）
      if (source is YouTubeSource && YouTubeSource.isMixPlaylistUrl(url)) {
        return _importMixPlaylist(
          url: url,
          customName: customName,
          refreshIntervalHours: refreshIntervalHours,
          notifyOnUpdate: notifyOnUpdate,
        );
      }

      // 解析播放列表
      final result = await source.parsePlaylist(url);

      // 获取分P信息并展开（仅Bilibili）
      final List<Track> expandedTracks;
      if (source is BilibiliSource) {
        expandedTracks = await _expandMultiPageVideos(
          source,
          result.tracks,
          (current, total, item) {
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(current: current.toString(), total: total.toString()),
            );
          },
        );
      } else {
        expandedTracks = result.tracks;
      }

      _updateProgress(
        status: ImportStatus.importing,
        total: expandedTracks.length,
        current: 0,
        currentItem: t.importSource.importingProgress,
      );

      // 创建歌单
      final playlistName = customName ?? result.title;
      final existingPlaylist =
          await _playlistRepository.getByName(playlistName);

      Playlist playlist;
      if (existingPlaylist != null) {
        // 更新现有歌单
        playlist = existingPlaylist;
      } else {
        // 创建新歌单
        // 注意：coverUrl 不在此處設置，會在導入完成後使用第一首歌曲的縮略圖
        playlist = Playlist()
          ..name = playlistName
          ..description = result.description
          ..sourceUrl = url
          ..importSourceType = source.sourceType
          ..refreshIntervalHours = refreshIntervalHours ?? 24
          ..notifyOnUpdate = notifyOnUpdate
          ..createdAt = DateTime.now();
        // 先保存以获取 ID（用于计算下载路径）
        final playlistId = await _playlistRepository.save(playlist);
        playlist.id = playlistId;
      }

      // 导入歌曲
      int addedCount = 0;
      int skippedCount = 0;
      final errors = <String>[];
      final isNewPlaylist = existingPlaylist == null;

      for (int i = 0; i < expandedTracks.length; i++) {
        if (_isCancelled) {
          // 记录需要清理的歌单 ID，不在此处直接删除
          // （在 Isar 写入事务进行中删除会导致崩溃）
          if (isNewPlaylist) {
            _cancelledPlaylistId = playlist.id;
          }
          throw ImportException(t.importSource.cancelled);
        }

        final track = expandedTracks[i];

        _updateProgress(
          current: i + 1,
          currentItem: track.title,
        );

        try {
          // 检查是否已存在（支持分P唯一性）
          final existing = await _trackRepository.getBySourceIdAndCid(
            track.sourceId,
            track.sourceType,
            cid: track.cid,
          );

          if (existing != null) {
            // 歌曲已存在，添加到歌单（如果不在）
            if (!playlist.trackIds.contains(existing.id)) {
              // 只添加歌单关联，不预计算下载路径（路径在下载完成时设置）
              existing.addToPlaylist(playlist.id, playlistName: playlist.name);
              await _trackRepository.save(existing);
              
              // 创建可变列表副本，避免 fixed-length list 错误
              final newTrackIds = List<int>.from(playlist.trackIds);
              newTrackIds.add(existing.id);
              playlist.trackIds = newTrackIds;
              addedCount++;
            } else {
              skippedCount++;
            }
          } else {
            // 只添加歌单关联，不预计算下载路径（路径在下载完成时设置）
            track.addToPlaylist(playlist.id, playlistName: playlist.name);
            
            // 保存新歌曲
            final savedTrack = await _trackRepository.save(track);
            // 创建可变列表副本，避免 fixed-length list 错误
            final newTrackIds = List<int>.from(playlist.trackIds);
            newTrackIds.add(savedTrack.id);
            playlist.trackIds = newTrackIds;
            addedCount++;
          }
        } catch (e) {
          errors.add('${track.title}: ${e.toString()}');
        }
      }

      // 更新歌单封面（使用第一首歌曲的縮略圖）
      if (!playlist.hasCustomCover && playlist.trackIds.isNotEmpty) {
        final firstTrack = await _trackRepository.getById(playlist.trackIds.first);
        if (firstTrack?.thumbnailUrl != null) {
          playlist.coverUrl = firstTrack!.thumbnailUrl;
        }
      }

      // 更新歌单
      playlist.lastRefreshed = DateTime.now();
      await _playlistRepository.save(playlist);

      _updateProgress(status: ImportStatus.completed);

      return ImportResult(
        playlist: playlist,
        addedCount: addedCount,
        skippedCount: skippedCount,
        errors: errors,
      );
    } catch (e) {
      _updateProgress(status: ImportStatus.failed, error: e.toString());
      rethrow;
    }
  }

  /// 導入 YouTube Mix 播放列表
  /// 
  /// Mix 播放列表是動態生成的，只保存元數據（不保存 tracks）
  /// tracks 會在進入歌單頁時從 InnerTube API 實時獲取
  Future<ImportResult> _importMixPlaylist({
    required String url,
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
  }) async {
    _updateProgress(status: ImportStatus.parsing, currentItem: t.importSource.parsingMixPlaylist);

    try {
      final youtubeSource = YouTubeSource();
      
      // 獲取 Mix 播放列表基本信息
      final mixInfo = await youtubeSource.getMixPlaylistInfo(url);
      
      _updateProgress(
        status: ImportStatus.importing,
        currentItem: t.importSource.creatingPlaylist,
      );

      // 創建歌單名稱
      final playlistName = customName ?? mixInfo.title;
      final existingPlaylist = await _playlistRepository.getByName(playlistName);

      Playlist playlist;
      if (existingPlaylist != null) {
        // 更新現有歌單（Mix 歌單只更新元數據）
        playlist = existingPlaylist
          ..mixPlaylistId = mixInfo.playlistId
          ..mixSeedVideoId = mixInfo.seedVideoId
          ..updatedAt = DateTime.now();
        // 只有在沒有自定義封面時才更新封面
        if (!existingPlaylist.hasCustomCover) {
          playlist.coverUrl = mixInfo.coverUrl;
        }
      } else {
        // 創建新的 Mix 歌單
        playlist = Playlist()
          ..name = playlistName
          ..description = t.importSource.mixPlaylistDescription
          ..coverUrl = mixInfo.coverUrl
          ..sourceUrl = url
          ..importSourceType = SourceType.youtube
          ..isMix = true
          ..mixPlaylistId = mixInfo.playlistId
          ..mixSeedVideoId = mixInfo.seedVideoId
          ..refreshIntervalHours = null  // Mix 不需要定時刷新
          ..notifyOnUpdate = notifyOnUpdate
          ..createdAt = DateTime.now();
      }

      // 保存歌單（Mix 歌單不保存 tracks）
      await _playlistRepository.save(playlist);

      _updateProgress(status: ImportStatus.completed);

      logInfo('Mix playlist imported: ${playlist.name} (playlistId: ${mixInfo.playlistId})');

      return ImportResult(
        playlist: playlist,
        addedCount: 0,  // Mix 歌單不保存 tracks
        skippedCount: 0,
        errors: [],
      );
    } catch (e) {
      _updateProgress(status: ImportStatus.failed, error: e.toString());
      rethrow;
    }
  }

  /// 刷新导入的歌单
  Future<ImportResult> refreshPlaylist(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw ImportException(t.importSource.playlistNotFound);
    }

    if (!playlist.isImported || playlist.sourceUrl == null) {
      throw ImportException(t.importSource.notImportedPlaylist);
    }

    // Mix 播放列表不需要刷新（tracks 是動態加載的）
    if (playlist.isMix) {
      logDebug('Skipping refresh for Mix playlist: ${playlist.name}');
      return ImportResult(
        playlist: playlist,
        addedCount: 0,
        skippedCount: 0,
        errors: [],
      );
    }

    _updateProgress(status: ImportStatus.parsing, currentItem: t.importSource.refreshingImport);

    try {
      final source = _sourceManager.detectSource(playlist.sourceUrl!);
      if (source == null) {
        throw ImportException(t.importSource.unrecognizedSource);
      }

      final result = await source.parsePlaylist(playlist.sourceUrl!);

      // 获取分P信息并展开（仅Bilibili）
      final List<Track> expandedTracks;
      if (source is BilibiliSource) {
        expandedTracks = await _expandMultiPageVideos(
          source,
          result.tracks,
          (current, total, item) {
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(current: current.toString(), total: total.toString()),
            );
          },
        );
      } else {
        expandedTracks = result.tracks;
      }

      _updateProgress(
        status: ImportStatus.importing,
        total: expandedTracks.length,
        current: 0,
      );

      // 保存原来的 trackIds 用于计算移除数量
      final originalTrackIds = Set<int>.from(playlist.trackIds);

      int addedCount = 0;
      int skippedCount = 0;
      final errors = <String>[];
      final newTrackIds = <int>[];

      for (int i = 0; i < expandedTracks.length; i++) {
        final track = expandedTracks[i];

        _updateProgress(
          current: i + 1,
          currentItem: track.title,
        );

        try {
          // 查找已存在的 Track（使用简单的 sourceId + cid 匹配）
          final existing = await _trackRepository.getBySourceIdAndCid(
            track.sourceId,
            track.sourceType,
            cid: track.cid,
          );

          if (existing != null) {
            newTrackIds.add(existing.id);
            if (!playlist.trackIds.contains(existing.id)) {
              // 新添加到歌单的 Track，只添加歌单关联（路径在下载完成时设置）
              existing.addToPlaylist(playlist.id, playlistName: playlist.name);
              await _trackRepository.save(existing);
              addedCount++;
            } else {
              // 已在歌单中，确保有歌单关联
              if (!existing.belongsToPlaylist(playlist.id)) {
                existing.addToPlaylist(playlist.id, playlistName: playlist.name);
                await _trackRepository.save(existing);
              }
              skippedCount++;
            }
          } else {
            // 只添加歌单关联，不预计算下载路径（路径在下载完成时设置）
            track.addToPlaylist(playlist.id, playlistName: playlist.name);
            
            final savedTrack = await _trackRepository.save(track);
            newTrackIds.add(savedTrack.id);
            addedCount++;
          }
        } catch (e) {
          errors.add('${track.title}: ${e.toString()}');
        }
      }

      // 计算被移除的歌曲（在原来列表中但不在新列表中的）
      final newTrackIdSet = Set<int>.from(newTrackIds);
      final removedTrackIds = originalTrackIds.difference(newTrackIdSet);
      final removedCount = removedTrackIds.length;

      // 清理被移除的 tracks 的 playlistIds 和 downloadPaths
      if (removedTrackIds.isNotEmpty) {
        final removedTracks = await _trackRepository.getByIds(removedTrackIds.toList());
        final tracksToDelete = <int>[];
        final tracksToUpdate = <Track>[];

        for (final track in removedTracks) {
          track.removeFromPlaylist(playlist.id);
          if (track.playlistInfo.isEmpty) {
            tracksToDelete.add(track.id);
          } else {
            tracksToUpdate.add(track);
          }
        }

        // 批量删除孤儿 tracks
        if (tracksToDelete.isNotEmpty) {
          await _isar.writeTxn(() => _isar.tracks.deleteAll(tracksToDelete));
          logDebug('Deleted ${tracksToDelete.length} orphan tracks after playlist refresh');
        }

        // 批量更新其他 tracks
        if (tracksToUpdate.isNotEmpty) {
          await _trackRepository.saveAll(tracksToUpdate);
          logDebug('Updated ${tracksToUpdate.length} tracks after playlist refresh');
        }
      }

      // 更新歌单
      playlist.trackIds = newTrackIds;
      playlist.lastRefreshed = DateTime.now();
      
      // 更新封面 URL：
      // 用戶手動設置的封面不會被自動更新
      // 否則使用第一首歌曲的縮略圖作為默認封面
      if (!playlist.hasCustomCover) {
        if (newTrackIds.isNotEmpty) {
          final firstTrack = await _trackRepository.getById(newTrackIds.first);
          if (firstTrack?.thumbnailUrl != null) {
            playlist.coverUrl = firstTrack!.thumbnailUrl;
          }
        } else {
          // 歌單為空時清空封面
          playlist.coverUrl = null;
        }
      }
      await _playlistRepository.save(playlist);

      _updateProgress(status: ImportStatus.completed);

      return ImportResult(
        playlist: playlist,
        addedCount: addedCount,
        skippedCount: skippedCount,
        removedCount: removedCount,
        errors: errors,
      );
    } catch (e) {
      _updateProgress(status: ImportStatus.failed, error: e.toString());
      rethrow;
    }
  }

  /// 检查需要刷新的歌单
  Future<List<Playlist>> getPlaylistsNeedingRefresh() async {
    return _playlistRepository.getNeedingRefresh();
  }

  /// 自动刷新所有需要刷新的歌单
  Future<Map<int, ImportResult>> autoRefreshAll() async {
    final playlists = await getPlaylistsNeedingRefresh();
    final results = <int, ImportResult>{};

    for (final playlist in playlists) {
      try {
        final result = await refreshPlaylist(playlist.id);
        results[playlist.id] = result;
      } catch (e) {
        // 记录错误但继续刷新其他歌单
      }
    }

    return results;
  }

  /// 展开多分P视频为独立Track
  Future<List<Track>> _expandMultiPageVideos(
    BilibiliSource source,
    List<Track> tracks,
    void Function(int current, int total, String item) onProgress,
  ) async {
    final expandedTracks = <Track>[];

    // 统计多P视频数量用于进度显示
    final multiPageCount = tracks.where((t) => (t.pageCount ?? 0) > 1).length;
    int multiPageProcessed = 0;

    for (final track in tracks) {
      // 单P视频直接添加（cid 会在播放时通过 ensureAudioUrl 获取）
      if ((track.pageCount ?? 0) <= 1) {
        track.pageNum = 1;
        expandedTracks.add(track);
        continue;
      }

      // 多P视频需要获取详细分P信息
      multiPageProcessed++;
      onProgress(multiPageProcessed, multiPageCount, track.title);

      try {
        // 获取分P信息
        final pages = await source.getVideoPages(track.sourceId);

        if (pages.length <= 1) {
          // API 返回单P，直接添加
          if (pages.isNotEmpty) {
            track.cid = pages.first.cid;
            track.pageNum = 1;
          }
          expandedTracks.add(track);
        } else {
          // 多P视频，展开为独立Track
          for (final page in pages) {
            expandedTracks.add(page.toTrack(track));
          }
        }

        // 添加小延迟避免请求过快
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // 获取分P失败，直接添加原始track
        expandedTracks.add(track);
      }
    }

    return expandedTracks;
  }

  void _updateProgress({
    int? current,
    int? total,
    String? currentItem,
    ImportStatus? status,
    String? error,
  }) {
    _currentProgress = _currentProgress.copyWith(
      current: current,
      total: total,
      currentItem: currentItem,
      status: status,
      error: error,
    );
    _progressController.add(_currentProgress);
  }

  void dispose() {
    _progressController.close();
  }
}

/// 导入异常
class ImportException implements Exception {
  final String message;
  const ImportException(this.message);

  @override
  String toString() => message;
}
