import 'dart:async';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/audio_stream_quality_fallback.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_exception.dart';
import '../../data/sources/source_provider.dart';

typedef AuthHeadersLoader = Future<Map<String, String>?> Function(
  SourceType sourceType,
);

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
}

class DefaultStreamResolutionService
    with Logging
    implements StreamResolutionService {
  DefaultStreamResolutionService({
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
    required SourceManager sourceManager,
    required AuthHeadersLoader getAuthHeaders,
  })  : _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager,
        _getAuthHeaders = getAuthHeaders;

  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;
  final AuthHeadersLoader _getAuthHeaders;
  final Set<int> _prefetchingTrackIds = {};
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
        return LocalStreamResolution(
          track: track,
          path: localFileState.localPath!,
        );
      }
    }

    return _resolveRemotePrimary(
      track,
      purpose: purpose,
      persist: persist,
      retryCount: 0,
    );
  }

  Future<RemoteStreamResolution> _resolveRemotePrimary(
    Track track, {
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

    try {
      final requestContext = await _buildRequestContext(track);
      final streamResult = await fetchAudioStreamWithQualityFallback(
        source: source,
        request: requestContext.request,
      );
      final updatedTrack = await _applyStreamResult(
        track,
        streamResult,
        persist: persist,
      );
      return RemoteStreamResolution(
        track: updatedTrack,
        stream: streamResult,
        authHeaders: requestContext.authHeaders,
      );
    } on SourceApiException {
      rethrow;
    } catch (_) {
      if (retryCount < 1) {
        await Future.delayed(AppConstants.queueSaveRetryDelay);
        return _resolveRemotePrimary(
          track,
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

    final requestContext = await _buildRequestContext(
      track,
      failedUrl: failedUrl,
    );
    final streamResult = await fetchAlternativeAudioStreamWithQualityFallback(
      source: source,
      request: requestContext.request,
    );
    if (streamResult == null) return null;

    final updatedTrack = await _applyStreamResult(
      track,
      streamResult,
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
    if (track.hasValidAudioUrl || _prefetchingTrackIds.contains(track.id)) {
      return;
    }

    _prefetchingTrackIds.add(track.id);
    try {
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

  Future<_StreamRequestContext> _buildRequestContext(
    Track track, {
    String? failedUrl,
  }) async {
    final settings = await _settingsRepository.get();
    final config = AudioStreamConfig.fromSettings(settings, track.sourceType);
    final authHeaders = settings.useAuthForPlay(track.sourceType)
        ? await _getAuthHeaders(track.sourceType)
        : null;
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
    required bool persist,
  }) async {
    final now = DateTime.now();
    track.audioUrl = streamResult.url;
    track.audioUrlExpiry =
        now.add(streamResult.expiry ?? const Duration(hours: 1));
    track.updatedAt = now;

    if (!persist) return track;

    final persistedTrack = await _findPersistedTrack(track);
    if (persistedTrack != null) {
      persistedTrack.audioUrl = track.audioUrl;
      persistedTrack.audioUrlExpiry = track.audioUrlExpiry;
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
    _downloadPathsChangedController.close();
  }
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
