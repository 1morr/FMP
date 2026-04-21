# FMP Phase 3 Boundary Purification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Purify the remaining internal audio-layer boundaries so `AudioController` stays the UI entry point, `QueueManager` stays the queue-facing API, and stream/request/persistence/runtime-truth responsibilities stop leaking across those seams.

**Architecture:** Phase 3 no longer invents the helper seams — the repo already has `AudioStreamManager`, `QueuePersistenceManager`, `PlaybackRequestExecutor`, `TemporaryPlayHandler`, and `MixPlaylistHandler`. This plan uses those existing seams and tightens ownership around them: remove the hidden reverse mutation path from stream logic back into `QueueManager`, consolidate stream-selection truth under `AudioStreamManager`, centralize `AudioController` playback-transition orchestration, align mix-mode runtime ownership, and normalize audio runtime settings selectors without changing public roles.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, Flutter test

---

## File map

### Primary production files
- Modify: `lib/services/audio/queue_manager.dart` — remove the long-lived stream-to-queue updater attachment and keep queue mutation ownership explicit.
- Modify: `lib/services/audio/audio_stream_manager.dart` — become the single runtime owner for stream refresh / fallback / header / local-file validity behavior.
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart` — keep delegate behavior aligned with the new stream-owner contract.
- Modify: `lib/services/audio/playback_request_executor.dart` — reduce it to request execution over an already-owned stream policy boundary.
- Modify: `lib/services/audio/audio_provider.dart` — keep `AudioController` as UI entry but centralize playback-transition orchestration and mix ownership projection.
- Modify: `lib/services/audio/temporary_play_handler.dart` — support the transition cleanup required by the centralized playback flow.
- Modify: `lib/services/audio/mix_playlist_handler.dart` — become the canonical in-memory active mix session holder.
- Modify: `lib/services/audio/queue_persistence_manager.dart` — remain the canonical persisted queue/mix/position state holder, with runtime selector cleanup.
- Modify: `lib/data/models/settings.dart` — only if needed to support clearer runtime settings selectors without changing stored truth.
- Modify: `lib/providers/playback_settings_provider.dart` — only if needed to align provider-facing runtime selector usage with the new audio truth boundary.

### Primary test files
- Modify: `test/services/audio/queue_manager_test.dart` — cover queue mutation ownership after removing the reverse stream mutation path.
- Modify: `test/services/audio/audio_stream_manager_test.dart` — cover stream policy ownership and fallback/header behavior.
- Modify: `test/services/audio/playback_request_executor_test.dart` — verify executor stays focused on request execution and supersession.
- Modify: `test/services/audio/temporary_play_handler_test.dart` — protect temporary-play restore planning under the new transition flow.
- Modify: `test/services/audio/queue_persistence_manager_test.dart` — cover persisted queue/mix/position ownership and selector behavior.
- Modify or create targeted audio controller regression tests only where the above seam changes require end-to-end confirmation.

### Docs to re-check while implementing
- Read: `docs/superpowers/specs/2026-04-21-fmp-phase3-boundary-purification-design.md`
- Re-check: `CLAUDE.md` Phase-3 / Phase-4 audio boundary notes after implementation
- Update only if implementation materially changes the documented boundary contract: `CLAUDE.md`

---

### Task 1: Remove the QueueManager ← AudioStreamManager reverse mutation path

**Files:**
- Modify: `lib/services/audio/queue_manager.dart`
- Modify: `lib/services/audio/audio_stream_manager.dart`
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart`
- Modify: `test/services/audio/queue_manager_test.dart`
- Modify: `test/services/audio/audio_stream_manager_test.dart`

- [ ] **Step 1: Write the failing queue/stream ownership tests**

Add focused tests proving queue state is no longer updated through a hidden long-lived stream callback, and that refreshed tracks are applied only through explicit caller-owned flow.

```dart
test('audio stream manager no longer attaches a queue-owned track updater', () {
  final source = File(
    'lib/services/audio/queue_manager.dart',
  ).readAsStringSync();

  expect(source.contains('attachQueueTrackUpdater('), isFalse);
});

test('audio stream manager delegates do not capture a queue updater callback', () {
  final source = File(
    'lib/services/audio/audio_stream_manager.dart',
  ).readAsStringSync();

  expect(source.contains('void Function(Track updatedTrack)? _queueTrackUpdater'),
      isFalse);
});
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:
```bash
flutter test test/services/audio/queue_manager_test.dart
```

Expected: FAIL because `QueueManager` still calls `attachQueueTrackUpdater(...)` today.

- [ ] **Step 3: Remove the reverse attachment from QueueManager**

Delete the constructor-time callback hookup so stream logic no longer owns a hidden path back into queue mutation.

```dart
QueueManager({
  required QueueRepository queueRepository,
  required TrackRepository trackRepository,
  required QueuePersistenceManager queuePersistenceManager,
})  : _queueRepository = queueRepository,
      _trackRepository = trackRepository,
      _queuePersistenceManager = queuePersistenceManager;
```

- [ ] **Step 4: Remove queue-updater storage from AudioStreamManager**

Refactor `AudioStreamManager` so it no longer stores or exposes a queue track updater callback.

```dart
AudioStreamManager({
  AudioStreamDelegate? delegate,
  TrackRepository? trackRepository,
  SettingsRepository? settingsRepository,
  SourceManager? sourceManager,
  BilibiliAccountService? bilibiliAccountService,
  YouTubeAccountService? youtubeAccountService,
  NeteaseAccountService? neteaseAccountService,
})  : _trackRepository = trackRepository,
      _settingsRepository = settingsRepository,
      _sourceManager = sourceManager,
      _bilibiliAccountService = bilibiliAccountService,
      _youtubeAccountService = youtubeAccountService,
      _neteaseAccountService = neteaseAccountService {
  _delegate = delegate ??
      AudioStreamDelegate(
        trackRepository: trackRepository!,
        settingsRepository: settingsRepository!,
        sourceManager: sourceManager!,
        getAuthHeaders: (sourceType) => buildAuthHeaders(
          sourceType,
          bilibiliAccountService: bilibiliAccountService,
          youtubeAccountService: youtubeAccountService,
          neteaseAccountService: neteaseAccountService,
        ),
      );
}
```

- [ ] **Step 5: Update the delegate contract so it stops calling back into queue state**

Remove delegate usage of `updateQueueTrack` and keep persistence local to repository writes.

```dart
AudioStreamDelegate({
  required TrackRepository trackRepository,
  required SettingsRepository settingsRepository,
  required SourceManager sourceManager,
  required Future<Map<String, String>?> Function(SourceType sourceType)
      getAuthHeaders,
})  : _trackRepository = trackRepository,
      _settingsRepository = settingsRepository,
      _sourceManager = sourceManager,
      _getAuthHeaders = getAuthHeaders;
```

- [ ] **Step 6: Re-run the focused queue/stream tests**

Run:
```bash
flutter test test/services/audio/queue_manager_test.dart
```

Expected: PASS.

Then run:
```bash
flutter test test/services/audio/audio_stream_manager_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the reverse-dependency removal**

```bash
git add lib/services/audio/queue_manager.dart lib/services/audio/audio_stream_manager.dart lib/services/audio/internal/audio_stream_delegate.dart test/services/audio/queue_manager_test.dart test/services/audio/audio_stream_manager_test.dart
git commit -m "refactor(audio): remove hidden queue stream backchannel"
```

---

### Task 2: Make AudioStreamManager the single owner of stream-selection policy

**Files:**
- Modify: `lib/services/audio/audio_stream_manager.dart`
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart`
- Modify: `lib/services/audio/playback_request_executor.dart`
- Modify: `test/services/audio/audio_stream_manager_test.dart`
- Modify: `test/services/audio/playback_request_executor_test.dart`

- [ ] **Step 1: Write the failing stream-ownership tests**

Add tests that prove stream-selection truth lives under `AudioStreamManager` and that `PlaybackRequestExecutor` does not re-own fallback/header policy.

```dart
test('playback request executor only executes using resolved stream access', () {
  final source = File(
    'lib/services/audio/playback_request_executor.dart',
  ).readAsStringSync();

  expect(source.contains('getAlternativeAudioStream('), isFalse);
  expect(source.contains('buildAuthHeaders('), isFalse);
});

test('audio stream manager owns playback header lookup', () {
  final source = File(
    'lib/services/audio/audio_stream_manager.dart',
  ).readAsStringSync();

  expect(source.contains('Future<Map<String, String>?> getPlaybackHeaders('),
      isTrue);
});
```

- [ ] **Step 2: Run the focused tests and confirm they fail where ownership still leaks**

Run:
```bash
flutter test test/services/audio/playback_request_executor_test.dart
```

Expected: FAIL because current code still reflects the pre-purified ownership split.

- [ ] **Step 3: Consolidate stream policy inside AudioStreamManager**

Move the remaining refresh / local-file validity / header / alternative-stream policy under the stream manager boundary.

```dart
abstract class PlaybackRequestStreamAccess {
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  });

  Future<Map<String, String>?> getPlaybackHeaders(Track track);
  Future<void> prefetchTrack(Track track);
}
```

Ensure the delegate remains the only place that knows how to derive fallback behavior from sources/settings.

- [ ] **Step 4: Keep PlaybackRequestExecutor execution-only**

Preserve executor responsibility as “play one resolved request and honor supersession,” not “decide stream policy.”

```dart
final (trackWithUrl, localPath, streamResult) =
    await _audioStreamManager.ensureAudioStream(track, persist: persist);

final url = localPath ?? trackWithUrl.audioUrl;
if (localPath != null) {
  await _audioService.playFile(url, track: trackWithUrl);
} else {
  final headers = await _audioStreamManager.getPlaybackHeaders(trackWithUrl);
  await _audioService.playUrl(url, headers: headers, track: trackWithUrl);
}
```

- [ ] **Step 5: Re-run the focused stream-policy tests**

Run:
```bash
flutter test test/services/audio/audio_stream_manager_test.dart
```

Expected: PASS.

Then run:
```bash
flutter test test/services/audio/playback_request_executor_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the stream-policy consolidation**

```bash
git add lib/services/audio/audio_stream_manager.dart lib/services/audio/internal/audio_stream_delegate.dart lib/services/audio/playback_request_executor.dart test/services/audio/audio_stream_manager_test.dart test/services/audio/playback_request_executor_test.dart
git commit -m "refactor(audio): centralize stream selection policy"
```

---

### Task 3: Centralize AudioController playback-transition orchestration

**Files:**
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `lib/services/audio/temporary_play_handler.dart`
- Modify: `lib/services/audio/playback_request_executor.dart`
- Modify: `test/services/audio/temporary_play_handler_test.dart`
- Modify: `test/services/audio/playback_request_executor_test.dart`

- [ ] **Step 1: Write the failing transition-orchestration tests**

Add tests or source-boundary assertions showing the restore/temporary transition logic still lives in too many controller methods.

```dart
test('temporary play restore planning stays in the handler seam', () {
  final source = File(
    'lib/services/audio/temporary_play_handler.dart',
  ).readAsStringSync();

  expect(source.contains('RestorePlaybackPlan'), isTrue);
});

test('audio controller does not duplicate restore plan calculation outside handler', () {
  final source = File(
    'lib/services/audio/audio_provider.dart',
  ).readAsStringSync();

  expect(source.contains('savedPosition - Duration('), isFalse);
});
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

Run:
```bash
flutter test test/services/audio/temporary_play_handler_test.dart
```

Expected: FAIL because the controller still owns part of the restore transition flow.

- [ ] **Step 3: Introduce one controller-internal transition seam**

Refactor the controller so temporary restore and queue restore execute through one internal transition pathway instead of ad hoc branches.

```dart
Future<void> _runPlaybackTransition(_PlaybackTransition transition) async {
  switch (transition) {
    case _RestoreSavedQueueTransition():
      await _restoreQueuePlayback(
        savedIndex: transition.savedIndex,
        savedPosition: transition.savedPosition,
        savedWasPlaying: transition.savedWasPlaying,
        rewindSeconds: transition.rewindSeconds,
        debugLabel: transition.debugLabel,
        clearSavedState: transition.clearSavedState,
      );
  }
}
```

Keep it private and internal-only.

- [ ] **Step 4: Push restore-plan logic fully into TemporaryPlayHandler**

Make `TemporaryPlayHandler` the only place that decides restore-plan shape.

```dart
final restorePlan = _temporaryPlayHandler.buildRestorePlan(
  state: TemporaryPlaybackState(
    savedQueueIndex: _context.savedQueueIndex,
    savedPosition: _context.savedPosition,
    savedWasPlaying: _context.savedWasPlaying,
  ),
  rememberPosition: positionSettings.enabled,
  rewindSeconds: positionSettings.tempPlayRewindSeconds,
);
```

Avoid any duplicate rewind/restore derivation outside the handler seam.

- [ ] **Step 5: Re-run the focused transition tests**

Run:
```bash
flutter test test/services/audio/temporary_play_handler_test.dart
```

Expected: PASS.

Then run:
```bash
flutter test test/services/audio/playback_request_executor_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the transition orchestration cleanup**

```bash
git add lib/services/audio/audio_provider.dart lib/services/audio/temporary_play_handler.dart lib/services/audio/playback_request_executor.dart test/services/audio/temporary_play_handler_test.dart test/services/audio/playback_request_executor_test.dart
git commit -m "refactor(audio): centralize playback transition orchestration"
```

---

### Task 4: Consolidate mix-mode runtime ownership

**Files:**
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `lib/services/audio/mix_playlist_handler.dart`
- Modify: `lib/services/audio/queue_manager.dart`
- Modify: `lib/services/audio/queue_persistence_manager.dart`
- Modify: `test/services/audio/audio_controller_mix_boundary_test.dart`
- Modify: `test/services/audio/queue_persistence_manager_test.dart`

- [ ] **Step 1: Write the failing mix-ownership tests**

Add tests that pin active mix session ownership to `MixPlaylistHandler` and persisted mix metadata ownership to `QueuePersistenceManager`.

```dart
test('mix playlist handler owns the active in-memory mix session', () {
  final source = File(
    'lib/services/audio/mix_playlist_handler.dart',
  ).readAsStringSync();

  expect(source.contains('class MixPlaylistSession'), isTrue);
  expect(source.contains('MixPlaylistSession? _current'), isTrue);
});

test('queue persistence manager owns persisted mix metadata writes', () {
  final source = File(
    'lib/services/audio/queue_persistence_manager.dart',
  ).readAsStringSync();

  expect(source.contains('Future<void> setMixMode('), isTrue);
});
```

- [ ] **Step 2: Run the focused tests and confirm they fail where ownership still overlaps**

Run:
```bash
flutter test test/services/audio/audio_controller_mix_boundary_test.dart
```

Expected: FAIL because mix ownership is still partially projected from multiple places.

- [ ] **Step 3: Keep persisted mix metadata in queue persistence only**

Make `QueueManager` delegate persisted mix writes to the persistence manager without re-owning that state.

```dart
Future<void> setMixMode({
  required bool enabled,
  String? playlistId,
  String? seedVideoId,
  String? title,
}) async {
  await _queuePersistenceManager.setMixMode(
    queue: _currentQueue,
    enabled: enabled,
    playlistId: playlistId,
    seedVideoId: seedVideoId,
    title: title,
  );
}
```

- [ ] **Step 4: Keep active mix runtime state in MixPlaylistHandler only**

Ensure controller logic treats `MixPlaylistHandler.current` as the in-memory active mix session source of truth.

```dart
final mixState = _mixPlaylistHandler.start(
  playlistId: playlistId,
  seedVideoId: seedVideoId,
  title: title,
);
mixState.addSeenVideoIds(tracks.map((t) => t.sourceId));
```

Project into `PlayerState`, but do not duplicate ownership.

- [ ] **Step 5: Re-run the focused mix tests**

Run:
```bash
flutter test test/services/audio/audio_controller_mix_boundary_test.dart
```

Expected: PASS.

Then run:
```bash
flutter test test/services/audio/queue_persistence_manager_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the mix-ownership consolidation**

```bash
git add lib/services/audio/audio_provider.dart lib/services/audio/mix_playlist_handler.dart lib/services/audio/queue_manager.dart lib/services/audio/queue_persistence_manager.dart test/services/audio/audio_controller_mix_boundary_test.dart test/services/audio/queue_persistence_manager_test.dart
git commit -m "refactor(audio): consolidate mix runtime ownership"
```

---

### Task 5: Normalize audio runtime settings selectors

**Files:**
- Modify: `lib/services/audio/audio_provider.dart`
- Modify: `lib/services/audio/audio_stream_manager.dart`
- Modify: `lib/services/audio/queue_persistence_manager.dart`
- Modify: `lib/providers/playback_settings_provider.dart` (only if needed)
- Modify: `test/services/audio/audio_stream_manager_test.dart`
- Modify: `test/services/audio/queue_persistence_manager_test.dart`

- [ ] **Step 1: Write the failing runtime-selector tests**

Add tests that pin one runtime selector path for position-restore and auth-for-play derivation.

```dart
test('queue persistence manager owns playback position restore selectors', () {
  final source = File(
    'lib/services/audio/queue_persistence_manager.dart',
  ).readAsStringSync();

  expect(source.contains('getPositionRestoreSettings()'), isTrue);
});

test('audio stream manager derives auth-for-play behavior through one settings path', () {
  final source = File(
    'lib/services/audio/audio_stream_manager.dart',
  ).readAsStringSync();

  expect(source.contains('settings.useAuthForPlay(track.sourceType)'), isTrue);
});
```

- [ ] **Step 2: Run the focused selector tests and confirm they fail where runtime derivation still drifts**

Run:
```bash
flutter test test/services/audio/queue_persistence_manager_test.dart
```

Expected: FAIL because selector behavior is not yet normalized around the intended seams.

- [ ] **Step 3: Introduce one internal runtime settings snapshot/adapter**

Keep storage unchanged, but normalize runtime derivation.

```dart
class AudioRuntimeSettings {
  const AudioRuntimeSettings({
    required this.rememberPlaybackPosition,
    required this.restartRewindSeconds,
    required this.tempPlayRewindSeconds,
  });

  final bool rememberPlaybackPosition;
  final int restartRewindSeconds;
  final int tempPlayRewindSeconds;
}
```

Use this internally where it removes repeated selector logic; do not broaden beyond audio-boundary needs.

- [ ] **Step 4: Route restore/auth selector reads through one place per concern**

For position restore, keep `QueuePersistenceManager` as the selector source. For stream auth/runtime playback behavior, keep `AudioStreamManager` as the selector source.

```dart
final positionSettings = await _queuePersistenceManager.getPositionRestoreSettings();
final settings = await _requireSettingsRepository().get();
if (settings.useAuthForPlay(track.sourceType)) {
  authHeaders = await buildAuthHeaders(...);
}
```

Remove duplicated concern-specific selector derivation where possible.

- [ ] **Step 5: Re-run the focused selector tests**

Run:
```bash
flutter test test/services/audio/queue_persistence_manager_test.dart
```

Expected: PASS.

Then run:
```bash
flutter test test/services/audio/audio_stream_manager_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the runtime-selector normalization**

```bash
git add lib/services/audio/audio_provider.dart lib/services/audio/audio_stream_manager.dart lib/services/audio/queue_persistence_manager.dart lib/providers/playback_settings_provider.dart test/services/audio/audio_stream_manager_test.dart test/services/audio/queue_persistence_manager_test.dart
git commit -m "refactor(audio): normalize runtime settings selectors"
```

---

## Self-review notes

- **Spec coverage:** The plan fits the approved design and the repo’s current state. It does not pretend the helper seams still need to be invented; instead it treats them as existing seams whose ownership needs tightening. It covers both `AudioController` and `QueueManager`, plus the directly related runtime truth-source cleanup.
- **Placeholder scan:** No `TBD`, `TODO`, “write tests later,” or vague “add appropriate handling” placeholders remain. Every task names exact files, concrete verification commands, and commit steps.
- **Type consistency:** The plan consistently treats `AudioController` as the UI-only public entry, `QueueManager` as the queue-facing public API, `AudioStreamManager` as the stream-policy owner, `QueuePersistenceManager` as the persistence selector owner, `TemporaryPlayHandler` as the restore-plan seam, and `MixPlaylistHandler` as the active in-memory mix-session holder.
