# Playback Request Session Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deepen FMP audio playback request and recovery ownership by moving request lifecycle state into `PlaybackRequestSession` and retry/recovery policy into `PlaybackRecoveryCoordinator`.

**Architecture:** `AudioController` remains the product-facing owner for `PlayerState`, queue/mix/temporary mode, source-error UI, history, lyrics, and notification/SMTC coordination. `PlaybackRequestSession` owns request tokens, supersession, backend stop/handoff, queue restore, fallback handoff, and media-open pending recovery. `PlaybackRecoveryCoordinator` owns retry generation, retry timer state, manual retry, network recovered handling, and premature-completion retry decisions.

**Tech Stack:** Dart, Flutter, Riverpod `StateNotifier`, FMP audio abstractions, Flutter test.

---

## File Structure

- Create: `lib/services/audio/playback_request_session.dart`
  - Owns request token creation, active request handle, supersession, play lock, backend stop before handoff, normal handoff, queue restore handoff, fallback handoff, and media-open pending recovery.
- Create: `lib/services/audio/playback_recovery_coordinator.dart`
  - Owns retry generation, retry attempt state, retry timers, saved recovery track/position, manual retry, network recovered handling, and premature completion recovery.
- Modify: `lib/services/audio/playback_request_executor.dart`
  - Either remove after migration or keep as a private-style helper used only by `PlaybackRequestSession`; it must no longer expose `requestId` and `isSuperseded` to `AudioController`.
- Modify: `lib/services/audio/audio_provider.dart`
  - Replace raw request/retry fields with the two new modules. Keep player state, mode, queue, Mix, source-error UI, history, lyrics, notification/SMTC, and radio filtering in the controller.
- Modify: `lib/services/audio/AGENTS.md`
  - Update ownership guidance for `PlaybackRequestSession` and `PlaybackRecoveryCoordinator`.
- Create: `test/services/audio/playback_request_session_test.dart`
  - Focused tests for supersession, stop/handoff, fallback, queue restore, and media-open recovery.
- Create: `test/services/audio/playback_recovery_coordinator_test.dart`
  - Focused tests for retry scheduling, generation guards, manual retry, network recovery, and premature completion.
- Modify: `test/services/audio/playback_request_executor_test.dart`
  - Migrate behavior that belongs to session tests, or reduce to helper-only coverage if the executor remains.
- Modify as needed: `test/services/audio/audio_controller_phase1_test.dart`
  - Keep as controller integration coverage for request behavior.
- Modify as needed: `test/services/audio/audio_auth_retry_phase4_test.dart`
  - Keep as controller integration coverage for recovery behavior.
- Modify as needed: `test/services/audio/audio_controller_mix_boundary_test.dart`
  - Keep Mix behavior coverage.

## Task 1: Add Playback Request Session Types

**Files:**
- Create: `lib/services/audio/playback_request_session.dart`
- Create: `test/services/audio/playback_request_session_test.dart`

- [ ] **Step 1: Write constructor and result type tests**

Create `test/services/audio/playback_request_session_test.dart` with these initial tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/playback_request_session.dart';

void main() {
  group('PlaybackSessionResult', () {
    test('completed result exposes track and stream metadata', () {
      final track = Track()
        ..sourceId = 'session-track'
        ..sourceType = SourceType.youtube
        ..title = 'Session Track';
      final streamResult = AudioStreamResult(
        url: 'https://example.com/session-track.m4a',
        container: 'm4a',
        codec: 'aac',
        streamType: StreamType.audioOnly,
      );

      final result = PlaybackSessionResult.completed(
        requestId: 7,
        track: track,
        attemptedUrl: 'https://example.com/session-track.m4a',
        streamResult: streamResult,
      );

      expect(result.kind, PlaybackSessionResultKind.completed);
      expect(result.requestId, 7);
      expect(result.track, same(track));
      expect(result.attemptedUrl, 'https://example.com/session-track.m4a');
      expect(result.streamResult, same(streamResult));
      expect(result.isCompleted, isTrue);
      expect(result.isSuperseded, isFalse);
    });

    test('superseded result is typed and carries no stale track', () {
      final result = PlaybackSessionResult.superseded(requestId: 8);

      expect(result.kind, PlaybackSessionResultKind.superseded);
      expect(result.requestId, 8);
      expect(result.track, isNull);
      expect(result.error, isNull);
      expect(result.isCompleted, isFalse);
      expect(result.isSuperseded, isTrue);
    });

    test('terminal media-open error carries visible message', () {
      final result = PlaybackSessionResult.terminalMediaOpenError(
        requestId: 9,
        message: 'Cannot play Track A',
      );

      expect(result.kind, PlaybackSessionResultKind.terminalMediaOpenError);
      expect(result.requestId, 9);
      expect(result.message, 'Cannot play Track A');
      expect(result.isTerminalMediaOpenError, isTrue);
    });

    test('failed result preserves original error and stack trace', () {
      final error = StateError('handoff failed');
      final stackTrace = StackTrace.current;
      final result = PlaybackSessionResult.failed(
        requestId: 10,
        error: error,
        stackTrace: stackTrace,
      );

      expect(result.kind, PlaybackSessionResultKind.failed);
      expect(result.requestId, 10);
      expect(result.error, same(error));
      expect(result.stackTrace, same(stackTrace));
      expect(result.isFailed, isTrue);
    });
  });

  group('PlaybackSessionCommand', () {
    test('normal play command keeps mode and side-effect flags explicit', () {
      final track = Track()
        ..sourceId = 'cmd-track'
        ..sourceType = SourceType.youtube
        ..title = 'Command Track';

      final command = PlaybackSessionCommand(
        track: track,
        mode: PlayMode.temporary,
        persist: false,
        recordHistory: false,
        prefetchNext: false,
        positionBeforeLoad: const Duration(seconds: 12),
        onPlaybackStarting: () async {},
      );

      expect(command.track, same(track));
      expect(command.mode, PlayMode.temporary);
      expect(command.persist, isFalse);
      expect(command.recordHistory, isFalse);
      expect(command.prefetchNext, isFalse);
      expect(command.positionBeforeLoad, const Duration(seconds: 12));
      expect(command.onPlaybackStarting, isNotNull);
    });

    test('restore command keeps seek and resume policy explicit', () {
      final track = Track()
        ..sourceId = 'restore-track'
        ..sourceType = SourceType.youtube
        ..title = 'Restore Track';

      final command = PlaybackRestoreCommand(
        track: track,
        mode: PlayMode.queue,
        position: const Duration(seconds: 42),
        shouldResume: true,
      );

      expect(command.track, same(track));
      expect(command.mode, PlayMode.queue);
      expect(command.position, const Duration(seconds: 42));
      expect(command.shouldResume, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

Expected: FAIL because `playback_request_session.dart` and its types do not exist.

- [ ] **Step 3: Add the session type definitions**

Create `lib/services/audio/playback_request_session.dart` with this content:

```dart
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
    required String message,
  }) {
    return PlaybackSessionResult._(
      requestId: requestId,
      kind: PlaybackSessionResultKind.terminalMediaOpenError,
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
    PlaybackSessionDelay? delay,
  })  : _audioService = audioService,
        _audioStreamManager = audioStreamManager,
        _getNextTrack = getNextTrack,
        _onLoadingStarted = onLoadingStarted,
        _onLoadingFinished = onLoadingFinished,
        _terminalMediaOpenMessage = terminalMediaOpenMessage,
        _delay = delay ?? Future<void>.delayed;

  final FmpAudioService _audioService;
  final PlaybackRequestStreamAccess _audioStreamManager;
  final Track? Function() _getNextTrack;
  final PlaybackSessionLoadingStarted _onLoadingStarted;
  final PlaybackSessionLoadingFinished _onLoadingFinished;
  final PlaybackSessionTerminalMessage _terminalMediaOpenMessage;
  final PlaybackSessionDelay _delay;

  int _requestId = 0;
  _SessionLock? _playLock;
  final Map<int, _PendingMediaOpenError> _pendingMediaOpenErrors = {};
  bool _isDisposed = false;

  int get activeRequestId => _requestId;
  bool get isInLoadingState => _playLock != null;

  void dispose() {
    _isDisposed = true;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = null;
    for (final pending in _pendingMediaOpenErrors.values) {
      if (!pending.recovered.isCompleted) {
        pending.recovered.complete(true);
      }
    }
    _pendingMediaOpenErrors.clear();
  }

  bool isSuperseded(int requestId) => requestId != _requestId;

  void cancelActive() {
    if (_isDisposed) return;
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
      if (execution == null) {
        await _waitForMediaOpenErrorRecovery(requestId);
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      if (!await _waitForMediaOpenErrorRecovery(requestId)) {
        result = PlaybackSessionResult.terminalMediaOpenError(
          requestId: requestId,
          message: _terminalMediaOpenMessage(command.track),
        );
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
      return result;
    } catch (error, stackTrace) {
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

  Future<PlaybackSessionResult> restore(
    PlaybackRestoreCommand command,
  ) async {
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
      if (execution == null) {
        await _waitForMediaOpenErrorRecovery(requestId);
        result = PlaybackSessionResult.superseded(requestId: requestId);
        return result;
      }
      if (!await _waitForMediaOpenErrorRecovery(requestId)) {
        result = PlaybackSessionResult.terminalMediaOpenError(
          requestId: requestId,
          message: _terminalMediaOpenMessage(command.track),
        );
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
      return result;
    } catch (error, stackTrace) {
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
    final requestId = _playLock?.requestId;
    _PendingMediaOpenError? pending;
    if (requestId != null) {
      if (_pendingMediaOpenErrors.containsKey(requestId)) {
        logDebug('Media open error already pending for request $requestId');
        return;
      }
      pending = _PendingMediaOpenError();
      _pendingMediaOpenErrors[requestId] = pending;
    }

    await _delay(const Duration(seconds: 2));
    if (_isDisposed) {
      _completeMediaOpenRecovery(pending, recovered: true);
      return;
    }

    final currentPosition = _audioService.position;
    final hasAdvanced =
        currentPosition - positionAtError > const Duration(milliseconds: 500);
    if (_audioService.isPlaying && hasAdvanced) {
      logDebug('Media open error recovered by backend: $error');
      _completeMediaOpenRecovery(pending, recovered: true);
      return;
    }

    logWarning('Media open error did not recover: $error');
    if (requestId != null && !isSuperseded(requestId)) {
      cancelActive();
    }
    try {
      await _audioService.stop();
    } catch (stopError) {
      logError('Failed to stop player after media open error', stopError);
    }
    pending?.terminalMessage = _terminalMediaOpenMessage(track);
    _completeMediaOpenRecovery(pending, recovered: false);
  }

  int _enterLoading() {
    final requestId = ++_requestId;
    _playLock?.completeIf(_playLock!.requestId);
    _playLock = _SessionLock(requestId);
    _onLoadingStarted(requestId);
    return requestId;
  }

  void _finishLoading(int requestId, PlaybackSessionResult result) {
    _playLock?.completeIf(requestId);
    if (_playLock?.requestId == requestId) {
      _playLock = null;
    }
    _onLoadingFinished(requestId, result);
  }

  Future<void> _stopForRequest(int requestId) async {
    if (isSuperseded(requestId)) return;
    await _audioService.stop();
  }

  Future<PlaybackRequestExecution?> _execute({
    required int requestId,
    required Track track,
    required bool persist,
    required bool prefetchNext,
  }) async {
    if (isSuperseded(requestId)) return null;

    final selection =
        await _audioStreamManager.selectPlayback(track, persist: persist);
    if (isSuperseded(requestId)) return null;

    try {
      await _playSelection(requestId, selection);
    } catch (error, stackTrace) {
      if (!isSuperseded(requestId)) {
        try {
          final fallbackSelection =
              await _audioStreamManager.selectFallbackPlayback(
            selection.track,
            failedUrl: selection.url,
          );
          if (fallbackSelection != null) {
            if (isSuperseded(requestId)) return null;
            await _playSelection(requestId, fallbackSelection);
            if (isSuperseded(requestId)) return null;
            _prefetchNextIfNeeded(prefetchNext);
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

    if (isSuperseded(requestId)) return null;
    _prefetchNextIfNeeded(prefetchNext);
    return PlaybackRequestExecution(
      track: selection.track,
      attemptedUrl: selection.url,
      streamResult: selection.streamResult,
    );
  }

  Future<PlaybackRequestExecution?> _executeQueueRestore({
    required int requestId,
    required Track track,
    required Duration position,
    required bool shouldResume,
  }) async {
    if (isSuperseded(requestId)) return null;

    final (trackWithUrl, localPath, streamResult) =
        await _audioStreamManager.ensureAudioStream(track, persist: true);
    if (isSuperseded(requestId)) return null;

    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw Exception('No audio URL available for: ${track.title}');
    }

    var attemptedUrl = url;
    if (localPath != null) {
      await _audioService.setFile(url, track: trackWithUrl);
    } else {
      final networkRequest =
          await _audioStreamManager.prepareNetworkPlayback(trackWithUrl, url);
      if (isSuperseded(requestId)) return null;
      attemptedUrl = networkRequest.url;
      await _audioService.setUrl(
        networkRequest.url,
        headers: networkRequest.headers,
        track: trackWithUrl,
      );
    }
    if (isSuperseded(requestId)) return null;

    if (position > Duration.zero) {
      await _audioService.seekTo(position);
      if (isSuperseded(requestId)) return null;
    }

    if (shouldResume) {
      await _audioService.play();
      if (isSuperseded(requestId)) return null;
    }

    return PlaybackRequestExecution(
      track: trackWithUrl,
      attemptedUrl: attemptedUrl,
      streamResult: streamResult,
    );
  }

  Future<void> _playSelection(
    int requestId,
    PlaybackSelection selection,
  ) async {
    if (selection.localPath != null) {
      await _audioService.playFile(selection.url, track: selection.track);
      return;
    }
    if (isSuperseded(requestId)) return;
    await _audioService.playUrl(
      selection.url,
      headers: selection.headers,
      track: selection.track,
    );
  }

  void _prefetchNextIfNeeded(bool prefetchNext) {
    if (!prefetchNext) return;
    final nextTrack = _getNextTrack();
    if (nextTrack != null) {
      unawaited(_audioStreamManager.prefetchTrack(nextTrack.copy()));
    }
  }

  Future<bool> _waitForMediaOpenErrorRecovery(int requestId) async {
    final pending = _pendingMediaOpenErrors[requestId];
    if (pending == null) return true;
    try {
      return pending.recovered.future;
    } finally {
      if (_pendingMediaOpenErrors[requestId] == pending) {
        _pendingMediaOpenErrors.remove(requestId);
      }
    }
  }

  void _completeMediaOpenRecovery(
    _PendingMediaOpenError? pending, {
    required bool recovered,
  }) {
    if (pending != null && !pending.recovered.isCompleted) {
      pending.recovered.complete(recovered);
    }
  }
}

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

class _SessionLock {
  _SessionLock(this.requestId) : completer = Completer<void>();

  final int requestId;
  final Completer<void> completer;

  void completeIf(int expectedRequestId) {
    if (requestId == expectedRequestId && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _PendingMediaOpenError {
  final recovered = Completer<bool>();
  String? terminalMessage;
}
```

- [ ] **Step 4: Run the new type tests**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

Expected: PASS for the result and command tests.

- [ ] **Step 5: Checkpoint**

Run:

```bash
git diff -- lib/services/audio/playback_request_session.dart test/services/audio/playback_request_session_test.dart
```

Expected: only the new session file and initial tests are changed.

Do not commit unless the user explicitly requested commits.

## Task 2: Move Normal And Restore Handoff Into Session

**Files:**
- Modify: `test/services/audio/playback_request_session_test.dart`
- Modify: `lib/services/audio/playback_request_session.dart`
- Modify: `lib/services/audio/audio_provider.dart`

- [ ] **Step 1: Add session handoff tests**

Append these tests inside `test/services/audio/playback_request_session_test.dart`:

```dart
  group('PlaybackRequestSession handoff', () {
    late FakeAudioService audioService;
    late _HarnessPlaybackRequestStreamAccess streamManager;
    late PlaybackRequestSession session;
    late List<int> loadingStarted;

    setUp(() {
      audioService = FakeAudioService();
      streamManager = _HarnessPlaybackRequestStreamAccess();
      loadingStarted = [];
      session = PlaybackRequestSession(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        onLoadingStarted: loadingStarted.add,
        onLoadingFinished: (_, __) {},
        terminalMediaOpenMessage: (track) => 'Cannot play ${track.title}',
        delay: (_) async {},
      );
    });

    tearDown(() {
      session.dispose();
    });

    test('start stops backend and plays selected stream', () async {
      final track = _track('session-start');

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(result.track?.sourceId, 'session-start');
      expect(result.attemptedUrl, 'https://example.com/session-start.m4a');
      expect(audioService.stopCallCount, 1);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/session-start.m4a');
      expect(loadingStarted, [1]);
    });

    test('start plays local selections with playFile', () async {
      final track = _track('local-session');
      streamManager.onSelectPlayback = (track, persist) async {
        return PlaybackSelection(
          track: track,
          url: '/music/local-session.m4a',
          localPath: '/music/local-session.m4a',
          headers: null,
          streamResult: null,
        );
      };

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(result.attemptedUrl, '/music/local-session.m4a');
      expect(audioService.playFileCalls.single.filePath,
          '/music/local-session.m4a');
      expect(audioService.playUrlCalls, isEmpty);
    });

    test('start uses manager fallback and preserves fallback metadata', () async {
      final track = _track('fallback-session');
      audioService.enqueuePlayUrlError(Exception('primary failed'));
      streamManager.onSelectFallbackPlayback = (track, failedUrl) async {
        expect(failedUrl, 'https://example.com/fallback-session.m4a');
        return PlaybackSelection(
          track: track,
          url: 'https://example.com/fallback-session-fallback.m3u8',
          localPath: null,
          headers: const {'X-Fallback': 'yes'},
          streamResult: AudioStreamResult(
            url: 'https://example.com/fallback-session-fallback.m3u8',
            container: 'm3u8',
            codec: 'aac',
            streamType: StreamType.muxed,
          ),
        );
      };

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(result.attemptedUrl,
          'https://example.com/fallback-session-fallback.m3u8');
      expect(result.streamResult?.streamType, StreamType.muxed);
      expect(audioService.playUrlCalls.map((call) => call.url), [
        'https://example.com/fallback-session.m4a',
        'https://example.com/fallback-session-fallback.m3u8',
      ]);
    });

    test('start preserves original handoff error when fallback fails', () async {
      final track = _track('fallback-fails');
      final primaryError = Exception('primary failed');
      audioService.enqueuePlayUrlError(primaryError);
      streamManager.onSelectFallbackPlayback = (_, __) async {
        throw Exception('fallback failed');
      };

      final result = await session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );

      expect(result.isFailed, isTrue);
      expect(result.error, same(primaryError));
    });

    test('restore prepares URL, seeks, and resumes when requested', () async {
      final track = _track('restore-session');

      final result = await session.restore(
        PlaybackRestoreCommand(
          track: track,
          mode: PlayMode.queue,
          position: const Duration(seconds: 35),
          shouldResume: true,
        ),
      );

      expect(result.isCompleted, isTrue);
      expect(audioService.stopCallCount, 1);
      expect(audioService.setUrlCalls.single.url,
          'https://example.com/restore-session.m4a');
      expect(audioService.seekCalls, [const Duration(seconds: 35)]);
      expect(audioService.isPlaying, isTrue);
    });

    test('superseded start does not stop or error newer request', () async {
      final firstTrack = _track('first-session');
      final secondTrack = _track('second-session');
      final firstGate = audioService.enqueuePendingPlayUrl();
      final secondGate = audioService.enqueuePendingPlayUrl();

      final first = session.start(
        PlaybackSessionCommand(
          track: firstTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      final second = session.start(
        PlaybackSessionCommand(
          track: secondTrack,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(2);

      firstGate.complete();
      expect((await first).isSuperseded, isTrue);

      expect(audioService.stopCallCount, 2);
      expect(audioService.playUrlCalls.map((call) => call.url), [
        'https://example.com/first-session.m4a',
        'https://example.com/second-session.m4a',
      ]);

      secondGate.complete();
      expect((await second).isCompleted, isTrue);
    });
  });
```

Add these imports at the top of the file:

```dart
import 'dart:async';

import 'package:fmp/services/audio/audio_stream_manager.dart';
import '../../support/fakes/fake_audio_service.dart';
```

Add these test helpers at the bottom of the file:

```dart
Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = sourceId;
}

class _HarnessPlaybackRequestStreamAccess
    implements PlaybackRequestStreamAccess {
  Future<PlaybackSelection> Function(Track track, bool persist)?
      onSelectPlayback;
  Future<PlaybackSelection?> Function(Track track, String? failedUrl)?
      onSelectFallbackPlayback;
  Future<PlaybackNetworkRequest> Function(Track track, String url)?
      onPrepareNetworkPlayback;
  Future<(Track, String?, AudioStreamResult?)> Function(
    Track track,
    bool persist,
  )? onEnsureAudioStream;

  @override
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  }) async {
    final custom = await onSelectPlayback?.call(track, persist);
    if (custom != null) return custom;
    return PlaybackSelection(
      track: track
        ..audioUrl = 'https://example.com/${track.sourceId}.m4a',
      url: 'https://example.com/${track.sourceId}.m4a',
      localPath: null,
      headers: const {'Referer': 'https://example.com'},
      streamResult: AudioStreamResult(
        url: 'https://example.com/${track.sourceId}.m4a',
        container: 'm4a',
        codec: 'aac',
        streamType: StreamType.audioOnly,
      ),
    );
  }

  @override
  Future<PlaybackSelection?> selectFallbackPlayback(
    Track track, {
    String? failedUrl,
  }) {
    return onSelectFallbackPlayback?.call(track, failedUrl) ??
        Future.value(null);
  }

  @override
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    final custom = await onEnsureAudioStream?.call(track, persist);
    if (custom != null) return custom;
    track.audioUrl = 'https://example.com/${track.sourceId}.m4a';
    return (
      track,
      null,
      AudioStreamResult(
        url: track.audioUrl!,
        container: 'm4a',
        codec: 'aac',
        streamType: StreamType.audioOnly,
      ),
    );
  }

  @override
  Future<Map<String, String>?> getPlaybackHeaders(
    Track track, {
    String? requestUrl,
  }) async {
    return const {'Referer': 'https://example.com'};
  }

  @override
  Future<PlaybackNetworkRequest> prepareNetworkPlayback(
    Track track,
    String url,
  ) async {
    final custom = await onPrepareNetworkPlayback?.call(track, url);
    if (custom != null) return custom;
    return PlaybackNetworkRequest(
      url: url,
      headers: const {'Referer': 'https://example.com'},
    );
  }

  @override
  Future<void> prefetchTrack(Track track) async {}
}
```

- [ ] **Step 2: Run session tests**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

Expected: PASS for command/result and handoff behavior.

- [ ] **Step 3: Replace `PlaybackRequestExecutor` construction in controller**

In `lib/services/audio/audio_provider.dart`, replace the field:

```dart
late final PlaybackRequestExecutor _playbackRequestExecutor;
```

with:

```dart
late final PlaybackRequestSession _playbackRequestSession;
```

Add import:

```dart
import 'playback_request_session.dart';
```

Remove import when unused:

```dart
import 'playback_request_executor.dart';
```

Replace constructor initialization:

```dart
_playbackRequestExecutor = PlaybackRequestExecutor(
  audioService: _audioService,
  audioStreamManager: _audioStreamManager,
  getNextTrack: _nextTrackForPrefetch,
  isSuperseded: _isSuperseded,
);
```

with:

```dart
_playbackRequestSession = PlaybackRequestSession(
  audioService: _audioService,
  audioStreamManager: _audioStreamManager,
  getNextTrack: _nextTrackForPrefetch,
  onLoadingStarted: (requestId) {
    _startSessionLoadingState(requestId);
  },
  onLoadingFinished: (requestId, result) {
    if (_context.activeRequestId == requestId && result.isSuperseded) {
      state = state.copyWith(isLoading: false);
      _context = _context.copyWith(activeRequestId: 0);
      _publishMobileAudioHandlerCurrentPlaybackState();
    }
  },
  terminalMediaOpenMessage: (track) =>
      t.audio.playbackFailedTrack(title: track.title),
);
```

- [ ] **Step 4: Split controller loading helpers to accept session IDs**

Replace `_enterLoadingState()` with a helper that no longer increments a
controller-local request counter:

```dart
void _startSessionLoadingState(int requestId) {
  _terminalMediaOpenErrorTrackKey = null;
  state = state.copyWith(
    isLoading: true,
    position: Duration.zero,
    bufferedPosition: Duration.zero,
    error: null,
    clearDuration: true,
    replaceCurrentStreamMetadata: true,
  );
  _context = _context.copyWith(activeRequestId: requestId);
  _publishMobileAudioHandlerLoadingState();
}

bool _isSessionSuperseded(int requestId) {
  return _playbackRequestSession.isSuperseded(requestId);
}
```

Update `_exitLoadingState` so its guard uses `_isSessionSuperseded`:

```dart
void _exitLoadingState(
  int requestId,
  Track? trackWithUrl, {
  PlayMode? mode,
  bool recordHistory = false,
  AudioStreamResult? streamResult,
}) {
  if (_isSessionSuperseded(requestId)) return;

  state = state.copyWith(
    isLoading: false,
    currentBitrate: streamResult?.bitrate,
    currentContainer: streamResult?.container,
    currentCodec: streamResult?.codec,
    currentStreamType: streamResult?.streamType,
    replaceCurrentStreamMetadata: true,
  );
  _context = _context.copyWith(activeRequestId: 0, mode: mode);

  if (trackWithUrl != null) {
    _updatePlayingTrack(trackWithUrl, recordHistory: recordHistory);
  }
}
```

Update `_resetLoadingState` and `_resetSourceErrorLoadingState`:

```dart
void _resetLoadingState({int? requestId}) {
  if (_isDisposed) return;
  if (requestId != null && _isSessionSuperseded(requestId)) return;
  state = state.copyWith(isLoading: false);
  _context = _context.copyWith(activeRequestId: 0);
  _publishMobileAudioHandlerCurrentPlaybackState();
}

void _resetSourceErrorLoadingState(int requestId) {
  if (_isDisposed || _isSessionSuperseded(requestId)) return;
  _context = _context.copyWith(activeRequestId: 0);
  _publishMobileAudioHandlerCurrentPlaybackState();
}
```

Remove the controller `_playLock` field, `_LockWithId` class, `_playRequestId`
field, `_enterLoadingState()`, `_supersedeInFlightPlaybackIntent()`,
`_isSuperseded(int requestId)`, and `_stopAudioForRequest(int requestId)`.

Replace callers of `_supersedeInFlightPlaybackIntent()` with:

```dart
_playbackRequestSession.cancelActive();
_context = _context.copyWith(activeRequestId: 0);
```

Replace request guards that still need to check a session request id:

```dart
_isSuperseded(requestId)
```

with:

```dart
_isSessionSuperseded(requestId)
```

This is the transition point where `PlaybackRequestSession` becomes the only
owner of playback request IDs. Do not keep `_playRequestId` alive for playback
start, restore, or prepare paths.

- [ ] **Step 5: Route `_executePlayRequest` through session**

In `_executePlayRequest`, keep these existing UI preparation lines before
starting the request:

```dart
final positionBeforeLoad = state.position;
_updatePlayingTrack(track);
_updateQueueState();
```

Then replace manual play-lock, backend stop, media-open wait, and the
`_playbackRequestExecutor.execute` block with:

```dart
bool completedSuccessfully = false;
int? requestId;

try {
  final requestTrack = _createPlaybackRequestTrack(track);
  final result = await _playbackRequestSession.start(
    PlaybackSessionCommand(
      track: requestTrack,
      mode: mode,
      persist: persist,
      recordHistory: recordHistory,
      prefetchNext: prefetchNext,
      positionBeforeLoad: positionBeforeLoad,
      onPlaybackStarting: onPlaybackStarting,
    ),
  );
  requestId = result.requestId;
  logDebug(
      '_executePlayRequest session finished for: ${track.title} (requestId: $requestId, mode: $mode, result: ${result.kind})');

  if (result.isSuperseded) return;
  if (result.isTerminalMediaOpenError) {
    state = state.copyWith(
      error: result.message,
      isLoading: false,
      isPlaying: false,
    );
    return;
  }
  if (result.isFailed) {
    final error = result.error!;
    final stackTrace = result.stackTrace ?? StackTrace.current;
    Error.throwWithStackTrace(error, stackTrace);
  }

  final trackWithUrl = result.track!;
  final streamResult = result.streamResult;
  _replaceQueueTrackIfCurrent(trackWithUrl);
  _exitLoadingState(
    requestId,
    trackWithUrl,
    mode: mode,
    recordHistory: recordHistory,
    streamResult: streamResult,
  );
  completedSuccessfully = true;
  _updateQueueState();

  if (recordHistory) {
    unawaited(_tryAutoMatchLyrics(track));
  }
  _triggerMixLoadMoreIfNearQueueEnd(mode);
  logDebug('_executePlayRequest completed successfully for: ${track.title}');
}
```

Update the existing `on SourceApiException`, generic `catch`, and `finally`
blocks so they use `requestId` only after the session result assigns it. The
catch blocks should no longer call `_stopAudioForRequest`; the session already
stopped the backend before handoff and returns failed results for handoff
failures. For source errors and retryable failures, use
`_resetLoadingState(requestId: requestId)` only when `requestId != null`; when
`requestId == null`, the failure happened before the session entered loading and
there is no loading state to reset. Use
`_scheduleRetryForSessionRequest(requestId, track, positionBeforeLoad)` only
when `requestId != null`, with `_isSessionSuperseded(requestId)` guards.

Add this helper:

```dart
void _scheduleRetryForSessionRequest(
  int requestId,
  Track track,
  Duration? position,
) {
  if (_isSessionSuperseded(requestId)) return;
  _scheduleRetry(track, position);
}
```

- [ ] **Step 6: Route queue restore through session**

In `_restoreQueuePlayback` and `_prepareCurrentTrack`, remove the initial
`final requestId = _enterLoadingState();` call. Keep the queue selection,
`_updatePlayingTrack(track)`, `_updateQueueState()`, and restore-position
calculation before calling the session. Session `onLoadingStarted` will call
`_startSessionLoadingState(requestId)` with the real request id.

Replace calls to:

```dart
final execution = await _playbackRequestExecutor.executeQueueRestore(
  requestId: requestId,
  track: requestTrack,
  position: restorePosition,
  shouldResume: restorePlan.savedWasPlaying,
);
```

with:

```dart
final result = await _playbackRequestSession.restore(
  PlaybackRestoreCommand(
    track: requestTrack,
    mode: targetMode,
    position: restorePosition,
    shouldResume: restorePlan.savedWasPlaying,
  ),
);
final requestId = result.requestId;
if (result.isSuperseded) return;
if (result.isTerminalMediaOpenError) {
  state = state.copyWith(
    error: result.message,
    isLoading: false,
    isPlaying: false,
  );
  return;
}
if (result.isFailed) {
  final error = result.error!;
  final stackTrace = result.stackTrace ?? StackTrace.current;
  Error.throwWithStackTrace(error, stackTrace);
}
final executionTrack = result.track!;
_replaceQueueTrackIfCurrent(executionTrack);
_exitLoadingState(
  requestId,
  executionTrack,
  mode: targetMode,
  streamResult: result.streamResult,
);
```

Apply the same pattern to other queue restore / prepare-resume paths that call
`executeQueueRestore`. Update catch/finally blocks to use `int? requestId` and
only call `_resetLoadingState(requestId: requestId)` after the session assigns a
request id.

- [ ] **Step 7: Run session and controller request tests**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS. If failures show mismatched request IDs, fix the session
callback bridge in this task; do not reintroduce controller-owned request IDs.

- [ ] **Step 8: Checkpoint**

Run:

```bash
git diff -- lib/services/audio/audio_provider.dart lib/services/audio/playback_request_session.dart test/services/audio/playback_request_session_test.dart
```

Expected: normal and restore handoff go through `PlaybackRequestSession`, with
controller source-error handling still intact and no `_playRequestId` /
`_LockWithId` usage remaining in `audio_provider.dart`.

Do not commit unless the user explicitly requested commits.

## Task 3: Move Media-Open Recovery Into Session

**Files:**
- Modify: `test/services/audio/playback_request_session_test.dart`
- Modify: `lib/services/audio/playback_request_session.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Modify as needed: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Add media-open session tests**

Append these tests inside the `PlaybackRequestSession handoff` group:

```dart
    test('media-open error recovers when backend advances', () async {
      final track = _track('media-open-recovers');
      final playGate = audioService.enqueuePendingPlayUrl();

      final play = session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      final mediaOpen = session.onMediaOpenError(
        error: 'Failed to open https://example.com/media-open-recovers.m4a.',
        track: track,
        positionAtError: Duration.zero,
      );
      audioService.setPlayingValue(true);
      audioService.setPositionValue(const Duration(seconds: 2));
      await mediaOpen;

      playGate.complete();
      final result = await play;
      expect(result.isCompleted, isTrue);
      expect(audioService.stopCallCount, 1);
    });

    test('media-open error becomes terminal when backend does not advance',
        () async {
      final track = _track('media-open-terminal');
      final playGate = audioService.enqueuePendingPlayUrl();

      final play = session.start(
        PlaybackSessionCommand(
          track: track,
          mode: PlayMode.queue,
          positionBeforeLoad: Duration.zero,
        ),
      );
      await audioService.waitForPlayUrlCallCount(1);

      await session.onMediaOpenError(
        error: 'Failed to open https://example.com/media-open-terminal.m4a.',
        track: track,
        positionAtError: Duration.zero,
      );

      playGate.complete();
      final result = await play;
      expect(result.isTerminalMediaOpenError, isTrue);
      expect(result.message, 'Cannot play media-open-terminal');
      expect(audioService.stopCallCount, 2);
    });
```

- [ ] **Step 2: Run media-open session tests**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart --plain-name media-open
```

Expected: PASS because Task 1 already added session media-open handling. If it
fails, fix `PlaybackRequestSession.onMediaOpenError` only; do not reintroduce a
controller-owned pending map.

- [ ] **Step 3: Route controller media-open errors to session**

In `_onAudioError`, replace the `_PendingMediaOpenError` block:

```dart
final requestId =
    _context.activeRequestId > 0 ? _context.activeRequestId : null;
_PendingMediaOpenError? pending;
if (requestId != null) {
  if (_pendingMediaOpenErrors.containsKey(requestId)) {
    logDebug(
        'Media open error already pending for request $requestId');
    return;
  }
  pending = _PendingMediaOpenError();
  _pendingMediaOpenErrors[requestId] = pending;
}
unawaited(_handleMediaOpenErrorIfStillFailed(
  error: error,
  track: track,
  positionAtError: state.position,
  requestId: requestId,
  pending: pending,
));
return;
```

with:

```dart
unawaited(_playbackRequestSession.onMediaOpenError(
  error: error,
  track: track,
  positionAtError: state.position,
));
return;
```

- [ ] **Step 4: Remove controller media-open internals**

Delete these members from `AudioController`:

```dart
final Map<int, _PendingMediaOpenError> _pendingMediaOpenErrors = {};
String? _terminalMediaOpenErrorTrackKey;
```

Delete `_PendingMediaOpenError`, `_handleMediaOpenErrorIfStillFailed`,
`_waitForMediaOpenErrorRecovery`, and `_completeMediaOpenRecovery` from
`audio_provider.dart`.

Remove this line from `_startSessionLoadingState`:

```dart
_terminalMediaOpenErrorTrackKey = null;
```

- [ ] **Step 5: Run media-open controller tests**

Run:

```bash
flutter test test/services/audio/audio_controller_phase1_test.dart --plain-name "media open"
```

Expected: PASS for terminal media-open and media-open cleanup tests.

- [ ] **Step 6: Run full request-focused tests**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 7: Checkpoint**

Run:

```bash
rg -n "_PendingMediaOpenError|_pendingMediaOpenErrors|_handleMediaOpenErrorIfStillFailed|_waitForMediaOpenErrorRecovery|_terminalMediaOpenErrorTrackKey" lib/services/audio/audio_provider.dart
```

Expected: no matches.

Do not commit unless the user explicitly requested commits.

## Task 4: Add Playback Recovery Coordinator

**Files:**
- Create: `lib/services/audio/playback_recovery_coordinator.dart`
- Create: `test/services/audio/playback_recovery_coordinator_test.dart`

- [ ] **Step 1: Write recovery coordinator tests**

Create `test/services/audio/playback_recovery_coordinator_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
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

    test('duplicate backend network error during same wait is suppressed', () {
      final track = _track('duplicate-error');
      coordinator.scheduleRetry(track: track, position: Duration.zero);

      final event = coordinator.onBackendNetworkError(
        track: track,
        position: const Duration(seconds: 3),
        isActiveRetryHandoff: false,
      );

      expect(event.kind, PlaybackRecoveryEventKind.staleEventIgnored);
      expect(timerFactory.timers, hasLength(1));
    });

    test('backend network error during retry handoff schedules fresh retry', () {
      final track = _track('handoff-error');
      coordinator.scheduleRetry(track: track, position: Duration.zero);

      final event = coordinator.onBackendNetworkError(
        track: track,
        position: const Duration(seconds: 7),
        isActiveRetryHandoff: true,
      );

      expect(event.kind, PlaybackRecoveryEventKind.retryScheduled);
      expect(coordinator.recoveryPosition, const Duration(seconds: 7));
      expect(timerFactory.timers, hasLength(2));
    });

    test('manual retry resets attempt and restores saved position', () async {
      final track = _track('manual-retry');
      coordinator.scheduleRetry(
        track: track,
        position: const Duration(seconds: 47),
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

    test('network recovered ignores stale track after generation changes',
        () async {
      final oldTrack = _track('old-track');
      final newTrack = _track('new-track');
      coordinator.scheduleRetry(
        track: oldTrack,
        position: const Duration(seconds: 12),
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
      );

      expect(event.kind, PlaybackRecoveryEventKind.retryScheduled);
      expect(coordinator.recoveryTrack?.sourceId, 'premature-current');
      expect(coordinator.recoveryPosition, const Duration(minutes: 4));
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

  @override
  Future<PlaybackSessionResult> retryPlayback({
    required Track track,
    required Duration? position,
    required PlayMode mode,
  }) async {
    calls.add(PlaybackRetryCall(track: track, position: position, mode: mode));
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
```

- [ ] **Step 2: Run recovery tests and verify they fail**

Run:

```bash
flutter test test/services/audio/playback_recovery_coordinator_test.dart
```

Expected: FAIL because `playback_recovery_coordinator.dart` does not exist.

- [ ] **Step 3: Add recovery coordinator implementation**

Create `lib/services/audio/playback_recovery_coordinator.dart`:

```dart
import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../data/models/track.dart';
import 'audio_playback_types.dart';
import 'playback_request_session.dart';

abstract class PlaybackRecoveryTimer {
  void cancel();
}

class _DartPlaybackRecoveryTimer implements PlaybackRecoveryTimer {
  _DartPlaybackRecoveryTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}

typedef PlaybackRecoveryTimerFactory = PlaybackRecoveryTimer Function(
  Duration delay,
  void Function() callback,
);

PlaybackRecoveryTimer _defaultTimerFactory(
  Duration delay,
  void Function() callback,
) {
  return _DartPlaybackRecoveryTimer(Timer(delay, callback));
}

abstract class PlaybackRetryExecutor {
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
  retryScheduled,
  retryExhausted,
  retrySucceeded,
  recoveryFailedNonRetryable,
  staleEventIgnored,
}

class PlaybackRecoveryState {
  const PlaybackRecoveryState({
    this.retryAttempt = 0,
    this.isNetworkError = false,
    this.isRetrying = false,
    this.nextRetryAt,
  });

  final int retryAttempt;
  final bool isNetworkError;
  final bool isRetrying;
  final DateTime? nextRetryAt;
}

class PlaybackRecoveryEvent {
  const PlaybackRecoveryEvent({
    required this.kind,
    required this.state,
    this.error,
    this.track,
    this.position,
  });

  factory PlaybackRecoveryEvent.stale() {
    return const PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.staleEventIgnored,
      state: PlaybackRecoveryState(),
    );
  }

  final PlaybackRecoveryEventKind kind;
  final PlaybackRecoveryState state;
  final Object? error;
  final Track? track;
  final Duration? position;
}

class PlaybackRecoveryCoordinator {
  PlaybackRecoveryCoordinator({
    required PlaybackRetryExecutor retryExecutor,
    PlaybackRecoveryTimerFactory? timerFactory,
  })  : _retryExecutor = retryExecutor,
        _timerFactory = timerFactory ?? _defaultTimerFactory;

  final PlaybackRetryExecutor _retryExecutor;
  final PlaybackRecoveryTimerFactory _timerFactory;

  PlaybackRecoveryTimer? _retryTimer;
  int _retryAttempt = 0;
  int _generation = 0;
  int? _scheduledRetryGeneration;
  String? _scheduledRetryTrackKey;
  Track? _trackToRecover;
  Duration? _positionToRecover;
  var _isDisposed = false;

  Track? get recoveryTrack => _trackToRecover;
  Duration? get recoveryPosition => _positionToRecover;

  void dispose() {
    _isDisposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  PlaybackRecoveryEvent scheduleRetry({
    required Track track,
    required Duration? position,
  }) {
    final generation = ++_generation;
    _scheduledRetryGeneration = generation;
    _scheduledRetryTrackKey = track.uniqueKey;
    _trackToRecover = track;
    if (position != null && position > Duration.zero) {
      _positionToRecover = position;
    }

    if (_retryAttempt >= NetworkRetryConfig.maxRetries) {
      return PlaybackRecoveryEvent(
        kind: PlaybackRecoveryEventKind.retryExhausted,
        state: PlaybackRecoveryState(
          retryAttempt: _retryAttempt,
          isNetworkError: true,
        ),
        track: track,
        position: _positionToRecover,
      );
    }

    final delay = NetworkRetryConfig.getRetryDelay(_retryAttempt);
    final nextRetryAt = DateTime.now().add(delay);
    _retryTimer?.cancel();
    _retryTimer = _timerFactory(delay, () {
      unawaited(_retryPlayback(track, _positionToRecover, generation));
    });

    return PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.retryScheduled,
      state: PlaybackRecoveryState(
        retryAttempt: _retryAttempt,
        isNetworkError: true,
        isRetrying: true,
        nextRetryAt: nextRetryAt,
      ),
      track: track,
      position: _positionToRecover,
    );
  }

  PlaybackRecoveryEvent onBackendNetworkError({
    required Track track,
    required Duration position,
    required bool isActiveRetryHandoff,
  }) {
    if (!isActiveRetryHandoff &&
        _scheduledRetryGeneration == _generation &&
        _scheduledRetryTrackKey == track.uniqueKey) {
      return PlaybackRecoveryEvent.stale();
    }
    return scheduleRetry(track: track, position: position);
  }

  Future<PlaybackRecoveryEvent> retryManually({
    required Track? fallbackTrack,
    required Duration fallbackPosition,
    required PlayMode mode,
  }) async {
    final track = _trackToRecover ?? fallbackTrack;
    if (track == null) return PlaybackRecoveryEvent.stale();
    final generation = ++_generation;
    _trackToRecover = track;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    final position = _positionToRecover ?? fallbackPosition;
    return _runRetry(track, position, mode, generation);
  }

  Future<PlaybackRecoveryEvent> onNetworkRecovered({
    required PlayMode mode,
    Duration stabilizationDelay = AppConstants.seekStabilizationDelay,
  }) async {
    final track = _trackToRecover;
    if (track == null) return PlaybackRecoveryEvent.stale();
    final position = _positionToRecover;
    final generation = ++_generation;
    _retryAttempt = 0;
    await Future<void>.delayed(stabilizationDelay);
    if (!_isGenerationCurrent(generation, track)) {
      return PlaybackRecoveryEvent.stale();
    }
    return _runRetry(track, position, mode, generation);
  }

  PlaybackRecoveryEvent onPrematureCompletion({
    required Track track,
    required Duration position,
  }) {
    return scheduleRetry(track: track, position: position);
  }

  void clearForNewPlayback(Track track) {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _trackToRecover = null;
    _positionToRecover = null;
    _scheduledRetryGeneration = null;
    _scheduledRetryTrackKey = null;
  }

  PlaybackRecoveryEvent reset() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _trackToRecover = null;
    _positionToRecover = null;
    _scheduledRetryGeneration = null;
    _scheduledRetryTrackKey = null;
    return const PlaybackRecoveryEvent(
      kind: PlaybackRecoveryEventKind.retrySucceeded,
      state: PlaybackRecoveryState(),
    );
  }

  bool _isGenerationCurrent(int generation, Track track) {
    return !_isDisposed &&
        generation == _generation &&
        _trackToRecover?.uniqueKey == track.uniqueKey;
  }

  Future<PlaybackRecoveryEvent> _retryPlayback(
    Track track,
    Duration? position,
    int generation,
  ) async {
    if (!_isGenerationCurrent(generation, track)) {
      return PlaybackRecoveryEvent.stale();
    }
    _retryAttempt++;
    return _runRetry(track, position, PlayMode.queue, generation);
  }

  Future<PlaybackRecoveryEvent> _runRetry(
    Track track,
    Duration? position,
    PlayMode mode,
    int generation,
  ) async {
    if (!_isGenerationCurrent(generation, track)) {
      return PlaybackRecoveryEvent.stale();
    }

    final result = await _retryExecutor.retryPlayback(
      track: track,
      position: position,
      mode: mode,
    );

    if (!_isGenerationCurrent(generation, track)) {
      return PlaybackRecoveryEvent.stale();
    }

    if (result.isCompleted) {
      _trackToRecover = null;
      _positionToRecover = null;
      _scheduledRetryGeneration = null;
      _scheduledRetryTrackKey = null;
      _retryAttempt = 0;
      return PlaybackRecoveryEvent(
        kind: PlaybackRecoveryEventKind.retrySucceeded,
        state: const PlaybackRecoveryState(),
        track: track,
        position: position,
      );
    }

    if (result.isFailed) {
      return PlaybackRecoveryEvent(
        kind: PlaybackRecoveryEventKind.recoveryFailedNonRetryable,
        state: const PlaybackRecoveryState(),
        error: result.error,
        track: track,
        position: position,
      );
    }

    return PlaybackRecoveryEvent.stale();
  }
}
```

- [ ] **Step 4: Run recovery coordinator tests**

Run:

```bash
flutter test test/services/audio/playback_recovery_coordinator_test.dart
```

Expected: PASS.

- [ ] **Step 5: Checkpoint**

Run:

```bash
git diff -- lib/services/audio/playback_recovery_coordinator.dart test/services/audio/playback_recovery_coordinator_test.dart
```

Expected: only the new coordinator and focused tests are changed.

Do not commit unless the user explicitly requested commits.

## Task 5: Route Controller Recovery Through Coordinator

**Files:**
- Modify: `lib/services/audio/audio_provider.dart`
- Modify as needed: `test/services/audio/audio_auth_retry_phase4_test.dart`
- Modify as needed: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Add recovery coordinator to controller**

In `audio_provider.dart`, add:

```dart
import 'playback_recovery_coordinator.dart';
```

Make `AudioController` implement the executor:

```dart
class AudioController extends StateNotifier<PlayerState>
    with Logging
    implements PlaybackRetryExecutor {
```

Add field:

```dart
late final PlaybackRecoveryCoordinator _recoveryCoordinator;
```

Initialize it in the constructor:

```dart
_recoveryCoordinator = PlaybackRecoveryCoordinator(
  retryExecutor: this,
);
```

Dispose it in `dispose()`:

```dart
_recoveryCoordinator.dispose();
```

- [ ] **Step 2: Implement `retryPlayback` on controller**

Add this method near the retry section:

```dart
@override
Future<PlaybackSessionResult> retryPlayback({
  required Track track,
  required Duration? position,
  required PlayMode mode,
}) async {
  final result = await _playbackRequestSession.start(
    PlaybackSessionCommand(
      track: _createPlaybackRequestTrack(track),
      mode: mode,
      persist: false,
      recordHistory: false,
      prefetchNext: true,
      positionBeforeLoad: position ?? Duration.zero,
    ),
  );
  if (result.isCompleted && position != null && position > Duration.zero) {
    await Future.delayed(AppConstants.seekStabilizationDelay);
    if (state.currentTrack?.uniqueKey == track.uniqueKey) {
      await seekTo(position);
    }
  }
  return result;
}
```

- [ ] **Step 3: Add helper to apply recovery state**

Add:

```dart
void _applyRecoveryEvent(PlaybackRecoveryEvent event) {
  switch (event.kind) {
    case PlaybackRecoveryEventKind.retryScheduled:
    case PlaybackRecoveryEventKind.retryExhausted:
    case PlaybackRecoveryEventKind.retrySucceeded:
      state = state.copyWith(
        isNetworkError: event.state.isNetworkError,
        isRetrying: event.state.isRetrying,
        retryAttempt: event.state.retryAttempt,
        nextRetryAt: event.state.nextRetryAt,
        clearNextRetryAt: event.state.nextRetryAt == null,
        error: event.kind == PlaybackRecoveryEventKind.retrySucceeded
            ? null
            : state.error,
      );
      return;
    case PlaybackRecoveryEventKind.recoveryFailedNonRetryable:
      state = state.copyWith(
        isNetworkError: false,
        isRetrying: false,
        retryAttempt: 0,
        nextRetryAt: null,
        clearNextRetryAt: true,
        error: event.error?.toString(),
      );
      return;
    case PlaybackRecoveryEventKind.staleEventIgnored:
      return;
  }
}
```

- [ ] **Step 4: Replace `_scheduleRetry` body**

Replace `_scheduleRetry(Track track, Duration? position)` with:

```dart
void _scheduleRetry(Track track, Duration? position) {
  final event = _recoveryCoordinator.scheduleRetry(
    track: track,
    position: position,
  );
  _applyRecoveryEvent(event);
}
```

- [ ] **Step 5: Replace `_resetRetryState` body**

Replace `_resetRetryState()` with:

```dart
void _resetRetryState() {
  final event = _recoveryCoordinator.reset();
  _applyRecoveryEvent(event);
}
```

Replace `_cancelRetryTimer()` with:

```dart
void _cancelRetryTimer() {
  _recoveryCoordinator.reset();
}
```

- [ ] **Step 6: Replace `retryManually` body**

Replace `retryManually()` with:

```dart
Future<void> retryManually() async {
  final track = _recoveryCoordinator.recoveryTrack ?? state.playingTrack;
  if (track == null) return;
  final currentMode = _context.isMix ? PlayMode.mix : PlayMode.queue;
  final event = await _recoveryCoordinator.retryManually(
    fallbackTrack: track,
    fallbackPosition: state.position,
    mode: currentMode,
  );
  _applyRecoveryEvent(event);
  if (event.kind == PlaybackRecoveryEventKind.recoveryFailedNonRetryable) {
    _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
  }
}
```

- [ ] **Step 7: Replace `_onNetworkRecovered` body**

Replace `_onNetworkRecovered()` with:

```dart
Future<void> _onNetworkRecovered() async {
  logInfo(
      '_onNetworkRecovered called, trackToRecover: ${_recoveryCoordinator.recoveryTrack?.title}');
  final currentMode = _context.isMix ? PlayMode.mix : PlayMode.queue;
  final event = await _recoveryCoordinator.onNetworkRecovered(
    mode: currentMode,
  );
  _applyRecoveryEvent(event);
  if (event.kind == PlaybackRecoveryEventKind.recoveryFailedNonRetryable) {
    final track = event.track;
    if (track != null) {
      _toastService.showError(t.audio.playbackFailedTrack(title: track.title));
    }
  }
}
```

- [ ] **Step 8: Route backend network error through coordinator**

In `_onAudioError`, replace the network-error scheduling block after
`positionBeforeStop` capture with:

```dart
_audioService.stop().then((_) {
  if (!_isAudioErrorRetryContextCurrent(track, retryRequestGeneration)) {
    return;
  }
  state = state.copyWith(isLoading: false, isPlaying: false);
  _resetLoadingState();
  final event = _recoveryCoordinator.onBackendNetworkError(
    track: track,
    position: positionBeforeStop,
    isActiveRetryHandoff: activeRetryRequestId != null,
  );
  _applyRecoveryEvent(event);
}).catchError((Object e, StackTrace stackTrace) {
  if (!_isAudioErrorRetryContextCurrent(track, retryRequestGeneration)) {
    return;
  }
  logError('Failed to stop player after error', e, stackTrace);
  state = state.copyWith(isLoading: false, isPlaying: false);
  _resetLoadingState();
  final event = _recoveryCoordinator.onBackendNetworkError(
    track: track,
    position: positionBeforeStop,
    isActiveRetryHandoff: activeRetryRequestId != null,
  );
  _applyRecoveryEvent(event);
});
```

- [ ] **Step 9: Route premature completion through coordinator**

Replace `_recoverFromPrematureCompletion(Duration position)` with:

```dart
void _recoverFromPrematureCompletion(Duration position) {
  final track = state.playingTrack ?? state.currentTrack;
  if (track == null) {
    logDebug('Premature completion ignored: no current track to recover');
    return;
  }

  state = state.copyWith(isLoading: false, isPlaying: false);
  _resetLoadingState();
  final event = _recoveryCoordinator.onPrematureCompletion(
    track: track,
    position: position,
  );
  _applyRecoveryEvent(event);
}
```

- [ ] **Step 10: Remove obsolete retry fields only after tests pass**

After the targeted tests in Step 11 pass, remove these fields:

```dart
Timer? _retryTimer;
int _retryAttempt = 0;
Track? _trackToRecoverAfterReconnect;
Duration? _positionToRecoverAfterReconnect;
int _retryGeneration = 0;
int? _scheduledRetryGeneration;
String? _scheduledRetryTrackKey;
```

Remove helpers that are fully replaced:

```dart
_isRetryGenerationCurrent
_isRetryTrackCurrent
_isDuplicateRetryingAudioError
_retryPlayback
```

Update `_isDuplicateRetryingAudioError(track)` call sites to use the
coordinator result from `onBackendNetworkError` rather than pre-checking in
controller.

- [ ] **Step 11: Run recovery integration tests**

Run:

```bash
flutter test test/services/audio/playback_recovery_coordinator_test.dart test/services/audio/audio_auth_retry_phase4_test.dart
```

Expected: PASS for focused coordinator tests and existing audio retry
integration tests.

- [ ] **Step 12: Run request integration tests**

Run:

```bash
flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 13: Checkpoint**

Run:

```bash
rg -n "_retryTimer|_retryAttempt|_trackToRecoverAfterReconnect|_positionToRecoverAfterReconnect|_retryGeneration|_scheduledRetryGeneration|_scheduledRetryTrackKey" lib/services/audio/audio_provider.dart
```

Expected: no matches.

Do not commit unless the user explicitly requested commits.

## Task 6: Remove Or Reduce PlaybackRequestExecutor

**Files:**
- Modify: `lib/services/audio/playback_request_executor.dart`
- Modify: `test/services/audio/playback_request_executor_test.dart`
- Modify: `lib/services/audio/playback_request_session.dart`

- [ ] **Step 1: Decide whether the executor still has a real seam**

Run:

```bash
rg -n "PlaybackRequestExecutor|PlaybackRequestExecution" lib test
```

Expected: matches only in `playback_request_executor.dart`,
`playback_request_session.dart`, and old tests.

If `PlaybackRequestExecutor` has only one adapter and only one caller after
Tasks 2-5, remove it. If keeping it shortens `PlaybackRequestSession`, make it
private to session ownership and remove request-id/supersession from its public
constructor.

- [ ] **Step 2A: If removing executor, delete the file and migrate tests**

Delete:

```text
lib/services/audio/playback_request_executor.dart
```

Move still-useful tests from `test/services/audio/playback_request_executor_test.dart`
into `test/services/audio/playback_request_session_test.dart`, using the
session test harness from Task 2.

Delete:

```text
test/services/audio/playback_request_executor_test.dart
```

- [ ] **Step 2B: If retaining executor, reduce interface**

If retaining the file, change the constructor to:

```dart
PlaybackRequestExecutor({
  required FmpAudioService audioService,
  required PlaybackRequestStreamAccess audioStreamManager,
  required Track? Function() getNextTrack,
})
```

Remove constructor field:

```dart
required bool Function(int requestId) isSuperseded,
```

Remove all request-id checks from the executor. The session must perform
supersession checks before and after calls into the executor.

- [ ] **Step 3: Run executor/session tests**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart
```

If retaining executor tests, run:

```bash
flutter test test/services/audio/playback_request_executor_test.dart
```

Expected: PASS for session tests, and executor tests only if the executor
remains.

- [ ] **Step 4: Checkpoint**

Run:

```bash
rg -n "isSuperseded|requestId" lib/services/audio/playback_request_executor.dart test/services/audio/playback_request_executor_test.dart
```

Expected: if the files still exist, no matches. If removed, `rg` reports files
do not exist.

Do not commit unless the user explicitly requested commits.

## Task 7: Documentation And Final Verification

**Files:**
- Modify: `lib/services/audio/AGENTS.md`
- Verify: all modified Dart/test files.

- [ ] **Step 1: Update audio ownership guidance**

In `lib/services/audio/AGENTS.md`, replace:

```text
- `AudioController` (`audio_provider.dart`) owns user-facing state, request
  supersession, temporary/mix/detached modes, notification/SMTC coordination,
  network retry, and source-error UI decisions.
- `PlaybackRequestExecutor` owns selecting and handing off a single playback
  request to the backend while preserving request IDs and fallback handoff
  errors.
```

with:

```text
- `AudioController` (`audio_provider.dart`) owns user-facing state,
  temporary/mix/detached modes, notification/SMTC coordination, queue-visible
  playback decisions, history/lyrics side effects, and source-error UI
  decisions.
- `PlaybackRequestSession` owns playback request tokens, supersession, active
  loading request state, backend stop/handoff, queue restore handoff, fallback
  handoff, and media-open pending recovery.
- `PlaybackRecoveryCoordinator` owns playback network retry generation,
  scheduled retry state, manual retry, network-recovered retry, and premature
  completion recovery.
```

Replace:

```text
Any method that fetches URLs outside `_executePlayRequest()` must:
1. Increment `_playRequestId` at start.
2. Check `_isSuperseded(requestId)` after each `await`.
3. Abort if superseded.
```

with:

```text
Any method that starts backend playback or fetches playback URLs outside
`PlaybackRequestSession` must either move into the session or use an explicit
session handle/cancellation check. Do not add new raw request-id counters in
`AudioController`.
```

- [ ] **Step 2: Run old-field search**

Run:

```bash
rg -n "_playRequestId|_LockWithId|_PendingMediaOpenError|_pendingMediaOpenErrors|_retryTimer|_retryAttempt|_retryGeneration|_trackToRecoverAfterReconnect|_positionToRecoverAfterReconnect" lib/services/audio/audio_provider.dart
```

Expected: no matches for request/retry internals removed from controller. If
`_playRequestId` remains temporarily for non-playback resume paths, document the
remaining owner in the final report and do not claim full cleanup.

- [ ] **Step 3: Run targeted audio tests**

Run:

```bash
flutter test test/services/audio/playback_request_session_test.dart test/services/audio/playback_recovery_coordinator_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full audio service tests**

Run:

```bash
flutter test test/services/audio
```

Expected: PASS.

- [ ] **Step 5: Run source fallback tests if stream fallback files changed**

If any implementation work changed `lib/services/audio/audio_stream_manager.dart`,
`lib/services/audio/internal/audio_stream_delegate.dart`, or source fallback
interfaces, run:

```bash
flutter test test/data/sources/audio_stream_quality_fallback_test.dart test/data/sources/youtube_source_test.dart
```

Expected: PASS.

- [ ] **Step 6: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: PASS, or only pre-existing warnings confirmed before this refactor.

- [ ] **Step 7: Review diff for scope**

Run:

```bash
git diff --stat
git diff -- lib/services/audio/audio_provider.dart lib/services/audio/playback_request_session.dart lib/services/audio/playback_recovery_coordinator.dart lib/services/audio/AGENTS.md
```

Expected: changes are limited to playback request session, playback recovery,
audio controller integration, tests, and audio ownership documentation.

- [ ] **Step 8: Final checkpoint**

Run:

```bash
git status --short
```

Expected: only files related to this plan and the already approved spec/plan are
modified or added.

Do not commit unless the user explicitly requested commits.

## Self-Review Notes

- Spec coverage: `PlaybackRequestSession`, `PlaybackRecoveryCoordinator`,
  `AudioController` ownership preservation, media-open recovery, retry
  generation/manual/network recovery, tests, documentation, and verification are
  covered by Tasks 1-7.
- Red-flag scan: this plan intentionally avoids incomplete instructions. Branching
  in Task 6 is explicit and gives concrete removal or retention steps.
- Type consistency: `PlaybackSessionCommand`, `PlaybackRestoreCommand`,
  `PlaybackSessionResult`, `PlaybackRecoveryCoordinator`,
  `PlaybackRecoveryEvent`, and `PlaybackRetryExecutor` are introduced before
  later tasks use them.
- Repository instruction conflict: the planning skill recommends frequent
  commits, but repository instructions say not to commit unless explicitly
  requested. This plan uses checkpoints instead of commit steps.
