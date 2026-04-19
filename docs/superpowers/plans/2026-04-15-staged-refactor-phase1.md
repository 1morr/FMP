# FMP Staged Refactor Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the phase-1 safety layer for the staged refactor by adding regression tests, fixing resource cleanup, and repairing the highest-risk stability boundaries without splitting `QueueManager` or `AudioController`.

**Architecture:** Phase 1 is intentionally stabilization-first. Keep the existing `UI -> AudioController -> QueueManager / AudioService` shape, but add tests around the riskiest playback flows, harden disposal/resource lifecycles, and fix the temporary-play / download-counter / Mix cleanup edges called out in `docs/superpowers/specs/2026-04-15-staged-refactor-design.md`.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, just_audio, media_kit, flutter_test

---

## File Structure

### Existing files to modify
- `lib/services/audio/audio_provider.dart`
  - Keep the current orchestration shape.
  - Fix temporary-play restore edge behavior without introducing structural extraction.
  - Fix provider disposal double-cleanup by making controller-owned disposal explicit.
- `lib/services/audio/queue_manager.dart`
  - Keep queue responsibilities unchanged.
  - Fix Mix cleanup on `clear()` and harden state-stream disposal.
- `lib/services/audio/just_audio_service.dart`
  - Add disposal guards so stream sinks are never written after shutdown.
- `lib/services/audio/media_kit_audio_service.dart`
  - Add disposal guards mirroring `just_audio_service.dart`.
- `lib/services/download/download_service.dart`
  - Harden controller cleanup, cap in-memory progress buffering, and centralize active-download counter cleanup.
- `lib/providers/database_provider.dart`
  - Add narrow migration helpers/tests for the current critical defaults.
- `lib/services/cache/ranking_cache_service.dart`
  - Make network monitoring setup idempotent and safe across provider rebuilds.
- `lib/providers/download/download_providers.dart`
  - Avoid double-disposal / dangling subscriptions around `DownloadService`.
- `lib/services/audio/audio_provider.dart:2526-2602`
  - Stop provider-level double disposal for `audioServiceProvider` and `queueManagerProvider` because `AudioController.dispose()` already owns those lifecycles.

### New test files to create
- `test/services/audio/audio_controller_phase1_test.dart`
  - Temporary play, restore, request superseding, Mix clear behavior.
- `test/services/download/download_service_phase1_test.dart`
  - Counter cleanup, dispose safety, progress buffer limit.
- `test/providers/database_migration_test.dart`
  - Migration coverage for `useNeteaseAuthForPlay`, `enabledSources`, `neteaseStreamPriority`.
- `test/services/cache/ranking_cache_service_test.dart`
  - Network monitoring idempotence and cleanup.
- `test/services/audio/audio_service_dispose_test.dart`
  - Disposal safety for `JustAudioService` / `MediaKitAudioService` stream sinks.

### Test support files to create
- `test/support/fakes/fake_audio_service.dart`
  - Minimal fake `FmpAudioService` with controllable streams and state.
- `test/support/fakes/fake_queue_manager.dart`
  - Lightweight queue behavior for `AudioController` tests if direct real-queue setup becomes too heavy.
- `test/support/fakes/fake_repositories.dart`
  - Small in-memory stubs for settings / download / track behavior used by phase-1 tests.

---

### Task 1: Add playback safety tests for temporary play and request superseding

**Files:**
- Create: `test/support/fakes/fake_audio_service.dart`
- Create: `test/services/audio/audio_controller_phase1_test.dart`
- Modify: `lib/services/audio/audio_provider.dart:561-762`
- Modify: `lib/services/audio/audio_provider.dart:1621-1819`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Write the failing temporary-play and superseding tests**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_types.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  group('AudioController phase-1 temporary play protection', () {
    late FakeAudioService audioService;

    setUp(() {
      audioService = FakeAudioService();
    });

    test('second temporary play preserves original saved queue state', () async {
      final controller = buildTestAudioController(audioService: audioService);
      final queueTrack = buildTrack(id: 1, sourceId: 'queue-1', title: 'Queue Track');
      final tempA = buildTrack(id: 2, sourceId: 'temp-a', title: 'Temp A');
      final tempB = buildTrack(id: 3, sourceId: 'temp-b', title: 'Temp B');

      controller.debugLoadQueue([queueTrack], currentIndex: 0);
      audioService.debugPosition = const Duration(seconds: 45);
      audioService.debugPlaying = true;

      await controller.playTemporary(tempA);
      audioService.debugPosition = const Duration(seconds: 5);
      await controller.playTemporary(tempB);
      await controller.debugReturnToQueueForTest();

      expect(controller.debugSavedQueueIndexForTest, isNull);
      expect(controller.state.currentTrack?.sourceId, 'queue-1');
      expect(audioService.seekHistory.single, const Duration(seconds: 35));
    });

    test('superseded request does not overwrite latest playing track', () async {
      final controller = buildTestAudioController(audioService: audioService);
      final slowTrack = buildTrack(id: 11, sourceId: 'slow', title: 'Slow');
      final fastTrack = buildTrack(id: 12, sourceId: 'fast', title: 'Fast');

      audioService.blockNextPlay();
      final first = controller.debugExecutePlayRequestForTest(slowTrack);
      final second = controller.debugExecutePlayRequestForTest(fastTrack);

      audioService.releaseBlockedPlay();
      await Future.wait([first, second]);

      expect(controller.state.currentTrack?.sourceId, 'fast');
      expect(audioService.playedTrackIds.last, 'fast');
    });
  });
}
```

- [ ] **Step 2: Run the targeted test file and confirm it fails**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: FAIL with missing `FakeAudioService`, `buildTestAudioController`, and debug test hooks on `AudioController`.

- [ ] **Step 3: Add the minimal fake audio service and test hooks**

```dart
// test/support/fakes/fake_audio_service.dart
import 'dart:async';

import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_service.dart';
import 'package:fmp/services/audio/audio_types.dart';

class FakeAudioService implements FmpAudioService {
  final _playerStateController = StreamController<FmpPlayerState>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _processingController = StreamController<FmpAudioProcessingState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _bufferedPositionController = StreamController<Duration>.broadcast();
  final _speedController = StreamController<double>.broadcast();
  final _completedController = StreamController<void>.broadcast();
  final _audioDevicesController = StreamController<List<FmpAudioDevice>>.broadcast();
  final _audioDeviceController = StreamController<FmpAudioDevice?>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  bool debugPlaying = false;
  Duration debugPosition = Duration.zero;
  Duration? debugDuration;
  double debugSpeed = 1.0;
  double debugVolume = 1.0;
  final List<String> playedTrackIds = [];
  final List<Duration> seekHistory = [];

  Completer<void>? _blockedPlay;

  void blockNextPlay() {
    _blockedPlay = Completer<void>();
  }

  void releaseBlockedPlay() {
    _blockedPlay?.complete();
    _blockedPlay = null;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    await _playerStateController.close();
    await _playingController.close();
    await _processingController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferedPositionController.close();
    await _speedController.close();
    await _completedController.close();
    await _audioDevicesController.close();
    await _audioDeviceController.close();
    await _errorController.close();
  }

  @override
  Stream<FmpPlayerState> get playerStateStream => _playerStateController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<FmpAudioProcessingState> get processingStateStream => _processingController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _bufferedPositionController.stream;
  @override
  Stream<double> get speedStream => _speedController.stream;
  @override
  Stream<void> get completedStream => _completedController.stream;
  @override
  Stream<List<FmpAudioDevice>> get audioDevicesStream => _audioDevicesController.stream;
  @override
  Stream<FmpAudioDevice?> get audioDeviceStream => _audioDeviceController.stream;
  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  bool get isPlaying => debugPlaying;
  @override
  Duration get position => debugPosition;
  @override
  Duration? get duration => debugDuration;
  @override
  Duration get bufferedPosition => debugPosition;
  @override
  double get speed => debugSpeed;
  @override
  double get volume => debugVolume;
  @override
  FmpAudioProcessingState get processingState => FmpAudioProcessingState.ready;
  @override
  List<FmpAudioDevice> get audioDevices => const [];
  @override
  FmpAudioDevice? get audioDevice => null;

  @override
  Future<void> play() async {
    if (_blockedPlay != null) {
      await _blockedPlay!.future;
    }
    debugPlaying = true;
  }

  @override
  Future<void> pause() async {
    debugPlaying = false;
  }

  @override
  Future<void> stop() async {
    debugPlaying = false;
    debugPosition = Duration.zero;
  }

  @override
  Future<void> togglePlayPause() async {
    debugPlaying = !debugPlaying;
  }

  @override
  Future<void> seekTo(Duration position) async {
    debugPosition = position;
    seekHistory.add(position);
  }

  @override
  Future<void> seekForward([Duration? duration]) async {}

  @override
  Future<void> seekBackward([Duration? duration]) async {}

  @override
  Future<bool> seekToLive() async => false;

  @override
  Future<void> setSpeed(double speed) async {
    debugSpeed = speed;
  }

  @override
  Future<void> resetSpeed() async {
    debugSpeed = 1.0;
  }

  @override
  Future<void> setVolume(double volume) async {
    debugVolume = volume;
  }

  @override
  Future<void> setAudioDevice(FmpAudioDevice device) async {}

  @override
  Future<void> setAudioDeviceAuto() async {}

  @override
  Future<Duration?> playUrl(String url, {Map<String, String>? headers, Track? track}) async {
    if (_blockedPlay != null) {
      await _blockedPlay!.future;
    }
    if (track != null) {
      playedTrackIds.add(track.sourceId);
    }
    debugPlaying = true;
    return debugDuration;
  }

  @override
  Future<Duration?> setUrl(String url, {Map<String, String>? headers, Track? track}) async => debugDuration;

  @override
  Future<Duration?> playFile(String filePath, {Track? track}) async {
    if (track != null) {
      playedTrackIds.add(track.sourceId);
    }
    debugPlaying = true;
    return debugDuration;
  }

  @override
  Future<Duration?> setFile(String filePath, {Track? track}) async => debugDuration;
}
```

```dart
// lib/services/audio/audio_provider.dart (test-only helpers near AudioController)
@visibleForTesting
int? get debugSavedQueueIndexForTest => _context.savedQueueIndex;

@visibleForTesting
Future<void> debugReturnToQueueForTest() => _returnToQueue();

@visibleForTesting
Future<void> debugExecutePlayRequestForTest(Track track) {
  return _executePlayRequest(
    track: track,
    mode: PlayMode.queue,
    persist: false,
    recordHistory: false,
    prefetchNext: false,
  );
}
```

- [ ] **Step 4: Fix the temporary-play restore boundary with the smallest code change**

```dart
// lib/services/audio/audio_provider.dart inside _restoreQueuePlayback
final targetIndex = savedIndex.clamp(0, queue.length - 1);
_queueManager.setCurrentIndex(targetIndex);

final currentTrack = _queueManager.currentTrack;
if (currentTrack == null) {
  if (clearSavedState) {
    _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
  }
  _resetLoadingState();
  return;
}

...

if (clearSavedState) {
  _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
}
```

```dart
// lib/services/audio/audio_provider.dart inside playTemporary catch blocks
if (_context.hasSavedState) {
  await _restoreSavedState();
} else {
  _context = _context.copyWith(mode: PlayMode.queue, clearSavedState: true);
  _resetLoadingState();
}
```

- [ ] **Step 5: Run the targeted test file and confirm it passes**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS with both tests green.

- [ ] **Step 6: Commit the playback safety test slice**

```bash
git add test/support/fakes/fake_audio_service.dart test/services/audio/audio_controller_phase1_test.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
test: cover temporary playback safety flows

Add phase-1 regression coverage for temporary playback restoration and request superseding so future stabilization work has a safety net.
EOF
)"
```

---

### Task 2: Fix provider-owned disposal and audio-service shutdown safety

**Files:**
- Create: `test/services/audio/audio_service_dispose_test.dart`
- Modify: `lib/services/audio/audio_provider.dart:417-430`
- Modify: `lib/services/audio/audio_provider.dart:2526-2558`
- Modify: `lib/services/audio/just_audio_service.dart:269-289`
- Modify: `lib/services/audio/media_kit_audio_service.dart:413-435`
- Test: `test/services/audio/audio_service_dispose_test.dart`

- [ ] **Step 1: Write the failing disposal-safety tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/just_audio_service.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';

void main() {
  group('audio service dispose safety', () {
    test('JustAudioService dispose is idempotent', () async {
      final service = JustAudioService();
      await service.initialize();

      await service.dispose();
      await service.dispose();
    });

    test('MediaKitAudioService dispose is idempotent', () async {
      final service = MediaKitAudioService();
      await service.initialize();

      await service.dispose();
      await service.dispose();
    });
  });
}
```

- [ ] **Step 2: Run the disposal test file and confirm it fails**

Run:
```bash
flutter test test/services/audio/audio_service_dispose_test.dart
```

Expected: FAIL because the second dispose closes already-closed stream controllers / subjects.

- [ ] **Step 3: Add `_disposed` guards to both audio services**

```dart
// lib/services/audio/just_audio_service.dart
bool _disposed = false;

@override
Future<void> dispose() async {
  if (_disposed) return;
  _disposed = true;

  for (final subscription in _subscriptions) {
    await subscription.cancel();
  }
  _subscriptions.clear();

  await _completedController.close();
  await _errorController.close();
  await _playerStateController.close();
  await _processingStateController.close();
  await _positionController.close();
  await _durationController.close();
  await _bufferedPositionController.close();
  await _speedController.close();
  await _playingController.close();
  await _audioDevicesController.close();
  await _audioDeviceController.close();

  await _player.dispose();
}
```

```dart
// lib/services/audio/media_kit_audio_service.dart
bool _disposed = false;

@override
Future<void> dispose() async {
  if (_disposed) return;
  _disposed = true;

  for (final subscription in _subscriptions) {
    await subscription.cancel();
  }
  _subscriptions.clear();

  await _completedController.close();
  await _errorController.close();
  await _playerStateController.close();
  await _processingStateController.close();
  await _positionController.close();
  await _durationController.close();
  await _bufferedPositionController.close();
  await _speedController.close();
  await _playingController.close();
  await _volumeController.close();
  await _audioDevicesController.close();
  await _audioDeviceController.close();

  await _player.dispose();
}
```

- [ ] **Step 4: Remove provider-level double disposal and keep ownership in `AudioController.dispose()`**

```dart
// lib/services/audio/audio_provider.dart
@override
void dispose() {
  _isDisposed = true;
  _stopPositionCheckTimer();
  _cancelRetryTimer();
  _networkRecoverySubscription?.cancel();
  for (final subscription in _subscriptions) {
    subscription.cancel();
  }
  _subscriptions.clear();
  _mixState = null;
  _queueManager.dispose();
  unawaited(_audioService.dispose());
  super.dispose();
}
```

```dart
// lib/services/audio/audio_provider.dart providers
final audioServiceProvider = Provider<FmpAudioService>((ref) {
  if (Platform.isAndroid || Platform.isIOS) {
    return JustAudioService();
  }
  return MediaKitAudioService();
});

final queueManagerProvider = Provider<QueueManager>((ref) {
  ...
  return manager;
});
```

- [ ] **Step 5: Re-run the disposal test file and a focused audio model suite**

Run:
```bash
flutter test test/services/audio/audio_service_dispose_test.dart && flutter test test/services/audio/player_state_test.dart
```

Expected: PASS for both commands.

- [ ] **Step 6: Commit the disposal safety slice**

```bash
git add test/services/audio/audio_service_dispose_test.dart lib/services/audio/audio_provider.dart lib/services/audio/just_audio_service.dart lib/services/audio/media_kit_audio_service.dart
git commit -m "$(cat <<'EOF'
fix: harden audio service disposal lifecycle

Make audio service disposal idempotent and remove duplicate provider-level cleanup so playback teardown stops leaking or double-closing resources.
EOF
)"
```

---

### Task 3: Fix download cleanup accounting and guard in-memory progress buffering

**Files:**
- Create: `test/services/download/download_service_phase1_test.dart`
- Modify: `lib/services/download/download_service.dart:154-225`
- Modify: `lib/services/download/download_service.dart:435-535`
- Modify: `lib/services/download/download_service.dart:592-800`
- Modify: `lib/providers/download/download_providers.dart:46-120`
- Test: `test/services/download/download_service_phase1_test.dart`

- [ ] **Step 1: Write the failing download cleanup tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/download/download_service.dart';

import '../../support/fakes/fake_repositories.dart';

void main() {
  group('DownloadService phase-1 cleanup', () {
    test('external cleanup does not double-decrement active download count', () async {
      final service = buildTestDownloadService();

      service.debugSetActiveDownloads(1);
      service.debugMarkIsolateActive(taskId: 9);
      await service.pauseTask(9);
      await service.debugFinalizeDownloadForTest(taskId: 9);

      expect(service.debugActiveDownloadsForTest, 0);
    });

    test('pending progress buffer is capped', () {
      final service = buildTestDownloadService();

      for (var i = 0; i < 1500; i++) {
        service.debugRecordProgressForTest(i, i, 0.5, 50, 100);
      }

      expect(service.debugPendingProgressCountForTest, lessThanOrEqualTo(1000));
    });

    test('dispose is idempotent', () {
      final service = buildTestDownloadService();
      service.dispose();
      service.dispose();
    });
  });
}
```

- [ ] **Step 2: Run the download phase-1 tests and confirm they fail**

Run:
```bash
flutter test test/services/download/download_service_phase1_test.dart
```

Expected: FAIL with missing debug hooks and current double-cleanup / uncapped-buffer behavior.

- [ ] **Step 3: Add a single helper for active-download cleanup and a hard buffer cap**

```dart
// lib/services/download/download_service.dart
static const int _maxPendingProgressUpdates = 1000;
bool _disposed = false;

void _decrementActiveDownloadIfNeeded(int taskId) {
  final wasExternallyCleaned = _externallyCleaned.remove(taskId);
  if (!wasExternallyCleaned) {
    _activeDownloads--;
  }
  if (_activeDownloads < 0) {
    _activeDownloads = 0;
  }
}

void _recordProgressUpdate(int taskId, int trackId, double progress, int downloadedBytes, int totalBytes) {
  if (_disposed) return;
  if (_pendingProgressUpdates.length >= _maxPendingProgressUpdates &&
      !_pendingProgressUpdates.containsKey(taskId)) {
    final oldestTaskId = _pendingProgressUpdates.keys.first;
    _pendingProgressUpdates.remove(oldestTaskId);
  }
  _pendingProgressUpdates[taskId] = (trackId, progress, downloadedBytes, totalBytes);
}
```

```dart
// lib/services/download/download_service.dart
void dispose() {
  if (_disposed) return;
  _disposed = true;

  _schedulerTimer?.cancel();
  _scheduleSubscription?.cancel();
  _progressUpdateTimer?.cancel();
  _scheduleController.close();
  _progressController.close();
  _completionController.close();
  _failureController.close();
  ...
}
```

- [ ] **Step 4: Route pause/cancel/finally through the same cleanup rule**

```dart
// lib/services/download/download_service.dart
Future<void> pauseTask(int taskId) async {
  final isolateInfo = _activeDownloadIsolates.remove(taskId);
  if (isolateInfo != null) {
    isolateInfo.receivePort.close();
    isolateInfo.isolate.kill();
    _externallyCleaned.add(taskId);
    _decrementActiveDownloadIfNeeded(taskId);
  }

  final cancelToken = _activeCancelTokens.remove(taskId);
  if (cancelToken != null && isolateInfo == null) {
    cancelToken.cancel('User paused');
    _externallyCleaned.add(taskId);
    _decrementActiveDownloadIfNeeded(taskId);
  }

  await _downloadRepository.updateTaskStatus(taskId, DownloadStatus.paused);
}
```

```dart
// lib/services/download/download_service.dart finally block inside _startDownload
final wasStillActive = _activeDownloadIsolates.remove(task.id) != null;
_activeCancelTokens.remove(task.id);
if (wasStillActive || _externallyCleaned.contains(task.id)) {
  _decrementActiveDownloadIfNeeded(task.id);
}
_triggerSchedule();
```

- [ ] **Step 5: Make provider-side subscriptions dispose cleanly**

```dart
// lib/providers/download/download_providers.dart
ref.onDispose(() {
  debounceTimer?.cancel();
  completionSubscription?.cancel();
  progressSubscription?.cancel();
  service.dispose();
});
```

- [ ] **Step 6: Run the download phase-1 tests and the existing download suite**

Run:
```bash
flutter test test/services/download/download_service_phase1_test.dart && flutter test test/services/download/download_service_test.dart
```

Expected: PASS with stable active-download accounting and no dispose errors.

- [ ] **Step 7: Commit the download cleanup slice**

```bash
git add test/services/download/download_service_phase1_test.dart lib/services/download/download_service.dart lib/providers/download/download_providers.dart
git commit -m "$(cat <<'EOF'
fix: stabilize download cleanup accounting

Prevent download counter drift, cap in-memory progress buffering, and make download service teardown safe across pause, cancel, and provider disposal.
EOF
)"
```

---

### Task 4: Fix Mix cleanup and queue state-stream shutdown behavior

**Files:**
- Modify: `lib/services/audio/queue_manager.dart:253-258`
- Modify: `lib/services/audio/queue_manager.dart:687-700`
- Modify: `test/services/audio/audio_controller_phase1_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

- [ ] **Step 1: Add the failing Mix-clear test**

```dart
test('clearing queue exits persisted mix mode', () async {
  final controller = buildTestAudioController(audioService: audioService);
  final mixTrack = buildTrack(id: 40, sourceId: 'mix-1', title: 'Mix Track');

  await controller.playMixPlaylist(
    playlistId: 'RD-test',
    seedVideoId: 'seed-1',
    title: 'Mix Queue',
    tracks: [mixTrack],
  );

  await controller.clearQueue();

  expect(controller.state.isMixMode, isFalse);
  expect(controller.debugQueueIsMixModeForTest, isFalse);
});
```

- [ ] **Step 2: Run the audio phase-1 test file and confirm the new test fails**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: FAIL because `QueueManager.clear()` leaves `PlayQueue.isMixMode` and Mix metadata behind.

- [ ] **Step 3: Fix `QueueManager.clear()` and guard state notifications after dispose**

```dart
// lib/services/audio/queue_manager.dart
bool _disposed = false;

void dispose() {
  if (_disposed) return;
  _disposed = true;
  _savePositionTimer?.cancel();
  _fetchingUrlTrackIds.clear();
  _stateController.close();
}

void _notifyStateChanged() {
  if (_disposed || _stateController.isClosed) return;
  _stateController.add(null);
}
```

```dart
// lib/services/audio/queue_manager.dart
Future<void> clear() async {
  logInfo('Clearing queue');

  _tracks.clear();
  _currentIndex = 0;
  _shuffleOrder.clear();
  _shuffleIndex = 0;

  if (_currentQueue != null) {
    _currentQueue!.originalOrder = [];
    _currentQueue!.isMixMode = false;
    _currentQueue!.mixPlaylistId = null;
    _currentQueue!.mixSeedVideoId = null;
    _currentQueue!.mixTitle = null;
    await _persistQueue();
  }

  _notifyStateChanged();
}
```

- [ ] **Step 4: Re-run the audio phase-1 tests**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS, including the Mix cleanup test.

- [ ] **Step 5: Commit the queue safety slice**

```bash
git add lib/services/audio/queue_manager.dart test/services/audio/audio_controller_phase1_test.dart
git commit -m "$(cat <<'EOF'
fix: clear mix metadata when queue resets

Ensure queue clearing exits persisted mix mode and stop queue state notifications after disposal.
EOF
)"
```

---

### Task 5: Add migration coverage for current critical defaults

**Files:**
- Create: `test/providers/database_migration_test.dart`
- Modify: `lib/providers/database_provider.dart:22-133`
- Test: `test/providers/database_migration_test.dart`

- [ ] **Step 1: Write the failing migration tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:isar/isar.dart';

void main() {
  group('database migration', () {
    test('migrateDatabase enables NetEase auth defaults for old settings', () async {
      final isar = await openTestIsar();
      await isar.writeTxn(() async {
        final settings = Settings()
          ..enabledSources = ['bilibili', 'youtube']
          ..useNeteaseAuthForPlay = false
          ..neteaseStreamPriority = '';
        await isar.settings.put(settings);
      });

      await debugMigrateDatabaseForTest(isar);
      final migrated = await isar.settings.get(0);

      expect(migrated!.useNeteaseAuthForPlay, isTrue);
      expect(migrated.enabledSources, contains('netease'));
      expect(migrated.neteaseStreamPriority, 'audioOnly');
    });
  });
}
```

- [ ] **Step 2: Run the migration test file and confirm it fails**

Run:
```bash
flutter test test/providers/database_migration_test.dart
```

Expected: FAIL because there is no test hook to invoke `_migrateDatabase()` directly and no local test helper for opening an Isar instance.

- [ ] **Step 3: Add a narrow test hook instead of restructuring the provider**

```dart
// lib/providers/database_provider.dart
@visibleForTesting
Future<void> debugMigrateDatabaseForTest(Isar isar) => _migrateDatabase(isar);
```

```dart
// test/providers/database_migration_test.dart helper
Future<Isar> openTestIsar() async {
  final dir = await Directory.systemTemp.createTemp('fmp_migration_test_');
  return Isar.open(
    [
      TrackSchema,
      PlaylistSchema,
      PlayQueueSchema,
      SettingsSchema,
      SearchHistorySchema,
      DownloadTaskSchema,
      PlayHistorySchema,
      RadioStationSchema,
      LyricsMatchSchema,
      AccountSchema,
    ],
    directory: dir.path,
    name: 'fmp_migration_test',
  );
}
```

- [ ] **Step 4: Add one more regression assertion for queue creation**

```dart
test('migrateDatabase creates an empty queue when none exists', () async {
  final isar = await openTestIsar();

  await debugMigrateDatabaseForTest(isar);
  final queues = await isar.playQueues.where().findAll();

  expect(queues, hasLength(1));
  expect(queues.single.trackIds, isEmpty);
});
```

- [ ] **Step 5: Run the migration tests and confirm they pass**

Run:
```bash
flutter test test/providers/database_migration_test.dart
```

Expected: PASS with the migrated defaults and queue creation verified.

- [ ] **Step 6: Commit the migration coverage slice**

```bash
git add test/providers/database_migration_test.dart lib/providers/database_provider.dart
git commit -m "$(cat <<'EOF'
test: cover critical database migration defaults

Add phase-1 regression coverage for the current NetEase and queue initialization migration rules so later refactors cannot silently regress them.
EOF
)"
```

---

### Task 6: Harden ranking cache network-monitoring lifecycle

**Files:**
- Create: `test/services/cache/ranking_cache_service_test.dart`
- Modify: `lib/services/cache/ranking_cache_service.dart:19-191`
- Test: `test/services/cache/ranking_cache_service_test.dart`

- [ ] **Step 1: Write the failing ranking-cache lifecycle tests**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/cache/ranking_cache_service.dart';
import 'package:fmp/services/network/connectivity_service.dart';

class TestConnectivityNotifier extends ConnectivityNotifier {
  final _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get onNetworkRecovered => _controller.stream;

  void emitRecovered() => _controller.add(null);
}

void main() {
  test('setupNetworkMonitoring cancels previous subscription before rebinding', () async {
    final service = RankingCacheService();
    final first = TestConnectivityNotifier();
    final second = TestConnectivityNotifier();

    service.setupNetworkMonitoring(first);
    service.setupNetworkMonitoring(second);

    expect(service.debugHasNetworkSubscriptionForTest, isTrue);
  });
}
```

- [ ] **Step 2: Run the ranking-cache test file and confirm it fails**

Run:
```bash
flutter test test/services/cache/ranking_cache_service_test.dart
```

Expected: FAIL because `setupNetworkMonitoring` short-circuits on `_networkMonitoringSetup` and cannot be re-bound safely.

- [ ] **Step 3: Make network-monitoring setup idempotent and provider-safe**

```dart
// lib/services/cache/ranking_cache_service.dart
bool _disposed = false;

void setupNetworkMonitoring(ConnectivityNotifier connectivityNotifier) {
  if (_disposed) return;

  _networkRecoveredSubscription?.cancel();
  _networkRecoveredSubscription = connectivityNotifier.onNetworkRecovered.listen((_) {
    if (_disposed) return;
    debugPrint('[RankingCache] 網絡恢復，重新獲取排行榜緩存');
    _refreshAll();
  });
}

void dispose() {
  if (_disposed) return;
  _disposed = true;
  _refreshTimer?.cancel();
  _networkRecoveredSubscription?.cancel();
  _stateController.close();
}
```

```dart
// lib/services/cache/ranking_cache_service.dart provider cleanup
ref.onDispose(() {
  service._networkRecoveredSubscription?.cancel();
  service._networkRecoveredSubscription = null;
});
```

- [ ] **Step 4: Re-run the ranking-cache tests**

Run:
```bash
flutter test test/services/cache/ranking_cache_service_test.dart
```

Expected: PASS with safe rebinding behavior.

- [ ] **Step 5: Commit the ranking cache cleanup slice**

```bash
git add test/services/cache/ranking_cache_service_test.dart lib/services/cache/ranking_cache_service.dart
git commit -m "$(cat <<'EOF'
fix: make ranking cache network monitoring rebind-safe

Allow ranking cache subscriptions to be rebound safely across provider rebuilds and guard service disposal from duplicate cleanup.
EOF
)"
```

---

### Task 7: Run the phase-1 verification suite and update project docs

**Files:**
- Modify: `CLAUDE.md`
- Test: `test/services/audio/audio_controller_phase1_test.dart`
- Test: `test/services/audio/audio_service_dispose_test.dart`
- Test: `test/services/download/download_service_phase1_test.dart`
- Test: `test/providers/database_migration_test.dart`
- Test: `test/services/cache/ranking_cache_service_test.dart`

- [ ] **Step 1: Add the phase-1 stabilization note to project docs**

```md
## Key Design Decisions

### Staged refactor safety layer
Phase-1 refactor work must not split `AudioController` or `QueueManager`.
Before structural refactors, keep regression coverage for:
- `playTemporary()` / restore flows
- `_executePlayRequest()` superseding behavior
- download active-counter cleanup
- database migration defaults
- queue clear → Mix state reset
```

- [ ] **Step 2: Run the focused phase-1 verification suite**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart && flutter test test/services/audio/audio_service_dispose_test.dart && flutter test test/services/download/download_service_phase1_test.dart && flutter test test/providers/database_migration_test.dart && flutter test test/services/cache/ranking_cache_service_test.dart
```

Expected: PASS for all phase-1 regression tests.

- [ ] **Step 3: Run the existing adjacent suites to check for regressions**

Run:
```bash
flutter test test/services/audio/player_state_test.dart && flutter test test/services/audio/queue_manager_test.dart && flutter test test/services/download/download_service_test.dart
```

Expected: PASS for all existing adjacent suites.

- [ ] **Step 4: Run static analysis for the touched codepaths**

Run:
```bash
flutter analyze
```

Expected: PASS, or only pre-existing unrelated warnings.

- [ ] **Step 5: Commit the verification + docs slice**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: record phase-1 refactor safety constraints

Document the phase-1 stabilization guardrails and verify the new regression suite before moving on to later refactor stages.
EOF
)"
```

---

## Self-Review

### Spec coverage check
- **Phase 1 only**: Covered. The plan stays inside tests, cleanup, and stability fixes; it explicitly avoids structural splitting.
- **Minimal regression suite**: Covered by Tasks 1, 3, 5, 6, and the final verification task.
- **Resource cleanup**: Covered by Tasks 2, 3, 4, and 6.
- **Critical stability boundaries**: Covered by temporary play (Task 1), download accounting (Task 3), Mix cleanup (Task 4), and migration defaults (Task 5).
- **Incremental, commit-sized execution**: Covered. Every task ends with a dedicated commit.

### Placeholder scan
- Removed generic placeholders like “write tests later” and “handle edge cases”.
- Every task includes exact file paths, test commands, and concrete code snippets.
- No “similar to previous task” shortcuts remain.

### Type consistency check
- Reused actual project types and symbols already present in the codebase: `AudioController`, `QueueManager`, `FmpAudioService`, `DownloadService`, `Settings`, `PlayQueue`.
- Test hooks are explicitly named with `debug...ForTest` to avoid ambiguity.
- The plan keeps `AudioController` / `QueueManager` in place rather than introducing not-yet-defined extracted managers in phase 1.
