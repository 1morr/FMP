import 'dart:async';

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/sources/base_source.dart';
import 'audio_service.dart';
import 'audio_stream_manager.dart';

class PlaybackRequestExecution {
  const PlaybackRequestExecution({
    required this.track,
    required this.attemptedUrl,
    required this.streamResult,
  });

  final Track track;
  final String attemptedUrl;
  final AudioStreamResult? streamResult;
}

class PlaybackRequestExecutor with Logging {
  PlaybackRequestExecutor({
    required FmpAudioService audioService,
    required PlaybackRequestStreamAccess audioStreamManager,
    required Track? Function() getNextTrack,
    required bool Function(int requestId) isSuperseded,
  })  : _audioService = audioService,
        _audioStreamManager = audioStreamManager,
        _getNextTrack = getNextTrack,
        _isSuperseded = isSuperseded;

  final FmpAudioService _audioService;
  final PlaybackRequestStreamAccess _audioStreamManager;
  final Track? Function() _getNextTrack;
  final bool Function(int requestId) _isSuperseded;

  Future<PlaybackRequestExecution?> executeQueueRestore({
    required int requestId,
    required Track track,
    required Duration position,
    required bool shouldResume,
  }) async {
    if (_isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded by newer request, aborting',
      );
      return null;
    }

    logDebug('Restoring queue track: ${track.title}');
    final (trackWithUrl, localPath, streamResult) =
        await _audioStreamManager.ensureAudioStream(track, persist: true);

    if (_isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded after URL fetch, aborting',
      );
      return null;
    }

    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw Exception('No audio URL available for: ${track.title}');
    }

    if (localPath != null) {
      await _audioService.setFile(url, track: trackWithUrl);
    } else {
      final headers = await _audioStreamManager.getPlaybackHeaders(trackWithUrl);
      if (_isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after header fetch, aborting',
        );
        return null;
      }
      await _audioService.setUrl(url, headers: headers, track: trackWithUrl);
    }

    if (_isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded after playback handoff, aborting',
      );
      return null;
    }

    if (position > Duration.zero) {
      await _audioService.seekTo(position);
      if (_isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after seek, aborting',
        );
        return null;
      }
    }

    if (shouldResume) {
      await _audioService.play();
      if (_isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after resume, aborting',
        );
        return null;
      }
    }

    return PlaybackRequestExecution(
      track: trackWithUrl,
      attemptedUrl: url,
      streamResult: streamResult,
    );
  }

  Future<PlaybackRequestExecution?> execute({
    required int requestId,
    required Track track,
    required bool persist,
    required bool prefetchNext,
  }) async {
    if (_isSuperseded(requestId)) {
      logDebug('Play request $requestId superseded by newer request, aborting');
      return null;
    }

    logDebug('Selecting playback for: ${track.title}');
    final selection =
        await _audioStreamManager.selectPlayback(track, persist: persist);

    if (_isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded after playback selection, aborting',
      );
      return null;
    }

    try {
      await _playSelection(requestId, selection);
    } catch (error, stackTrace) {
      if (!_isSuperseded(requestId)) {
        try {
          logInfo(
            'Attempting manager-selected fallback playback for: ${track.title} (failed URL: ${selection.url})',
          );
          final fallbackSelection =
              await _audioStreamManager.selectFallbackPlayback(
            selection.track,
            failedUrl: selection.url,
          );

          if (fallbackSelection != null) {
            if (_isSuperseded(requestId)) {
              logDebug(
                'Play request $requestId superseded after fallback selection, aborting',
              );
              return null;
            }

            await _playSelection(requestId, fallbackSelection);

            if (_isSuperseded(requestId)) {
              logDebug(
                'Play request $requestId superseded after fallback handoff, aborting',
              );
              return null;
            }

            if (prefetchNext) {
              final nextTrack = _getNextTrack();
              if (nextTrack != null) {
                unawaited(_audioStreamManager.prefetchTrack(nextTrack.copy()));
              }
            }

            return PlaybackRequestExecution(
              track: fallbackSelection.track,
              attemptedUrl: fallbackSelection.url,
              streamResult: fallbackSelection.streamResult,
            );
          }
        } catch (fallbackError, fallbackStackTrace) {
          logError(
            'Manager-selected fallback playback failed for: ${track.title}',
            fallbackError,
            fallbackStackTrace,
          );
        }
      }

      Error.throwWithStackTrace(error, stackTrace);
    }

    if (_isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded after playback handoff, aborting',
      );
      return null;
    }

    if (prefetchNext) {
      final nextTrack = _getNextTrack();
      if (nextTrack != null) {
        unawaited(_audioStreamManager.prefetchTrack(nextTrack.copy()));
      }
    }

    return PlaybackRequestExecution(
      track: selection.track,
      attemptedUrl: selection.url,
      streamResult: selection.streamResult,
    );
  }

  Future<void> _playSelection(int requestId, PlaybackSelection selection) async {
    final urlType = selection.localPath != null ? 'downloaded' : 'stream';
    logDebug(
      'Playing track: ${selection.track.title}, URL type: $urlType, source: ${selection.track.sourceType}',
    );

    if (selection.localPath != null) {
      await _audioService.playFile(selection.url, track: selection.track);
      return;
    }

    if (_isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded before playback handoff, aborting',
      );
      return;
    }

    await _audioService.playUrl(
      selection.url,
      headers: selection.headers,
      track: selection.track,
    );
  }
}
