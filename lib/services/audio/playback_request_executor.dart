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

    logDebug('Fetching audio URL for: ${track.title}');
    final (trackWithUrl, localPath, streamResult) =
        await _audioStreamManager.ensureAudioStream(track, persist: persist);

    if (_isSuperseded(requestId)) {
      logDebug('Play request $requestId superseded after URL fetch, aborting');
      return null;
    }

    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw Exception('No audio URL available for: ${track.title}');
    }

    final urlType = localPath != null ? 'downloaded' : 'stream';
    logDebug(
      'Playing track: ${track.title}, URL type: $urlType, source: ${track.sourceType}',
    );

    if (localPath != null) {
      await _audioService.playFile(url, track: trackWithUrl);
    } else {
      final headers = await _audioStreamManager.getPlaybackHeaders(trackWithUrl);
      if (_isSuperseded(requestId)) {
        logDebug('Play request $requestId superseded after header fetch, aborting');
        return null;
      }
      await _audioService.playUrl(url, headers: headers, track: trackWithUrl);
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
        unawaited(_audioStreamManager.prefetchTrack(nextTrack));
      }
    }

    return PlaybackRequestExecution(
      track: trackWithUrl,
      attemptedUrl: url,
      streamResult: streamResult,
    );
  }
}
