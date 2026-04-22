# FMP Phase 4 Long-Term Optimization and Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve long-term performance and regression safety in the stabilized post-Phase-3 codebase without reopening the ownership boundaries that were just purified.

**Architecture:** Phase 4 stays inside proven hotspots: widget subscription granularity, playlist/file-cache I/O fan-out, play-history query duplication, high-risk regression coverage, and Windows close/accessibility follow-up. The plan keeps `AudioController`, `QueueManager`, and the existing provider graph in place, and adds only the smallest new selector/test seams needed to reduce rebuild cost and raise protection coverage.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, Flutter test, Windows desktop integration

---

## File map

- Create: `lib/providers/audio_player_selectors.dart` — fine-grained audio selector providers for player widgets.
- Modify: `lib/providers/download/download_providers.dart` — per-task progress selectors and lighter download-page subscriptions.
- Modify: `lib/providers/download/file_exists_cache.dart` — path-scoped selectors and batched preload behavior.
- Modify: `lib/providers/play_history_provider.dart` — shared snapshot-driven history derivation.
- Modify: `lib/data/repositories/play_history_repository.dart` — shared filtered snapshot/query helpers for history data.
- Create: `lib/services/audio/audio_runtime_platform.dart` — testable platform-split audio backend selection seam.
- Modify: `lib/services/audio/audio_provider.dart` — consume the testable runtime-platform seam.
- Modify: `lib/ui/pages/player/player_page.dart`
- Modify: `lib/ui/widgets/player/mini_player.dart`
- Modify: `lib/ui/widgets/track_detail_panel.dart`
- Modify: `lib/ui/pages/settings/download_manager_page.dart`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart`
- Modify: `lib/services/platform/windows_desktop_service.dart`
- Modify: `lib/ui/widgets/custom_title_bar.dart`
- Modify: `lib/app.dart`
- Modify: `lib/ui/windows/lyrics_window.dart`
- Test: `test/ui/pages/player/player_page_phase4_test.dart`
- Test: `test/ui/pages/settings/download_manager_page_phase4_test.dart`
- Test: `test/providers/download/file_exists_cache_phase4_test.dart`
- Test: `test/providers/play_history_provider_phase4_test.dart`
- Test: `test/data/repositories/play_history_repository_phase4_test.dart`
- Test: `test/services/audio/audio_auth_retry_phase4_test.dart`
- Test: `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`
- Test: `test/services/import/import_service_phase4_test.dart`
- Test: `test/services/audio/audio_runtime_platform_phase4_test.dart`
- Test: `test/services/platform/windows_desktop_service_phase4_test.dart`
- Modify if behavior/docs materially change: `CLAUDE.md`

---

### Task 1: Add fine-grained player audio selectors

**Files:**
- Create: `lib/providers/audio_player_selectors.dart`
- Modify: `lib/ui/pages/player/player_page.dart`
- Modify: `lib/ui/widgets/player/mini_player.dart`
- Modify: `lib/ui/widgets/track_detail_panel.dart`
- Test: `test/ui/pages/player/player_page_phase4_test.dart`
- Test: `test/ui/widgets/mini_player_test.dart`

- [ ] **Step 1: Write the failing selector tests**
```dart
test('player page stops watching the whole audio controller state', () async {
  final source = await File(
    '${Directory.current.path}/lib/ui/pages/player/player_page.dart',
  ).readAsString();
  expect(source.contains('ref.watch(audioControllerProvider);'), isFalse);
});

test('audio player selectors file exposes speed and stream metadata providers', () async {
  final source = await File(
    '${Directory.current.path}/lib/providers/audio_player_selectors.dart',
  ).readAsString();
  expect(source.contains('final playbackSpeedProvider'), isTrue);
  expect(source.contains('final currentStreamMetadataProvider'), isTrue);
});
```
- [ ] **Step 2: Run the tests to verify the current code fails**
Run: `flutter test test/ui/pages/player/player_page_phase4_test.dart test/ui/widgets/mini_player_test.dart`
Expected: FAIL because `audio_player_selectors.dart` does not exist and `player_page.dart` still watches broad audio state.
- [ ] **Step 3: Create the selector providers**
```dart
final playbackSpeedProvider = Provider<double>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.speed));
});

final desktopAudioDevicesProvider = Provider<List<FmpAudioDevice>>((ref) {
  return ref.watch(audioControllerProvider.select((s) => s.audioDevices));
});

final currentStreamMetadataProvider = Provider<({
  int? bitrate,
  String? container,
  String? codec,
  StreamType? streamType,
})>((ref) {
  return ref.watch(audioControllerProvider.select((s) => (
        bitrate: s.currentBitrate,
        container: s.currentContainer,
        codec: s.currentCodec,
        streamType: s.currentStreamType,
      )));
});
```
- [ ] **Step 4: Rewire the player widgets to the selectors**
```dart
final currentTrack = ref.watch(currentTrackProvider);
final position = ref.watch(positionProvider);
final duration = ref.watch(durationProvider);
final speed = ref.watch(playbackSpeedProvider);
final stream = ref.watch(currentStreamMetadataProvider);
final controller = ref.read(audioControllerProvider.notifier);
```
- [ ] **Step 5: Re-run the focused player tests**
Run: `flutter test test/ui/pages/player/player_page_phase4_test.dart test/ui/widgets/mini_player_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit the player selector cleanup**
```bash
git add lib/providers/audio_player_selectors.dart lib/ui/pages/player/player_page.dart lib/ui/widgets/player/mini_player.dart lib/ui/widgets/track_detail_panel.dart test/ui/pages/player/player_page_phase4_test.dart test/ui/widgets/mini_player_test.dart
git commit -m "refactor(phase4): narrow player widget subscriptions"
```

---

### Task 2: Add per-task download progress selectors

**Files:**
- Modify: `lib/providers/download/download_providers.dart`
- Modify: `lib/ui/pages/settings/download_manager_page.dart`
- Test: `test/providers/download/download_providers_phase4_test.dart`
- Test: `test/ui/pages/settings/download_manager_page_phase4_test.dart`

- [ ] **Step 1: Write the failing download selector tests**
```dart
test('download providers expose a task-scoped progress provider', () async {
  final source = await File(
    '${Directory.current.path}/lib/providers/download/download_providers.dart',
  ).readAsString();
  expect(source.contains('final downloadTaskProgressProvider'), isTrue);
});

test('download manager tile watches task-scoped progress instead of the whole map', () async {
  final source = await File(
    '${Directory.current.path}/lib/ui/pages/settings/download_manager_page.dart',
  ).readAsString();
  expect(source.contains('ref.watch(downloadTaskProgressProvider(task.id))'), isTrue);
  expect(source.contains('ref.watch(downloadProgressStateProvider)'), isFalse);
});
```
- [ ] **Step 2: Run the tests and confirm they fail**
Run: `flutter test test/providers/download/download_providers_phase4_test.dart test/ui/pages/settings/download_manager_page_phase4_test.dart`
Expected: FAIL because the page still watches `downloadProgressStateProvider` directly.
- [ ] **Step 3: Add the family progress provider**
```dart
final downloadTaskProgressProvider = Provider.family<(double, int, int?), int>((ref, taskId) {
  final entry = ref.watch(
    downloadProgressStateProvider.select((state) => state[taskId]),
  );
  return entry ?? (0.0, 0, null);
});
```
- [ ] **Step 4: Move each task tile to the family provider**
```dart
final (progress, downloadedBytes, totalBytes) =
    ref.watch(downloadTaskProgressProvider(task.id));
```
- [ ] **Step 5: Re-run the focused download tests**
Run: `flutter test test/providers/download/download_providers_phase4_test.dart test/ui/pages/settings/download_manager_page_phase4_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit the download selector cleanup**
```bash
git add lib/providers/download/download_providers.dart lib/ui/pages/settings/download_manager_page.dart test/providers/download/download_providers_phase4_test.dart test/ui/pages/settings/download_manager_page_phase4_test.dart
git commit -m "refactor(phase4): scope download progress subscriptions by task"
```

---

### Task 3: Batch playlist cover-path I/O and remove whole-cache watchers

**Files:**
- Modify: `lib/providers/download/file_exists_cache.dart`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart`
- Modify: `lib/ui/widgets/track_detail_panel.dart`
- Test: `test/providers/download/file_exists_cache_phase4_test.dart`

- [ ] **Step 1: Write the failing cache/fan-out tests**
```dart
test('file exists cache exposes a path-scoped selector provider', () async {
  final source = await File(
    '${Directory.current.path}/lib/providers/download/file_exists_cache.dart',
  ).readAsString();
  expect(source.contains('final filePathExistsProvider'), isTrue);
});

test('playlist detail page tracks a cached cover-path set instead of track count only', () async {
  final source = await File(
    '${Directory.current.path}/lib/ui/pages/library/playlist_detail_page.dart',
  ).readAsString();
  expect(source.contains('_cachedCoverPaths'), isTrue);
});
```
- [ ] **Step 2: Run the tests and confirm they fail**
Run: `flutter test test/providers/download/file_exists_cache_phase4_test.dart`
Expected: FAIL because the path-scoped provider and cover-path cache set do not exist yet.
- [ ] **Step 3: Add path-scoped cache selection and batched preload**
```dart
final filePathExistsProvider = Provider.family<bool, String>((ref, path) {
  return ref.watch(fileExistsCacheProvider.select((paths) => paths.contains(path)));
});

Future<void> preloadPaths(List<String> paths, {int batchSize = 64}) async {
  final uncached = paths.toSet().difference(state).toList();
  final existing = <String>{};
  for (var i = 0; i < uncached.length; i += batchSize) {
    final batch = uncached.skip(i).take(batchSize).toList();
    final results = await Future.wait(
      batch.map((path) async => (path: path, exists: await File(path).exists())),
    );
    for (final result in results) {
      if (result.exists) existing.add(result.path);
    }
  }
  if (existing.isNotEmpty) state = {...state, ...existing};
}
```
- [ ] **Step 4: Only preload when the actual cover-path set changes**
```dart
Set<String> _cachedCoverPaths = const {};

void _checkAndPreloadCache(List<Track> tracks) {
  final coverPaths = tracks
      .where((t) => t.hasAnyDownload)
      .map((t) => '${t.allDownloadPaths.first.replaceAll(RegExp(r'[/\\][^/\\]+$'), '')}/cover.jpg')
      .toSet();
  if (setEquals(coverPaths, _cachedCoverPaths)) return;
  _cachedCoverPaths = coverPaths;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && coverPaths.isNotEmpty) {
      ref.read(fileExistsCacheProvider.notifier).preloadPaths(coverPaths.toList());
    }
  });
}
```
- [ ] **Step 5: Re-run the cache tests**
Run: `flutter test test/providers/download/file_exists_cache_phase4_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit the playlist/cache fan-out optimization**
```bash
git add lib/providers/download/file_exists_cache.dart lib/ui/pages/library/playlist_detail_page.dart lib/ui/widgets/track_detail_panel.dart test/providers/download/file_exists_cache_phase4_test.dart
git commit -m "refactor(phase4): batch playlist cover cache I/O"
```

---

### Task 4: Share play-history snapshots across derived providers

**Files:**
- Modify: `lib/data/repositories/play_history_repository.dart`
- Modify: `lib/providers/play_history_provider.dart`
- Modify: `lib/ui/pages/history/play_history_page.dart`
- Test: `test/data/repositories/play_history_repository_phase4_test.dart`
- Test: `test/providers/play_history_provider_phase4_test.dart`

- [ ] **Step 1: Write the failing history snapshot tests**
```dart
test('play history providers expose a shared snapshot provider', () async {
  final source = await File(
    '${Directory.current.path}/lib/providers/play_history_provider.dart',
  ).readAsString();
  expect(source.contains('final playHistorySnapshotProvider'), isTrue);
});

test('repository exposes a filtered snapshot helper', () async {
  final source = await File(
    '${Directory.current.path}/lib/data/repositories/play_history_repository.dart',
  ).readAsString();
  expect(source.contains('Future<List<PlayHistory>> loadHistorySnapshot('), isTrue);
});
```
- [ ] **Step 2: Run the tests and confirm they fail**
Run: `flutter test test/data/repositories/play_history_repository_phase4_test.dart test/providers/play_history_provider_phase4_test.dart`
Expected: FAIL because the shared snapshot seam does not exist yet.
- [ ] **Step 3: Add the repository snapshot helper and derived provider**
```dart
Future<List<PlayHistory>> loadHistorySnapshot({
  Set<SourceType>? sourceTypes,
  DateTime? startDate,
  DateTime? endDate,
  String? searchKeyword,
}) async {
  return queryHistory(
    sourceTypes: sourceTypes,
    startDate: startDate,
    endDate: endDate,
    searchKeyword: searchKeyword,
    sortOrder: HistorySortOrder.timeDesc,
    limit: 1000,
  );
}

final playHistorySnapshotProvider = StreamProvider.autoDispose<List<PlayHistory>>((ref) async* {
  final repo = ref.watch(playHistoryRepositoryProvider);
  yield await repo.loadHistorySnapshot();
  await for (final _ in repo.watchHistory()) {
    yield await repo.loadHistorySnapshot();
  }
});
```
- [ ] **Step 4: Re-derive recent/stats/grouped views from the snapshot**
```dart
final recentPlayHistoryProvider = Provider.autoDispose<AsyncValue<List<PlayHistory>>>((ref) {
  final snapshot = ref.watch(playHistorySnapshotProvider);
  return snapshot.whenData((records) => _distinctRecent(records, limit: 10));
});
```
- [ ] **Step 5: Re-run the history tests**
Run: `flutter test test/data/repositories/play_history_repository_phase4_test.dart test/providers/play_history_provider_phase4_test.dart test/ui/pages/history/play_history_page_phase2_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit the history snapshot optimization**
```bash
git add lib/data/repositories/play_history_repository.dart lib/providers/play_history_provider.dart lib/ui/pages/history/play_history_page.dart test/data/repositories/play_history_repository_phase4_test.dart test/providers/play_history_provider_phase4_test.dart test/ui/pages/history/play_history_page_phase2_test.dart
git commit -m "refactor(phase4): share play history snapshots across derived views"
```

---

### Task 5: Add high-risk regression protection suites

**Files:**
- Create: `lib/services/audio/audio_runtime_platform.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Test: `test/services/audio/audio_auth_retry_phase4_test.dart`
- Test: `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`
- Test: `test/services/import/import_service_phase4_test.dart`
- Test: `test/services/audio/audio_runtime_platform_phase4_test.dart`
- Modify: `test/services/account/netease_account_service_test.dart`
- Modify: `test/services/account/youtube_account_service_test.dart`

- [ ] **Step 1: Write the failing regression suites**
```dart
test('auth-for-play propagates headers through playback and download entry points',
    () async {
  final playbackSource = RecordingAudioSource();
  final downloadSource = RecordingAudioSource();

  await runPlaybackAuthScenario(
    source: playbackSource,
    useAuthForPlay: true,
    expectedHeaders: {'Authorization': 'Bearer playback'},
  );
  await runDownloadAuthScenario(
    source: downloadSource,
    useAuthForPlay: true,
    expectedHeaders: {'Authorization': 'Bearer playback'},
  );

  expect(playbackSource.lastAuthHeaders, {'Authorization': 'Bearer playback'});
  expect(downloadSource.lastAuthHeaders, {'Authorization': 'Bearer playback'});
});

test('network retry resumes from saved position after recovery', () async {
  final harness = await createRetryRecoveryHarness();
  await harness.controller.playSingle(harness.track);
  harness.audioService.emitNetworkError('connection reset');
  await harness.emitNetworkRecovered();

  expect(harness.audioService.seekCalls.last, const Duration(seconds: 42));
  expect(harness.controller.state.currentTrack?.sourceId, harness.track.sourceId);
});

test('lyrics auto-match keeps source ordering and clears loading state',
    () async {
  final result = await runLyricsAutoMatchScenario(
    priorities: ['netease', 'qqmusic', 'lrclib'],
  );

  expect(result.visitedSources, ['netease', 'qqmusic', 'lrclib']);
  expect(result.isMatchingAfterCompletion, isFalse);
});

test('import service dispatches source urls through the correct parser path',
    () async {
  final harness = createImportDispatchHarness();

  await harness.import('https://music.163.com/#/playlist?id=1');
  await harness.import('https://www.youtube.com/playlist?list=PL123');

  expect(harness.calls, ['netease-playlist', 'youtube-playlist']);
});

test('audio runtime platform selects desktop backend on Windows and Linux', () {
  expect(selectAudioRuntimePlatform('windows'), AudioRuntimePlatform.desktop);
  expect(selectAudioRuntimePlatform('linux'), AudioRuntimePlatform.desktop);
  expect(selectAudioRuntimePlatform('android'), AudioRuntimePlatform.mobile);
});
```
- [ ] **Step 2: Run the new suites and confirm they fail**
Run: `flutter test test/services/audio/audio_auth_retry_phase4_test.dart test/services/lyrics/lyrics_auto_match_service_phase4_test.dart test/services/import/import_service_phase4_test.dart test/services/audio/audio_runtime_platform_phase4_test.dart test/services/account/netease_account_service_test.dart test/services/account/youtube_account_service_test.dart`
Expected: FAIL because the new suites and the testable platform seam do not exist yet.
- [ ] **Step 3: Extract the testable runtime-platform seam**
```dart
enum AudioRuntimePlatform { mobile, desktop }

AudioRuntimePlatform detectAudioRuntimePlatform() {
  return Platform.isAndroid || Platform.isIOS
      ? AudioRuntimePlatform.mobile
      : AudioRuntimePlatform.desktop;
}
```
- [ ] **Step 4: Consume the seam in audio backend selection**
```dart
final audioServiceProvider = Provider<FmpAudioService>((ref) {
  switch (detectAudioRuntimePlatform()) {
    case AudioRuntimePlatform.mobile:
      return JustAudioService();
    case AudioRuntimePlatform.desktop:
      return MediaKitAudioService();
  }
});
```
- [ ] **Step 5: Re-run the regression suites**
Run: `flutter test test/services/audio/audio_auth_retry_phase4_test.dart test/services/lyrics/lyrics_auto_match_service_phase4_test.dart test/services/import/import_service_phase4_test.dart test/services/audio/audio_runtime_platform_phase4_test.dart test/services/account/netease_account_service_test.dart test/services/account/youtube_account_service_test.dart`
Expected: PASS.
- [ ] **Step 6: Commit the protection suite expansion**
```bash
git add lib/services/audio/audio_runtime_platform.dart lib/services/audio/audio_provider.dart test/services/audio/audio_auth_retry_phase4_test.dart test/services/lyrics/lyrics_auto_match_service_phase4_test.dart test/services/import/import_service_phase4_test.dart test/services/audio/audio_runtime_platform_phase4_test.dart test/services/account/netease_account_service_test.dart test/services/account/youtube_account_service_test.dart
git commit -m "test(phase4): add high-risk audio and import regression suites"
```

---

### Task 6: Unify Windows close handling and narrow accessibility exclusions

**Files:**
- Modify: `lib/services/platform/windows_desktop_service.dart`
- Modify: `lib/ui/widgets/custom_title_bar.dart`
- Modify: `lib/app.dart`
- Modify: `lib/ui/windows/lyrics_window.dart`
- Test: `test/services/platform/windows_desktop_service_phase4_test.dart`
- Modify if behavior notes change: `CLAUDE.md`

- [ ] **Step 1: Write the failing Windows follow-up tests**
```dart
test('system close and title-bar close route through the same Windows close handler', () async {
  final source = await File(
    '${Directory.current.path}/lib/services/platform/windows_desktop_service.dart',
  ).readAsString();
  expect(source.contains('handleCloseIntent('), isTrue);
});

test('app no longer wraps the entire Windows tree in ExcludeSemantics', () async {
  final source = await File(
    '${Directory.current.path}/lib/app.dart',
  ).readAsString();
  expect(source.contains('content = ExcludeSemantics(child: content);'), isFalse);
});
```
- [ ] **Step 2: Run the Windows-focused tests and confirm they fail**
Run: `flutter test test/services/platform/windows_desktop_service_phase4_test.dart`
Expected: FAIL because the unified close-intent method and narrowed semantics scope are not implemented yet.
- [ ] **Step 3: Collapse close handling into one code path**
```dart
Future<void> handleCloseIntent({required bool fromSystemClose}) async {
  final isPreventClose = await windowManager.isPreventClose();
  if (isPreventClose) {
    await minimizeToTray();
    if (await _isInstallerRunning()) {
      await _forceExit();
    }
    return;
  }
  await _forceExit();
}
```
- [ ] **Step 4: Keep semantics only on safe leaf widgets**
```dart
builder: (context, child) {
  return _AppContentWrapper(child: child);
}
```
Add explicit semantics labels to the title-bar controls.

```dart
Semantics(
  label: 'Close window',
  button: true,
  child: _TitleBarButton(
    icon: Icons.close,
    onPressed: () => service.handleCloseIntent(fromSystemClose: false),
    isClose: true,
  ),
)
```
- [ ] **Step 5: Re-run the Windows tests and docs check**
Run: `flutter test test/services/platform/windows_desktop_service_phase4_test.dart`
Expected: PASS.

Update `CLAUDE.md` if the implementation changes the documented Windows behavior.

Add or revise bullets under the Windows/UI guidance sections so they explicitly say:

```md
- Windows close behavior must route both custom title-bar close and system close through `WindowsDesktopService.handleCloseIntent(...)`.
- Do not wrap the whole Windows app tree in `ExcludeSemantics`; prefer leaf-level exclusions or explicit `Semantics` labels.
```
- [ ] **Step 6: Commit the Windows follow-up cleanup**
```bash
git add lib/services/platform/windows_desktop_service.dart lib/ui/widgets/custom_title_bar.dart lib/app.dart lib/ui/windows/lyrics_window.dart test/services/platform/windows_desktop_service_phase4_test.dart CLAUDE.md
git commit -m "fix(phase4): unify Windows close path and accessibility handling"
```
