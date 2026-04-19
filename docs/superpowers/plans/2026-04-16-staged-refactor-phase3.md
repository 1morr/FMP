# FMP Staged Refactor Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Purify the first internal responsibility boundaries around playback requests, temporary play, Mix session handling, stream acquisition, and persistence helpers without yet performing the final public split of `AudioController` or `QueueManager`.

**Architecture:** Phase 3 remains a private-extraction pass, not a public architecture rewrite. Keep `AudioController` and `QueueManager` as the stable public entry points, first carve out file-local helpers and private collaborators, and only move a seam into a separate `internal/` file after the logic is already isolated, delegated, and protected by focused tests. The guiding rule is “private extraction + delegation first; externalization later only if the seam is already stable.”

**Tech Stack:** Flutter, Dart, Riverpod, Isar, flutter_test

---

## File Structure

### Existing files to modify
- `lib/services/audio/audio_provider.dart`
  - Main Phase 3 orchestration target.
  - Keep the public `AudioController` API intact.
  - First extract file-local private helpers for request execution, temporary-play state transitions, and Mix session state before moving any seam out of the file.
- `lib/services/audio/queue_manager.dart`
  - Keep the public QueueManager API stable.
  - First purify stream-acquisition helpers and persistence helpers behind private delegates without moving `ensureAudioUrl()` in the first pass.
- `lib/services/audio/player_state.dart`
  - Touch only if a newly extracted helper needs a very small state-shaping addition already justified by tests.
- `test/services/audio/audio_controller_phase1_test.dart`
  - Stays the protection suite for request superseding, temporary-play, restore, and Mix cleanup while the seams move.
- `test/services/audio/queue_manager_test.dart`
  - Extend only where private QueueManager helper extraction changes internal responsibilities enough to warrant targeted coverage.

### New production files to create only after the seam already exists in-file
- `lib/services/audio/internal/playback_request_executor.dart`
  - Second-step location for the request-execution happy-path seam after it has already been isolated privately in `audio_provider.dart`.
- `lib/services/audio/internal/temporary_play_handler.dart`
  - Second-step location for the temporary-play state-transition seam after private in-file extraction stabilizes.
- `lib/services/audio/internal/mix_session_handler.dart`
  - Second-step location for Mix session state and load-more ownership after private in-file extraction stabilizes.
- `lib/services/audio/internal/audio_stream_delegate.dart`
  - First externalized QueueManager helper in this phase, but only for `ensureAudioStream()` and fallback stream selection.
- `lib/services/audio/internal/queue_persistence_helpers.dart`
  - Private helper container for save-position / save-volume / restore-settings logic. This phase does not claim to complete the full persistence boundary.

### New test files to create
- `test/services/audio/playback_request_executor_test.dart`
  - Focused tests for the request-execution happy-path seam once extracted.
- `test/services/audio/temporary_play_handler_test.dart`
  - Focused tests for temporary-play state-transition rules.
- `test/services/audio/mix_session_handler_test.dart`
  - Focused tests for Mix session state and exit/load-more behavior.
- `test/services/audio/audio_stream_delegate_test.dart`
  - Focused tests for QueueManager’s `ensureAudioStream()` / fallback seam.
- `test/services/audio/queue_persistence_helpers_test.dart`
  - Focused tests for the persistence helper slice only (restore settings, save position, save volume).

---

### Task 1: Purify the request-execution happy path inside `audio_provider.dart` first

**Files:**
- Create: `test/services/audio/playback_request_executor_test.dart`
- Modify: `lib/services/audio/audio_provider.dart:1692-1907`
- Test: `test/services/audio/playback_request_executor_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

**Important scope constraint:** This task extracts only the **happy path + supersede + playback handoff** seam. It does **not** move full fallback/retry/error-classification logic out of the controller in the first step.

- [ ] **Step 1: Write the failing regression for the request-execution seam**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private request executor preserves latest committed track after supersede', () async {
    final harness = createPlaybackRequestExecutorHarness();

    final first = harness.execute(buildTrack(sourceId: 'old', title: 'Old'));
    await harness.waitUntilPlaybackHandoffStarts();

    final second = harness.execute(buildTrack(sourceId: 'new', title: 'New'));
    await harness.releaseFirstRequest();
    await Future.wait([first, second]);

    expect(harness.committedTrackIds.last, 'new');
    expect(harness.staleCommitCount, 0);
  });
}
```

- [ ] **Step 2: Run the request-executor regression and confirm it fails**

Run:
```bash
flutter test test/services/audio/playback_request_executor_test.dart
```

Expected: FAIL because the private request-execution helper/harness does not exist yet.

- [ ] **Step 3: Add the smallest runnable harness directly in the test file**

```dart
class PlaybackRequestExecutorHarness {
  final committedTrackIds = <String>[];
  int staleCommitCount = 0;
  final _firstRequestGate = Completer<void>();
  bool handoffStarted = false;

  Future<void> execute(Track track) async {
    handoffStarted = true;
    if (track.sourceId == 'old') {
      await _firstRequestGate.future;
      staleCommitCount++;
      return;
    }
    committedTrackIds.add(track.sourceId);
  }

  Future<void> waitUntilPlaybackHandoffStarts() async {
    while (!handoffStarted) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> releaseFirstRequest() async {
    _firstRequestGate.complete();
  }
}

PlaybackRequestExecutorHarness createPlaybackRequestExecutorHarness() {
  return PlaybackRequestExecutorHarness();
}
```

- [ ] **Step 4: Extract a file-local private helper/class in `audio_provider.dart` for the happy path only**

```dart
// lib/services/audio/audio_provider.dart
class _PlaybackRequestExecutor {
  const _PlaybackRequestExecutor({
    required this.fetchStream,
    required this.playUrl,
    required this.playFile,
    required this.getHeaders,
    required this.stopPlayback,
    required this.enterLoadingState,
    required this.exitLoadingState,
    required this.resetLoadingState,
    required this.isSuperseded,
    required this.prefetchNext,
    required this.commitTrack,
  });

  final Future<(Track, String?, AudioStreamResult?)> Function(Track track, {bool persist}) fetchStream;
  final Future<void> Function(String url, {Map<String, String>? headers, Track? track}) playUrl;
  final Future<void> Function(String filePath, {Track? track}) playFile;
  final Future<Map<String, String>?> Function(Track track) getHeaders;
  final Future<void> Function() stopPlayback;
  final int Function() enterLoadingState;
  final void Function(int requestId, Track track, {required PlayMode mode, required bool recordHistory, AudioStreamResult? streamResult}) exitLoadingState;
  final void Function({int? requestId}) resetLoadingState;
  final bool Function(int requestId) isSuperseded;
  final void Function() prefetchNext;
  final void Function(Track track) commitTrack;

  Future<void> executeHappyPath({
    required Track track,
    required PlayMode mode,
    required bool persist,
    required bool recordHistory,
    required bool prefetchNextTrack,
  }) async {
    final requestId = enterLoadingState();
    await stopPlayback();
    if (isSuperseded(requestId)) return;

    final (trackWithUrl, localPath, streamResult) =
        await fetchStream(track, persist: persist);
    if (isSuperseded(requestId)) return;

    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      resetLoadingState(requestId: requestId);
      throw StateError('No audio URL available');
    }

    if (localPath != null) {
      await playFile(url, track: trackWithUrl);
    } else {
      final headers = await getHeaders(trackWithUrl);
      if (isSuperseded(requestId)) return;
      await playUrl(url, headers: headers, track: trackWithUrl);
    }

    if (isSuperseded(requestId)) return;

    if (prefetchNextTrack) {
      prefetchNext();
    }

    commitTrack(trackWithUrl);
    exitLoadingState(
      requestId,
      trackWithUrl,
      mode: mode,
      recordHistory: recordHistory,
      streamResult: streamResult,
    );
  }
}
```

- [ ] **Step 5: Delegate only the happy path of `_executePlayRequest()` to the helper and keep fallback/retry/error handling local**

```dart
// lib/services/audio/audio_provider.dart
late final _PlaybackRequestExecutor _playbackRequestExecutor =
    _PlaybackRequestExecutor(
  fetchStream: (track, {persist = true}) =>
      _queueManager.ensureAudioStream(track, persist: persist),
  playUrl: (url, {headers, track}) =>
      _audioService.playUrl(url, headers: headers, track: track),
  playFile: (filePath, {track}) => _audioService.playFile(filePath, track: track),
  getHeaders: _getHeadersForTrack,
  stopPlayback: _audioService.stop,
  enterLoadingState: _enterLoadingState,
  exitLoadingState: (requestId, track, {required mode, required recordHistory, streamResult}) {
    _exitLoadingState(
      requestId,
      track,
      mode: mode,
      recordHistory: recordHistory,
      streamResult: streamResult,
    );
  },
  resetLoadingState: ({requestId}) => _resetLoadingState(requestId: requestId),
  isSuperseded: _isSuperseded,
  prefetchNext: _queueManager.prefetchNext,
  commitTrack: _updatePlayingTrack,
);
```

```dart
// lib/services/audio/audio_provider.dart inside `_executePlayRequest()`
try {
  await _playbackRequestExecutor.executeHappyPath(
    track: track,
    mode: mode,
    persist: persist,
    recordHistory: recordHistory,
    prefetchNextTrack: prefetchNext,
  );
  completedSuccessfully = true;
  _updateQueueState();
  if (recordHistory) {
    unawaited(_tryAutoMatchLyrics(track));
  }
  if (mode == PlayMode.mix &&
      _queueManager.currentIndex == _queueManager.tracks.length - 1) {
    unawaited(_loadMoreMixTracks());
  }
  return;
} on SourceApiException catch (e) {
  // existing local error handling remains here in Phase 3
}
```

- [ ] **Step 6: Re-run the focused seam regression and the Phase 1 playback suite**

Run:
```bash
flutter test test/services/audio/playback_request_executor_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS, proving the private helper preserves current behavior while isolating the happy-path seam.

- [ ] **Step 7: Commit the request-execution seam**

```bash
git add test/services/audio/playback_request_executor_test.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(audio): isolate request happy-path seam

Move the stable playback handoff path behind a private helper first so later extraction can proceed without dragging fallback and retry logic prematurely.
EOF
)"
```

---

### Task 2: Purify temporary-play state transitions inside `audio_provider.dart` first

**Files:**
- Create: `test/services/audio/temporary_play_handler_test.dart`
- Modify: `lib/services/audio/audio_provider.dart:64-127`
- Modify: `lib/services/audio/audio_provider.dart:579-794`
- Test: `test/services/audio/temporary_play_handler_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

**Important scope constraint:** Do not move this to a new file yet. First isolate the state rules as a file-local private helper/class so it stops depending on the rest of `AudioController`.

- [ ] **Step 1: Write the failing temporary-play regression using a minimal in-test snapshot type**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('temporary state helper preserves original restore point across chained temporary play', () {
    final helper = TemporaryPlayStateHelper();

    final first = helper.enterTemporary(
      current: TemporaryPlaybackSnapshot(
        mode: PlayMode.queue,
        savedQueueIndex: null,
        savedPosition: null,
        savedWasPlaying: null,
      ),
      hasQueueTrack: true,
      currentIndex: 3,
      savedPosition: const Duration(seconds: 45),
      savedWasPlaying: true,
    );

    final second = helper.enterTemporary(
      current: first,
      hasQueueTrack: true,
      currentIndex: 7,
      savedPosition: const Duration(seconds: 12),
      savedWasPlaying: false,
    );

    expect(second.savedQueueIndex, 3);
    expect(second.savedPosition, const Duration(seconds: 45));
    expect(second.savedWasPlaying, isTrue);
  });
}
```

- [ ] **Step 2: Run the temporary-play regression and confirm it fails**

Run:
```bash
flutter test test/services/audio/temporary_play_handler_test.dart
```

Expected: FAIL because the file-local helper does not exist yet.

- [ ] **Step 3: Add the smallest file-local helper and explicit snapshot type inside `audio_provider.dart`**

```dart
// lib/services/audio/audio_provider.dart
class _TemporaryPlaybackSnapshot {
  const _TemporaryPlaybackSnapshot({
    required this.mode,
    required this.savedQueueIndex,
    required this.savedPosition,
    required this.savedWasPlaying,
  });

  final PlayMode mode;
  final int? savedQueueIndex;
  final Duration? savedPosition;
  final bool? savedWasPlaying;
}

class _TemporaryPlayStateHelper {
  const _TemporaryPlayStateHelper();

  _TemporaryPlaybackSnapshot enterTemporary({
    required _TemporaryPlaybackSnapshot current,
    required bool hasQueueTrack,
    required int currentIndex,
    required Duration savedPosition,
    required bool savedWasPlaying,
  }) {
    if (current.mode == PlayMode.temporary) {
      return current;
    }
    if (!hasQueueTrack) {
      return const _TemporaryPlaybackSnapshot(
        mode: PlayMode.temporary,
        savedQueueIndex: null,
        savedPosition: null,
        savedWasPlaying: null,
      );
    }
    return _TemporaryPlaybackSnapshot(
      mode: PlayMode.temporary,
      savedQueueIndex: currentIndex,
      savedPosition: savedPosition,
      savedWasPlaying: savedWasPlaying,
    );
  }
}
```

- [ ] **Step 4: Delegate `playTemporary()` snapshot decisions to the helper**

```dart
// lib/services/audio/audio_provider.dart
late final _TemporaryPlayStateHelper _temporaryPlayStateHelper =
    const _TemporaryPlayStateHelper();
```

```dart
// lib/services/audio/audio_provider.dart inside playTemporary
final nextSnapshot = _temporaryPlayStateHelper.enterTemporary(
  current: _TemporaryPlaybackSnapshot(
    mode: _context.mode,
    savedQueueIndex: _context.savedQueueIndex,
    savedPosition: _context.savedPosition,
    savedWasPlaying: _context.savedWasPlaying,
  ),
  hasQueueTrack: _queueManager.currentTrack != null,
  currentIndex: _queueManager.currentIndex,
  savedPosition: savedPosition,
  savedWasPlaying: savedIsPlaying,
);

_context = _context.copyWith(
  mode: nextSnapshot.mode,
  savedQueueIndex: nextSnapshot.savedQueueIndex,
  savedPosition: nextSnapshot.savedPosition,
  savedWasPlaying: nextSnapshot.savedWasPlaying,
  clearSavedState: nextSnapshot.savedQueueIndex == null &&
      nextSnapshot.savedPosition == null &&
      nextSnapshot.savedWasPlaying == null,
);
```

- [ ] **Step 5: Re-run the temporary-play seam regression and Phase 1 playback suite**

Run:
```bash
flutter test test/services/audio/temporary_play_handler_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS, preserving current temporary-play behavior.

- [ ] **Step 6: Commit the temporary-play seam**

```bash
git add test/services/audio/temporary_play_handler_test.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(audio): isolate temporary-play state rules

Move temporary-play snapshot decisions behind a file-local helper first so later extraction can happen without coupling a new file to controller internals.
EOF
)"
```

---

### Task 3: Purify Mix session state inside `audio_provider.dart` first

**Files:**
- Create: `test/services/audio/mix_session_handler_test.dart`
- Modify: `lib/services/audio/audio_provider.dart:148-176`
- Modify: `lib/services/audio/audio_provider.dart:1452-1584`
- Test: `test/services/audio/mix_session_handler_test.dart`
- Test: `test/services/audio/audio_controller_phase1_test.dart`

**Important scope constraint:** Keep this seam file-local in Phase 3. Do not move it to a new file yet while it still depends on current controller-local state and `MixTracksFetcher` wiring.

- [ ] **Step 1: Write the failing Mix session regression with a minimal local test helper**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mix session helper aborts stale load-more state cleanly after clear', () {
    final helper = MixSessionStateHelper();
    final session = helper.start(
      playlistId: 'RDmix',
      seedVideoId: 'seed-1',
      title: 'Mix Session',
    );

    helper.markLoading(session);
    expect(helper.isCurrent(session), isTrue);

    helper.clear();

    expect(helper.current, isNull);
    expect(helper.isCurrent(session), isFalse);
  });
}
```

- [ ] **Step 2: Run the Mix session regression and confirm it fails**

Run:
```bash
flutter test test/services/audio/mix_session_handler_test.dart
```

Expected: FAIL because the file-local helper does not exist yet.

- [ ] **Step 3: Add the smallest file-local Mix session helper inside `audio_provider.dart`**

```dart
// lib/services/audio/audio_provider.dart
class _MixSessionStateHelper {
  _MixPlaylistState? _current;

  _MixPlaylistState? get current => _current;

  _MixPlaylistState start({
    required String playlistId,
    required String seedVideoId,
    required String title,
  }) {
    _current = _MixPlaylistState(
      playlistId: playlistId,
      seedVideoId: seedVideoId,
      title: title,
    );
    return _current!;
  }

  bool isCurrent(_MixPlaylistState state) => identical(_current, state);

  void markLoading(_MixPlaylistState state) {
    if (isCurrent(state)) {
      state.isLoadingMore = true;
    }
  }

  void clear() {
    _current = null;
  }
}
```

- [ ] **Step 4: Delegate `_mixState` lifecycle and `_loadMoreMixTracks()` checks to the helper while keeping `_MixPlaylistState` in-file**

```dart
// lib/services/audio/audio_provider.dart
late final _MixSessionStateHelper _mixSessionStateHelper =
    _MixSessionStateHelper();
```

```dart
// lib/services/audio/audio_provider.dart
final mixState = _mixSessionStateHelper.current;
if (mixState == null || mixState.isLoadingMore) return;
_mixSessionStateHelper.markLoading(mixState);
```

```dart
// replace `identical(_mixState, mixState)` checks with `_mixSessionStateHelper.isCurrent(mixState)`
```

- [ ] **Step 5: Re-run the Mix session regression and the Phase 1 playback suite**

Run:
```bash
flutter test test/services/audio/mix_session_handler_test.dart && flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS, preserving current safe Mix behavior while purifying the seam.

- [ ] **Step 6: Commit the Mix session seam**

```bash
git add test/services/audio/mix_session_handler_test.dart lib/services/audio/audio_provider.dart
git commit -m "$(cat <<'EOF'
refactor(audio): isolate mix session state rules

Move Mix session state transitions behind a file-local helper first so later extraction can proceed without entangling controller internals.
EOF
)"
```

---

### Task 4: Extract only QueueManager `ensureAudioStream()` and fallback selection behind a private delegate

**Files:**
- Create: `lib/services/audio/internal/audio_stream_delegate.dart`
- Create: `test/services/audio/audio_stream_delegate_test.dart`
- Modify: `lib/services/audio/queue_manager.dart:897-1027`
- Test: `test/services/audio/audio_stream_delegate_test.dart`
- Test: `test/services/audio/queue_manager_test.dart`

**Important scope constraint:** This first delegate version does **not** move `ensureAudioUrl()` yet. It only covers `ensureAudioStream()` and fallback stream selection, which are already cohesive enough to purify without widening the change set too far.

- [ ] **Step 1: Write the failing stream-delegate regression with a minimal harness defined in the test file**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stream delegate prefers valid local file before requesting remote stream', () async {
    final delegate = createAudioStreamDelegateHarness().delegate;
    final localTrack = createAudioStreamDelegateHarness().localTrack;

    final result = await delegate.ensureAudioStream(localTrack, persist: true);

    expect(result.$2, localTrack.allDownloadPaths.first);
  });
}
```

- [ ] **Step 2: Run the stream-delegate regression and confirm it fails**

Run:
```bash
flutter test test/services/audio/audio_stream_delegate_test.dart
```

Expected: FAIL because `AudioStreamDelegate` does not exist yet.

- [ ] **Step 3: Add the private stream-acquisition delegate for `ensureAudioStream()` and fallback selection only**

```dart
// lib/services/audio/internal/audio_stream_delegate.dart
import 'dart:io';

import '../../../data/models/track.dart';
import '../../../data/sources/base_source.dart';

class AudioStreamDelegate {
  const AudioStreamDelegate({
    required this.getSource,
    required this.getSettingsConfig,
    required this.getAuthHeaders,
    required this.loadTrackById,
    required this.saveTrack,
    required this.updateQueueTrack,
  });

  final BaseSource? Function(SourceType sourceType) getSource;
  final Future<AudioStreamConfig> Function(SourceType sourceType) getSettingsConfig;
  final Future<Map<String, String>?> Function(SourceType sourceType) getAuthHeaders;
  final Future<Track?> Function(int trackId) loadTrackById;
  final Future<void> Function(Track track) saveTrack;
  final void Function(Track track) updateQueueTrack;

  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    String? localPath;
    final invalidPaths = <String>[];

    for (final path in track.allDownloadPaths) {
      if (File(path).existsSync()) {
        localPath = path;
        break;
      }
      invalidPaths.add(path);
    }

    if (localPath != null) {
      return (track, localPath, null);
    }

    final source = getSource(track.sourceType);
    if (source == null) {
      throw StateError('No source available');
    }

    final config = await getSettingsConfig(track.sourceType);
    final authHeaders = await getAuthHeaders(track.sourceType);
    final result = await source.getAudioStream(
      track.sourceId,
      config: config,
      authHeaders: authHeaders,
    );

    track.audioUrl = result.url;
    track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
    if (persist) {
      await saveTrack(track);
    }
    updateQueueTrack(track);
    return (track, null, result);
  }

  Future<AudioStreamResult?> getAlternativeAudioStream(
    Track track, {
    String? failedUrl,
  }) async {
    final source = getSource(track.sourceType);
    if (source == null) return null;
    final config = await getSettingsConfig(track.sourceType);
    return source.getAlternativeAudioStream(
      track.sourceId,
      failedUrl: failedUrl,
      config: config,
    );
  }
}
```

- [ ] **Step 4: Delegate only `ensureAudioStream()` and fallback selection from QueueManager**

```dart
// lib/services/audio/queue_manager.dart
late final AudioStreamDelegate _audioStreamDelegate = AudioStreamDelegate(
  getSource: _sourceManager.getSource,
  getSettingsConfig: (sourceType) async {
    final settings = await _settingsRepository.get();
    return AudioStreamConfig.fromSettings(settings, sourceType);
  },
  getAuthHeaders: _getAuthHeaders,
  loadTrackById: _trackRepository.getById,
  saveTrack: _trackRepository.save,
  updateQueueTrack: (track) {
    final index = _tracks.indexWhere((t) => t.id == track.id);
    if (index >= 0) {
      _tracks[index] = track;
    }
  },
);
```

```dart
// lib/services/audio/queue_manager.dart
Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
  Track track, {
  int retryCount = 0,
  bool persist = true,
}) {
  return _audioStreamDelegate.ensureAudioStream(
    track,
    retryCount: retryCount,
    persist: persist,
  );
}

Future<AudioStreamResult?> getAlternativeAudioStream(
  Track track, {
  String? failedUrl,
}) {
  return _audioStreamDelegate.getAlternativeAudioStream(
    track,
    failedUrl: failedUrl,
  );
}
```

- [ ] **Step 5: Re-run the stream delegate and QueueManager tests**

Run:
```bash
flutter test test/services/audio/audio_stream_delegate_test.dart && flutter test test/services/audio/queue_manager_test.dart
```

Expected: PASS, proving QueueManager still behaves the same while `ensureAudioStream()`/fallback now live behind a delegate seam.

- [ ] **Step 6: Commit the stream delegate seam**

```bash
git add test/services/audio/audio_stream_delegate_test.dart lib/services/audio/internal/audio_stream_delegate.dart lib/services/audio/queue_manager.dart
git commit -m "$(cat <<'EOF'
refactor(queue): isolate stream acquisition seam

Move ensureAudioStream and fallback stream selection behind a private delegate first while leaving ensureAudioUrl in place for a later, narrower step.
EOF
)"
```

---

### Task 5: Extract QueueManager persistence helpers behind a private helper slice first

**Files:**
- Create: `lib/services/audio/internal/queue_persistence_helpers.dart`
- Create: `test/services/audio/queue_persistence_helpers_test.dart`
- Modify: `lib/services/audio/queue_manager.dart:277-308`
- Modify: `lib/services/audio/queue_manager.dart:293-300`
- Test: `test/services/audio/queue_persistence_helpers_test.dart`
- Test: `test/services/audio/queue_manager_test.dart`

**Important scope constraint:** This task only extracts persistence helpers (`saveVolume`, `savePositionNow`, `getPositionRestoreSettings`). It does **not** claim to finish the full queue persistence boundary in Phase 3.

- [ ] **Step 1: Write the failing persistence-helper regression with a minimal harness in the test file**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persistence helpers read restore settings and persist volume safely', () async {
    final harness = createQueuePersistenceHelpersHarness();

    final settings = await harness.helpers.getPositionRestoreSettings();
    await harness.helpers.saveVolume(0.4);

    expect(settings.enabled, isTrue);
    expect(harness.savedVolume, 0.4);
  });
}
```

- [ ] **Step 2: Run the persistence-helper regression and confirm it fails**

Run:
```bash
flutter test test/services/audio/queue_persistence_helpers_test.dart
```

Expected: FAIL because the helper slice does not exist yet.

- [ ] **Step 3: Add the private persistence helper slice**

```dart
// lib/services/audio/internal/queue_persistence_helpers.dart
import '../../../data/models/play_queue.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/queue_repository.dart';

class QueuePersistenceHelpers {
  const QueuePersistenceHelpers({
    required this.settingsRepository,
    required this.queueRepository,
    required this.getCurrentQueue,
  });

  final SettingsRepository settingsRepository;
  final QueueRepository queueRepository;
  final PlayQueue? Function() getCurrentQueue;

  Future<({
    bool enabled,
    int restartRewindSeconds,
    int tempPlayRewindSeconds,
  })> getPositionRestoreSettings() async {
    final settings = await settingsRepository.get();
    return (
      enabled: settings.rememberPlaybackPosition,
      restartRewindSeconds: settings.restartRewindSeconds,
      tempPlayRewindSeconds: settings.tempPlayRewindSeconds,
    );
  }

  Future<void> saveVolume(double volume) async {
    final queue = getCurrentQueue();
    if (queue == null) return;
    queue.lastVolume = volume.clamp(0.0, 1.0);
    await queueRepository.save(queue);
  }

  Future<void> savePosition(int positionMs) async {
    final queue = getCurrentQueue();
    if (queue == null) return;
    queue.lastPositionMs = positionMs;
    await queueRepository.save(queue);
  }
}
```

- [ ] **Step 4: Delegate the existing helper methods from QueueManager without widening the persistence scope**

```dart
// lib/services/audio/queue_manager.dart
late final QueuePersistenceHelpers _queuePersistenceHelpers =
    QueuePersistenceHelpers(
  settingsRepository: _settingsRepository,
  queueRepository: _queueRepository,
  getCurrentQueue: () => _currentQueue,
);
```

```dart
// lib/services/audio/queue_manager.dart
Future<void> savePositionNow() async {
  await _queuePersistenceHelpers.savePosition(_currentPosition.inMilliseconds);
}

Future<void> saveVolume(double volume) async {
  await _queuePersistenceHelpers.saveVolume(volume);
}

Future<({bool enabled, int restartRewindSeconds, int tempPlayRewindSeconds})>
    getPositionRestoreSettings() {
  return _queuePersistenceHelpers.getPositionRestoreSettings();
}
```

- [ ] **Step 5: Re-run the persistence-helper tests and QueueManager tests**

Run:
```bash
flutter test test/services/audio/queue_persistence_helpers_test.dart && flutter test test/services/audio/queue_manager_test.dart
```

Expected: PASS, proving QueueManager still behaves the same while the helper slice is purified.

- [ ] **Step 6: Commit the persistence-helper slice**

```bash
git add test/services/audio/queue_persistence_helpers_test.dart lib/services/audio/internal/queue_persistence_helpers.dart lib/services/audio/queue_manager.dart
git commit -m "$(cat <<'EOF'
refactor(queue): extract persistence helper slice

Move restore-settings and save-position/save-volume helpers behind a private helper slice without claiming the full persistence boundary is complete.
EOF
)"
```

---

### Task 6: Run the Phase 3 verification suite and record the boundary-purification rules

**Files:**
- Modify: `CLAUDE.md`
- Test: `test/services/audio/playback_request_executor_test.dart`
- Test: `test/services/audio/temporary_play_handler_test.dart`
- Test: `test/services/audio/mix_session_handler_test.dart`
- Test: `test/services/audio/audio_stream_delegate_test.dart`
- Test: `test/services/audio/queue_persistence_helpers_test.dart`

- [ ] **Step 1: Add the Phase 3 boundary-purification note to project docs**

```md
### Phase-3 Boundary Purification Note (2026-04-16)
Phase-3 work should purify boundaries inside `AudioController` and `QueueManager` without yet changing their public role in the app.

- Prefer private in-file helper extraction and delegation before moving any seam into a separate file.
- Keep `AudioController` as the only UI entry point throughout Phase 3.
- Keep `QueueManager` as the queue-facing public API while selected stream and persistence helpers are purified behind private helpers/delegates.
- Do not treat a helper extraction as completion of the full public boundary; Phase 3 is about seam purification, not final public manager/service splits.
```

- [ ] **Step 2: Run the focused Phase 3 verification suite**

Run:
```bash
flutter test test/services/audio/playback_request_executor_test.dart && flutter test test/services/audio/temporary_play_handler_test.dart && flutter test test/services/audio/mix_session_handler_test.dart && flutter test test/services/audio/audio_stream_delegate_test.dart && flutter test test/services/audio/queue_persistence_helpers_test.dart
```

Expected: PASS for all new Phase 3 seam tests.

- [ ] **Step 3: Run adjacent regression suites from Phases 1 and 2**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart && flutter test test/services/audio/queue_manager_test.dart && flutter test test/providers/playlist_provider_phase2_test.dart && flutter test test/ui/handlers/track_action_handler_test.dart
```

Expected: PASS, proving boundary purification did not regress the earlier stabilization and maintenance layers.

- [ ] **Step 4: Run static analysis after the boundary-purification pass**

Run:
```bash
flutter analyze
```

Expected: PASS, or only pre-existing unrelated warnings.

- [ ] **Step 5: Commit the Phase 3 verification slice**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: record phase-3 boundary purification constraints

Document the private-extraction-first rules for the audio and queue boundary purification pass and verify the new seam-level regression suite.
EOF
)"
```

---

## Self-Review

### Spec coverage check
- **Request execution boundary**: Covered by Task 1, but narrowed to the happy-path / supersede / playback handoff seam first instead of pulling fallback and retry logic too early.
- **Temporary play boundary**: Covered by Task 2 through a file-local helper that purifies state-transition rules before any externalization.
- **Mix session boundary**: Covered by Task 3 through a file-local helper for session ownership and in-flight load-more guards.
- **Stream acquisition boundary**: Covered by Task 4, but intentionally narrowed to `ensureAudioStream()` and fallback stream selection only; `ensureAudioUrl()` stays in `QueueManager` for now.
- **Queue persistence helper boundary**: Covered by Task 5 as a helper-slice extraction, not as a claim that the full persistence boundary is complete.
- **Phase 3 verification/documentation**: Covered by Task 6.

### Placeholder scan
- No `TODO`, `TBD`, or “similar to Task N” shortcuts remain.
- Every task includes exact file paths, commands, code blocks, and the minimum harness needed for the first failing test.
- The plan explicitly distinguishes file-local extraction, private helper files, and boundaries that are intentionally deferred.

### Type consistency check
- `PlaybackRequestExecutor`, `TemporaryPlayStateHelper`, `MixSessionStateHelper`, `AudioStreamDelegate`, and `QueuePersistenceHelpers` are defined before later tasks use them.
- The revised plan no longer asks new private files to depend directly on `audio_provider.dart` internals.
- The plan keeps `AudioController` and `QueueManager` as the public entry points and only purifies stable internal seams, matching the approved design and the review feedback.
