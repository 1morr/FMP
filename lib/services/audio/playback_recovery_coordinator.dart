import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../data/models/track.dart';
import 'audio_playback_types.dart';
import 'playback_request_session.dart';

abstract interface class PlaybackRecoveryTimer {
  void cancel();
}

class _TimerPlaybackRecoveryTimer implements PlaybackRecoveryTimer {
  _TimerPlaybackRecoveryTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}

typedef PlaybackRecoveryTimerFactory = PlaybackRecoveryTimer Function(
  Duration delay,
  void Function() callback,
);

typedef PlaybackRecoveryDelay = Future<void> Function(Duration delay);

typedef PlaybackRecoveryEventListener = void Function(
  PlaybackRecoveryEvent event,
);

typedef PlaybackRecoveryRetryableError = bool Function(Object error);

PlaybackRecoveryTimer defaultPlaybackRecoveryTimerFactory(
  Duration delay,
  void Function() callback,
) {
  return _TimerPlaybackRecoveryTimer(Timer(delay, callback));
}

Future<void> defaultPlaybackRecoveryDelay(Duration delay) {
  return Future<void>.delayed(delay);
}

abstract interface class PlaybackRetryExecutor {
  Future<PlaybackSessionResult> retryPlayback({
    required Track track,
    required Duration? position,
    required PlayMode mode,
  });
}

class PlaybackRetryCall {
  const PlaybackRetryCall({
    required this.track,
    required this.position,
    required this.mode,
  });

  final Track track;
  final Duration? position;
  final PlayMode mode;
}

enum PlaybackRecoveryEventKind {
  retryStarted,
  retryScheduled,
  retryExhausted,
  retrySucceeded,
  recoveryFailedNonRetryable,
  staleEventIgnored,
}

class PlaybackRecoveryState {
  const PlaybackRecoveryState({
    required this.isNetworkError,
    required this.isRetrying,
    required this.retryAttempt,
    required this.nextRetryAt,
  });

  const PlaybackRecoveryState.clear()
      : isNetworkError = false,
        isRetrying = false,
        retryAttempt = 0,
        nextRetryAt = null;

  final bool isNetworkError;
  final bool isRetrying;
  final int retryAttempt;
  final DateTime? nextRetryAt;
}

class PlaybackRecoveryEvent {
  const PlaybackRecoveryEvent({
    required this.kind,
    required this.state,
    this.track,
    this.position,
    this.result,
    this.error,
  });

  factory PlaybackRecoveryEvent.stale() {
    return const PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.staleEventIgnored,
      state: PlaybackRecoveryState.clear(),
    );
  }

  final PlaybackRecoveryEventKind kind;
  final PlaybackRecoveryState state;
  final Track? track;
  final Duration? position;
  final PlaybackSessionResult? result;
  final Object? error;
}

class PlaybackRecoveryCoordinator {
  PlaybackRecoveryCoordinator({
    required PlaybackRetryExecutor retryExecutor,
    PlaybackRecoveryTimerFactory timerFactory =
        defaultPlaybackRecoveryTimerFactory,
    PlaybackRecoveryDelay delay = defaultPlaybackRecoveryDelay,
    PlaybackRecoveryEventListener? onRecoveryEvent,
    PlaybackRecoveryRetryableError? isRetryableError,
  })  : _retryExecutor = retryExecutor,
        _timerFactory = timerFactory,
        _delay = delay,
        _onRecoveryEvent = onRecoveryEvent,
        _isRetryableError = isRetryableError ?? ((_) => false);

  final PlaybackRetryExecutor _retryExecutor;
  final PlaybackRecoveryTimerFactory _timerFactory;
  final PlaybackRecoveryDelay _delay;
  final PlaybackRecoveryEventListener? _onRecoveryEvent;
  final PlaybackRecoveryRetryableError _isRetryableError;

  PlaybackRecoveryTimer? _retryTimer;
  int _retryAttempt = 0;
  int _retryGeneration = 0;
  int? _scheduledRetryGeneration;
  String? _scheduledRetryTrackKey;
  Track? _recoveryTrack;
  Duration? _recoveryPosition;
  var _disposed = false;

  Track? get recoveryTrack => _recoveryTrack;
  Duration? get recoveryPosition => _recoveryPosition;

  PlaybackRecoveryEvent scheduleRetry({
    required Track track,
    required Duration? position,
    required PlayMode mode,
  }) {
    final generation = ++_retryGeneration;
    _recoveryTrack = track;
    _saveMeaningfulPosition(position);

    if (_retryAttempt >= NetworkRetryConfig.maxRetries) {
      _cancelRetryTimer();
      _clearScheduledRetryMarker();
      return PlaybackRecoveryEvent(
        kind: PlaybackRecoveryEventKind.retryExhausted,
        state: PlaybackRecoveryState(
          isNetworkError: true,
          isRetrying: false,
          retryAttempt: _retryAttempt,
          nextRetryAt: null,
        ),
        track: track,
        position: _recoveryPosition,
      );
    }

    final retryDelay = NetworkRetryConfig.getRetryDelay(_retryAttempt);
    final nextRetryAt = DateTime.now().add(retryDelay);
    _cancelRetryTimer();
    _scheduledRetryGeneration = generation;
    _scheduledRetryTrackKey = track.uniqueKey;
    _retryTimer = _timerFactory(retryDelay, () {
      if (!_isRetryGenerationCurrent(generation, track)) return;
      _clearScheduledRetryMarker();
      unawaited(_runScheduledRetry(
        track: track,
        position: _recoveryPosition,
        generation: generation,
        mode: mode,
      ));
    });

    return PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.retryScheduled,
      state: PlaybackRecoveryState(
        isNetworkError: true,
        isRetrying: true,
        retryAttempt: _retryAttempt,
        nextRetryAt: nextRetryAt,
      ),
      track: track,
      position: _recoveryPosition,
    );
  }

  PlaybackRecoveryEvent onBackendNetworkError({
    required Track track,
    required Duration? position,
    required bool isActiveRetryHandoff,
    required PlayMode mode,
  }) {
    if (!isActiveRetryHandoff && _isDuplicateRetryingAudioError(track)) {
      return PlaybackRecoveryEvent.stale();
    }
    if (isActiveRetryHandoff) {
      _retryAttempt = 0;
    }
    return scheduleRetry(track: track, position: position, mode: mode);
  }

  Future<PlaybackRecoveryEvent> retryManually({
    required Track? fallbackTrack,
    required Duration? fallbackPosition,
    required PlayMode mode,
  }) {
    final track = _recoveryTrack ?? fallbackTrack;
    if (track == null) {
      return Future.value(PlaybackRecoveryEvent.stale());
    }

    final position = _recoveryPosition ?? fallbackPosition;
    final generation = ++_retryGeneration;
    _recoveryTrack = track;
    _saveMeaningfulPosition(position);
    _retryAttempt = 0;
    _clearScheduledRetryMarker();
    _cancelRetryTimer();

    return _runRetry(
      track: track,
      position: _recoveryPosition,
      generation: generation,
      mode: mode,
    );
  }

  Future<PlaybackRecoveryEvent> onNetworkRecovered({
    required PlayMode mode,
    Duration stabilizationDelay = AppConstants.seekStabilizationDelay,
  }) async {
    final track = _recoveryTrack;
    if (track == null) {
      return PlaybackRecoveryEvent.stale();
    }

    final position = _recoveryPosition;
    final generation = ++_retryGeneration;
    _retryAttempt = 0;
    _clearScheduledRetryMarker();
    _cancelRetryTimer();

    await _delay(stabilizationDelay);
    if (!_isRetryGenerationCurrent(generation, track)) {
      return PlaybackRecoveryEvent.stale();
    }

    return _runRetry(
      track: track,
      position: position,
      generation: generation,
      mode: mode,
    );
  }

  PlaybackRecoveryEvent onPrematureCompletion({
    required Track track,
    required Duration? position,
    required PlayMode mode,
  }) {
    return scheduleRetry(track: track, position: position, mode: mode);
  }

  void clearForNewPlayback(Track track) {
    _retryGeneration++;
    _cancelRetryTimer();
    _retryAttempt = 0;
    _recoveryTrack = null;
    _recoveryPosition = null;
    _clearScheduledRetryMarker();
  }

  PlaybackRecoveryEvent reset() {
    _retryGeneration++;
    _cancelRetryTimer();
    _retryAttempt = 0;
    _recoveryTrack = null;
    _recoveryPosition = null;
    _clearScheduledRetryMarker();
    return const PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.retrySucceeded,
      state: PlaybackRecoveryState.clear(),
    );
  }

  void dispose() {
    _disposed = true;
    reset();
  }

  Future<PlaybackRecoveryEvent> _runRetry({
    required Track track,
    required Duration? position,
    required int generation,
    required PlayMode mode,
  }) async {
    if (!_isRetryGenerationCurrent(generation, track)) {
      return PlaybackRecoveryEvent.stale();
    }

    _retryAttempt++;
    _onRecoveryEvent?.call(PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.retryStarted,
      state: PlaybackRecoveryState(
        isNetworkError: true,
        isRetrying: true,
        retryAttempt: _retryAttempt,
        nextRetryAt: null,
      ),
      track: track,
      position: position,
    ));

    late final PlaybackSessionResult result;
    try {
      result = await _retryExecutor.retryPlayback(
        track: track,
        position: position,
        mode: mode,
      );
    } catch (error) {
      if (!_isRetryGenerationCurrent(generation, track)) {
        return PlaybackRecoveryEvent.stale();
      }
      if (_isRetryableError(error)) {
        final event = scheduleRetry(
          track: track,
          position: position,
          mode: mode,
        );
        return PlaybackRecoveryEvent(
          kind: event.kind,
          state: event.state,
          track: event.track,
          position: event.position,
          error: error,
        );
      }
      reset();
      return PlaybackRecoveryEvent(
        kind: PlaybackRecoveryEventKind.recoveryFailedNonRetryable,
        state: const PlaybackRecoveryState.clear(),
        track: track,
        position: position,
        error: error,
      );
    }

    if (!_isRetryGenerationCurrent(generation, track)) {
      return PlaybackRecoveryEvent.stale();
    }

    if (result.isCompleted) {
      reset();
      return PlaybackRecoveryEvent(
        kind: PlaybackRecoveryEventKind.retrySucceeded,
        state: const PlaybackRecoveryState.clear(),
        track: track,
        position: position,
        result: result,
      );
    }

    if (result.isSuperseded) {
      return PlaybackRecoveryEvent.stale();
    }

    if (result.isTerminalMediaOpenError) {
      reset();
      return PlaybackRecoveryEvent(
        kind: PlaybackRecoveryEventKind.recoveryFailedNonRetryable,
        state: const PlaybackRecoveryState.clear(),
        track: track,
        position: position,
        result: result,
        error: result.message,
      );
    }

    final error = result.error;
    if (error != null && _isRetryableError(error)) {
      final event = scheduleRetry(
        track: track,
        position: position,
        mode: mode,
      );
      return PlaybackRecoveryEvent(
        kind: event.kind,
        state: event.state,
        track: event.track,
        position: event.position,
        result: result,
        error: error,
      );
    }

    reset();
    return PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.recoveryFailedNonRetryable,
      state: const PlaybackRecoveryState.clear(),
      track: track,
      position: position,
      result: result,
      error: result.error ?? result,
    );
  }

  bool _isRetryGenerationCurrent(int generation, Track track) {
    return !_disposed &&
        generation == _retryGeneration &&
        _recoveryTrack?.uniqueKey == track.uniqueKey;
  }

  bool _isDuplicateRetryingAudioError(Track track) {
    return _scheduledRetryGeneration == _retryGeneration &&
        _scheduledRetryTrackKey == track.uniqueKey;
  }

  void _clearScheduledRetryMarker() {
    _scheduledRetryGeneration = null;
    _scheduledRetryTrackKey = null;
  }

  void _saveMeaningfulPosition(Duration? position) {
    if (position != null && position > Duration.zero) {
      _recoveryPosition = position;
    }
  }

  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _runScheduledRetry({
    required Track track,
    required Duration? position,
    required int generation,
    required PlayMode mode,
  }) async {
    final event = await _runRetry(
      track: track,
      position: position,
      generation: generation,
      mode: mode,
    );
    if (event.kind == PlaybackRecoveryEventKind.staleEventIgnored) return;
    _onRecoveryEvent?.call(event);
  }
}
