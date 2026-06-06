import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/playback_recovery_coordinator.dart';
import 'package:fmp/services/audio/playback_request_session.dart';

void main() {
  group('PlaybackRecoveryCoordinator', () {
    late _FakeRetryExecutor executor;
    late _ManualRetryTimerFactory timerFactory;
    late PlaybackRecoveryCoordinator coordinator;

    setUp(() {
      executor = _FakeRetryExecutor();
      timerFactory = _ManualRetryTimerFactory();
      coordinator = PlaybackRecoveryCoordinator(
        retryExecutor: executor,
        timerFactory: timerFactory.create,
        delay: timerFactory.delay,
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('scheduleRetry stores track, position, and retry state patch', () {
      final track = _track('retry-schedule');

      final event = coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 14),
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.retryScheduled);
      expect(event.state.isNetworkError, isTrue);
      expect(event.state.isRetrying, isTrue);
      expect(event.state.retryAttempt, 0);
      expect(event.state.nextRetryAt, isNotNull);
      expect(coordinator.recoveryTrack?.sourceId, 'retry-schedule');
      expect(coordinator.recoveryPosition, const Duration(seconds: 14));
      expect(timerFactory.timers, hasLength(1));
    });

    test('scheduled retry uses the mode captured when retry was scheduled',
        () async {
      final track = _track('retry-mix-mode');
      executor.nextResult = PlaybackSessionResult.completed(
        requestId: 12,
        track: track,
        attemptedUrl: 'https://example.com/retry-mix-mode.m4a',
        streamResult: null,
      );

      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 15),
        mode: PlayMode.mix,
      );

      timerFactory.timers.last.fire();
      await pumpEventQueue();

      expect(executor.calls.single.mode, PlayMode.mix);
    });

    test('duplicate backend network error during same wait is suppressed', () {
      final track = _track('duplicate-error');
      coordinator.scheduleRetry(
        track: track,
        position: Duration.zero,
        mode: PlayMode.queue,
      );

      final event = coordinator.onBackendNetworkError(
        track: track,
        position: const Duration(seconds: 3),
        isActiveRetryHandoff: false,
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.staleEventIgnored);
      expect(timerFactory.timers, hasLength(1));
    });

    test('backend network error during retry handoff schedules fresh retry',
        () {
      final track = _track('handoff-error');
      coordinator.scheduleRetry(
        track: track,
        position: Duration.zero,
        mode: PlayMode.queue,
      );

      final event = coordinator.onBackendNetworkError(
        track: track,
        position: const Duration(seconds: 7),
        isActiveRetryHandoff: true,
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.retryScheduled);
      expect(event.state.retryAttempt, 0);
      expect(coordinator.recoveryPosition, const Duration(seconds: 7));
      expect(timerFactory.timers, hasLength(2));
    });

    test('manual retry resets attempt and restores saved position', () async {
      final track = _track('manual-retry');
      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 47),
        mode: PlayMode.queue,
      );
      executor.nextResult = PlaybackSessionResult.completed(
        requestId: 11,
        track: track,
        attemptedUrl: 'https://example.com/manual-retry.m4a',
        streamResult: null,
      );

      final event = await coordinator.retryManually(
        fallbackTrack: null,
        fallbackPosition: Duration.zero,
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.retrySucceeded);
      expect(executor.calls.single.track.sourceId, 'manual-retry');
      expect(executor.calls.single.position, const Duration(seconds: 47));
      expect(event.state.isNetworkError, isFalse);
      expect(event.state.isRetrying, isFalse);
      expect(event.state.retryAttempt, 0);
    });

    test('retry start listener fires before retry completes', () async {
      final track = _track('retry-started');
      final events = <PlaybackRecoveryEvent>[];
      final pendingResult = Completer<PlaybackSessionResult>();
      coordinator.dispose();
      coordinator = PlaybackRecoveryCoordinator(
        retryExecutor: executor,
        timerFactory: timerFactory.create,
        delay: timerFactory.delay,
        onRecoveryEvent: events.add,
      );
      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 19),
        mode: PlayMode.queue,
      );
      executor.nextCompleter = pendingResult;

      final retry = coordinator.retryManually(
        fallbackTrack: null,
        fallbackPosition: Duration.zero,
        mode: PlayMode.queue,
      );
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.kind, PlaybackRecoveryEventKind.retryStarted);
      expect(events.single.state.isNetworkError, isTrue);
      expect(events.single.state.isRetrying, isTrue);
      expect(events.single.state.retryAttempt, 1);
      expect(events.single.state.nextRetryAt, isNull);
      pendingResult.complete(PlaybackSessionResult.completed(
        requestId: 31,
        track: track,
        attemptedUrl: 'https://example.com/retry-started.m4a',
        streamResult: null,
      ));

      final event = await retry;

      expect(event.kind, PlaybackRecoveryEventKind.retrySucceeded);
    });

    test('network recovered ignores stale track after generation changes',
        () async {
      final oldTrack = _track('old-track');
      final newTrack = _track('new-track');
      coordinator.scheduleRetry(
        track: oldTrack,
        position: const Duration(seconds: 12),
        mode: PlayMode.queue,
      );
      final recovery = coordinator.onNetworkRecovered(
        mode: PlayMode.queue,
        stabilizationDelay: const Duration(milliseconds: 500),
      );

      coordinator.clearForNewPlayback(newTrack);
      timerFactory.completeDelay(const Duration(milliseconds: 500));
      final event = await recovery;

      expect(event.kind, PlaybackRecoveryEventKind.staleEventIgnored);
      expect(executor.calls, isEmpty);
    });

    test('premature completion schedules current-track retry', () {
      final track = _track('premature-current');

      final event = coordinator.onPrematureCompletion(
        track: track,
        position: const Duration(minutes: 4),
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.retryScheduled);
      expect(coordinator.recoveryTrack?.sourceId, 'premature-current');
      expect(coordinator.recoveryPosition, const Duration(minutes: 4));
    });

    test('reset returns clear retry state event', () {
      final track = _track('reset-track');
      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 9),
        mode: PlayMode.queue,
      );

      final event = coordinator.reset();

      expect(event.kind, PlaybackRecoveryEventKind.retrySucceeded);
      expect(event.state.isNetworkError, isFalse);
      expect(event.state.isRetrying, isFalse);
      expect(event.state.retryAttempt, 0);
      expect(event.state.nextRetryAt, isNull);
      expect(coordinator.recoveryTrack, isNull);
      expect(coordinator.recoveryPosition, isNull);
      expect(timerFactory.timers.single.canceled, isTrue);
    });

    test('network recovered can use default stabilization delay', () async {
      final event = await coordinator.onNetworkRecovered(
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.staleEventIgnored);
      expect(executor.calls, isEmpty);
      expect(timerFactory.delayCompleters, isEmpty);
    });

    test('nonretryable failure exposes original error', () async {
      final track = _track('nonretryable-failure');
      final error = StateError('decoder failed');
      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 5),
        mode: PlayMode.queue,
      );
      executor.nextResult = PlaybackSessionResult.failed(
        requestId: 13,
        error: error,
        stackTrace: StackTrace.current,
      );

      final event = await coordinator.retryManually(
        fallbackTrack: null,
        fallbackPosition: Duration.zero,
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.recoveryFailedNonRetryable);
      expect(event.error, same(error));
      expect(event.result?.error, same(error));
    });

    test('retry exhausted does not leave duplicate wait markers active',
        () async {
      final track = _track('exhausted-duplicate-marker');
      final retryableError = StateError('retryable network failure');
      final events = <PlaybackRecoveryEvent>[];
      coordinator.dispose();
      coordinator = PlaybackRecoveryCoordinator(
        retryExecutor: executor,
        timerFactory: timerFactory.create,
        delay: timerFactory.delay,
        isRetryableError: (error) => identical(error, retryableError),
        onRecoveryEvent: events.add,
      );
      executor.nextResult = PlaybackSessionResult.failed(
        requestId: 40,
        error: retryableError,
        stackTrace: StackTrace.current,
      );
      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 5),
        mode: PlayMode.queue,
      );

      for (var i = 0; i < NetworkRetryConfig.maxRetries; i++) {
        timerFactory.timers.last.fire();
        await pumpEventQueue();
      }
      expect(events.last.kind, PlaybackRecoveryEventKind.retryExhausted);

      final event = coordinator.onBackendNetworkError(
        track: track,
        position: const Duration(seconds: 8),
        isActiveRetryHandoff: false,
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.retryExhausted);
    });

    test('scheduled retry success notifies listener and clears retry state',
        () async {
      final track = _track('scheduled-success');
      final received = Completer<PlaybackRecoveryEvent>();
      coordinator.dispose();
      coordinator = PlaybackRecoveryCoordinator(
        retryExecutor: executor,
        timerFactory: timerFactory.create,
        delay: timerFactory.delay,
        onRecoveryEvent: (event) {
          if (event.kind == PlaybackRecoveryEventKind.retrySucceeded &&
              !received.isCompleted) {
            received.complete(event);
          }
        },
      );
      executor.nextResult = PlaybackSessionResult.completed(
        requestId: 21,
        track: track,
        attemptedUrl: 'https://example.com/scheduled-success.m4a',
        streamResult: null,
      );

      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 23),
        mode: PlayMode.queue,
      );
      timerFactory.timers.single.fire();
      final event = await received.future;

      expect(event.kind, PlaybackRecoveryEventKind.retrySucceeded);
      expect(event.state.isNetworkError, isFalse);
      expect(event.state.isRetrying, isFalse);
      expect(coordinator.recoveryTrack, isNull);
      expect(coordinator.recoveryPosition, isNull);
      expect(executor.calls.single.track.sourceId, 'scheduled-success');
    });

    test('scheduled retry retryable failure notifies rescheduled retry',
        () async {
      final track = _track('scheduled-retryable');
      final retryableError = StateError('network retryable');
      final received = Completer<PlaybackRecoveryEvent>();
      coordinator.dispose();
      coordinator = PlaybackRecoveryCoordinator(
        retryExecutor: executor,
        timerFactory: timerFactory.create,
        delay: timerFactory.delay,
        isRetryableError: (error) => identical(error, retryableError),
        onRecoveryEvent: (event) {
          if (event.kind == PlaybackRecoveryEventKind.retryScheduled &&
              !received.isCompleted) {
            received.complete(event);
          }
        },
      );
      executor.nextResult = PlaybackSessionResult.failed(
        requestId: 22,
        error: retryableError,
        stackTrace: StackTrace.current,
      );

      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 31),
        mode: PlayMode.queue,
      );
      timerFactory.timers.single.fire();
      final event = await received.future;

      expect(event.kind, PlaybackRecoveryEventKind.retryScheduled);
      expect(event.state.isNetworkError, isTrue);
      expect(event.state.isRetrying, isTrue);
      expect(event.error, same(retryableError));
      expect(timerFactory.timers, hasLength(2));
      expect(coordinator.recoveryPosition, const Duration(seconds: 31));
    });

    test('scheduled retry nonretryable exception notifies failure event',
        () async {
      final track = _track('scheduled-exception');
      final error = StateError('fatal retry exception');
      final received = Completer<PlaybackRecoveryEvent>();
      coordinator.dispose();
      coordinator = PlaybackRecoveryCoordinator(
        retryExecutor: executor,
        timerFactory: timerFactory.create,
        delay: timerFactory.delay,
        onRecoveryEvent: (event) {
          if (event.kind ==
                  PlaybackRecoveryEventKind.recoveryFailedNonRetryable &&
              !received.isCompleted) {
            received.complete(event);
          }
        },
      );
      executor.nextThrow = error;

      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 41),
        mode: PlayMode.queue,
      );
      timerFactory.timers.single.fire();
      final event = await received.future;

      expect(event.kind, PlaybackRecoveryEventKind.recoveryFailedNonRetryable);
      expect(event.error, same(error));
      expect(event.result, isNull);
      expect(coordinator.recoveryTrack, isNull);
    });

    test('terminal media-open retry failure exposes message', () async {
      final track = _track('terminal-media-open');
      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 6),
        mode: PlayMode.queue,
      );
      executor.nextResult = PlaybackSessionResult.terminalMediaOpenError(
        requestId: 23,
        track: track,
        message: 'Failed to open stream URL',
      );

      final event = await coordinator.retryManually(
        fallbackTrack: null,
        fallbackPosition: Duration.zero,
        mode: PlayMode.queue,
      );

      expect(event.kind, PlaybackRecoveryEventKind.recoveryFailedNonRetryable);
      expect(event.error, 'Failed to open stream URL');
      expect(event.result?.track, same(track));
      expect(event.result?.message, 'Failed to open stream URL');
    });

    test('stale timer after reset does not notify listener', () async {
      final track = _track('stale-timer');
      final events = <PlaybackRecoveryEvent>[];
      coordinator.dispose();
      coordinator = PlaybackRecoveryCoordinator(
        retryExecutor: executor,
        timerFactory: timerFactory.create,
        delay: timerFactory.delay,
        onRecoveryEvent: events.add,
      );

      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 11),
        mode: PlayMode.queue,
      );
      coordinator.reset();
      timerFactory.timers.single.fire();
      await pumpEventQueue();

      expect(events, isEmpty);
      expect(executor.calls, isEmpty);
    });
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId;
}

class _FakeRetryExecutor implements PlaybackRetryExecutor {
  final calls = <PlaybackRetryCall>[];
  PlaybackSessionResult? nextResult;
  Completer<PlaybackSessionResult>? nextCompleter;
  Object? nextThrow;

  @override
  Future<PlaybackSessionResult> retryPlayback({
    required Track track,
    required Duration? position,
    required PlayMode mode,
  }) async {
    calls.add(PlaybackRetryCall(track: track, position: position, mode: mode));
    final error = nextThrow;
    if (error != null) throw error;
    final completer = nextCompleter;
    if (completer != null) {
      nextCompleter = null;
      return completer.future;
    }
    return nextResult ?? PlaybackSessionResult.superseded(requestId: 12);
  }
}

class _ManualRetryTimerFactory {
  final timers = <_ManualRetryTimer>[];
  final delayCompleters = <Duration, Completer<void>>{};

  PlaybackRecoveryTimer create(Duration delay, void Function() callback) {
    final timer = _ManualRetryTimer(delay, callback);
    timers.add(timer);
    return timer;
  }

  Future<void> delay(Duration delay) {
    return (delayCompleters[delay] ??= Completer<void>()).future;
  }

  void completeDelay(Duration delay) {
    final completer = delayCompleters[delay];
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _ManualRetryTimer implements PlaybackRecoveryTimer {
  _ManualRetryTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  var canceled = false;

  void fire() {
    if (!canceled) callback();
  }

  @override
  void cancel() {
    canceled = true;
  }
}
