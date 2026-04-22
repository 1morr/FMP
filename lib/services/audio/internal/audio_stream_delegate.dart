import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/track.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/track_repository.dart';
import '../../../data/sources/base_source.dart';
import '../../../data/sources/source_provider.dart';

typedef AuthHeadersLoader = Future<Map<String, String>?> Function(
  SourceType sourceType,
);

class AudioStreamDelegate {
  AudioStreamDelegate({
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

  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    final localFileState = _inspectLocalFiles(track);

    if (localFileState.localPath != null) {
      if (localFileState.invalidPaths.isNotEmpty && persist) {
        _clearInvalidPaths(track, localFileState.invalidPaths);
        await _trackRepository.save(track);
      }
      return (track, localFileState.localPath, null);
    }

    if (localFileState.invalidPaths.isNotEmpty && persist) {
      track.clearAllDownloadPaths();
      await _trackRepository.save(track);
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
      final streamResult = await source.getAudioStream(
        track.sourceId,
        config: config,
        authHeaders: authHeaders,
      );

      track.audioUrl = streamResult.url;
      track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
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
    return source.getAlternativeAudioStream(
      track.sourceId,
      failedUrl: failedUrl,
      config: config,
    );
  }

  _LocalFileState _inspectLocalFiles(Track track) {
    String? localPath;
    final invalidPaths = <String>[];

    for (final path in track.allDownloadPaths) {
      if (File(path).existsSync()) {
        localPath = path;
        break;
      }
      invalidPaths.add(path);
    }

    return _LocalFileState(localPath: localPath, invalidPaths: invalidPaths);
  }

  void _clearInvalidPaths(Track track, List<String> invalidPaths) {
    track.playlistInfo = track.playlistInfo
        .map((info) => PlaylistDownloadInfo()
          ..playlistId = info.playlistId
          ..playlistName = info.playlistName
          ..downloadPath = invalidPaths.contains(info.downloadPath)
              ? ''
              : info.downloadPath)
        .toList();
  }
}

class _LocalFileState {
  const _LocalFileState({required this.localPath, required this.invalidPaths});

  final String? localPath;
  final List<String> invalidPaths;
}
