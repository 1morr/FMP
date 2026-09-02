import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/audio_stream_quality_fallback.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_exception.dart';
import '../../data/sources/source_provider.dart';
import '../account/source_auth_context.dart';

class DownloadPathsChangedEvent {
  const DownloadPathsChangedEvent({
    required this.track,
    required this.removedPaths,
  });

  final Track track;
  final List<String> removedPaths;
}

enum StreamResolutionPurpose {
  playback,
  download,
  prefetch,
  refresh,
}

sealed class StreamResolutionResult {
  Track get track;
}

final class LocalStreamResolution extends StreamResolutionResult {
  LocalStreamResolution({
    required this.track,
    required this.path,
  });

  @override
  final Track track;
  final String path;
}

final class RemoteStreamResolution extends StreamResolutionResult {
  RemoteStreamResolution({
    required this.track,
    required this.stream,
    required this.authHeaders,
  });

  @override
  final Track track;
  final AudioStreamResult stream;
  final Map<String, String>? authHeaders;
}

abstract interface class StreamResolutionService {
  Stream<DownloadPathsChangedEvent> get downloadPathsChangedStream;

  Future<StreamResolutionResult> resolvePrimary(
    Track track, {
    required StreamResolutionPurpose purpose,
    bool persist = true,
  });

  Future<RemoteStreamResolution?> resolveFallback(
    Track track, {
    required StreamResolutionPurpose purpose,
    required String failedUrl,
    bool persist = false,
  });

  Future<void> prefetchTrack(Track track);

  /// 丟棄這首歌可重用的解析結果，強制下一次解析重新打網路。
  ///
  /// 播放失敗時必須呼叫：URL 還沒過期**不等於**它還能用（CDN 可能已經 403），
  /// 而沒有這個出口的話，短路會把同一個死 URL 無限次交還回去。
  void invalidateStream(Track track);
}

class DefaultStreamResolutionService
    with Logging
    implements StreamResolutionService {
  DefaultStreamResolutionService({
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
    required SourceManager sourceManager,
    required SourcePlaybackAuthContext sourceAuthContext,
  })  : _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager,
        _sourceAuthContext = sourceAuthContext;

  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;
  final SourcePlaybackAuthContext _sourceAuthContext;
  final Set<int> _prefetchingTrackIds = {};

  /// 行程內的串流解析快取。
  ///
  /// 短路命中時沒有新的 [AudioStreamResult]，但「播放中的位元率/編碼/容器來自
  /// 本次請求的 AudioStreamResult」是寫在 AGENTS.md 裡的契約，而 [Track] 沒有
  /// 這些欄位、這一期也不能加（schema 變更集中在後續階段）。所以中繼資料只能
  /// 留在記憶體裡：重啟之後會落空，那一次照常重新解析。
  final _resolvedStreams = <String, _ResolvedStream>{};

  /// 佇列可以有上千首，快取不能無界成長。夠裝「目前這首 + 預取的下一首 +
  /// 一個隨機播放的來回窗口」即可。
  static const int _maxResolvedStreams = 32;
  final _downloadPathsChangedController =
      StreamController<DownloadPathsChangedEvent>.broadcast();
  var _isDisposed = false;

  @override
  Stream<DownloadPathsChangedEvent> get downloadPathsChangedStream =>
      _downloadPathsChangedController.stream;

  @override
  Future<StreamResolutionResult> resolvePrimary(
    Track track, {
    required StreamResolutionPurpose purpose,
    bool persist = true,
  }) async {
    if (purpose != StreamResolutionPurpose.download) {
      final localFileState = _inspectLocalFiles(track);

      if (localFileState.invalidPaths.isNotEmpty) {
        track = await _clearInvalidDownloadPaths(
          track,
          localFileState.invalidPaths,
        );
      }

      if (localFileState.localPath != null) {
        logDebug('Using local file for ${_describe(track)}');
        return LocalStreamResolution(
          track: track,
          path: localFileState.localPath!,
        );
      }
    }

    final requestContext = await _buildRequestContext(track);
    // 下載刻意不重用：一次下載可能跑得比 5 分鐘的安全邊界還久，中途 URL 失效
    // 會讓整個檔案廢掉，而下載本來就不在意多付一次解析。
    final reusable = purpose == StreamResolutionPurpose.download
        ? null
        : _reusableResolution(track, requestContext);
    if (reusable != null) {
      logDebug('Reusing resolved stream for ${_describe(track)} '
          '(${purpose.name})');
      return reusable;
    }

    return _resolveRemotePrimary(
      track,
      requestContext: requestContext,
      purpose: purpose,
      persist: persist,
      retryCount: 0,
    );
  }

  Future<RemoteStreamResolution> _resolveRemotePrimary(
    Track track, {
    required _StreamRequestContext requestContext,
    required StreamResolutionPurpose purpose,
    required bool persist,
    required int retryCount,
  }) async {
    final source = _sourceManager.audioStreamSource(track.sourceType);
    if (source == null) {
      throw StateError(
        'No audio stream source available for ${track.sourceType.name}',
      );
    }

    final stopwatch = Stopwatch()..start();
    logDebug('Resolving stream for ${_describe(track)} (${purpose.name})');
    try {
      final streamResult = await fetchAudioStreamWithQualityFallback(
        source: source,
        request: requestContext.request,
      );
      final updatedTrack = await _applyStreamResult(
        track,
        streamResult,
        requestContext: requestContext,
        persist: persist,
      );
      logDebug('Resolved stream for ${_describe(track)} in '
          '${stopwatch.elapsedMilliseconds}ms '
          '(${streamResult.streamType.name}, ${streamResult.bitrate ?? '?'}bps)');
      return RemoteStreamResolution(
        track: updatedTrack,
        stream: streamResult,
        authHeaders: requestContext.authHeaders,
      );
    } on SourceApiException catch (error) {
      logWarning('Stream resolution failed for ${_describe(track)} after '
          '${stopwatch.elapsedMilliseconds}ms: ${error.kind.name}');
      rethrow;
    } catch (_) {
      if (retryCount < 1) {
        logWarning('Retrying stream resolution for ${_describe(track)} after '
            '${stopwatch.elapsedMilliseconds}ms');
        await Future.delayed(AppConstants.queueSaveRetryDelay);
        return _resolveRemotePrimary(
          track,
          requestContext: await _buildRequestContext(track),
          purpose: purpose,
          persist: persist,
          retryCount: retryCount + 1,
        );
      }
      rethrow;
    }
  }

  @override
  Future<RemoteStreamResolution?> resolveFallback(
    Track track, {
    required StreamResolutionPurpose purpose,
    required String failedUrl,
    bool persist = false,
  }) async {
    final source = _sourceManager.audioStreamSource(track.sourceType);
    if (source == null) {
      throw StateError(
        'No audio stream source available for ${track.sourceType.name}',
      );
    }

    final stopwatch = Stopwatch()..start();
    logDebug('Resolving fallback stream for ${_describe(track)}');
    final requestContext = await _buildRequestContext(
      track,
      failedUrl: failedUrl,
    );
    final streamResult = await fetchAlternativeAudioStreamWithQualityFallback(
      source: source,
      request: requestContext.request,
    );
    if (streamResult == null) {
      logWarning('No fallback stream for ${_describe(track)} after '
          '${stopwatch.elapsedMilliseconds}ms');
      return null;
    }
    logDebug('Resolved fallback stream for ${_describe(track)} in '
        '${stopwatch.elapsedMilliseconds}ms');

    final updatedTrack = await _applyStreamResult(
      track,
      streamResult,
      requestContext: requestContext,
      persist: persist,
    );
    return RemoteStreamResolution(
      track: updatedTrack,
      stream: streamResult,
      authHeaders: requestContext.authHeaders,
    );
  }

  @override
  Future<void> prefetchTrack(Track track) async {
    if (_isDisposed ||
        track.hasValidAudioUrl ||
        _prefetchingTrackIds.contains(track.id)) {
      return;
    }

    _prefetchingTrackIds.add(track.id);
    try {
      // 刻意不落盤。預取要的是「下一次播放不用再打網路」，而那靠的是把 URL
      // 寫進佇列裡那個 track 實例（_applyStreamResult 會就地改）加上行程內的
      // 解析快取 —— 兩者都在記憶體。預取是 fire-and-forget，讓它去寫 Isar 等於
      // 讓一個沒人等的寫入去撞正在關閉的資料庫。真正播放時才會落盤。
      await resolvePrimary(
        track,
        purpose: StreamResolutionPurpose.prefetch,
        persist: false,
      );
    } catch (error, stackTrace) {
      logError(
        'Failed to prefetch audio URL for ${track.sourceType.name}:${track.sourceId}',
        error,
        stackTrace,
      );
    } finally {
      _prefetchingTrackIds.remove(track.id);
    }
  }

  @override
  void invalidateStream(Track track) {
    if (_resolvedStreams.remove(_resolutionKey(track)) != null) {
      logDebug('Discarded the reusable stream for ${_describe(track)}');
    }
  }

  /// 快取 key。
  ///
  /// 不能只用 [Track.uniqueKey]：它是 `sourceType:sourceId[:cid]`，**不含
  /// pageNum**，所以 cid 還沒解析出來的 Bilibili 分 P 曲目彼此撞 key ——
  /// 那會把 P1 的 URL 餵給 P2。
  String _resolutionKey(Track track) =>
      '${track.uniqueKey}|${track.pageNum ?? ''}';

  /// 這次請求可以直接重用先前的解析結果嗎？
  ///
  /// 五個條件全中才算數，任何一個不中都寧可重打網路。設定與登入狀態每次都
  /// 重新讀（`_buildRequestContext` 只碰本機），所以換音質或登入／登出會讓
  /// 快取自然失效，不需要額外訂閱任何變更事件。
  RemoteStreamResolution? _reusableResolution(
    Track track,
    _StreamRequestContext requestContext,
  ) {
    if (!track.hasValidAudioUrl) return null;

    final key = _resolutionKey(track);
    final cached = _resolvedStreams.remove(key);
    if (cached == null) return null;
    if (cached.stream.url != track.audioUrl) return null;
    if (!_sameConfig(cached.config, requestContext.request.config)) return null;
    if (!mapEquals(cached.authHeaders, requestContext.authHeaders)) return null;

    // 重新插入 = 更新 LRU 順序（Dart 的 Map 保有插入順序）。
    _resolvedStreams[key] = cached;
    return RemoteStreamResolution(
      track: track,
      stream: cached.stream,
      authHeaders: requestContext.authHeaders,
    );
  }

  void _rememberResolution(
    Track track,
    AudioStreamResult streamResult,
    _StreamRequestContext requestContext,
  ) {
    final key = _resolutionKey(track);
    _resolvedStreams.remove(key);
    _resolvedStreams[key] = _ResolvedStream(
      stream: streamResult,
      config: requestContext.request.config,
      authHeaders: requestContext.authHeaders,
    );
    while (_resolvedStreams.length > _maxResolvedStreams) {
      _resolvedStreams.remove(_resolvedStreams.keys.first);
    }
  }

  /// [AudioStreamConfig] 沒有值相等，所以逐欄位比。
  bool _sameConfig(AudioStreamConfig a, AudioStreamConfig b) =>
      a.qualityLevel == b.qualityLevel &&
      listEquals(a.formatPriority, b.formatPriority) &&
      listEquals(a.streamPriority, b.streamPriority);

  /// 解析路徑所有 log 的統一識別碼。
  ///
  /// 不用 title：同名曲目在三個源之間分不開，而排查解析問題時要的正是
  /// 「哪一個源的哪一支 id」。與既有的 prefetch 錯誤訊息格式一致。
  String _describe(Track track) =>
      '${track.sourceType.name}:${track.sourceId}';

  Future<_StreamRequestContext> _buildRequestContext(
    Track track, {
    String? failedUrl,
  }) async {
    final settings = await _settingsRepository.get();
    final config = AudioStreamConfig.fromSettings(settings, track.sourceType);
    final authHeaders = await _sourceAuthContext.authForPlay(track.sourceType);
    return _StreamRequestContext(
      request: AudioStreamRequest(
        sourceId: track.sourceId,
        cid: track.cid,
        pageNum: track.pageNum,
        config: config,
        authHeaders: authHeaders,
        failedUrl: failedUrl,
      ),
      authHeaders: authHeaders,
    );
  }

  Future<Track> _applyStreamResult(
    Track track,
    AudioStreamResult streamResult, {
    required _StreamRequestContext requestContext,
    required bool persist,
  }) async {
    final now = DateTime.now();
    track.audioUrl = streamResult.url;
    track.audioUrlExpiry =
        now.add(streamResult.expiry ?? const Duration(hours: 1));
    // cid 是不變值。回寫之後下一次解析就會把它帶進請求裡，Bilibili 因此少打
    // 一支 /x/web-interface/view。已經有值的不覆蓋 —— 那是分 P 的身分。
    // 必須排在 _rememberResolution 之前：cid 會進 uniqueKey，也就進快取 key。
    track.cid ??= streamResult.cid;
    track.updatedAt = now;
    _rememberResolution(track, streamResult, requestContext);

    // 預取是 fire-and-forget，關閉之後還在飛的那一次不可以再碰資料庫 ——
    // 它會撞上正在關閉的 Isar。
    if (!persist || _isDisposed) return track;

    final persistedTrack = await _findPersistedTrack(track);
    if (persistedTrack != null) {
      persistedTrack.audioUrl = track.audioUrl;
      persistedTrack.audioUrlExpiry = track.audioUrlExpiry;
      persistedTrack.cid ??= track.cid;
      await _trackRepository.save(persistedTrack);
      _syncPlaylistInfo(track, persistedTrack);
      return track;
    }

    return _trackRepository.save(track);
  }

  _LocalFileState _inspectLocalFiles(Track track) {
    String? localPath;
    final invalidPaths = <String>[];

    for (final path in track.allDownloadPaths) {
      if (File(path).existsSync()) {
        localPath ??= path;
      } else {
        invalidPaths.add(path);
      }
    }

    return _LocalFileState(localPath: localPath, invalidPaths: invalidPaths);
  }

  Future<Track> _clearInvalidDownloadPaths(
    Track requestTrack,
    List<String> invalidPaths,
  ) async {
    final persistedTrack = await _findPersistedTrack(requestTrack);
    final targetTrack = persistedTrack ?? requestTrack;
    final removedPaths = _clearInvalidPaths(targetTrack, invalidPaths);
    if (removedPaths.isEmpty) return targetTrack;

    if (persistedTrack != null) {
      await _trackRepository.save(persistedTrack);
      _syncPlaylistInfo(requestTrack, persistedTrack);
      _emitDownloadPathsChanged(
        DownloadPathsChangedEvent(
          track: persistedTrack,
          removedPaths: removedPaths,
        ),
      );
      return persistedTrack;
    }

    _emitDownloadPathsChanged(
      DownloadPathsChangedEvent(
        track: requestTrack,
        removedPaths: removedPaths,
      ),
    );
    return requestTrack;
  }

  Future<Track?> _findPersistedTrack(Track track) async {
    if (track.id > 0) {
      final byId = await _trackRepository.getById(track.id);
      if (byId != null) return byId;
    }

    if (track.cid != null) {
      return _trackRepository.getBySourceIdAndCid(
        track.sourceId,
        track.sourceType,
        cid: track.cid,
      );
    }

    final candidates = await _trackRepository.getBySourceIds([track.sourceId]);
    final sameSource = candidates
        .where((candidate) => candidate.sourceType == track.sourceType)
        .toList();
    if (sameSource.length == 1) return sameSource.single;

    if (track.pageNum != null) {
      final pageMatches = sameSource
          .where((candidate) => candidate.pageNum == track.pageNum)
          .toList();
      if (pageMatches.length == 1) return pageMatches.single;
    }

    return null;
  }

  List<String> _clearInvalidPaths(Track track, List<String> invalidPaths) {
    final invalidPathSet = invalidPaths.toSet();
    final removedPaths = <String>[];
    track.playlistInfo = track.playlistInfo.map((info) {
      final updatedInfo = info.copy();
      if (invalidPathSet.contains(info.downloadPath)) {
        removedPaths.add(info.downloadPath);
        updatedInfo.downloadPath = '';
      }
      return updatedInfo;
    }).toList();
    return removedPaths;
  }

  void _syncPlaylistInfo(Track requestTrack, Track persistedTrack) {
    requestTrack.id = persistedTrack.id;
    requestTrack.playlistInfo =
        persistedTrack.playlistInfo.map((info) => info.copy()).toList();
  }

  void _emitDownloadPathsChanged(DownloadPathsChangedEvent event) {
    if (_isDisposed || _downloadPathsChangedController.isClosed) return;
    _downloadPathsChangedController.add(event);
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _resolvedStreams.clear();
    _downloadPathsChangedController.close();
  }
}

class _ResolvedStream {
  const _ResolvedStream({
    required this.stream,
    required this.config,
    required this.authHeaders,
  });

  final AudioStreamResult stream;
  final AudioStreamConfig config;
  final Map<String, String>? authHeaders;
}

class _StreamRequestContext {
  const _StreamRequestContext({
    required this.request,
    required this.authHeaders,
  });

  final AudioStreamRequest request;
  final Map<String, String>? authHeaders;
}

class _LocalFileState {
  const _LocalFileState({required this.localPath, required this.invalidPaths});

  final String? localPath;
  final List<String> invalidPaths;
}
