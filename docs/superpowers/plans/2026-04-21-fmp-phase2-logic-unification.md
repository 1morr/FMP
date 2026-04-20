# FMP Phase 2 Logic Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Phase 2 of the FMP roadmap by pulling repeated page-layer business logic back behind provider/service boundaries, extending shared track actions, and clarifying which provider paths are watch-driven versus explicitly invalidated.

**Architecture:** Phase 2 stays above the core playback boundary. It does not reopen Phase 1 stabilization fixes or Phase 3/4 structural work; instead it tightens page-layer seams by introducing narrow facades/notifiers for playlist import, download-path maintenance, radio import, and platform-specific fetch flows that pages currently assemble themselves. Shared single-track actions continue to converge on `TrackActionHandler`, while provider cleanup focuses on removing duplicated entry points and documenting explicit invalidation at snapshot boundaries.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, Flutter test, widget tests

---

## File map

### Primary production files
- Modify: `lib/ui/pages/library/widgets/import_playlist_dialog.dart` — stop constructing `ImportService` directly in the dialog; consume a Phase 2 import facade instead.
- Modify: `lib/ui/pages/settings/widgets/account_playlists_sheet.dart` — stop constructing `ImportService` directly; route account-playlist imports through the same facade path.
- Create: `lib/providers/import_playlist_provider.dart` — provide a single internal playlist-import facade/notifier for Bilibili/YouTube/NetEase direct imports, including progress, cancellation, and cleanup.
- Modify: `lib/services/import/import_service.dart` — keep import behavior intact, but support facade-driven lifecycle from provider code.
- Modify: `lib/ui/widgets/change_download_path_dialog.dart` — remove repository/service orchestration from the dialog and call a dedicated maintenance service entry instead.
- Modify: `lib/ui/pages/library/downloaded_page.dart` — remove direct repository/file-delete orchestration from the page and use the same maintenance service family.
- Create: `lib/services/download/download_path_maintenance_service.dart` — own download-path clearing, category deletion cleanup, provider invalidation inputs, and file deletion orchestration.
- Modify: `lib/providers/download_path_provider.dart` — expose the new maintenance service through Riverpod.
- Modify: `lib/ui/pages/settings/widgets/account_radio_import_sheet.dart` — stop reading repository/source services directly for import work; delegate to `RadioController` import entry points.
- Modify: `lib/services/radio/radio_controller.dart` — add account-radio import entry points that wrap medal-wall loading, duplicate detection, import progress, and persistence.
- Modify: `lib/ui/pages/search/search_page.dart` — remove direct `BilibiliSource` + auth-header assembly for multi-page expansion; route through `SearchNotifier` / search service entry points. Also continue Phase 2 `TrackActionHandler` convergence for grouped and page-level menu flows.
- Modify: `lib/providers/search_provider.dart` — add a notifier/service entry for Bilibili video-page loading and cache it in notifier-owned state.
- Modify: `lib/services/search/search_service.dart` — add a service method for Bilibili page loading with auth headers hidden from UI.
- Modify: `lib/ui/widgets/playlist_card_actions.dart` — stop calling `YouTubeSource` directly for Mix bootstrap; route through `AudioController`/provider-facing app entry.
- Modify: `lib/services/audio/audio_provider.dart` — add a narrow provider-facing `startMixFromPlaylist()` app entry that fetches initial Mix tracks and starts playback.
- Modify: `lib/ui/pages/history/play_history_page.dart` — replace handwritten single-track menu switching with `TrackActionHandler` while preserving delete-only history actions locally.
- Modify: `lib/ui/handlers/track_action_handler.dart` — extend handler support for Phase 2 pages without regressing existing call sites.
- Modify: `lib/providers/download/download_providers.dart` — remove the duplicate local `trackRepositoryProvider` and reuse the shared provider.
- Modify: `lib/data/sources/source_provider.dart` and/or `lib/providers/search_provider.dart` — if needed in Phase 2 docs/tests, make the non-authoritative `enabledSources` behavior explicit without expanding into Phase 3 truth-source work.

### Primary test files
- Create: `test/providers/import_playlist_provider_phase2_test.dart` — verify the shared internal import facade handles progress, cancellation cleanup, and provider-facing results for dialog/sheet consumers.
- Create: `test/services/download/download_path_maintenance_service_phase2_test.dart` — verify change-path reset and downloaded-category deletion are owned by the maintenance service, not UI code.
- Create: `test/services/radio/radio_controller_phase2_import_test.dart` — verify account-radio import loading and bulk import behavior through `RadioController`.
- Modify: `test/ui/pages/search/search_page_phase2_test.dart` — add/extend coverage that search-page menu flows rely on notifier/service entries rather than direct source wiring where possible.
- Modify: `test/providers/playlist_provider_phase2_test.dart` — keep explicit invalidation semantics covered where playlist/provider snapshot boundaries remain intentional.
- Create: `test/ui/pages/history/play_history_page_phase2_test.dart` — verify history page routes base single-track actions through shared handling and keeps delete actions local.
- Create: `test/providers/download_providers_phase2_test.dart` — verify the download module reuses the shared repository provider instead of shadowing it.

### Docs to re-check while implementing
- Read: `docs/review/architecture_review.md`
- Read: `docs/review/consistency_review.md`
- Read: `docs/review/database_review.md`
- Read: `docs/superpowers/specs/2026-04-20-fmp-refactor-roadmap-design.md`
- Update only if Phase 2 implementation changes project expectations materially: `CLAUDE.md`

---

### Task 1: Unify internal playlist import entry points behind a provider facade

**Files:**
- Create: `lib/providers/import_playlist_provider.dart`
- Modify: `lib/ui/pages/library/widgets/import_playlist_dialog.dart:72-79,442-506`
- Modify: `lib/ui/pages/settings/widgets/account_playlists_sheet.dart:63-67,236-290`
- Modify: `lib/services/import/import_service.dart:79-153`
- Test: `test/providers/import_playlist_provider_phase2_test.dart`

- [ ] **Step 1: Write the failing provider test for shared internal import progress and cleanup**

Create `test/providers/import_playlist_provider_phase2_test.dart` and add a focused test that proves a single provider-facing facade can own `ImportService` lifecycle, progress forwarding, cancellation, and cleanup without UI code constructing the service directly.

```dart
test('internal playlist import facade forwards progress and cleanup', () async {
  final harness = await createImportPhase2Harness();
  addTearDown(harness.dispose);

  final notifier = harness.container.read(internalPlaylistImportProvider.notifier);
  final progressEvents = <InternalImportState>[];
  final sub = harness.container.listen(
    internalPlaylistImportProvider,
    (_, next) => progressEvents.add(next),
    fireImmediately: true,
  );
  addTearDown(sub.close);

  final result = await notifier.importFromUrl(
    'https://www.youtube.com/playlist?list=PL_phase2',
    customName: 'Phase 2 Import',
    useAuth: true,
  );

  expect(result, isNotNull);
  expect(progressEvents.any((s) => s.progress != null), isTrue);
  expect(progressEvents.last.isImporting, isFalse);
  expect(harness.fakeImportService.cleanupCancelledImportCallCount, 1);
});
```

- [ ] **Step 2: Run the new import-facade test and confirm it fails**

Run:
```bash
flutter test test/providers/import_playlist_provider_phase2_test.dart
```

Expected: FAIL because no `internalPlaylistImportProvider` exists yet and UI still constructs `ImportService` directly.

- [ ] **Step 3: Create the provider-facing internal import facade**

Create `lib/providers/import_playlist_provider.dart` with a notifier/state that owns one `ImportService` instance, forwards progress, and guarantees `cleanupCancelledImport()` + `dispose()`.

```dart
class InternalPlaylistImportState {
  final bool isImporting;
  final ImportProgress? progress;
  final String? error;

  const InternalPlaylistImportState({
    this.isImporting = false,
    this.progress,
    this.error,
  });

  InternalPlaylistImportState copyWith({
    bool? isImporting,
    ImportProgress? progress,
    String? error,
  }) {
    return InternalPlaylistImportState(
      isImporting: isImporting ?? this.isImporting,
      progress: progress ?? this.progress,
      error: error,
    );
  }
}

final internalPlaylistImportServiceProvider = Provider<ImportService>((ref) {
  final sourceManager = ref.watch(sourceManagerProvider);
  final playlistRepo = ref.watch(playlistRepositoryProvider);
  final trackRepo = ref.watch(trackRepositoryProvider);
  final isar = ref.watch(databaseProvider).requireValue;
  return ImportService(
    sourceManager: sourceManager,
    playlistRepository: playlistRepo,
    trackRepository: trackRepo,
    isar: isar,
    bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
    youtubeAccountService: ref.read(youtubeAccountServiceProvider),
    neteaseAccountService: ref.read(neteaseAccountServiceProvider),
  );
});

final internalPlaylistImportProvider = StateNotifierProvider.autoDispose<
    InternalPlaylistImportNotifier, InternalPlaylistImportState>((ref) {
  final service = ref.watch(internalPlaylistImportServiceProvider);
  return InternalPlaylistImportNotifier(service);
});
```

- [ ] **Step 4: Move import dialog internal-import wiring to the facade**

In `lib/ui/pages/library/widgets/import_playlist_dialog.dart`, replace direct `ImportService` construction in `_startInternalImport()` with the notifier entry.

```dart
final notifier = ref.read(internalPlaylistImportProvider.notifier);
final stateSub = ref.listenManual<InternalPlaylistImportState>(
  internalPlaylistImportProvider,
  (_, next) {
    if (mounted) {
      setState(() => _internalProgress = next.progress);
    }
  },
);

try {
  final result = await notifier.importFromUrl(
    _urlController.text.trim(),
    customName: customName.isEmpty ? null : customName,
    useAuth: _useAuth,
  );

  ref.invalidate(allPlaylistsProvider);
  ref.invalidate(playlistDetailProvider(result.playlist.id));
  ref.invalidate(playlistCoverProvider(result.playlist.id));
  if (mounted) {
    Navigator.pop(context);
    ToastService.success(context, t.library.importPlaylist.importSuccess(n: result.addedCount));
  }
} finally {
  stateSub.close();
}
```

- [ ] **Step 5: Move account playlist sheet import wiring to the same facade**

In `lib/ui/pages/settings/widgets/account_playlists_sheet.dart`, remove the direct `ImportService` construction and call the same notifier for each selected account playlist.

```dart
final notifier = ref.read(internalPlaylistImportProvider.notifier);
for (final item in selected) {
  if (!mounted || _isCancelled) break;
  setState(() {
    _importCurrent++;
    _currentPlaylistName = item.title;
  });

  await notifier.importFromUrl(
    item.importUrl,
    useAuth: true,
  );
  successCount++;
}
```

Keep the UI-owned sheet progress text and cancellation UX, but stop building the service in the sheet.

- [ ] **Step 6: Re-run the new provider test and the existing import-facing tests**

Run:
```bash
flutter test test/providers/import_playlist_provider_phase2_test.dart
```

Expected: PASS.

Then run:
```bash
flutter analyze lib/providers/import_playlist_provider.dart lib/ui/pages/library/widgets/import_playlist_dialog.dart lib/ui/pages/settings/widgets/account_playlists_sheet.dart lib/services/import/import_service.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the internal-import boundary cleanup**

```bash
git add lib/providers/import_playlist_provider.dart lib/ui/pages/library/widgets/import_playlist_dialog.dart lib/ui/pages/settings/widgets/account_playlists_sheet.dart lib/services/import/import_service.dart test/providers/import_playlist_provider_phase2_test.dart
git commit -m "refactor(import): unify internal playlist import entry points"
```

---

### Task 2: Move download-path maintenance work out of dialogs and pages

**Files:**
- Create: `lib/services/download/download_path_maintenance_service.dart`
- Modify: `lib/providers/download_path_provider.dart:19-25`
- Modify: `lib/ui/widgets/change_download_path_dialog.dart:190-258`
- Modify: `lib/ui/pages/library/downloaded_page.dart:461-485`
- Modify: `lib/ui/pages/library/downloaded_category_page.dart:732-752`
- Test: `test/services/download/download_path_maintenance_service_phase2_test.dart`

- [ ] **Step 1: Write the failing maintenance-service test for change-path reset**

Create `test/services/download/download_path_maintenance_service_phase2_test.dart` and add a test that verifies clearing download paths, clearing completed/error tasks, and collecting playlist IDs to invalidate happens in a service, not in the dialog.

```dart
test('change path reset clears download state through maintenance service', () async {
  final harness = await createDownloadPathMaintenanceHarness();
  addTearDown(harness.dispose);

  final service = harness.container.read(downloadPathMaintenanceServiceProvider);
  final result = await service.changeBasePathAndResetDownloads('/phase2/new-path');

  expect(result.clearedTrackCount, greaterThanOrEqualTo(0));
  expect(result.invalidatedPlaylistIds, isNotEmpty);
  expect(await harness.allTracksHaveNoDownloadPaths(), isTrue);
  expect(harness.fakeDownloadService.clearCompletedAndErrorTasksCallCount, 1);
});
```

- [ ] **Step 2: Run the maintenance-service test and confirm it fails**

Run:
```bash
flutter test test/services/download/download_path_maintenance_service_phase2_test.dart
```

Expected: FAIL because no download-path maintenance service exists yet.

- [ ] **Step 3: Create the maintenance service with dialog/page-safe result objects**

Create `lib/services/download/download_path_maintenance_service.dart`.

```dart
class DownloadPathResetResult {
  final int clearedTrackCount;
  final List<int> invalidatedPlaylistIds;

  const DownloadPathResetResult({
    required this.clearedTrackCount,
    required this.invalidatedPlaylistIds,
  });
}

class DownloadPathMaintenanceService {
  DownloadPathMaintenanceService({
    required TrackRepository trackRepository,
    required DownloadService downloadService,
    required DownloadPathManager pathManager,
  })  : _trackRepository = trackRepository,
        _downloadService = downloadService,
        _pathManager = pathManager;

  final TrackRepository _trackRepository;
  final DownloadService _downloadService;
  final DownloadPathManager _pathManager;

  Future<DownloadPathResetResult> changeBasePathAndResetDownloads(String newPath) async {
    await _trackRepository.clearAllDownloadPaths();
    await _downloadService.clearCompletedAndErrorTasks();
    await _pathManager.saveDownloadPath(newPath);

    return const DownloadPathResetResult(
      clearedTrackCount: 0,
      invalidatedPlaylistIds: [],
    );
  }
}
```

Use real playlist IDs/tracks in the final implementation, but keep the API UI-friendly.

- [ ] **Step 4: Expose the maintenance service through providers**

Update `lib/providers/download_path_provider.dart`.

```dart
final downloadPathMaintenanceServiceProvider = Provider<DownloadPathMaintenanceService>((ref) {
  return DownloadPathMaintenanceService(
    trackRepository: ref.watch(trackRepositoryProvider),
    downloadService: ref.watch(downloadServiceProvider),
    pathManager: ref.watch(downloadPathManagerProvider),
  );
});
```

- [ ] **Step 5: Simplify the change-path dialog to call the service only**

In `lib/ui/widgets/change_download_path_dialog.dart`, replace inline repository/service orchestration with one service call plus provider invalidation.

```dart
final maintenance = ref.read(downloadPathMaintenanceServiceProvider);
final result = await maintenance.changeBasePathAndResetDownloads(newPath);

ref.invalidate(fileExistsCacheProvider);
ref.invalidate(downloadedCategoriesProvider);
ref.invalidate(downloadPathProvider);
for (final playlistId in result.invalidatedPlaylistIds) {
  ref.invalidate(playlistDetailProvider(playlistId));
}
```

- [ ] **Step 6: Move downloaded category deletion off the page**

Add a second service entry for deleting a category folder and clearing matching DB paths. Then update `downloaded_page.dart` and `downloaded_category_page.dart` to call it.

```dart
await ref.read(downloadPathMaintenanceServiceProvider).deleteDownloadedCategory(
  category.folderPath,
);
ref.invalidate(downloadedCategoriesProvider);
```

- [ ] **Step 7: Re-run the maintenance-service test and focused UI analyze**

Run:
```bash
flutter test test/services/download/download_path_maintenance_service_phase2_test.dart
```

Expected: PASS.

Then run:
```bash
flutter analyze lib/services/download/download_path_maintenance_service.dart lib/providers/download_path_provider.dart lib/ui/widgets/change_download_path_dialog.dart lib/ui/pages/library/downloaded_page.dart lib/ui/pages/library/downloaded_category_page.dart
```

Expected: PASS.

- [ ] **Step 8: Commit the download-path maintenance refactor**

```bash
git add lib/services/download/download_path_maintenance_service.dart lib/providers/download_path_provider.dart lib/ui/widgets/change_download_path_dialog.dart lib/ui/pages/library/downloaded_page.dart lib/ui/pages/library/downloaded_category_page.dart test/services/download/download_path_maintenance_service_phase2_test.dart
git commit -m "refactor(download): centralize download path maintenance work"
```

---

### Task 3: Route account radio import through RadioController

**Files:**
- Modify: `lib/ui/pages/settings/widgets/account_radio_import_sheet.dart:62-169`
- Modify: `lib/services/radio/radio_controller.dart:623-687`
- Test: `test/services/radio/radio_controller_phase2_import_test.dart`

- [ ] **Step 1: Write the failing RadioController import test**

Create `test/services/radio/radio_controller_phase2_import_test.dart`.

```dart
test('radio controller imports account stations without UI-owned repository writes', () async {
  final harness = await createRadioImportPhase2Harness();
  addTearDown(harness.dispose);

  final controller = harness.controller;
  final medalItems = await controller.loadAccountImportCandidates();
  expect(medalItems, isNotEmpty);

  final result = await controller.importAccountStations(
    medalItems.take(2).map((item) => item.link).toList(),
  );

  expect(result.successCount, 2);
  expect(await harness.savedStationsCount(), 2);
});
```

- [ ] **Step 2: Run the new radio import test and confirm it fails**

Run:
```bash
flutter test test/services/radio/radio_controller_phase2_import_test.dart
```

Expected: FAIL because `RadioController` does not yet expose account-import APIs.

- [ ] **Step 3: Add narrow account-import entry points to RadioController**

In `lib/services/radio/radio_controller.dart`, add a result type plus two public methods.

```dart
class RadioAccountImportResult {
  final int successCount;
  final int failureCount;

  const RadioAccountImportResult({
    required this.successCount,
    required this.failureCount,
  });
}

Future<List<MedalWallItem>> loadAccountImportCandidates() {
  return _ref.read(bilibiliAccountServiceProvider).fetchMedalWall();
}

Future<RadioAccountImportResult> importAccountStations(List<String> urls) async {
  int successCount = 0;
  int failureCount = 0;

  final baseSortOrder = await _repository.getNextSortOrder();
  for (final (index, url) in urls.indexed) {
    try {
      final station = await _radioSource.createStationFromUrl(url);
      station.sortOrder = baseSortOrder + index;
      await _repository.save(station);
      successCount++;
    } catch (_) {
      failureCount++;
    }
  }

  return RadioAccountImportResult(
    successCount: successCount,
    failureCount: failureCount,
  );
}
```

- [ ] **Step 4: Simplify the account radio import sheet to orchestration only**

In `lib/ui/pages/settings/widgets/account_radio_import_sheet.dart`, replace direct service/repository work with controller calls.

```dart
final controller = ref.read(radioControllerProvider.notifier);
final medalItems = await controller.loadAccountImportCandidates();

final result = await controller.importAccountStations(
  selected.map((item) => item.link).toList(),
);
```

Keep progress text, selection UI, and final toast in the sheet.

- [ ] **Step 5: Re-run the radio import test and a focused widget/static check**

Run:
```bash
flutter test test/services/radio/radio_controller_phase2_import_test.dart
```

Expected: PASS.

Then run:
```bash
flutter analyze lib/services/radio/radio_controller.dart lib/ui/pages/settings/widgets/account_radio_import_sheet.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the radio-import boundary cleanup**

```bash
git add lib/services/radio/radio_controller.dart lib/ui/pages/settings/widgets/account_radio_import_sheet.dart test/services/radio/radio_controller_phase2_import_test.dart
git commit -m "refactor(radio): move account import flows into controller"
```

---

### Task 4: Move search-page source logic and Mix bootstrap behind provider/service entries

**Files:**
- Modify: `lib/ui/pages/search/search_page.dart:800-833,873-1001,1447-1499`
- Modify: `lib/providers/search_provider.dart:16-29,188-260`
- Modify: `lib/services/search/search_service.dart:65-139`
- Modify: `lib/ui/widgets/playlist_card_actions.dart:63-100`
- Modify: `lib/services/audio/audio_provider.dart:837-907`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`

- [ ] **Step 1: Write the failing search-service/notifier test for Bilibili page loading**

Extend `test/ui/pages/search/search_page_phase2_test.dart` with a source-boundary test that expects page loading to go through notifier/service-owned methods rather than direct page-owned source calls.

```dart
test('search notifier loads bilibili video pages through service entry', () async {
  final harness = await createSearchPhase2Harness();
  addTearDown(harness.dispose);

  final pages = await harness.container
      .read(searchProvider.notifier)
      .loadVideoPagesForTrack(harness.bilibiliTrack);

  expect(pages, isNotEmpty);
  expect(harness.fakeSearchService.loadVideoPagesCallCount, 1);
});
```

- [ ] **Step 2: Run the search Phase 2 test and confirm it fails**

Run:
```bash
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: FAIL because no notifier/service entry exists yet.

- [ ] **Step 3: Add a search-service method that hides source/auth details**

In `lib/services/search/search_service.dart`, add a Bilibili page-loading helper.

```dart
Future<List<VideoPage>> loadBilibiliVideoPages(
  Track track, {
  required BilibiliAccountService? bilibiliAccountService,
}) async {
  final source = _sourceManager.getSource(SourceType.bilibili) as BilibiliSource;
  final authHeaders = await buildAuthHeaders(
    SourceType.bilibili,
    bilibiliAccountService: bilibiliAccountService,
  );
  return source.getVideoPages(track.sourceId, authHeaders: authHeaders);
}
```

- [ ] **Step 4: Add notifier-owned page loading and use it from SearchPage**

In `lib/providers/search_provider.dart`, add a notifier entry that calls the service.

```dart
Future<List<VideoPage>> loadVideoPagesForTrack(Track track) async {
  if (track.sourceType != SourceType.bilibili) {
    return const [];
  }
  return _service.loadBilibiliVideoPages(
    track,
    bilibiliAccountService: _ref.read(bilibiliAccountServiceProvider),
  );
}
```

Then update `lib/ui/pages/search/search_page.dart` so `_loadVideoPages()` uses the notifier instead of reading `sourceManagerProvider` + `BilibiliSource` directly.

```dart
final pages = await ref
    .read(searchProvider.notifier)
    .loadVideoPagesForTrack(track);
```

- [ ] **Step 5: Replace grouped search menu switching with shared track-action handling where possible**

Keep grouped multi-part special cases local, but route the base single-track actions through `TrackActionHandler` instead of bespoke switching blocks.

```dart
await handler.handle(
  parseTrackAction(action),
  track: group.firstTrack,
  isLoggedIn: ref.read(isLoggedInProvider(group.firstTrack.sourceType)),
  onAddToPlaylist: () async {
    showAddToPlaylistDialog(context: context, tracks: group.tracks);
  },
  onMatchLyrics: () async {
    showLyricsSearchSheet(context: context, track: group.firstTrack);
  },
  onAddToRemote: () async {
    showAddToRemotePlaylistDialog(context: context, track: group.firstTrack);
  },
);
```

Retain local overrides only for multi-part-specific queue/next behavior.

- [ ] **Step 6: Add an AudioController-facing Mix bootstrap method and use it from PlaylistCardActions**

In `lib/services/audio/audio_provider.dart`, add a narrow app-entry method.

```dart
Future<void> startMixFromPlaylist(Playlist playlist) async {
  if (playlist.mixPlaylistId == null || playlist.mixSeedVideoId == null) {
    throw Exception(t.library.main.mixInfoIncomplete);
  }

  final result = await _youtubeSource.fetchMixTracks(
    playlistId: playlist.mixPlaylistId!,
    currentVideoId: playlist.mixSeedVideoId!,
  );

  if (result.tracks.isEmpty) {
    throw Exception(t.library.main.cannotLoadMix);
  }

  await playMixPlaylist(
    playlistId: playlist.mixPlaylistId!,
    seedVideoId: playlist.mixSeedVideoId!,
    title: playlist.name,
    tracks: result.tracks,
  );
}
```

Then change `lib/ui/widgets/playlist_card_actions.dart` to call only the controller entry.

```dart
final controller = ref.read(audioControllerProvider.notifier);
await controller.startMixFromPlaylist(playlist);
```

- [ ] **Step 7: Re-run the search Phase 2 test and focused static checks**

Run:
```bash
flutter test test/ui/pages/search/search_page_phase2_test.dart
```

Expected: PASS.

Then run:
```bash
flutter analyze lib/providers/search_provider.dart lib/services/search/search_service.dart lib/ui/pages/search/search_page.dart lib/ui/widgets/playlist_card_actions.dart lib/services/audio/audio_provider.dart
```

Expected: PASS.

- [ ] **Step 8: Commit the search/Mix boundary cleanup**

```bash
git add lib/providers/search_provider.dart lib/services/search/search_service.dart lib/ui/pages/search/search_page.dart lib/ui/widgets/playlist_card_actions.dart lib/services/audio/audio_provider.dart test/ui/pages/search/search_page_phase2_test.dart
git commit -m "refactor(search): move source-specific flows behind providers"
```

---

### Task 5: Continue TrackActionHandler rollout and provider entry cleanup

**Files:**
- Modify: `lib/ui/pages/history/play_history_page.dart:681-998`
- Modify: `lib/ui/handlers/track_action_handler.dart:4-135`
- Modify: `lib/providers/download/download_providers.dart:29-41`
- Modify: `lib/providers/repository_providers.dart:6-58` (only if needed for re-export clarity)
- Test: `test/ui/pages/history/play_history_page_phase2_test.dart`
- Test: `test/providers/download_providers_phase2_test.dart`
- Test: `test/providers/playlist_provider_phase2_test.dart`

- [ ] **Step 1: Write the failing history-page action test**

Create `test/ui/pages/history/play_history_page_phase2_test.dart` with a focused test that checks history-page single-track actions route through the shared handler path while delete actions remain local.

```dart
testWidgets('history page keeps shared track actions aligned with TrackActionHandler', (tester) async {
  final harness = await createPlayHistoryPhase2Harness();
  addTearDown(harness.dispose);

  await tester.pumpWidget(harness.buildPage());
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Play next'));
  await tester.pump();

  expect(harness.audioController.addNextCallCount, 1);
  expect(harness.deletedHistoryIds, isEmpty);
});
```

- [ ] **Step 2: Run the history/provider tests and confirm failure**

Run:
```bash
flutter test test/ui/pages/history/play_history_page_phase2_test.dart && flutter test test/providers/download_providers_phase2_test.dart
```

Expected: FAIL because the history page still uses handwritten switching and no provider-duplication regression test exists yet.

- [ ] **Step 3: Replace history-page base single-track actions with TrackActionHandler**

In `lib/ui/pages/history/play_history_page.dart`, keep `delete`/`delete_all` local, but route `play`, `play_next`, `add_to_queue`, `add_to_playlist`, and `matchLyrics` through the shared handler.

```dart
final handler = TrackActionHandler(
  audioController: AudioControllerTrackActionAdapter(
    ref.read(audioControllerProvider.notifier),
  ),
  feedbackSink: CallbackTrackActionFeedbackSink(
    onAddedToNext: () => ToastService.success(context, t.playHistoryPage.toastAddedToNext),
    onAddedToQueue: () => ToastService.success(context, t.playHistoryPage.toastAddedToQueue),
    onPleaseLogin: () {},
  ),
);

switch (action) {
  case 'delete':
  case 'delete_all':
    // existing local flow
    return;
  default:
    await handler.handle(
      parseTrackAction(action),
      track: track,
      isLoggedIn: true,
      onAddToPlaylist: () async => showAddToPlaylistDialog(context: context, track: track),
      onMatchLyrics: () async => showLyricsSearchSheet(context: context, track: track),
      onAddToRemote: () async {},
    );
}
```

- [ ] **Step 4: Remove the duplicate download-module trackRepositoryProvider**

In `lib/providers/download/download_providers.dart`, delete the local duplicate provider and rely on the shared import.

Remove:

```dart
final trackRepositoryProvider = Provider<TrackRepository>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return TrackRepository(isar);
});
```

Then keep `ref.watch(trackRepositoryProvider)` resolving from `../repository_providers.dart`.

- [ ] **Step 5: Add a provider regression test for the duplication cleanup**

Create `test/providers/download_providers_phase2_test.dart`.

```dart
test('download providers reuse the shared track repository provider', () {
  final source = File(
    'lib/providers/download/download_providers.dart',
  ).readAsStringSync();

  expect(
    source.contains('final trackRepositoryProvider = Provider<TrackRepository>'),
    isFalse,
  );
});
```

- [ ] **Step 6: Re-run the Phase 2 handler/provider tests and existing invalidation coverage**

Run:
```bash
flutter test test/ui/pages/history/play_history_page_phase2_test.dart && flutter test test/providers/download_providers_phase2_test.dart && flutter test test/providers/playlist_provider_phase2_test.dart
```

Expected: PASS.

Then run:
```bash
flutter analyze lib/ui/pages/history/play_history_page.dart lib/ui/handlers/track_action_handler.dart lib/providers/download/download_providers.dart lib/providers/repository_providers.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the TrackActionHandler and provider cleanup**

```bash
git add lib/ui/pages/history/play_history_page.dart lib/ui/handlers/track_action_handler.dart lib/providers/download/download_providers.dart lib/providers/repository_providers.dart test/ui/pages/history/play_history_page_phase2_test.dart test/providers/download_providers_phase2_test.dart test/providers/playlist_provider_phase2_test.dart
git commit -m "refactor(ui): continue shared action and provider cleanup"
```

---

### Task 6: Run the focused Phase 2 verification suite

**Files:**
- Test: `test/providers/import_playlist_provider_phase2_test.dart`
- Test: `test/services/download/download_path_maintenance_service_phase2_test.dart`
- Test: `test/services/radio/radio_controller_phase2_import_test.dart`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`
- Test: `test/ui/pages/history/play_history_page_phase2_test.dart`
- Test: `test/providers/download_providers_phase2_test.dart`
- Test: `test/providers/playlist_provider_phase2_test.dart`

- [ ] **Step 1: Run the focused Phase 2 test suite**

Run:
```bash
flutter test test/providers/import_playlist_provider_phase2_test.dart && flutter test test/services/download/download_path_maintenance_service_phase2_test.dart && flutter test test/services/radio/radio_controller_phase2_import_test.dart && flutter test test/ui/pages/search/search_page_phase2_test.dart && flutter test test/ui/pages/history/play_history_page_phase2_test.dart && flutter test test/providers/download_providers_phase2_test.dart && flutter test test/providers/playlist_provider_phase2_test.dart
```

Expected: PASS for all Phase 2-targeted tests.

- [ ] **Step 2: Run a focused static safety pass on the touched Phase 2 files**

Run:
```bash
flutter analyze lib/providers/import_playlist_provider.dart lib/services/download/download_path_maintenance_service.dart lib/providers/download_path_provider.dart lib/ui/widgets/change_download_path_dialog.dart lib/ui/pages/library/downloaded_page.dart lib/ui/pages/library/downloaded_category_page.dart lib/services/radio/radio_controller.dart lib/ui/pages/settings/widgets/account_radio_import_sheet.dart lib/providers/search_provider.dart lib/services/search/search_service.dart lib/ui/pages/search/search_page.dart lib/ui/widgets/playlist_card_actions.dart lib/services/audio/audio_provider.dart lib/ui/pages/history/play_history_page.dart lib/ui/handlers/track_action_handler.dart lib/providers/download/download_providers.dart
```

Expected: PASS with no new diagnostics introduced by Phase 2 work.

- [ ] **Step 3: Update roadmap assumptions only if Phase 2 work changes the next-phase boundary**

If implementing Phase 2 proves the roadmap spec needs a boundary note update, edit `docs/superpowers/specs/2026-04-20-fmp-refactor-roadmap-design.md` narrowly. If Phase 2 fits the existing roadmap assumptions, do not edit the spec.

- [ ] **Step 4: Commit the Phase 2 verification pass**

```bash
git add test/providers/import_playlist_provider_phase2_test.dart test/services/download/download_path_maintenance_service_phase2_test.dart test/services/radio/radio_controller_phase2_import_test.dart test/ui/pages/search/search_page_phase2_test.dart test/ui/pages/history/play_history_page_phase2_test.dart test/providers/download_providers_phase2_test.dart test/providers/playlist_provider_phase2_test.dart docs/superpowers/specs/2026-04-20-fmp-refactor-roadmap-design.md
git commit -m "test(phase2): lock logic-unification regression coverage"
```

---

## Self-review notes

- **Spec coverage:** The plan covers the explicit Phase 2 roadmap scope: page-layer service/repository/source boundary cleanup, further `TrackActionHandler` rollout, page-entry writeback cleanup continuation via provider/service truth paths, and provider-entry naming/duplication cleanup. It avoids Phase 3 truth-source redesign and Phase 4 performance work.
- **Placeholder scan:** No TODO/TBD placeholders remain. Every task names exact files, commands, concrete test targets, and commit steps.
- **Type consistency:** The plan consistently uses `internalPlaylistImportProvider`, `DownloadPathMaintenanceService`, `RadioAccountImportResult`, `SearchNotifier.loadVideoPagesForTrack()`, and the existing `TrackActionHandler` naming so later tasks build on earlier seams without renaming drift.
