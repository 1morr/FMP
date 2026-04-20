# FMP Phase 1 Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a stable Phase 1 baseline for FMP by fixing the highest-risk runtime defects and data-consistency issues from the review documents, while adding only the minimum regression tests directly tied to those fixes.

**Architecture:** Phase 1 is intentionally narrow. It fixes playback/platform control ownership, NetEase URL-expiry semantics, download resume correctness, queue/shuffle consistency, migration/backup/default-value truth-source issues, and the smallest set of tests needed to keep those fixes from regressing. It does **not** include performance tuning, UI-wide boundary cleanup, or directory restructuring.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, Dio/HttpClient, audio_service, media_kit, just_audio, Flutter test

---

## File map

### Primary production files
- Modify: `lib/services/audio/audio_provider.dart` — restore-flow superseded check; optional audio handler/SMTC callback restoration seam if kept in AudioController
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart` — remove NetEase 1-hour hardcoded URL expiry in playback stream fetch path
- Modify: `lib/services/radio/radio_controller.dart` — return global media-control ownership to music after radio playback ends / returns to music
- Modify: `lib/services/download/download_service.dart` — fix resume behavior when server ignores `Range`; remove NetEase 1-hour hardcoded URL expiry in download stream fetch path
- Modify: `lib/services/audio/queue_manager.dart` — either maintain `_shuffleOrder` on move or make move behavior safe under shuffle constraints
- Modify: `lib/ui/pages/queue/queue_page.dart` — disable drag reorder under shuffle if Phase 1 takes the simpler UX-safe path
- Modify: `lib/data/repositories/track_repository.dart` — preserve `playlistName` when cleaning invalid download paths
- Modify: `lib/providers/database_provider.dart` — add missing migration fixes and shared bootstrap entry
- Modify: `lib/ui/pages/settings/developer_options_page.dart` — make reset-all-data reuse shared bootstrap logic
- Modify: `lib/services/backup/backup_data.dart` — align `SettingsBackup` fields/defaults with current `Settings`
- Modify: `lib/services/backup/backup_service.dart` — export/import the added settings fields and fix restore fallbacks
- Modify: `lib/ui/pages/settings/account_management_page.dart` — remove page-entry settings writeback side effect
- Modify: `lib/services/account/netease_account_service.dart` — tighten login success boundary to validated account status
- Modify: `lib/ui/pages/settings/netease_login_page.dart` — wait for actual validation before reporting login success
- Modify: `lib/data/sources/base_source.dart` — if needed, extend `AudioStreamResult` with expiry metadata for source-truth URL validity
- Modify: `lib/data/sources/netease_source.dart` — expose/propagate the real 16-minute expiry through the source result if using source-truth expiry metadata

### Primary test files
- Modify: `test/services/audio/audio_controller_phase1_test.dart` — add regression coverage for restore supersession / handler ownership if testable through current seams
- Modify: `test/services/download/download_service_phase1_test.dart` — add resume-200-OK corruption regression coverage
- Modify: `test/providers/database_migration_test.dart` — add migration coverage for missing fields and bootstrap consistency
- Create: `test/services/backup/backup_settings_phase1_test.dart` — verify settings backup/export/import field coverage and fallback defaults
- Create or modify: `test/services/audio/queue_manager_phase1_shuffle_test.dart` — verify shuffle drag-reorder behavior, either disabled or internally remapped
- Create or modify: `test/services/account/netease_account_phase1_test.dart` — verify invalid `MUSIC_U` is not treated as successful login if current test seams permit

### Docs to re-check while implementing
- Read: `docs/review/summary_review.md`
- Read: `docs/review/stability_review.md`
- Read: `docs/review/database_review.md`
- Read: `docs/review/platform_review.md`
- Read: `docs/review/testing_review.md`
- Read: `docs/superpowers/specs/2026-04-20-fmp-refactor-roadmap-design.md`
- Update only if behavior or architecture expectations materially change: `CLAUDE.md`

---

### Task 1: Fix NetEase URL expiry truth source

**Files:**
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart:58-87`
- Modify: `lib/services/download/download_service.dart:604-619`
- Modify: `lib/data/sources/base_source.dart:45-74`
- Modify: `lib/data/sources/netease_source.dart:25-28,104-170`
- Test: `test/services/audio/audio_controller_phase1_test.dart`
- Test: `test/services/download/download_service_phase1_test.dart`

- [ ] **Step 1: Write the failing test for playback-side URL expiry semantics**

Add a focused test to `test/services/audio/audio_controller_phase1_test.dart` that proves NetEase URLs are not treated as one-hour valid. Use a fake NetEase track and assert the stored expiry is aligned with the source-defined window, not an hour.

```dart
test('NetEase stream fetch does not stamp a one-hour expiry', () async {
  final track = _track('netease-expiry', title: 'Netease Expiry')
    ..sourceType = SourceType.netease;

  await controller.playTrack(track);

  final savedTrack = await TrackRepository(isar).getById(track.id);
  expect(savedTrack, isNotNull);
  expect(savedTrack!.audioUrlExpiry, isNotNull);

  final ttl = savedTrack.audioUrlExpiry!.difference(DateTime.now());
  expect(ttl.inMinutes <= 20, isTrue);
});
```

- [ ] **Step 2: Run the focused audio test and confirm it fails for the right reason**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart --plain-name "NetEase stream fetch does not stamp a one-hour expiry"
```

Expected: FAIL because current code sets `DateTime.now().add(const Duration(hours: 1))` in `audio_stream_delegate.dart`.

- [ ] **Step 3: Write the failing test for download-side URL expiry semantics**

Add a focused test to `test/services/download/download_service_phase1_test.dart` that verifies a NetEase download path does not save one-hour expiry metadata after fetching a stream.

```dart
test('NetEase download stream fetch does not stamp a one-hour expiry', () async {
  final track = Track()
    ..sourceId = 'netease-download-expiry'
    ..sourceType = SourceType.netease
    ..title = 'Netease Download Expiry'
    ..artist = 'Test Artist'
    ..createdAt = DateTime.now();
  await trackRepository.save(track);

  final playlist = Playlist()..name = 'Phase1';
  final task = await downloadRepository.saveTask(
    DownloadTask()
      ..trackId = track.id
      ..playlistId = playlist.id
      ..playlistName = playlist.name
      ..status = DownloadStatus.downloading
      ..createdAt = DateTime.now(),
  );

  final service = DownloadService(
    downloadRepository: downloadRepository,
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
    sourceManager: _SingleSourceManager(_StaticAudioSource('http://127.0.0.1:1/audio.m4a')),
  );

  await service.debugPrepareStreamForTesting(task.id);

  final savedTrack = await trackRepository.getById(track.id);
  expect(savedTrack, isNotNull);
  final ttl = savedTrack!.audioUrlExpiry!.difference(DateTime.now());
  expect(ttl.inMinutes <= 20, isTrue);

  service.dispose();
});
```

- [ ] **Step 4: Run the focused download test and confirm it fails**

Run:
```bash
flutter test test/services/download/download_service_phase1_test.dart --plain-name "NetEase download stream fetch does not stamp a one-hour expiry"
```

Expected: FAIL because current code sets one hour in `download_service.dart`.

- [ ] **Step 5: Implement minimal source-truth expiry propagation**

Update `AudioStreamResult` in `lib/data/sources/base_source.dart` to carry optional expiry metadata, and use it in `NeteaseSource.getAudioStream()`.

```dart
class AudioStreamResult {
  final String url;
  final int? bitrate;
  final String? container;
  final String? codec;
  final StreamType streamType;
  final Duration? validity;

  const AudioStreamResult({
    required this.url,
    this.bitrate,
    this.container,
    this.codec,
    required this.streamType,
    this.validity,
  });
}
```

In `lib/data/sources/netease_source.dart`:

```dart
return AudioStreamResult(
  url: url,
  bitrate: br,
  container: type ?? 'mp3',
  codec: _mapCodec(type),
  streamType: StreamType.audioOnly,
  validity: _audioUrlExpiry,
);
```

- [ ] **Step 6: Replace the one-hour expiry stamping in playback and download paths**

In `lib/services/audio/internal/audio_stream_delegate.dart`, replace:

```dart
track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
```

with:

```dart
track.audioUrlExpiry = streamResult.validity != null
    ? DateTime.now().add(streamResult.validity!)
    : DateTime.now().add(const Duration(hours: 1));
```

In `lib/services/download/download_service.dart`, replace:

```dart
track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
```

with:

```dart
track.audioUrlExpiry = streamResult.validity != null
    ? DateTime.now().add(streamResult.validity!)
    : DateTime.now().add(const Duration(hours: 1));
```

- [ ] **Step 7: Re-run the two focused tests and confirm they pass**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart --plain-name "NetEase stream fetch does not stamp a one-hour expiry" && flutter test test/services/download/download_service_phase1_test.dart --plain-name "NetEase download stream fetch does not stamp a one-hour expiry"
```

Expected: PASS.

- [ ] **Step 8: Commit the expiry fix**

```bash
git add lib/data/sources/base_source.dart lib/data/sources/netease_source.dart lib/services/audio/internal/audio_stream_delegate.dart lib/services/download/download_service.dart test/services/audio/audio_controller_phase1_test.dart test/services/download/download_service_phase1_test.dart
git commit -m "fix(netease): honor source-defined audio URL expiry"
```

---

### Task 2: Fix global media-control ownership handoff between radio and music

**Files:**
- Modify: `lib/services/audio/audio_provider.dart:1277-1317`
- Modify: `lib/services/radio/radio_controller.dart:287-342,498-579`
- Test: `test/services/audio/audio_controller_phase1_test.dart`
- Test: `test/services/radio/radio_controller_phase1_test.dart`

- [ ] **Step 1: Write a failing regression test for callback ownership restoration**

Create `test/services/radio/radio_controller_phase1_test.dart` with a focused test that simulates radio taking ownership and then returning to music. Assert the global callbacks point back to music handlers afterward.

```dart
test('returning from radio restores music media-control callbacks', () async {
  final audioController = ref.read(audioControllerProvider.notifier);
  final radioController = RadioController(
    ref: ref,
    repository: repository,
    radioSource: radioSource,
    audioService: fakeAudioService,
  );

  audioController.initialize();
  final initialOnPlay = audioHandler.onPlay;
  final initialOnPause = audioHandler.onPause;

  await radioController.play(station);
  expect(identical(audioHandler.onPlay, radioController.resume), isTrue);
  expect(identical(audioHandler.onPause, radioController.pause), isTrue);

  await radioController.returnToMusic();
  expect(audioHandler.onPlay, same(initialOnPlay));
  expect(audioHandler.onPause, same(initialOnPause));
});
```

- [ ] **Step 2: Run the focused radio test and confirm it fails**

Run:
```bash
flutter test test/services/radio/radio_controller_phase1_test.dart --plain-name "returning from radio restores music media-control callbacks"
```

Expected: FAIL because radio clears state but does not restore music bindings.

- [ ] **Step 3: Add a minimal rebind seam in AudioController**

In `lib/services/audio/audio_provider.dart`, add one small public method that only re-applies handler ownership:

```dart
void restoreGlobalMediaControls() {
  _setupAudioHandler();
  _setupWindowsSmtc();
}
```

- [ ] **Step 4: Call the rebind seam after radio relinquishes ownership**

In `lib/services/radio/radio_controller.dart`, after `await stop();` and before/after `returnFromRadio(...)`, restore music-side callback ownership.

```dart
final audioController = _ref.read(audioControllerProvider.notifier);
audioController.restoreGlobalMediaControls();
await audioController.returnFromRadio(
  savedQueueIndex: savedQueueIndex,
  savedPosition: savedPosition,
  savedWasPlaying: forcePlay || savedWasPlaying,
);
audioController.restoreGlobalMediaControls();
```

Also restore ownership in `stop()` after clearing radio-side platform state if the radio controller is no longer the active owner.

- [ ] **Step 5: Re-run the focused callback test and confirm it passes**

Run:
```bash
flutter test test/services/radio/radio_controller_phase1_test.dart --plain-name "returning from radio restores music media-control callbacks"
```

Expected: PASS.

- [ ] **Step 6: Commit the callback-ownership fix**

```bash
git add lib/services/audio/audio_provider.dart lib/services/radio/radio_controller.dart test/services/radio/radio_controller_phase1_test.dart
git commit -m "fix(radio): restore music media-control ownership after handoff"
```

---

### Task 3: Make resumed downloads safe when servers ignore Range

**Files:**
- Modify: `lib/services/download/download_service.dart:1174-1191`
- Test: `test/services/download/download_service_phase1_test.dart`

- [ ] **Step 1: Write the failing regression test for resume + 200 OK**

Add a test to `test/services/download/download_service_phase1_test.dart` that serves full content with `200 OK` even when `Range` is sent, starts from a partial temp file, and verifies the final file is not corrupted by append.

```dart
test('resume restarts cleanly when server ignores range and returns 200', () async {
  final baseDir = await Directory.systemTemp.createTemp('download_resume_200_');
  addTearDown(() async {
    if (await baseDir.exists()) {
      await baseDir.delete(recursive: true);
    }
  });

  final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 251));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() async => server.close(force: true));
  server.listen((request) async {
    request.response.statusCode = 200;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  });

  final savePath = '${baseDir.path}/audio.m4a';
  final tempPath = '$savePath.downloading';
  final tempFile = File(tempPath);
  await tempFile.writeAsBytes(bytes.sublist(0, 256));

  final params = _IsolateDownloadParams(
    url: 'http://${server.address.address}:${server.port}/audio.m4a',
    savePath: savePath,
    headers: const {},
    sendPort: ReceivePort().sendPort,
    resumePosition: 256,
  );

  await _runIsolateDownloadForTesting(params);

  final finalBytes = await File(savePath).readAsBytes();
  expect(finalBytes, bytes);
});
```

- [ ] **Step 2: Run the focused download test and confirm it fails**

Run:
```bash
flutter test test/services/download/download_service_phase1_test.dart --plain-name "resume restarts cleanly when server ignores range and returns 200"
```

Expected: FAIL because current code appends the whole file onto the partial file.

- [ ] **Step 3: Implement minimal resume-status handling**

In `lib/services/download/download_service.dart`, inside `_isolateDownload`, replace the current response handling with resume-aware status checking.

```dart
final isResume = params.resumePosition > 0;

if (response.statusCode >= 400) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error, 'HTTP ${response.statusCode}'));
  return;
}

if (isResume && response.statusCode == 200) {
  final partialFile = File(params.savePath);
  if (await partialFile.exists()) {
    await partialFile.delete();
  }
}

if (isResume && response.statusCode != 206 && response.statusCode != 200) {
  sendPort.send(_IsolateMessage(_IsolateMessageType.error, 'HTTP ${response.statusCode}'));
  return;
}

final shouldAppend = isResume && response.statusCode == 206;
final file = File(params.savePath);
final sink = file.openWrite(mode: shouldAppend ? FileMode.append : FileMode.write);
final totalBytes = response.contentLength > 0
    ? (shouldAppend ? response.contentLength + params.resumePosition : response.contentLength)
    : -1;
int receivedBytes = shouldAppend ? params.resumePosition : 0;
```

- [ ] **Step 4: Re-run the focused resume test and confirm it passes**

Run:
```bash
flutter test test/services/download/download_service_phase1_test.dart --plain-name "resume restarts cleanly when server ignores range and returns 200"
```

Expected: PASS.

- [ ] **Step 5: Commit the resume fix**

```bash
git add lib/services/download/download_service.dart test/services/download/download_service_phase1_test.dart
git commit -m "fix(download): restart cleanly when resume gets full response"
```

---

### Task 4: Fix shuffle drag-reorder consistency and optimistic reorder rollback

**Files:**
- Modify: `lib/services/audio/queue_manager.dart:592-612`
- Modify: `lib/ui/pages/queue/queue_page.dart:199-220`
- Modify: `lib/ui/pages/radio/radio_page.dart:215-226`
- Modify: `lib/ui/pages/library/library_page.dart:199-217`
- Modify: `lib/services/radio/radio_controller.dart:675-682`
- Modify: `lib/services/library/playlist_service.dart` or related reorder entry if rollback must route through service calls
- Test: `test/services/audio/queue_manager_phase1_shuffle_test.dart`
- Test: `test/ui/pages/radio/radio_page_phase1_test.dart`
- Test: `test/ui/pages/library/library_page_phase1_test.dart`

- [ ] **Step 1: Write the failing queue shuffle regression test**

Create `test/services/audio/queue_manager_phase1_shuffle_test.dart`.

```dart
test('shuffle reorder keeps upcoming order consistent after move', () async {
  await queueManager.playAll([
    _track('a'),
    _track('b'),
    _track('c'),
    _track('d'),
  ]);
  await queueManager.toggleShuffle();

  await queueManager.move(0, 2);

  final upcoming = queueManager.getUpcomingTracks(count: 10);
  expect(upcoming, isNotEmpty);
  expect(
    upcoming.every((track) => queueManager.tracks.any((t) => t.id == track.id)),
    isTrue,
  );
});
```

- [ ] **Step 2: Run the shuffle regression test and confirm failure or inconsistency**

Run:
```bash
flutter test test/services/audio/queue_manager_phase1_shuffle_test.dart
```

Expected: FAIL or expose that reordered queue state does not align with shuffle navigation semantics.

- [ ] **Step 3: Choose the low-risk Phase 1 path: disable drag reorder while shuffle is enabled**

In `lib/ui/pages/queue/queue_page.dart`, gate drag handling under shuffle.

```dart
final isShuffleEnabled = ref.watch(audioControllerProvider.select((s) => s.isShuffleEnabled));

if (isShuffleEnabled) {
  return;
}

ref.read(audioControllerProvider.notifier).moveInQueue(oldIndex, newIndex);
```

Also disable the drag affordance in the queue row when shuffle is enabled.

- [ ] **Step 4: Write the failing optimistic rollback tests for radio and playlist reorder**

Create focused widget/notifier tests that force persistence failure and require old order restoration.

```dart
testWidgets('radio reorder rolls back when persistence fails', (tester) async {
  final oldStations = [station1, station2, station3];
  final failingController = _FailingRadioController(oldStations);

  await tester.pumpWidget(_buildRadioPage(failingController));
  await tester.drag(find.byType(ReorderableWrap).first, const Offset(0, 40));
  await tester.pump();

  expect(failingController.state.stations.map((s) => s.id), [1, 2, 3]);
});
```

- [ ] **Step 5: Run the rollback tests and confirm failure**

Run:
```bash
flutter test test/ui/pages/radio/radio_page_phase1_test.dart && flutter test test/ui/pages/library/library_page_phase1_test.dart
```

Expected: FAIL because current code updates UI optimistically without restoring the previous order on failure.

- [ ] **Step 6: Implement rollback for radio reorder**

In `lib/ui/pages/radio/radio_page.dart`, keep a snapshot and restore it on failure.

```dart
final previousStations = List<RadioStation>.from(stations);
ref.read(radioControllerProvider.notifier).updateStationsOrder(updatedStations);
try {
  final newOrder = updatedStations.map((s) => s.id).toList();
  await ref.read(radioControllerProvider.notifier).reorderStations(newOrder);
} catch (e) {
  ref.read(radioControllerProvider.notifier).updateStationsOrder(previousStations);
  if (context.mounted) {
    ToastService.show(context, t.general.operationFailed(error: '$e'));
  }
}
```

- [ ] **Step 7: Implement rollback for playlist reorder**

In `lib/ui/pages/library/library_page.dart`, keep a snapshot and restore it on failure.

```dart
Future<void> _savePlaylistOrder() async {
  if (_localPlaylists == null) return;

  final previous = List<Playlist>.from(ref.read(playlistListProvider).playlists);
  final service = ref.read(playlistServiceProvider);
  try {
    await service.reorderPlaylists(_localPlaylists!);
  } catch (e) {
    setState(() {
      _localPlaylists = List<Playlist>.from(previous);
    });
    if (mounted) {
      ToastService.show(context, t.general.operationFailed(error: '$e'));
    }
  }
}
```

- [ ] **Step 8: Re-run queue and reorder tests and confirm they pass**

Run:
```bash
flutter test test/services/audio/queue_manager_phase1_shuffle_test.dart && flutter test test/ui/pages/radio/radio_page_phase1_test.dart && flutter test test/ui/pages/library/library_page_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit queue/reorder consistency fixes**

```bash
git add lib/services/audio/queue_manager.dart lib/ui/pages/queue/queue_page.dart lib/ui/pages/radio/radio_page.dart lib/ui/pages/library/library_page.dart test/services/audio/queue_manager_phase1_shuffle_test.dart test/ui/pages/radio/radio_page_phase1_test.dart test/ui/pages/library/library_page_phase1_test.dart
git commit -m "fix(queue): preserve reorder consistency under phase-one constraints"
```

---

### Task 5: Unify bootstrap, migration, backup defaults, and remove page-entry writeback

**Files:**
- Modify: `lib/providers/database_provider.dart:23-131`
- Modify: `lib/ui/pages/settings/developer_options_page.dart:560-573`
- Modify: `lib/services/backup/backup_data.dart:412-559`
- Modify: `lib/services/backup/backup_service.dart:178-210,550-604`
- Modify: `lib/ui/pages/settings/account_management_page.dart:29-43`
- Modify: `lib/data/models/settings.dart:87-184`
- Modify: `lib/data/models/play_queue.dart:27-42`
- Test: `test/providers/database_migration_test.dart`
- Test: `test/services/backup/backup_settings_phase1_test.dart`

- [ ] **Step 1: Write the failing migration tests for missing fields**

Extend `test/providers/database_migration_test.dart`.

```dart
test('migrates rememberPlaybackPosition tempPlayRewindSeconds disabledLyricsSources and lastVolume defaults', () async {
  tempDir = await Directory.systemTemp.createTemp('database_migration_test_');
  isar = await Isar.open(
    [SettingsSchema, PlayQueueSchema],
    directory: tempDir.path,
    name: 'database_migration_test',
  );

  final legacySettings = Settings()
    ..rememberPlaybackPosition = false
    ..tempPlayRewindSeconds = 0
    ..disabledLyricsSources = '';
  final legacyQueue = PlayQueue()..lastVolume = 0.0;

  await isar.writeTxn(() async {
    await isar.settings.put(legacySettings);
    await isar.playQueues.put(legacyQueue);
  });

  await runDatabaseMigrationForTesting(isar);

  final migratedSettings = await isar.settings.get(0);
  final migratedQueue = (await isar.playQueues.where().findAll()).single;

  expect(migratedSettings!.rememberPlaybackPosition, isTrue);
  expect(migratedSettings.tempPlayRewindSeconds, 10);
  expect(migratedSettings.disabledLyricsSources, 'lrclib');
  expect(migratedQueue.lastVolume, 1.0);
});
```

- [ ] **Step 2: Write the failing bootstrap consistency test for reset path**

Add a test that ensures reset-created defaults match bootstrap-created defaults.

```dart
test('reset bootstrap matches initial bootstrap defaults', () async {
  tempDir = await Directory.systemTemp.createTemp('database_migration_test_');
  isar = await Isar.open(
    [SettingsSchema, PlayQueueSchema],
    directory: tempDir.path,
    name: 'database_migration_test',
  );

  await runDatabaseMigrationForTesting(isar);
  final initialSettings = await isar.settings.get(0);

  await isar.writeTxn(() async {
    await isar.clear();
  });

  await runDatabaseMigrationForTesting(isar);
  final resetSettings = await isar.settings.get(0);

  expect(resetSettings!.maxCacheSizeMB, initialSettings!.maxCacheSizeMB);
});
```

- [ ] **Step 3: Run the migration tests and confirm failure**

Run:
```bash
flutter test test/providers/database_migration_test.dart
```

Expected: FAIL because the missing fields are not repaired and reset bootstrap differs from the normal bootstrap path.

- [ ] **Step 4: Implement shared bootstrap and missing migration fixes**

In `lib/providers/database_provider.dart`, extract settings/queue bootstrap to a single helper and add missing field repairs.

```dart
Future<void> _ensureBootstrapDefaults(Isar isar) async {
  var settings = await isar.settings.get(0);
  if (settings == null) {
    settings = Settings();
    if (Platform.isAndroid || Platform.isIOS) {
      settings.maxCacheSizeMB = 16;
    }
    await isar.settings.put(settings);
  }

  final queues = await isar.playQueues.where().findAll();
  if (queues.isEmpty) {
    await isar.playQueues.put(PlayQueue());
  }
}
```

Also add:

```dart
if (!settings.rememberPlaybackPosition) {
  settings.rememberPlaybackPosition = true;
  needsUpdate = true;
}
if (settings.tempPlayRewindSeconds < 1) {
  settings.tempPlayRewindSeconds = 10;
  needsUpdate = true;
}
if (settings.disabledLyricsSources.isEmpty) {
  settings.disabledLyricsSources = 'lrclib';
  needsUpdate = true;
}
```

And for queue defaults:

```dart
for (final queue in queues) {
  if (queue.lastVolume <= 0) {
    queue.lastVolume = 1.0;
    await isar.playQueues.put(queue);
  }
}
```

- [ ] **Step 5: Make reset-all-data reuse shared bootstrap**

In `lib/ui/pages/settings/developer_options_page.dart`, replace manual `Settings()` / `PlayQueue()` recreation with a shared bootstrap call.

```dart
await isar.writeTxn(() async {
  await isar.clear();
});
await runDatabaseMigrationForTesting(isar);
```

- [ ] **Step 6: Remove page-entry auth-for-play writeback**

In `lib/ui/pages/settings/account_management_page.dart`, delete the entire `initState()` + `_ensureAuthSettings()` writeback path.

Remove:

```dart
@override
void initState() {
  super.initState();
  _ensureAuthSettings();
}

Future<void> _ensureAuthSettings() async {
  final settingsRepo = ref.read(settingsRepositoryProvider);
  await settingsRepo.update((s) {
    s.setUseAuthForPlay(SourceType.bilibili, false);
    s.setUseAuthForPlay(SourceType.youtube, false);
    s.setUseAuthForPlay(SourceType.netease, true);
  });
}
```

- [ ] **Step 7: Write the failing backup field-coverage tests**

Create `test/services/backup/backup_settings_phase1_test.dart`.

```dart
test('settings backup round-trips current auth and refresh fields', () async {
  final settings = Settings()
    ..neteaseStreamPriority = 'audioOnly'
    ..useBilibiliAuthForPlay = true
    ..useYoutubeAuthForPlay = true
    ..useNeteaseAuthForPlay = true
    ..rankingRefreshIntervalMinutes = 30
    ..radioRefreshIntervalMinutes = 9
    ..disabledLyricsSources = 'lrclib';

  final backup = SettingsBackup(
    neteaseStreamPriority: settings.neteaseStreamPriority,
    useBilibiliAuthForPlay: settings.useBilibiliAuthForPlay,
    useYoutubeAuthForPlay: settings.useYoutubeAuthForPlay,
    useNeteaseAuthForPlay: settings.useNeteaseAuthForPlay,
    rankingRefreshIntervalMinutes: settings.rankingRefreshIntervalMinutes,
    radioRefreshIntervalMinutes: settings.radioRefreshIntervalMinutes,
    disabledLyricsSources: settings.disabledLyricsSources,
  );

  final restored = SettingsBackup.fromJson(backup.toJson());
  expect(restored.neteaseStreamPriority, 'audioOnly');
  expect(restored.useBilibiliAuthForPlay, isTrue);
  expect(restored.useYoutubeAuthForPlay, isTrue);
  expect(restored.useNeteaseAuthForPlay, isTrue);
  expect(restored.rankingRefreshIntervalMinutes, 30);
  expect(restored.radioRefreshIntervalMinutes, 9);
  expect(restored.disabledLyricsSources, 'lrclib');
});
```

- [ ] **Step 8: Run backup tests and confirm failure**

Run:
```bash
flutter test test/services/backup/backup_settings_phase1_test.dart
```

Expected: FAIL because `SettingsBackup` does not currently contain those fields.

- [ ] **Step 9: Align backup model and restore defaults with current Settings**

In `lib/services/backup/backup_data.dart`, add these fields to `SettingsBackup`:

```dart
final String neteaseStreamPriority;
final bool useBilibiliAuthForPlay;
final bool useYoutubeAuthForPlay;
final bool useNeteaseAuthForPlay;
final int rankingRefreshIntervalMinutes;
final int radioRefreshIntervalMinutes;
```

Constructor defaults should align with current `Settings`:

```dart
this.disabledLyricsSources = 'lrclib',
this.autoMatchLyrics = false,
this.minimizeToTrayOnClose = false,
this.enableGlobalHotkeys = false,
this.neteaseStreamPriority = 'audioOnly',
this.useBilibiliAuthForPlay = false,
this.useYoutubeAuthForPlay = false,
this.useNeteaseAuthForPlay = true,
this.rankingRefreshIntervalMinutes = 60,
this.radioRefreshIntervalMinutes = 5,
```

Update `fromJson()` and `toJson()` accordingly.

In `lib/services/backup/backup_service.dart`, include export/import wiring for all added fields.

- [ ] **Step 10: Re-run migration and backup tests and confirm they pass**

Run:
```bash
flutter test test/providers/database_migration_test.dart && flutter test test/services/backup/backup_settings_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 11: Commit the data-consistency fixes**

```bash
git add lib/providers/database_provider.dart lib/ui/pages/settings/developer_options_page.dart lib/services/backup/backup_data.dart lib/services/backup/backup_service.dart lib/ui/pages/settings/account_management_page.dart test/providers/database_migration_test.dart test/services/backup/backup_settings_phase1_test.dart
git commit -m "fix(data): align phase-one migration and backup defaults"
```

---

### Task 6: Tighten NetEase login success boundary

**Files:**
- Modify: `lib/services/account/netease_account_service.dart:60-89,331-356`
- Modify: `lib/ui/pages/settings/netease_login_page.dart:153-163,257-265`
- Test: `test/services/account/netease_account_phase1_test.dart`

- [ ] **Step 1: Write the failing login-boundary test**

Create `test/services/account/netease_account_phase1_test.dart`.

```dart
test('invalid MUSIC_U does not remain logged in after validation fails', () async {
  final service = buildNeteaseAccountServiceForTest(
    checkAccountStatusResult: const AccountCheckResult(status: AccountStatus.invalid),
  );

  await service.loginWithCookies(musicU: 'invalid-cookie', csrf: '');
  await service.fetchAndUpdateUserInfo();

  final account = await service.getCurrentAccount();
  expect(account?.isLoggedIn, isFalse);
});
```

- [ ] **Step 2: Run the focused login test and confirm it fails**

Run:
```bash
flutter test test/services/account/netease_account_phase1_test.dart --plain-name "invalid MUSIC_U does not remain logged in after validation fails"
```

Expected: FAIL because current flow keeps the optimistic logged-in state.

- [ ] **Step 3: Make validation failure roll back login state**

In `lib/services/account/netease_account_service.dart`, update `fetchAndUpdateUserInfo()`.

```dart
Future<void> fetchAndUpdateUserInfo() async {
  try {
    final result = await checkAccountStatus();
    if (result.status != AccountStatus.valid) {
      await _updateAccount(isLoggedIn: false);
      return;
    }
    // existing success path...
  } catch (e) {
    logError('Failed to fetch Netease user info', e);
    await _updateAccount(isLoggedIn: false);
  }
}
```

- [ ] **Step 4: Make the login page wait for validated status before signaling success**

In `lib/ui/pages/settings/netease_login_page.dart`, replace the optimistic success callbacks:

```dart
await accountService.loginWithCookies(
  musicU: musicU,
  csrf: csrf,
);
await accountService.fetchAndUpdateUserInfo();
final account = await accountService.getCurrentAccount();
if (account?.isLoggedIn == true) {
  await _cleanupWebView();
  widget.onLoginSuccess();
} else {
  throw Exception('Netease login validation failed');
}
```

And in QR login polling:

```dart
if (result.code == 803) {
  await accountService.fetchAndUpdateUserInfo();
  final account = await accountService.getCurrentAccount();
  if (!mounted) return;
  if (account?.isLoggedIn == true) {
    widget.onLoginSuccess();
  } else {
    setState(() => _status = 801);
  }
}
```

- [ ] **Step 5: Re-run the login-boundary test and confirm it passes**

Run:
```bash
flutter test test/services/account/netease_account_phase1_test.dart --plain-name "invalid MUSIC_U does not remain logged in after validation fails"
```

Expected: PASS.

- [ ] **Step 6: Commit the NetEase login boundary fix**

```bash
git add lib/services/account/netease_account_service.dart lib/ui/pages/settings/netease_login_page.dart test/services/account/netease_account_phase1_test.dart
git commit -m "fix(netease): require validated account status after login"
```

---

### Task 7: Run the Phase 1 verification suite

**Files:**
- Test: `test/services/audio/audio_controller_phase1_test.dart`
- Test: `test/services/download/download_service_phase1_test.dart`
- Test: `test/providers/database_migration_test.dart`
- Test: `test/services/backup/backup_settings_phase1_test.dart`
- Test: `test/services/audio/queue_manager_phase1_shuffle_test.dart`
- Test: `test/services/radio/radio_controller_phase1_test.dart`
- Test: `test/services/account/netease_account_phase1_test.dart`

- [ ] **Step 1: Run the focused Phase 1 suite**

Run:
```bash
flutter test test/services/audio/audio_controller_phase1_test.dart && flutter test test/services/download/download_service_phase1_test.dart && flutter test test/providers/database_migration_test.dart && flutter test test/services/backup/backup_settings_phase1_test.dart && flutter test test/services/audio/queue_manager_phase1_shuffle_test.dart && flutter test test/services/radio/radio_controller_phase1_test.dart && flutter test test/services/account/netease_account_phase1_test.dart
```

Expected: PASS for all Phase 1-targeted tests.

- [ ] **Step 2: Run a wider static safety pass**

Run:
```bash
flutter analyze
```

Expected: PASS with no new diagnostics introduced by Phase 1 work.

- [ ] **Step 3: Update roadmap status note if implementation changes scope assumptions**

If Phase 1 implementation proves that any roadmap assumption in `docs/superpowers/specs/2026-04-20-fmp-refactor-roadmap-design.md` is incorrect, update that spec before closing Phase 1. If no assumptions changed, do not edit the spec.

- [ ] **Step 4: Commit the verification pass**

```bash
git add test/services/audio/audio_controller_phase1_test.dart test/services/download/download_service_phase1_test.dart test/providers/database_migration_test.dart test/services/backup/backup_settings_phase1_test.dart test/services/audio/queue_manager_phase1_shuffle_test.dart test/services/radio/radio_controller_phase1_test.dart test/services/account/netease_account_phase1_test.dart docs/superpowers/specs/2026-04-20-fmp-refactor-roadmap-design.md
git commit -m "test(phase1): lock phase-one stabilization baseline"
```

---

## Self-review notes

- **Spec coverage:** The plan covers the Phase 1 scope from the design doc: playback/platform control ownership, NetEase expiry semantics, resume correctness, shuffle/reorder consistency, migration/backup/default-value truth source, page-entry writeback removal, and direct regression tests for these fixes.
- **Placeholder scan:** No TODO/TBD placeholders remain. All tasks point to exact files, commands, and concrete code snippets.
- **Type consistency:** The plan consistently references `AudioStreamResult.validity`, `restoreGlobalMediaControls()`, `SettingsBackup` alignment, and test file names introduced in earlier tasks.

Plan complete and saved to `docs/superpowers/plans/2026-04-20-fmp-phase1-stabilization.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?