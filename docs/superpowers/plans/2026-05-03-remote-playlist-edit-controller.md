# Remote Playlist Edit Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize remote playlist add/remove/sync orchestration for Bilibili, YouTube, and Netease behind a source-neutral planner/controller with structured partial-success results.

**Architecture:** Keep source-specific dialogs responsible for rendering and selection state, but move submit orchestration into `RemotePlaylistEditController`. The controller uses `RemotePlaylistEditPlanner` for add/remove transitions, source adapters for platform API calls, and existing remote sync services for imported-playlist refresh/local removal sync.

**Tech Stack:** Flutter/Dart, Riverpod providers, existing Bilibili/YouTube/Netease account playlist services, Isar-backed playlist/track models, `flutter_test` source-shape and behavior tests.

---

## Next Roadmap Phase

Phase 0 and Phase 1 are complete on local `main`. The approved roadmap's next dependency-safe phase is **Phase 2: Remote playlist edit result and planner/controller** (`docs/superpowers/specs/2026-05-02-program-logic-repair-roadmap-design.md:117-146`).

## File Structure

- Create `lib/services/library/remote_playlist_edit_result.dart`: immutable edit result, per-track failure, summary metadata, and merge helpers.
- Create `lib/services/library/remote_playlist_edit_planner.dart`: source-neutral selection transition planning and editable-track filtering.
- Create `lib/services/library/remote_playlist_edit_controller.dart`: controller, adapter interface, source adapters, and submit methods.
- Modify `lib/providers/remote_playlist_sync_provider.dart`: provide `RemotePlaylistEditController` with source adapters and existing sync services.
- Modify `lib/providers/account_provider.dart`: remove `remotePlaylistActionsServiceProvider` after consumers migrate.
- Modify `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart`: delegate `_submit()` to the controller.
- Modify `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart`: delegate `_submit()` to the controller.
- Modify `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart`: delegate `_submit()` to the controller.
- Modify `lib/ui/pages/library/playlist_detail_page.dart`: delegate remote removal to the controller.
- Delete `lib/services/library/remote_playlist_actions_service.dart` and `lib/services/library/remote_playlist_removal_sync_service.dart` once consumers are gone.
- Test `test/services/library/remote_playlist_edit_planner_test.dart`: planner transitions, missing tracks, mixed/logged-out skipped tracks.
- Test `test/services/library/remote_playlist_edit_controller_test.dart`: controller partial success, confirmed removal sync, source adapter behavior.
- Update existing tests under `test/services/library/remote_playlist_*_test.dart` and `test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart` for the new files.

---

### Task 1: Remote edit result and planner contract

**Files:**
- Create: `lib/services/library/remote_playlist_edit_result.dart`
- Create: `lib/services/library/remote_playlist_edit_planner.dart`
- Create: `test/services/library/remote_playlist_edit_planner_test.dart`
- Keep: `lib/services/library/remote_playlist_selection_changes.dart` until Task 5 cleanup

- [ ] **Step 1: Write planner/result tests**

Create `test/services/library/remote_playlist_edit_planner_test.dart` with these tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_edit_planner.dart';

void main() {
  group('RemotePlaylistEditPlanner', () {
    test('plans add/remove transitions and missing tracks per playlist', () {
      final tracks = [_track(SourceType.youtube, 1, 'a'), _track(SourceType.youtube, 2, 'b')];
      final plan = RemotePlaylistEditPlanner.planSelectionEdit(
        sourceType: SourceType.youtube,
        tracks: tracks,
        selectedPlaylistIds: {'full', 'partial'},
        originalPlaylistIds: {'full', 'removed'},
        deselectedPartialPlaylistIds: {'partial-removed'},
        existingTrackSourceIdsByPlaylist: {'partial': {'a'}},
        isLoggedIn: (_) => true,
      );

      expect(plan.playlistIdsToAdd, ['partial']);
      expect(plan.playlistIdsToRemove, ['removed', 'partial-removed']);
      expect(plan.missingSourceIdsFor('partial'), ['b']);
      expect(plan.editableTracks.map((track) => track.id), [1, 2]);
      expect(plan.skippedTrackIds, isEmpty);
    });

    test('represents mixed-source and logged-out tracks as skipped', () {
      final plan = RemotePlaylistEditPlanner.planSelectionEdit(
        sourceType: SourceType.youtube,
        tracks: [
          _track(SourceType.youtube, 1, 'yt'),
          _track(SourceType.bilibili, 2, 'BV'),
          _track(SourceType.netease, 3, 'ne'),
        ],
        selectedPlaylistIds: {'PL'},
        originalPlaylistIds: const {},
        deselectedPartialPlaylistIds: const {},
        existingTrackSourceIdsByPlaylist: const {},
        isLoggedIn: (sourceType) => sourceType == SourceType.youtube,
      );

      expect(plan.editableTracks.map((track) => track.id), [1]);
      expect(plan.skippedTrackIds, [2, 3]);
    });
  });
}

Track _track(SourceType sourceType, int id, String sourceId) => Track()
  ..id = id
  ..sourceType = sourceType
  ..sourceId = sourceId
  ..title = sourceId;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test --no-pub test/services/library/remote_playlist_edit_planner_test.dart`
Expected: FAIL with missing `remote_playlist_edit_planner.dart` / `RemotePlaylistEditPlanner`.

- [ ] **Step 3: Implement result and planner**

Create `lib/services/library/remote_playlist_edit_result.dart` with:

```dart
import '../../data/models/track.dart';

class RemotePlaylistEditFailure {
  final int trackId;
  final String remotePlaylistId;
  final Object error;
  const RemotePlaylistEditFailure({required this.trackId, required this.remotePlaylistId, required this.error});
}

class RemotePlaylistEditSummary {
  final int changedPlaylistCount;
  final int addedTrackCount;
  final int removedTrackCount;
  final int skippedTrackCount;
  final int failedTrackCount;
  const RemotePlaylistEditSummary({required this.changedPlaylistCount, required this.addedTrackCount, required this.removedTrackCount, required this.skippedTrackCount, required this.failedTrackCount});
}

class RemotePlaylistEditResult {
  final SourceType sourceType;
  final List<int> confirmedAddedTrackIds;
  final List<int> confirmedRemovedTrackIds;
  final List<int> skippedTrackIds;
  final List<RemotePlaylistEditFailure> failures;
  final List<String> changedRemotePlaylistIds;
  const RemotePlaylistEditResult({required this.sourceType, this.confirmedAddedTrackIds = const [], this.confirmedRemovedTrackIds = const [], this.skippedTrackIds = const [], this.failures = const [], this.changedRemotePlaylistIds = const []});

  bool get changedRemote => changedRemotePlaylistIds.isNotEmpty;
  bool get hasFailures => failures.isNotEmpty;
  List<int> get failedTrackIds => failures.map((failure) => failure.trackId).toSet().toList(growable: false);
  RemotePlaylistEditSummary get summary => RemotePlaylistEditSummary(
        changedPlaylistCount: changedRemotePlaylistIds.toSet().length,
        addedTrackCount: confirmedAddedTrackIds.toSet().length,
        removedTrackCount: confirmedRemovedTrackIds.toSet().length,
        skippedTrackCount: skippedTrackIds.toSet().length,
        failedTrackCount: failedTrackIds.length,
      );

  RemotePlaylistEditResult merge(RemotePlaylistEditResult other) {
    assert(sourceType == other.sourceType);
    return RemotePlaylistEditResult(
      sourceType: sourceType,
      confirmedAddedTrackIds: {...confirmedAddedTrackIds, ...other.confirmedAddedTrackIds}.toList(),
      confirmedRemovedTrackIds: {...confirmedRemovedTrackIds, ...other.confirmedRemovedTrackIds}.toList(),
      skippedTrackIds: {...skippedTrackIds, ...other.skippedTrackIds}.toList(),
      failures: [...failures, ...other.failures],
      changedRemotePlaylistIds: {...changedRemotePlaylistIds, ...other.changedRemotePlaylistIds}.toList(),
    );
  }
}
```

Create `lib/services/library/remote_playlist_edit_planner.dart` with:

```dart
import '../../data/models/track.dart';
import 'remote_playlist_selection_changes.dart';

class RemotePlaylistEditPlan {
  final SourceType sourceType;
  final List<Track> editableTracks;
  final List<int> skippedTrackIds;
  final List<String> playlistIdsToAdd;
  final List<String> playlistIdsToRemove;
  final Map<String, Set<String>> existingTrackSourceIdsByPlaylist;
  const RemotePlaylistEditPlan({required this.sourceType, required this.editableTracks, required this.skippedTrackIds, required this.playlistIdsToAdd, required this.playlistIdsToRemove, required this.existingTrackSourceIdsByPlaylist});

  List<String> sourceIdsFor(Iterable<Track> tracks) => tracks.map((track) => track.sourceId).toList(growable: false);
  List<String> missingSourceIdsFor(String playlistId) => missingRemoteTrackIds<String>(allTrackIds: sourceIdsFor(editableTracks), existingTrackIds: existingTrackSourceIdsByPlaylist[playlistId] ?? const <String>{});
}

class RemotePlaylistEditPlanner {
  const RemotePlaylistEditPlanner._();

  static RemotePlaylistEditPlan planSelectionEdit({required SourceType sourceType, required List<Track> tracks, required Set<String> selectedPlaylistIds, required Set<String> originalPlaylistIds, required Set<String> deselectedPartialPlaylistIds, required Map<String, Set<String>> existingTrackSourceIdsByPlaylist, required bool Function(SourceType sourceType) isLoggedIn}) {
    final editable = <Track>[];
    final skipped = <int>[];
    for (final track in tracks) {
      if (track.sourceType == sourceType && isLoggedIn(track.sourceType)) {
        editable.add(track);
      } else {
        skipped.add(track.id);
      }
    }
    final changes = computeRemotePlaylistSelectionChanges<String>(selectedIds: selectedPlaylistIds, originalIds: originalPlaylistIds, deselectedPartialIds: deselectedPartialPlaylistIds);
    return RemotePlaylistEditPlan(sourceType: sourceType, editableTracks: editable, skippedTrackIds: skipped, playlistIdsToAdd: changes.toAdd, playlistIdsToRemove: changes.toRemove, existingTrackSourceIdsByPlaylist: existingTrackSourceIdsByPlaylist);
  }
}
```

- [ ] **Step 4: Run planner tests**

Run: `flutter test --no-pub test/services/library/remote_playlist_edit_planner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/library/remote_playlist_edit_result.dart lib/services/library/remote_playlist_edit_planner.dart test/services/library/remote_playlist_edit_planner_test.dart
git commit -m "feat(remote): add playlist edit planner result"
```

---

### Task 2: Controller and source adapters

**Files:**
- Create: `lib/services/library/remote_playlist_edit_controller.dart`
- Create: `test/services/library/remote_playlist_edit_controller_test.dart`
- Modify: `lib/providers/remote_playlist_sync_provider.dart`

- [ ] **Step 1: Write controller behavior tests**

Create `test/services/library/remote_playlist_edit_controller_test.dart` with this complete test scaffold:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_edit_controller.dart';
import 'package:fmp/services/library/remote_playlist_edit_planner.dart';
import 'package:fmp/services/library/remote_playlist_edit_result.dart';

void main() {
  group('RemotePlaylistEditController', () {
    test('submitSelectionEdit refreshes changed remote playlists', () async {
      final refreshed = <String>[];
      final controller = _controller(
        adapter: _FakeAdapter(addConfirmedIds: [1], changedIds: ['PL']),
        refreshRemoteIds: (sourceType, remoteIds) async => refreshed.addAll(remoteIds),
      );

      final result = await controller.submitSelectionEdit(
        sourceType: SourceType.youtube,
        tracks: [_track(SourceType.youtube, 1, 'a')],
        selectedPlaylistIds: {'PL'},
        originalPlaylistIds: const {},
        deselectedPartialPlaylistIds: const {},
        existingTrackSourceIdsByPlaylist: const {},
      );

      expect(result.confirmedAddedTrackIds, [1]);
      expect(refreshed, ['PL']);
    });

    test('syncs only confirmed remote removals to local imported playlist', () async {
      final playlist = Playlist()
        ..id = 9
        ..name = 'Imported'
        ..sourceUrl = 'https://www.youtube.com/playlist?list=PL'
        ..importSourceType = SourceType.youtube;
      final syncedLocalIds = <int>[];
      final refreshedIds = <String>[];
      final controller = _controller(
        adapter: _FakeAdapter(removeConfirmedIds: [1], skippedIds: [2], changedIds: ['PL']),
        removeLocalTracks: (_, trackIds) async => syncedLocalIds.addAll(trackIds),
        refreshRemoteIds: (sourceType, remoteIds) async => refreshedIds.addAll(remoteIds),
      );

      final result = await controller.removeTracksFromImportedPlaylist(
        playlist: playlist,
        tracks: [_track(SourceType.youtube, 1, 'ok'), _track(SourceType.youtube, 2, 'missing')],
      );

      expect(result.confirmedRemovedTrackIds, [1]);
      expect(result.skippedTrackIds, [2]);
      expect(syncedLocalIds, [1]);
      expect(refreshedIds, ['PL']);
    });

    test('removeTracksFromImportedPlaylist skips invalid remote playlist URLs', () async {
      final controller = _controller(adapter: _FakeAdapter());
      final result = await controller.removeTracksFromImportedPlaylist(
        playlist: Playlist()
          ..id = 1
          ..name = 'Bad'
          ..sourceUrl = 'https://example.test/no-id'
          ..importSourceType = SourceType.youtube,
        tracks: [_track(SourceType.youtube, 7, 'yt')],
      );

      expect(result.changedRemote, isFalse);
      expect(result.skippedTrackIds, [7]);
    });
  });

  group('source adapters', () {
    test('YouTube adapter skips removals when setVideoId is missing', () async {
      final removeCalls = <String>[];
      final adapter = YouTubeRemotePlaylistEditAdapter(
        addToPlaylist: (_, __) async {},
        getSetVideoId: (playlistId, videoId) async => videoId == 'ok' ? 'set-ok' : null,
        removeFromPlaylist: (playlistId, videoId, setVideoId) async => removeCalls.add('$playlistId:$videoId:$setVideoId'),
      );

      final result = await adapter.submit(RemotePlaylistEditPlan(
        sourceType: SourceType.youtube,
        editableTracks: [_track(SourceType.youtube, 1, 'ok'), _track(SourceType.youtube, 2, 'missing')],
        skippedTrackIds: const [],
        playlistIdsToAdd: const [],
        playlistIdsToRemove: const ['PL'],
        existingTrackSourceIdsByPlaylist: const {},
      ));

      expect(result.confirmedRemovedTrackIds, [1]);
      expect(result.skippedTrackIds, [2]);
      expect(result.changedRemotePlaylistIds, ['PL']);
      expect(removeCalls, ['PL:ok:set-ok']);
    });

    test('Netease adapter adds only missing tracks for partial playlists', () async {
      final addCalls = <String>[];
      final adapter = NeteaseRemotePlaylistEditAdapter(
        addTracksToPlaylist: (playlistId, trackIds) async => addCalls.add('$playlistId:${trackIds.join(',')}'),
        removeTracksFromPlaylist: (_, __) async {},
      );

      final result = await adapter.submit(RemotePlaylistEditPlan(
        sourceType: SourceType.netease,
        editableTracks: [_track(SourceType.netease, 1, '11'), _track(SourceType.netease, 2, '22')],
        skippedTrackIds: const [],
        playlistIdsToAdd: const ['P'],
        playlistIdsToRemove: const [],
        existingTrackSourceIdsByPlaylist: const {'P': {'11'}},
      ));

      expect(result.confirmedAddedTrackIds, [2]);
      expect(result.changedRemotePlaylistIds, ['P']);
      expect(addCalls, ['P:22']);
    });
  });
}

RemotePlaylistEditController _controller({
  RemotePlaylistEditAdapter? adapter,
  Future<void> Function(SourceType sourceType, Iterable<String> remoteIds)? refreshRemoteIds,
  Future<void> Function(int playlistId, List<int> trackIds)? removeLocalTracks,
}) {
  final fallback = adapter ?? _FakeAdapter();
  return RemotePlaylistEditController(
    bilibiliAdapter: fallback,
    youtubeAdapter: fallback,
    neteaseAdapter: fallback,
    refreshMatchingImportedPlaylists: ({required sourceType, required remotePlaylistIds}) async => refreshRemoteIds?.call(sourceType, remotePlaylistIds),
    removeTracksFromLocalPlaylist: removeLocalTracks ?? (_, __) async {},
    isLoggedIn: (_) => true,
  );
}

class _FakeAdapter implements RemotePlaylistEditAdapter {
  _FakeAdapter({this.addConfirmedIds = const [], this.removeConfirmedIds = const [], this.skippedIds = const [], this.changedIds = const []});

  final List<int> addConfirmedIds;
  final List<int> removeConfirmedIds;
  final List<int> skippedIds;
  final List<String> changedIds;

  @override
  Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan) async {
    return RemotePlaylistEditResult(
      sourceType: plan.sourceType,
      confirmedAddedTrackIds: addConfirmedIds,
      confirmedRemovedTrackIds: removeConfirmedIds,
      skippedTrackIds: skippedIds,
      changedRemotePlaylistIds: changedIds,
    );
  }
}

Track _track(SourceType sourceType, int id, String sourceId) => Track()
  ..id = id
  ..sourceType = sourceType
  ..sourceId = sourceId
  ..title = sourceId;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test --no-pub test/services/library/remote_playlist_edit_controller_test.dart`
Expected: FAIL with missing `remote_playlist_edit_controller.dart`.

- [ ] **Step 3: Implement controller contracts**

Implement `RemotePlaylistEditAdapter` with `Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan)`. Implement `RemotePlaylistEditController.submitSelectionEdit(...)` and `removeTracksFromImportedPlaylist(...)` with these public signatures:

```dart
typedef RefreshMatchingImportedPlaylists = Future<void> Function({
  required SourceType sourceType,
  required Iterable<String> remotePlaylistIds,
});
typedef RemoveTracksFromLocalPlaylist = Future<void> Function(
  int playlistId,
  List<int> trackIds,
);
typedef IsRemoteSourceLoggedIn = bool Function(SourceType sourceType);

abstract class RemotePlaylistEditAdapter {
  Future<RemotePlaylistEditResult> submit(RemotePlaylistEditPlan plan);
}

class RemotePlaylistEditController {
  Future<RemotePlaylistEditResult> submitSelectionEdit({
    required SourceType sourceType,
    required List<Track> tracks,
    required Set<String> selectedPlaylistIds,
    required Set<String> originalPlaylistIds,
    required Set<String> deselectedPartialPlaylistIds,
    required Map<String, Set<String>> existingTrackSourceIdsByPlaylist,
  });

  Future<RemotePlaylistEditResult> removeTracksFromImportedPlaylist({
    required Playlist playlist,
    required List<Track> tracks,
  });
}
```

The controller flow must be:

```dart
final plan = RemotePlaylistEditPlanner.planSelectionEdit(...);
final result = await _adapterFor(plan.sourceType).submit(plan);
if (result.changedRemote) {
  await refreshMatchingImportedPlaylists(
    sourceType: plan.sourceType,
    remotePlaylistIds: result.changedRemotePlaylistIds,
  );
}
if (localRemovalPlaylist != null && result.confirmedRemovedTrackIds.isNotEmpty) {
  await removeTracksFromLocalPlaylist(
    localRemovalPlaylist.id,
    result.confirmedRemovedTrackIds,
  );
}
return result;
```

Implement source adapters in the same file using injectable callbacks, not concrete service classes:

- `BilibiliRemotePlaylistEditAdapter({required getVideoAid, required updateVideoFavorites})`: per editable track, call `getVideoAid(track)`, then `updateVideoFavorites(videoAid: aid, addFolderIds: parsedAddIds, removeFolderIds: parsedRemoveIds)` using only missing add folders.
- `YouTubeRemotePlaylistEditAdapter({required addToPlaylist, required getSetVideoId, required removeFromPlaylist})`: call `addToPlaylist` for missing adds; for removals call `getSetVideoId`, skip when null, otherwise call `removeFromPlaylist`.
- `NeteaseRemotePlaylistEditAdapter({required addTracksToPlaylist, required removeTracksFromPlaylist})`: call `addTracksToPlaylist(playlistId, missingIds)` and `removeTracksFromPlaylist(playlistId, editableSourceIds)` per playlist.

Each adapter must catch per-track or per-playlist failures, append `RemotePlaylistEditFailure`, continue remaining operations, and only include a track ID in confirmed lists after that remote operation succeeds.

- [ ] **Step 4: Wire provider**

In `lib/providers/remote_playlist_sync_provider.dart`, add imports for account providers/services and create:

```dart
final remotePlaylistEditControllerProvider = Provider<RemotePlaylistEditController>((ref) {
  final bilibiliService = ref.watch(bilibiliFavoritesServiceProvider);
  final youtubeService = ref.watch(youtubePlaylistServiceProvider);
  final neteaseService = ref.watch(neteasePlaylistServiceProvider);

  return RemotePlaylistEditController(
    bilibiliAdapter: BilibiliRemotePlaylistEditAdapter(
      getVideoAid: bilibiliService.getVideoAid,
      updateVideoFavorites: bilibiliService.updateVideoFavorites,
    ),
    youtubeAdapter: YouTubeRemotePlaylistEditAdapter(
      addToPlaylist: youtubeService.addToPlaylist,
      getSetVideoId: youtubeService.getSetVideoId,
      removeFromPlaylist: youtubeService.removeFromPlaylist,
    ),
    neteaseAdapter: NeteaseRemotePlaylistEditAdapter(
      addTracksToPlaylist: neteaseService.addTracksToPlaylist,
      removeTracksFromPlaylist: neteaseService.removeTracksFromPlaylist,
    ),
    refreshMatchingImportedPlaylists: ({required sourceType, required remotePlaylistIds}) => ref.read(remotePlaylistSyncServiceProvider).refreshMatchingImportedPlaylists(sourceType: sourceType, remotePlaylistIds: remotePlaylistIds),
    removeTracksFromLocalPlaylist: (playlistId, trackIds) => ref.read(playlistDetailProvider(playlistId).notifier).removeTracks(trackIds),
    isLoggedIn: (sourceType) => ref.read(isLoggedInProvider(sourceType)),
  );
});
```

- [ ] **Step 5: Verify and commit**

Run: `flutter test --no-pub test/services/library/remote_playlist_edit_planner_test.dart test/services/library/remote_playlist_edit_controller_test.dart test/services/library/remote_playlist_sync_service_test.dart`
Expected: PASS.

```bash
git add lib/services/library/remote_playlist_edit_controller.dart lib/providers/remote_playlist_sync_provider.dart test/services/library/remote_playlist_edit_controller_test.dart
git commit -m "feat(remote): add playlist edit controller"
```

---

### Task 3: Migrate add-to-remote dialogs to controller submits

**Files:**
- Modify: `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart`
- Modify: `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart`
- Modify: `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart`
- Test: `test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart`

- [ ] **Step 1: Add source-shape tests**

Extend `test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart` with assertions that each source dialog imports `remote_playlist_sync_provider.dart`, calls `remotePlaylistEditControllerProvider`, and no longer calls remote write APIs directly inside `_submit()`.

```dart
test('source remote playlist dialogs delegate submit orchestration to controller', () {
  for (final path in [
    'lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart',
    'lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart',
    'lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart',
  ]) {
    final source = File(path).readAsStringSync();
    expect(source, contains('remotePlaylistEditControllerProvider'));
    final submitBody = _methodBody(source, '_submit');
    expect(submitBody, contains('.submitSelectionEdit('));
    expect(submitBody, isNot(contains('updateVideoFavorites(')));
    expect(submitBody, isNot(contains('addToPlaylist(')));
    expect(submitBody, isNot(contains('removeFromPlaylist(')));
    expect(submitBody, isNot(contains('addTracksToPlaylist(')));
    expect(submitBody, isNot(contains('removeTracksFromPlaylist(')));
  }
});
```

- [ ] **Step 2: Run structure test to verify failure**

Run: `flutter test --no-pub test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart`
Expected: FAIL because dialogs still orchestrate submits directly.

- [ ] **Step 3: Replace each `_submit()` remote API loop**

In each dialog, keep loading, membership checking, partial state, and UI unchanged. Replace the remote write loops plus manual refresh calls with:

```dart
final result = await ref.read(remotePlaylistEditControllerProvider).submitSelectionEdit(
  sourceType: SourceType.youtube,
  tracks: _tracks,
  selectedPlaylistIds: _selectedIds,
  originalPlaylistIds: _originalIds,
  deselectedPartialPlaylistIds: _deselectedPartialIds,
  existingTrackSourceIdsByPlaylist: _existingTrackIdsByPlaylist,
);
```

Use `SourceType.bilibili` and `SourceType.netease` in their dialogs. Treat success as `result.changedRemote`; keep current `ToastService.success(context, t.remote.updated)` and `Navigator.pop(context, true)` on success. When `!result.changedRemote && result.hasFailures`, show `ToastService.error(context, result.failures.first.error.toString())` and keep the sheet open.

- [ ] **Step 4: Run dialog and controller tests**

Run: `flutter test --no-pub test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart test/services/library/remote_playlist_edit_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart
git commit -m "refactor(remote): route add dialogs through edit controller"
```

---

### Task 4: Migrate imported-playlist remote removal to controller

**Files:**
- Modify: `lib/ui/pages/library/playlist_detail_page.dart`
- Test: `test/services/library/remote_playlist_edit_controller_test.dart`
- Test: `test/services/library/remote_playlist_actions_service_test.dart` (remove after service deletion in Task 5)

- [ ] **Step 1: Add controller removal tests**

Extend `test/services/library/remote_playlist_edit_controller_test.dart` to cover Bilibili, YouTube, and Netease removal result semantics:

```dart
test('removeTracksFromImportedPlaylist skips invalid remote playlist URLs', () async {
  final controller = _controller(adapter: _FakeAdapter());
  final result = await controller.removeTracksFromImportedPlaylist(
    playlist: Playlist()..id = 1..name = 'Bad'..sourceUrl = 'https://example.test/no-id'..importSourceType = SourceType.youtube,
    tracks: [_track(SourceType.youtube, 7, 'yt')],
  );
  expect(result.changedRemote, isFalse);
  expect(result.skippedTrackIds, [7]);
});
```

- [ ] **Step 2: Run controller tests to verify missing coverage fails if behavior is absent**

Run: `flutter test --no-pub test/services/library/remote_playlist_edit_controller_test.dart`
Expected before migration: controller tests from Task 2 pass; the new invalid URL test fails until `removeTracksFromImportedPlaylist` parses and skips invalid URLs.

- [ ] **Step 3: Update `playlist_detail_page.dart` removal flows**

Replace both calls to `remotePlaylistActionsServiceProvider` plus `remotePlaylistRemovalSyncServiceProvider.syncAfterRemoval(...)` with:

```dart
final result = await ref.read(remotePlaylistEditControllerProvider).removeTracksFromImportedPlaylist(
  playlist: playlist,
  tracks: tracks,
);
if (!result.changedRemote) return;
```

For the single-track path pass `tracks: [track]`. Keep confirmation dialogs and existing source-specific exception catches until Task 5 removes unused imports. The controller must sync only `result.confirmedRemovedTrackIds` to local imported playlist.

- [ ] **Step 4: Run focused tests**

Run: `flutter test --no-pub test/services/library/remote_playlist_edit_controller_test.dart test/services/library/remote_playlist_removal_sync_service_test.dart`
Expected: PASS; removal sync service tests still pass until deletion.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/pages/library/playlist_detail_page.dart test/services/library/remote_playlist_edit_controller_test.dart
git commit -m "refactor(remote): route imported removals through edit controller"
```

---

### Task 5: Remove legacy remote action services and verify integration

**Files:**
- Delete: `lib/services/library/remote_playlist_actions_service.dart`
- Delete: `lib/services/library/remote_playlist_removal_sync_service.dart`
- Delete: `test/services/library/remote_playlist_actions_service_test.dart`
- Delete: `test/services/library/remote_playlist_removal_sync_service_test.dart`
- Modify: `lib/providers/account_provider.dart`
- Modify: `lib/providers/remote_playlist_sync_provider.dart`
- Modify: `test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart`

- [ ] **Step 1: Add source-shape cleanup assertions**

Extend the structure test:

```dart
test('legacy remote action services are removed from providers and UI', () {
  final accountProvider = File('lib/providers/account_provider.dart').readAsStringSync();
  final syncProvider = File('lib/providers/remote_playlist_sync_provider.dart').readAsStringSync();
  final detailPage = File('lib/ui/pages/library/playlist_detail_page.dart').readAsStringSync();

  expect(accountProvider, isNot(contains('remotePlaylistActionsServiceProvider')));
  expect(syncProvider, isNot(contains('remotePlaylistRemovalSyncServiceProvider')));
  expect(detailPage, isNot(contains('remotePlaylistActionsServiceProvider')));
  expect(detailPage, isNot(contains('remotePlaylistRemovalSyncServiceProvider')));
});
```

- [ ] **Step 2: Run cleanup test to verify failure**

Run: `flutter test --no-pub test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart`
Expected: FAIL while legacy providers/files still exist.

- [ ] **Step 3: Delete legacy providers and imports**

Remove `remotePlaylistActionsServiceProvider` from `lib/providers/account_provider.dart`. Remove `remotePlaylistRemovalSyncServiceProvider` from `lib/providers/remote_playlist_sync_provider.dart`. Delete the two legacy service files and their tests. Remove stale imports in `playlist_detail_page.dart` if analyzer reports them.

- [ ] **Step 4: Run final focused verification**

Run:

```bash
flutter test --no-pub test/services/library/remote_playlist_edit_planner_test.dart test/services/library/remote_playlist_edit_controller_test.dart test/services/library/remote_playlist_sync_service_test.dart test/services/library/remote_playlist_selection_changes_test.dart test/services/library/remote_playlist_track_filter_test.dart test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart
flutter analyze --no-pub
```

Expected: all tests PASS and analyzer reports `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/account_provider.dart lib/providers/remote_playlist_sync_provider.dart lib/ui/pages/library/playlist_detail_page.dart test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart
git rm lib/services/library/remote_playlist_actions_service.dart lib/services/library/remote_playlist_removal_sync_service.dart test/services/library/remote_playlist_actions_service_test.dart test/services/library/remote_playlist_removal_sync_service_test.dart
git commit -m "refactor(remote): remove legacy playlist action services"
```

---

### Task 6: Final review readiness

**Files:**
- Verify only; no planned production edits.

- [ ] **Step 1: Run the complete Phase 2 focused test set**

Run:

```bash
flutter test --no-pub test/services/library/remote_playlist_edit_planner_test.dart test/services/library/remote_playlist_edit_controller_test.dart test/services/library/remote_playlist_sync_service_test.dart test/services/library/remote_playlist_selection_changes_test.dart test/services/library/remote_playlist_track_filter_test.dart test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart
```

Expected: all tests PASS.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze --no-pub`
Expected: `No issues found!`.

- [ ] **Step 3: Inspect remaining orchestration bypasses**

Run searches:

```bash
grep -R "remotePlaylistActionsServiceProvider\|RemotePlaylistActionsService\|remotePlaylistRemovalSyncServiceProvider\|RemotePlaylistRemovalSyncService" lib test
grep -R "updateVideoFavorites(\|addToPlaylist(\|removeFromPlaylist(\|addTracksToPlaylist(\|removeTracksFromPlaylist(" lib/ui/widgets/dialogs lib/ui/pages/library/playlist_detail_page.dart
```

Expected: first command has no matches; second command has no submit-orchestration matches in remote playlist dialogs or playlist detail removal paths.

- [ ] **Step 4: Commit only if verification fixes were needed**

If Step 3 finds an in-scope bypass, fix it, rerun Steps 1-3, then commit:

```bash
git add lib/services/library/remote_playlist_edit_controller.dart lib/services/library/remote_playlist_edit_planner.dart lib/services/library/remote_playlist_edit_result.dart lib/providers/remote_playlist_sync_provider.dart lib/providers/account_provider.dart lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart lib/ui/pages/library/playlist_detail_page.dart test/services/library/remote_playlist_edit_controller_test.dart test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart
git commit -m "fix(remote): complete edit controller migration"
```

If no bypass is found, do not create a commit.

---

## Rollback Considerations

- Each task is a separate commit. To rollback UI migration while keeping contracts, revert Task 3 and Task 4 commits first.
- Task 1 and Task 2 are additive until Task 5 deletes legacy services.
- If provider wiring causes runtime issues, revert Task 5 to restore legacy services, then fix controller tests before deleting them again.

## Self-Review Checklist

- Spec coverage: Phase 2 acceptance criteria map to Tasks 1-5: partial adds (Tasks 1-3), confirmed removal local sync (Tasks 2 and 4), mixed/logged-out skips (Task 1), source-specific dialogs render only (Tasks 3 and 5), structured result (Task 1).
- Placeholder scan: no TBD/TODO/fill-in placeholders remain.
- Type consistency: `RemotePlaylistEditPlan`, `RemotePlaylistEditResult`, and `RemotePlaylistEditController` names/signatures are consistent across tasks.
