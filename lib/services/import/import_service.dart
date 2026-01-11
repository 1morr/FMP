import 'dart:async';

import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/bilibili_source.dart';
import '../../data/sources/source_provider.dart';

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
class ImportService {
  final SourceManager _sourceManager;
  final PlaylistRepository _playlistRepository;
  final TrackRepository _trackRepository;

  // 导入进度流
  final _progressController = StreamController<ImportProgress>.broadcast();
  Stream<ImportProgress> get progressStream => _progressController.stream;

  ImportProgress _currentProgress = const ImportProgress();

  ImportService({
    required SourceManager sourceManager,
    required PlaylistRepository playlistRepository,
    required TrackRepository trackRepository,
  })  : _sourceManager = sourceManager,
        _playlistRepository = playlistRepository,
        _trackRepository = trackRepository;

  /// 从 URL 导入歌单/收藏夹
  Future<ImportResult> importFromUrl(
    String url, {
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
  }) async {
    _updateProgress(status: ImportStatus.parsing, currentItem: '解析URL...');

    try {
      // 识别音源类型
      final source = _sourceManager.detectSource(url);
      if (source == null) {
        throw ImportException('无法识别的 URL 格式');
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
              currentItem: '正在获取分P信息 ($current/$total)',
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
        currentItem: '正在导入...',
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
        playlist = Playlist()
          ..name = playlistName
          ..description = result.description
          ..coverUrl = result.coverUrl
          ..sourceUrl = url
          ..importSourceType = source.sourceType
          ..refreshIntervalHours = refreshIntervalHours ?? 24
          ..notifyOnUpdate = notifyOnUpdate
          ..createdAt = DateTime.now();
      }

      // 导入歌曲
      int addedCount = 0;
      int skippedCount = 0;
      final errors = <String>[];

      for (int i = 0; i < expandedTracks.length; i++) {
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
              // 创建可变列表副本，避免 fixed-length list 错误
              final newTrackIds = List<int>.from(playlist.trackIds);
              newTrackIds.add(existing.id);
              playlist.trackIds = newTrackIds;
              addedCount++;
            } else {
              skippedCount++;
            }
          } else {
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

  /// 刷新导入的歌单
  Future<ImportResult> refreshPlaylist(int playlistId) async {
    final playlist = await _playlistRepository.getById(playlistId);
    if (playlist == null) {
      throw ImportException('歌单不存在');
    }

    if (!playlist.isImported || playlist.sourceUrl == null) {
      throw ImportException('这不是导入的歌单');
    }

    _updateProgress(status: ImportStatus.parsing, currentItem: '正在刷新...');

    try {
      final source = _sourceManager.detectSource(playlist.sourceUrl!);
      if (source == null) {
        throw ImportException('无法识别音源');
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
              currentItem: '正在获取分P信息 ($current/$total)',
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
          // 检查是否已存在（支持分P唯一性）
          final existing = await _trackRepository.getBySourceIdAndCid(
            track.sourceId,
            track.sourceType,
            cid: track.cid,
          );

          if (existing != null) {
            newTrackIds.add(existing.id);
            if (!playlist.trackIds.contains(existing.id)) {
              addedCount++;
            } else {
              skippedCount++;
            }
          } else {
            final savedTrack = await _trackRepository.save(track);
            newTrackIds.add(savedTrack.id);
            addedCount++;
          }
        } catch (e) {
          errors.add('${track.title}: ${e.toString()}');
        }
      }

      // 计算被移除的歌曲数量（在原来列表中但不在新列表中的）
      final newTrackIdSet = Set<int>.from(newTrackIds);
      final removedCount = originalTrackIds.difference(newTrackIdSet).length;

      // 更新歌单
      playlist.trackIds = newTrackIds;
      playlist.lastRefreshed = DateTime.now();
      if (result.coverUrl != null && playlist.coverUrl == null) {
        playlist.coverUrl = result.coverUrl;
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
