import 'dart:async';

import 'package:isar/isar.dart';

import '../../core/logger.dart';
import '../../core/utils/auth_headers_utils.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/source_capabilities.dart';
import '../../data/sources/source_provider.dart';
import '../account/bilibili_account_service.dart';
import '../account/netease_account_service.dart';
import '../account/youtube_account_service.dart';
import '../library/playlist_mutation_service.dart';
import 'youtube_mix_shorthand.dart';
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
  final bool pruningSkipped;
  final List<String> errors;

  const ImportResult({
    required this.playlist,
    required this.addedCount,
    required this.skippedCount,
    this.removedCount = 0,
    this.pruningSkipped = false,
    required this.errors,
  });
}

class _TrackExpansionResult {
  final List<Track> tracks;
  final bool isComplete;

  const _TrackExpansionResult({
    required this.tracks,
    required this.isComplete,
  });
}

abstract class ImportServiceFacade {
  Stream<ImportProgress> get progressStream;

  Future<ImportResult> importFromUrl(
    String url, {
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
    bool useAuth = false,
  });

  void cancelImport();

  Future<void> cleanupCancelledImport();

  void dispose();
}

/// 外部导入服务
class ImportService with Logging implements ImportServiceFacade {
  final SourceManager _sourceManager;
  final PlaylistRepository _playlistRepository;
  final TrackRepository _trackRepository;
  final Isar _isar;
  final PlaylistMutationService _mutationService;
  final BilibiliAccountService? _bilibiliAccountService;
  final YouTubeAccountService? _youtubeAccountService;
  final NeteaseAccountService? _neteaseAccountService;

  // 导入进度流
  final _progressController = StreamController<ImportProgress>.broadcast();
  @override
  Stream<ImportProgress> get progressStream => _progressController.stream;

  ImportProgress _currentProgress = const ImportProgress();

  /// 取消标记
  bool _isCancelled = false;

  /// 取消导入后需要清理的歌单 ID
  int? _cancelledPlaylistId;

  /// 取消当前导入
  @override
  void cancelImport() {
    _isCancelled = true;
  }

  /// 清理取消导入后残留的歌单（在导入完全停止后调用）
  @override
  Future<void> cleanupCancelledImport() async {
    final playlistId = _cancelledPlaylistId;
    _cancelledPlaylistId = null;
    if (playlistId != null) {
      try {
        await _mutationService.deletePlaylist(playlistId);
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
    PlaylistMutationService? mutationService,
    BilibiliAccountService? bilibiliAccountService,
    YouTubeAccountService? youtubeAccountService,
    NeteaseAccountService? neteaseAccountService,
  })  : _sourceManager = sourceManager,
        _playlistRepository = playlistRepository,
        _trackRepository = trackRepository,
        _isar = isar,
        _mutationService = mutationService ??
            PlaylistMutationService(
              isar: isar,
            ),
        _bilibiliAccountService = bilibiliAccountService,
        _youtubeAccountService = youtubeAccountService,
        _neteaseAccountService = neteaseAccountService;

  /// 获取指定平台的认证 headers
  Future<Map<String, String>?> _getAuthHeaders(SourceType sourceType) =>
      buildAuthHeaders(sourceType,
          bilibiliAccountService: _bilibiliAccountService,
          youtubeAccountService: _youtubeAccountService,
          neteaseAccountService: _neteaseAccountService);

  /// 从 URL 导入歌单/收藏夹
  @override
  Future<ImportResult> importFromUrl(
    String url, {
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
    bool useAuth = false,
  }) async {
    _isCancelled = false;
    _cancelledPlaylistId = null;
    _updateProgress(
        status: ImportStatus.parsing, currentItem: t.importSource.parsingUrl);

    try {
      final normalizedUrl = normalizeYouTubeMixShorthandUrl(url) ?? url.trim();

      // 识别音源类型
      final source = _sourceManager.playlistParsingSourceForUrl(normalizedUrl);
      if (source == null) {
        throw ImportException(t.importSource.unrecognizedUrlFormat);
      }

      final dynamicPlaylistSource =
          _sourceManager.dynamicPlaylistSourceForUrl(normalizedUrl);
      if (dynamicPlaylistSource != null &&
          dynamicPlaylistSource.sourceType == source.sourceType) {
        return _importMixPlaylist(
          source: dynamicPlaylistSource,
          url: normalizedUrl,
          customName: customName,
          refreshIntervalHours: refreshIntervalHours,
          notifyOnUpdate: notifyOnUpdate,
        );
      }

      // 解析播放列表
      Map<String, String>? authHeaders;
      if (useAuth) {
        authHeaders = await _getAuthHeaders(source.sourceType);
      }
      final result =
          await source.parsePlaylist(normalizedUrl, authHeaders: authHeaders);

      // 获取分P信息并展开
      final List<Track> expandedTracks;
      final pagedVideoSource =
          _sourceManager.pagedVideoSource(source.sourceType);
      if (pagedVideoSource != null) {
        final expansion = await _expandMultiPageVideos(
          pagedVideoSource,
          result.tracks,
          (current, total, item) {
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(
                  current: current.toString(), total: total.toString()),
            );
          },
        );
        expandedTracks = expansion.tracks;
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
          await _playlistRepository.getBySourceUrl(normalizedUrl);

      Playlist playlist;
      if (existingPlaylist != null) {
        // 更新现有歌单
        playlist = existingPlaylist
          ..importSourceType = source.sourceType
          ..ownerName = result.ownerName
          ..ownerUserId = result.ownerUserId
          ..useAuthForRefresh = useAuth
          ..refreshIntervalHours = refreshIntervalHours
          ..notifyOnUpdate = notifyOnUpdate
          ..updatedAt = DateTime.now();
        await _playlistRepository.save(playlist);
      } else {
        // 创建新歌单
        // 处理同名歌单：自动添加后缀避免唯一索引冲突
        final uniqueName = await _generateUniqueName(playlistName);
        // 注意：coverUrl 不在此處設置，會在導入完成後使用第一首歌曲的縮略圖
        playlist = Playlist()
          ..name = uniqueName
          ..description = result.description
          ..sourceUrl = normalizedUrl
          ..importSourceType = source.sourceType
          ..ownerName = result.ownerName
          ..ownerUserId = result.ownerUserId
          ..useAuthForRefresh = useAuth
          ..refreshIntervalHours = refreshIntervalHours // 默认为 null（不开启自动刷新）
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
      final tracksToImport = <Track>[];

      for (int i = 0; i < expandedTracks.length; i++) {
        _throwIfCancelledForImportCreation(isNewPlaylist, playlist.id);

        final track = expandedTracks[i];
        _updateProgress(
          current: i + 1,
          currentItem: track.title,
        );
        tracksToImport.add(track);
      }

      _throwIfCancelledForImportCreation(isNewPlaylist, playlist.id);
      final mutationResult = await _mutationService.addTracks(
        playlist.id,
        tracksToImport,
      );
      _throwIfCancelledForImportCreation(isNewPlaylist, playlist.id);
      addedCount = mutationResult.addedCount + mutationResult.repairedCount;
      skippedCount = tracksToImport.length - addedCount;
      errors.addAll(mutationResult.errors.map((error) => error.toString()));
      playlist = (await _playlistRepository.getById(playlist.id)) ?? playlist;

      // 更新歌单封面（平台封面优先，回退到第一首歌封面）
      await _updatePlaylistCover(playlist, result.coverUrl, playlist.trackIds);
      _throwIfCancelledForImportCreation(isNewPlaylist, playlist.id);

      // 更新歌单
      playlist.lastRefreshed = DateTime.now();
      await _playlistRepository.save(playlist);
      _throwIfCancelledForImportCreation(isNewPlaylist, playlist.id);

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
    required DynamicPlaylistSource source,
    required String url,
    String? customName,
    int? refreshIntervalHours,
    bool notifyOnUpdate = true,
  }) async {
    _updateProgress(
        status: ImportStatus.parsing,
        currentItem: t.importSource.parsingMixPlaylist);

    try {
      // 獲取 Mix 播放列表基本信息
      final mixInfo = await source.getMixPlaylistInfo(url);

      _updateProgress(
        status: ImportStatus.importing,
        currentItem: t.importSource.creatingPlaylist,
      );

      // 創建歌單名稱
      final playlistName = customName ?? mixInfo.title;
      final existingPlaylist = await _playlistRepository.getBySourceUrl(url);

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
        final uniqueName = await _generateUniqueName(playlistName);
        playlist = Playlist()
          ..name = uniqueName
          ..description = t.importSource.mixPlaylistDescription
          ..coverUrl = mixInfo.coverUrl
          ..sourceUrl = url
          ..importSourceType = SourceType.youtube
          ..isMix = true
          ..mixPlaylistId = mixInfo.playlistId
          ..mixSeedVideoId = mixInfo.seedVideoId
          ..refreshIntervalHours = null // Mix 不需要定時刷新
          ..notifyOnUpdate = notifyOnUpdate
          ..createdAt = DateTime.now();
      }

      // 保存歌單（Mix 歌單不保存 tracks）
      await _playlistRepository.save(playlist);

      _updateProgress(status: ImportStatus.completed);

      logInfo(
          'Mix playlist imported: ${playlist.name} (playlistId: ${mixInfo.playlistId})');

      return ImportResult(
        playlist: playlist,
        addedCount: 0, // Mix 歌單不保存 tracks
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
    _isCancelled = false;
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

    _updateProgress(
        status: ImportStatus.parsing,
        currentItem: t.importSource.refreshingImport);

    try {
      final source =
          _sourceManager.playlistParsingSourceForUrl(playlist.sourceUrl!);
      if (source == null) {
        throw ImportException(t.importSource.unrecognizedSource);
      }

      Map<String, String>? authHeaders;
      if (playlist.useAuthForRefresh) {
        authHeaders = await _getAuthHeaders(source.sourceType);
      }
      final result = await source.parsePlaylist(playlist.sourceUrl!,
          authHeaders: authHeaders);
      _throwIfCancelled();

      // 获取分P信息并展开
      final List<Track> expandedTracks;
      final bool expansionComplete;
      final pagedVideoSource =
          _sourceManager.pagedVideoSource(source.sourceType);
      if (pagedVideoSource != null) {
        final expansion = await _expandMultiPageVideos(
          pagedVideoSource,
          result.tracks,
          (current, total, item) {
            _throwIfCancelled();
            _updateProgress(
              status: ImportStatus.importing,
              current: current,
              total: total,
              currentItem: t.importSource.gettingPageInfo(
                  current: current.toString(), total: total.toString()),
            );
          },
        );
        expandedTracks = expansion.tracks;
        expansionComplete = expansion.isComplete;
      } else {
        expandedTracks = result.tracks;
        expansionComplete = true;
      }
      _throwIfCancelled();

      final sourceDataComplete = expansionComplete &&
          (result.totalCount <= 0 || result.tracks.length >= result.totalCount);

      _updateProgress(
        status: ImportStatus.importing,
        total: expandedTracks.length,
        current: 0,
      );

      for (int i = 0; i < expandedTracks.length; i++) {
        _throwIfCancelled();
        _updateProgress(
          current: i + 1,
          currentItem: expandedTracks[i].title,
        );
      }

      _throwIfCancelled();
      final mutationResult =
          await _mutationService.replaceTracksFromRemoteRefresh(
        playlist.id,
        expandedTracks,
        RemoteRefreshMutationPolicy(
          sourceDataComplete: sourceDataComplete,
          platformCoverUrl: result.coverUrl,
        ),
      );
      _throwIfCancelled();

      final refreshedPlaylist =
          await _playlistRepository.getById(playlist.id) ?? playlist;
      if (result.ownerName != null) {
        refreshedPlaylist.ownerName = result.ownerName;
      }
      if (result.ownerUserId != null) {
        refreshedPlaylist.ownerUserId = result.ownerUserId;
      }
      await _playlistRepository.save(refreshedPlaylist);
      _throwIfCancelled();
      final savedPlaylist =
          await _playlistRepository.getById(playlist.id) ?? refreshedPlaylist;
      _updateProgress(status: ImportStatus.completed);

      return ImportResult(
        playlist: savedPlaylist,
        addedCount: mutationResult.addedCount + mutationResult.repairedCount,
        skippedCount: mutationResult.skippedCount,
        removedCount: mutationResult.removedCount,
        pruningSkipped: mutationResult.pruningSkipped,
        errors: mutationResult.errors.map((error) => error.toString()).toList(),
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
  Future<_TrackExpansionResult> _expandMultiPageVideos(
    PagedVideoSource source,
    List<Track> tracks,
    void Function(int current, int total, String item) onProgress,
  ) async {
    final expandedTracks = <Track>[];
    var isComplete = true;

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
        isComplete = false;
        expandedTracks.add(track);
      }
    }

    return _TrackExpansionResult(
      tracks: expandedTracks,
      isComplete: isComplete,
    );
  }

  /// 更新歌单封面：自定义封面不覆盖，优先平台封面，回退到第一首歌缩略图
  Future<void> _updatePlaylistCover(
    Playlist playlist,
    String? platformCoverUrl,
    List<int> trackIds,
  ) async {
    if (playlist.hasCustomCover) return;
    if (platformCoverUrl != null) {
      playlist.coverUrl = platformCoverUrl;
    } else if (trackIds.isNotEmpty) {
      final firstTrack = await _trackRepository.getById(trackIds.first);
      if (firstTrack?.thumbnailUrl != null) {
        playlist.coverUrl = firstTrack!.thumbnailUrl;
      }
    } else {
      playlist.coverUrl = null;
    }
  }

  /// 生成唯一歌单名称，同名时自动添加后缀 (2), (3), ...
  Future<String> _generateUniqueName(String baseName) async {
    // Single query: fetch all names starting with baseName
    final existingNames = await _isar.playlists
        .filter()
        .nameStartsWith(baseName)
        .nameProperty()
        .findAll();
    final nameSet = existingNames.toSet();

    if (!nameSet.contains(baseName)) return baseName;
    for (int i = 2; i <= 100; i++) {
      final candidate = '$baseName ($i)';
      if (!nameSet.contains(candidate)) return candidate;
    }
    // 极端情况：用时间戳
    return '$baseName (${DateTime.now().millisecondsSinceEpoch})';
  }

  void _throwIfCancelled() {
    if (_isCancelled) {
      throw const ImportException('Import cancelled');
    }
  }

  void _throwIfCancelledForImportCreation(bool isNewPlaylist, int playlistId) {
    if (_isCancelled) {
      if (isNewPlaylist) {
        _cancelledPlaylistId = playlistId;
      }
      throw ImportException(t.importSource.cancelled);
    }
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

  @override
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
