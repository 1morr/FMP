import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/track_repository.dart';
import '../../../data/sources/audio_stream_quality_fallback.dart';
import '../../../data/sources/base_source.dart';
import '../../../data/sources/source_exception.dart';
import '../../../data/sources/source_provider.dart';

typedef AuthHeadersLoader = Future<Map<String, String>?> Function(
  SourceType sourceType,
);

typedef DownloadPathsChanged = void Function(DownloadPathsChangedEvent event);

class DownloadPathsChangedEvent {
  const DownloadPathsChangedEvent({
    required this.track,
    required this.removedPaths,
  });

  final Track track;
  final List<String> removedPaths;
}

class AudioStreamDelegate {
  AudioStreamDelegate({
    required TrackRepository trackRepository,
    required SettingsRepository settingsRepository,
    required SourceManager sourceManager,
    required AuthHeadersLoader getAuthHeaders,
    DownloadPathsChanged? onDownloadPathsChanged,
  })  : _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager,
        _getAuthHeaders = getAuthHeaders,
        _onDownloadPathsChanged = onDownloadPathsChanged;

  final TrackRepository _trackRepository;
  final SettingsRepository _settingsRepository;
  final SourceManager _sourceManager;
  final AuthHeadersLoader _getAuthHeaders;
  final DownloadPathsChanged? _onDownloadPathsChanged;

  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    final localFileState = _inspectLocalFiles(track);

    if (localFileState.invalidPaths.isNotEmpty) {
      track =
          await _clearInvalidDownloadPaths(track, localFileState.invalidPaths);
    }

    if (localFileState.localPath != null) {
      return (track, localFileState.localPath, null);
    }

    final source = _sourceManager.getSource(track.sourceType);
    if (source == null) {
      throw Exception('No source available for ${track.sourceType}');
    }

    try {
      final settings = await _settingsRepository.get();
      final config = AudioStreamConfig.fromSettings(settings, track.sourceType);
      final authHeaders = settings.useAuthForPlay(track.sourceType)
          ? await _getAuthHeaders(track.sourceType)
          : null;
      final streamResult = await fetchTrackAudioStreamWithQualityFallback(
        source: source,
        track: track,
        config: config,
        authHeaders: authHeaders,
      );

      track.audioUrl = streamResult.url;
      track.audioUrlExpiry = DateTime.now().add(
        streamResult.expiry ?? const Duration(hours: 1),
      );
      track.updatedAt = DateTime.now();

      if (persist) {
        final freshTrack = await _trackRepository.getById(track.id);
        if (freshTrack != null) {
          freshTrack.audioUrl = track.audioUrl;
          freshTrack.audioUrlExpiry = track.audioUrlExpiry;
          await _trackRepository.save(freshTrack);
          track.playlistInfo = freshTrack.playlistInfo;
        } else {
          await _trackRepository.save(track);
        }
      }

      return (track, null, streamResult);
    } on SourceApiException {
      rethrow;
    } catch (_) {
      if (retryCount < 1) {
        await Future.delayed(AppConstants.queueSaveRetryDelay);
        return ensureAudioStream(
          track,
          retryCount: retryCount + 1,
          persist: persist,
        );
      }
      rethrow;
    }
  }

  Future<AudioStreamResult?> getAlternativeAudioStream(
    Track track, {
    String? failedUrl,
  }) async {
    final source = _sourceManager.getSource(track.sourceType);
    if (source == null) return null;

    final settings = await _settingsRepository.get();
    final config = AudioStreamConfig.fromSettings(settings, track.sourceType);
    final authHeaders = settings.useAuthForPlay(track.sourceType)
        ? await _getAuthHeaders(track.sourceType)
        : null;

    for (final level in audioQualityFallbackLevels(
      config.qualityLevel,
      includeCurrent: false,
    )) {
      final fallbackConfig = config.copyWith(qualityLevel: level);
      final sourceAlternative = await fetchTrackAlternativeAudioStream(
        source: source,
        track: track,
        failedUrl: failedUrl,
        config: fallbackConfig,
        authHeaders: authHeaders,
      );
      if (sourceAlternative != null) return sourceAlternative;

      try {
        final primaryFallback = await fetchTrackAudioStream(
          source: source,
          track: track,
          config: fallbackConfig,
          authHeaders: authHeaders,
        );
        if (primaryFallback.url != failedUrl) {
          return primaryFallback;
        }
      } on SourceApiException catch (error) {
        if (!error.kind.canFallbackToLowerAudioQuality) rethrow;
      }
    }

    return fetchTrackAlternativeAudioStream(
      source: source,
      track: track,
      failedUrl: failedUrl,
      config: config,
      authHeaders: authHeaders,
    );
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
      _onDownloadPathsChanged?.call(
        DownloadPathsChangedEvent(
          track: persistedTrack,
          removedPaths: removedPaths,
        ),
      );
      return persistedTrack;
    }

    _onDownloadPathsChanged?.call(
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
}

class _LocalFileState {
  const _LocalFileState({required this.localPath, required this.invalidPaths});

  final String? localPath;
  final List<String> invalidPaths;
}
