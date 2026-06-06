import 'dart:async';

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/sources/base_source.dart';
import 'audio_playback_types.dart';
import 'audio_service.dart';
import 'audio_stream_manager.dart';

enum PlaybackSessionResultKind {
  completed,
  superseded,
  terminalMediaOpenError,
  failed,
}

class PlaybackSessionCommand {
  const PlaybackSessionCommand({
    required this.track,
    required this.mode,
    required this.positionBeforeLoad,
    this.persist = true,
    this.recordHistory = true,
    this.prefetchNext = true,
    this.onPlaybackStarting,
  });

  final Track track;
  final PlayMode mode;
  final Duration positionBeforeLoad;
  final bool persist;
  final bool recordHistory;
  final bool prefetchNext;
  final Future<void> Function()? onPlaybackStarting;
}

class PlaybackRestoreCommand {
  const PlaybackRestoreCommand({
    required this.track,
    required this.mode,
    required this.position,
    required this.shouldResume,
  });

  final Track track;
  final PlayMode mode;
  final Duration position;
  final bool shouldResume;
}

class PlaybackSessionResult {
  const PlaybackSessionResult._({
    required this.requestId,
    required this.kind,
    this.track,
    this.attemptedUrl,
    this.streamResult,
    this.message,
    this.error,
    this.stackTrace,
  });

  factory PlaybackSessionResult.completed({
    required int requestId,
    required Track track,
    required String attemptedUrl,
    required AudioStreamResult? streamResult,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.completed,
      track: track,
      attemptedUrl: attemptedUrl,
      streamResult: streamResult,
    );
  }

  factory PlaybackSessionResult.superseded({
    required int requestId,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.superseded,
    );
  }

  factory PlaybackSessionResult.terminalMediaOpenError({
    required int requestId,
    required Track track,
    required String message,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.terminalMediaOpenError,
      track: track,
      message: message,
    );
  }

  factory PlaybackSessionResult.failed({
    required int requestId,
    required Object error,
    required StackTrace stackTrace,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.failed,
      error: error,
      stackTrace: stackTrace,
    );
  }

  final int requestId;
  final PlaybackSessionResultKind kind;
  final Track? track;
  final String? attemptedUrl;
  final AudioStreamResult? streamResult;
  final String? message;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isCompleted => kind == PlaybackSessionResultKind.completed;
  bool get isSuperseded => kind == PlaybackSessionResultKind.superseded;
  bool get isTerminalMediaOpenError =>
      kind == PlaybackSessionResultKind.terminalMediaOpenError;
  bool get isFailed => kind == PlaybackSessionResultKind.failed;
}

typedef PlaybackSessionLoadingStarted = void Function(int requestId);
typedef PlaybackSessionLoadingFinished = void Function(
  int requestId,
  PlaybackSessionResult result,
);
typedef PlaybackSessionCurrentTrack = Track? Function();
typedef PlaybackSessionTerminalMessage = String Function(Track track);
typedef PlaybackSessionTerminalMediaOpen = void Function({
  required Track track,
  required String message,
});
typedef PlaybackSessionPosition = Duration Function();
typedef PlaybackSessionIsPlaying = bool Function();
typedef PlaybackSessionDelay = Future<void> Function(Duration duration);

class PlaybackRequestSession with Logging {
  PlaybackRequestSession({
    required FmpAudioService audioService,
    required PlaybackRequestStreamAccess audioStreamManager,
    required Track? Function() getNextTrack,
    required PlaybackSessionLoadingStarted onLoadingStarted,
    required PlaybackSessionLoadingFinished onLoadingFinished,
    required PlaybackSessionTerminalMessage terminalMediaOpenMessage,
    PlaybackSessionTerminalMediaOpen? onTerminalMediaOpenError,
    PlaybackSessionDelay? delay,
  })  : _audioService = audioService,
        _audioStreamManager = audioStreamManager,
        _getNextTrack = getNextTrack,
        _onLoadingStarted = onLoadingStarted,
        _onLoadingFinished = onLoadingFinished,
        _terminalMediaOpenMessage = terminalMediaOpenMessage,
        _onTerminalMediaOpenError = onTerminalMediaOpenError,
        _delay = delay ?? Future<void>.delayed;

  static const _mediaOpenRecoveryDelay = Duration(seconds: 2);
  static const _mediaOpenRecoveryAdvance = Duration(milliseconds: 500);

  final FmpAudioService _audioService;
  final PlaybackRequestStreamAccess _audioStreamManager;
  final Track? Function() _getNextTrack;
  final PlaybackSessionLoadingStarted _onLoadingStarted;
  final PlaybackSessionLoadingFinished _onLoadingFinished;
  final PlaybackSessionTerminalMessage _terminalMediaOpenMessage;
  final PlaybackSessionTerminalMediaOpen? _onTerminalMediaOpenError;
  final PlaybackSessionDelay _delay;

  int _requestId = 0;
  _SessionLock? _playLock;
  final Map<int, _PendingMediaOpenError> _pendingMediaOpenErrors = {};
  _PendingPostHandoffMediaOpenError? _pendingPostHandoffMediaOpenError;
  bool _isDisposed = false;

  int get activeRequestId => _requestId;
  bool get isInLoadingState => _playLock != null;

  void dispose() {
    _isDisposed = true;
    _requestId++;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = null;
    for (final pending in _pendingMediaOpenErrors.values) {
      pending.complete(recovered: true);
    }
    _pendingMediaOpenErrors.clear();
    _pendingPostHandoffMediaOpenError?.complete();
    _pendingPostHandoffMediaOpenError = null;
  }

  bool isSuperseded(int requestId) => _isDisposed || requestId != _requestId;

  void cancelActive() {
    if (_isDisposed) return;
    _cancelPostHandoffMediaOpenError();
    _requestId++;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = null;
  }

  Future<PlaybackSessionResult> start(PlaybackSessionCommand command) async {
    final requestId = _enterLoading();
    late PlaybackSessionResult result;
    try {
      await command.onPlaybackStarting?.call();
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      await _stopForRequest(requestId);
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      final execution = await _execute(
        requestId: requestId,
        track: command.track,
        persist: command.persist,
        prefetchNext: command.prefetchNext,
      );
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (execution == null) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      result = PlaybackSessionResult.completed(
        requestId: requestId,
        track: execution.track,
        attemptedUrl: execution.attemptedUrl,
        streamResult: execution.streamResult,
      );
      final completedMediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (completedMediaOpenResult != null) {
        result = completedMediaOpenResult;
      }
      return result;
    } catch (error, stackTrace) {
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      result = PlaybackSessionResult.failed(
        requestId: requestId,
        error: error,
        stackTrace: stackTrace,
      );
      return result;
    } finally {
      _finishLoading(requestId, result);
    }
  }

  Future<PlaybackSessionResult> restore(PlaybackRestoreCommand command) async {
    final requestId = _enterLoading();
    late PlaybackSessionResult result;
    try {
      await _stopForRequest(requestId);
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      final execution = await _executeQueueRestore(
        requestId: requestId,
        track: command.track,
        position: command.position,
        shouldResume: command.shouldResume,
      );
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (execution == null) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }

      result = PlaybackSessionResult.completed(
        requestId: requestId,
        track: execution.track,
        attemptedUrl: execution.attemptedUrl,
        streamResult: execution.streamResult,
      );
      final completedMediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (completedMediaOpenResult != null) {
        result = completedMediaOpenResult;
      }
      return result;
    } catch (error, stackTrace) {
      final mediaOpenResult = await _consumeMediaOpenResult(requestId);
      if (mediaOpenResult != null) {
        result = mediaOpenResult;
        return result;
      }
      if (isSuperseded(requestId)) {
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      result = PlaybackSessionResult.failed(
        requestId: requestId,
        error: error,
        stackTrace: stackTrace,
      );
      return result;
    } finally {
      _finishLoading(requestId, result);
    }
  }

  Future<void> onMediaOpenError({
    required String error,
    required Track track,
    required Duration positionAtError,
  }) async {
    if (_isDisposed) return;
    final requestId = _playLock?.requestId;
    if (requestId == null) {
      await _handlePostHandoffMediaOpenError(
        error: error,
        track: track,
        positionAtError: positionAtError,
      );
      return;
    }

    final existing = _pendingMediaOpenErrors[requestId];
    if (existing != null) {
      logDebug('Media open error already pending for request $requestId');
      await existing.recovered.future;
      return;
    }

    final pending = _PendingMediaOpenError(track);
    _pendingMediaOpenErrors[requestId] = pending;

    await _delay(_mediaOpenRecoveryDelay);
    if (_isDisposed ||
        _pendingMediaOpenErrors[requestId] != pending ||
        isSuperseded(requestId)) {
      pending.complete(recovered: true);
      return;
    }

    final currentPosition = _audioService.position;
    final hasAdvanced =
        currentPosition - positionAtError > _mediaOpenRecoveryAdvance;
    if (_audioService.isPlaying && hasAdvanced) {
      logDebug('Media open error recovered by backend: $error');
      pending.complete(recovered: true);
      return;
    }

    logWarning('Media open error did not recover: $error');
    cancelActive();
    final terminalGeneration = _requestId;
    try {
      await _audioService.stop();
    } catch (stopError, stackTrace) {
      logError('Failed to stop player after media open error', stopError,
          stackTrace);
    }

    if (_isDisposed ||
        _pendingMediaOpenErrors[requestId] != pending ||
        _requestId != terminalGeneration) {
      pending.complete(recovered: true);
      return;
    }

    pending.terminalMessage = _terminalMediaOpenMessage(track);
    pending.complete(recovered: false);
  }

  Future<void> _handlePostHandoffMediaOpenError({
    required String error,
    required Track track,
    required Duration positionAtError,
  }) async {
    final existing = _pendingPostHandoffMediaOpenError;
    if (existing != null) {
      if (existing.track.uniqueKey == track.uniqueKey) {
        logDebug('Post-handoff media open error already pending');
        await existing.completer.future;
      }
      return;
    }

    final pending = _PendingPostHandoffMediaOpenError(track);
    _pendingPostHandoffMediaOpenError = pending;
    try {
      await _delay(_mediaOpenRecoveryDelay);
      if (_isDisposed || _pendingPostHandoffMediaOpenError != pending) {
        pending.complete();
        return;
      }

      final currentPosition = _audioService.position;
      final hasAdvanced =
          currentPosition - positionAtError > _mediaOpenRecoveryAdvance;
      if (_audioService.isPlaying && hasAdvanced) {
        logDebug('Post-handoff media open error recovered by backend: $error');
        pending.complete();
        return;
      }

      logWarning('Post-handoff media open error did not recover: $error');
      try {
        await _audioService.stop();
      } catch (stopError, stackTrace) {
        logError('Failed to stop player after media open error', stopError,
            stackTrace);
      }

      if (_isDisposed || _pendingPostHandoffMediaOpenError != pending) {
        pending.complete();
        return;
      }

      final message = _terminalMediaOpenMessage(track);
      _onTerminalMediaOpenError?.call(track: track, message: message);
      pending.complete();
    } finally {
      if (_pendingPostHandoffMediaOpenError == pending) {
        _pendingPostHandoffMediaOpenError = null;
      }
    }
  }

  int _enterLoading() {
    _cancelPostHandoffMediaOpenError();
    final requestId = ++_requestId;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = _SessionLock(requestId);
    _onLoadingStarted(requestId);
    return requestId;
  }

  void _cancelPostHandoffMediaOpenError() {
    _pendingPostHandoffMediaOpenError?.complete();
    _pendingPostHandoffMediaOpenError = null;
  }

  void _finishLoading(int requestId, PlaybackSessionResult result) {
    if (_isDisposed) return;
    _playLock?.completeIf(requestId);
    if (_playLock?.requestId == requestId) {
      _playLock = null;
    }
    _onLoadingFinished(requestId, result);
  }

  Future<PlaybackSessionResult?> _consumeMediaOpenResult(
    int requestId,
  ) async {
    final pending = _pendingMediaOpenErrors[requestId];
    if (pending == null) return null;
    try {
      final recovered = await pending.recovered.future;
      if (recovered) return null;
      return PlaybackSessionResult.terminalMediaOpenError(
        requestId: requestId,
        track: pending.track,
        message:
            pending.terminalMessage ?? _terminalMediaOpenMessage(pending.track),
      );
    } finally {
      if (_pendingMediaOpenErrors[requestId] == pending) {
        _pendingMediaOpenErrors.remove(requestId);
      }
    }
  }

  Future<void> _stopForRequest(int requestId) async {
    if (isSuperseded(requestId)) return;
    await _audioService.stop();
  }

  Future<_PlaybackRequestExecution?> _execute({
    required int requestId,
    required Track track,
    required bool persist,
    required bool prefetchNext,
  }) async {
    if (isSuperseded(requestId)) {
      logDebug('Play request $requestId superseded by newer request, aborting');
      return null;
    }

    logDebug('Selecting playback for: ${track.title}');
    final selection =
        await _audioStreamManager.selectPlayback(track, persist: persist);

    if (isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded after playback selection, aborting',
      );
      return null;
    }

    try {
      await _playSelection(requestId, selection);
    } catch (error, stackTrace) {
      if (!isSuperseded(requestId)) {
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
            if (isSuperseded(requestId)) {
              logDebug(
                'Play request $requestId superseded after fallback selection, aborting',
              );
              return null;
            }

            await _playSelection(requestId, fallbackSelection);

            if (isSuperseded(requestId)) {
              logDebug(
                'Play request $requestId superseded after fallback handoff, aborting',
              );
              return null;
            }

            _prefetchNextIfRequested(prefetchNext);

            return _PlaybackRequestExecution(
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

    if (isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded after playback handoff, aborting',
      );
      return null;
    }

    _prefetchNextIfRequested(prefetchNext);

    return _PlaybackRequestExecution(
      track: selection.track,
      attemptedUrl: selection.url,
      streamResult: selection.streamResult,
    );
  }

  Future<_PlaybackRequestExecution?> _executeQueueRestore({
    required int requestId,
    required Track track,
    required Duration position,
    required bool shouldResume,
  }) async {
    if (isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded by newer request, aborting',
      );
      return null;
    }

    logDebug('Restoring queue track: ${track.title}');
    final (trackWithUrl, localPath, streamResult) =
        await _audioStreamManager.ensureAudioStream(track, persist: true);

    if (isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded after URL fetch, aborting',
      );
      return null;
    }

    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw Exception('No audio URL available for: ${track.title}');
    }

    var attemptedUrl = url;
    if (localPath != null) {
      await _waitForRequestOperation<void>(
        requestId: requestId,
        operation: _audioService.setFile(url, track: trackWithUrl),
        description: 'setFile',
      );
    } else {
      final networkRequest =
          await _audioStreamManager.prepareNetworkPlayback(trackWithUrl, url);
      if (isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after playback preparation, aborting',
        );
        return null;
      }
      attemptedUrl = networkRequest.url;
      await _waitForRequestOperation<void>(
        requestId: requestId,
        operation: _audioService.setUrl(
          networkRequest.url,
          headers: networkRequest.headers,
          track: trackWithUrl,
        ),
        description: 'setUrl',
      );
    }

    if (isSuperseded(requestId)) {
      logDebug(
        'Queue restore request $requestId superseded after playback handoff, aborting',
      );
      return null;
    }

    if (position > Duration.zero) {
      await _waitForRequestOperation<void>(
        requestId: requestId,
        operation: _audioService.seekTo(position),
        description: 'seekTo',
      );
      if (isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after seek, aborting',
        );
        return null;
      }
    }

    if (shouldResume) {
      await _waitForRequestOperation<void>(
        requestId: requestId,
        operation: _audioService.play(),
        description: 'play',
      );
      if (isSuperseded(requestId)) {
        logDebug(
          'Queue restore request $requestId superseded after resume, aborting',
        );
        return null;
      }
    }

    return _PlaybackRequestExecution(
      track: trackWithUrl,
      attemptedUrl: attemptedUrl,
      streamResult: streamResult,
    );
  }

  Future<void> _playSelection(
      int requestId, PlaybackSelection selection) async {
    final urlType = selection.localPath != null ? 'downloaded' : 'stream';
    logDebug(
      'Playing track: ${selection.track.title}, URL type: $urlType, source: ${selection.track.sourceType}',
    );

    if (selection.localPath != null) {
      await _waitForRequestOperation<void>(
        requestId: requestId,
        operation:
            _audioService.playFile(selection.url, track: selection.track),
        description: 'playFile',
      );
      return;
    }

    if (isSuperseded(requestId)) {
      logDebug(
        'Play request $requestId superseded before playback handoff, aborting',
      );
      return;
    }

    await _waitForRequestOperation<void>(
      requestId: requestId,
      operation: _audioService.playUrl(
        selection.url,
        headers: selection.headers,
        track: selection.track,
      ),
      description: 'playUrl',
    );
  }

  Future<T?> _waitForRequestOperation<T>({
    required int requestId,
    required Future<T> operation,
    required String description,
  }) async {
    final operationCompleter = Completer<T?>();
    unawaited(operation.then((value) {
      if (!operationCompleter.isCompleted) {
        operationCompleter.complete(value);
      }
    }).catchError((Object error, StackTrace stackTrace) {
      if (isSuperseded(requestId)) {
        logError(
          '$description failed after request $requestId was superseded',
          error,
          stackTrace,
        );
        if (!operationCompleter.isCompleted) {
          operationCompleter.complete(null);
        }
        return;
      }
      if (!operationCompleter.isCompleted) {
        operationCompleter.completeError(error, stackTrace);
      }
    }));

    final lock = _playLock;
    if (lock == null || lock.requestId != requestId) {
      return operationCompleter.future;
    }

    return Future.any([
      operationCompleter.future,
      lock.completer.future.then<T?>((_) => null),
    ]);
  }

  void _prefetchNextIfRequested(bool prefetchNext) {
    if (!prefetchNext) return;
    final nextTrack = _getNextTrack();
    if (nextTrack != null) {
      unawaited(_audioStreamManager.prefetchTrack(nextTrack.copy()));
    }
  }
}

class _PlaybackRequestExecution {
  const _PlaybackRequestExecution({
    required this.track,
    required this.attemptedUrl,
    required this.streamResult,
  });

  final Track track;
  final String attemptedUrl;
  final AudioStreamResult? streamResult;
}

class _SessionLock {
  _SessionLock(this.requestId);

  final int requestId;
  final Completer<void> completer = Completer<void>();

  void completeIf(int id) {
    if (id == requestId && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _PendingMediaOpenError {
  _PendingMediaOpenError(this.track);

  final Track track;
  final Completer<bool> recovered = Completer<bool>();
  String? terminalMessage;

  void complete({required bool recovered}) {
    if (!this.recovered.isCompleted) {
      this.recovered.complete(recovered);
    }
  }
}

class _PendingPostHandoffMediaOpenError {
  _PendingPostHandoffMediaOpenError(this.track);

  final Track track;
  final Completer<void> completer = Completer<void>();

  void complete() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
}
