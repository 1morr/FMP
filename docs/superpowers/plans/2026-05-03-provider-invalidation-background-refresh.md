# Provider Invalidation and Background Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize playlist/download provider invalidation and make background refresh side effects named and observable.

**Architecture:** Add a provider-layer `LibraryInvalidationCoordinator` that owns Riverpod invalidation decisions for playlist detail, playlist cover, all-playlists snapshots, downloaded categories, downloaded category tracks, and file-existence cache. Existing provider/UI mutation code will call the coordinator instead of manually guessing provider families. Remote playlist sync keeps refresh orchestration in `RefreshManagerNotifier`, but uses a named fire-and-forget launcher that logs failures.

**Tech Stack:** Flutter, Dart, Riverpod, Isar-backed providers, `AppLogger`, `package:path`.

---

## File Structure

- Create: `lib/providers/library_invalidation_coordinator.dart`
  - Plain coordinator class with callback-injected invalidation functions.
  - `libraryInvalidationCoordinatorProvider` wiring callbacks to Riverpod providers.
  - Named methods: `playlistChanged`, `playlistsChanged`, `playlistMutationCompleted`, `downloadStateChanged`, `refreshLoadedPlaylistDetails`, `startRefreshLoadedPlaylistDetails`.
- Modify: `lib/providers/playlist_provider.dart:1-548`
  - Replace local playlist direct invalidations with coordinator calls.
  - Remove `PlaylistListNotifier.invalidatePlaylistProviders` after all call sites migrate.
  - Keep `PlaylistDetailNotifier.refreshTracks()` as the silent loaded-detail refresh primitive, but log failures.
- Modify: `lib/providers/refresh_provider.dart:172-191`
  - Replace refresh success invalidations with coordinator call.
- Modify: `lib/providers/download/download_event_handler.dart:7-73`
  - Replace three invalidation callbacks with one batched `downloadStateChanged` callback.
- Modify: `lib/providers/download/download_providers.dart:16-76`
  - Wire `DownloadEventHandler` to `libraryInvalidationCoordinatorProvider.downloadStateChanged`.
- Modify: `lib/providers/startup_download_sync_provider.dart:1-46`
  - Use coordinator for downloaded categories, file cache, and affected playlist cover/detail refreshes.
- Modify UI call sites that currently invalidate providers directly:
  - `lib/ui/pages/library/downloaded_page.dart:32-72,455-469`
  - `lib/ui/pages/library/downloaded_category_page.dart:739-752,1008-1020`
  - `lib/ui/pages/library/widgets/import_playlist_dialog.dart:498-518`
  - `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:459-560`
  - `lib/ui/widgets/change_download_path_dialog.dart:216-222`
  - `lib/ui/pages/library/import_preview_page.dart:295-299`
- Modify: `lib/providers/remote_playlist_sync_provider.dart:12-66`
  - Rename the callback concept to fire-and-forget imported playlist refresh.
  - Log background refresh failures through `AppLogger.error`.
- Modify: `lib/services/library/remote_playlist_sync_service.dart:3-29`
  - Rename constructor field from `refreshPlaylist` to `startPlaylistRefresh` so behavior is explicit.
- Modify: `CLAUDE.md`
  - Add `libraryInvalidationCoordinatorProvider` to the Riverpod provider list and document the rule.
- Test: `test/providers/library_invalidation_coordinator_test.dart`
- Test: `test/providers/download/download_event_handler_test.dart`
- Test: `test/providers/playlist_provider_phase2_test.dart`
- Test: `test/providers/remote_playlist_sync_service_test.dart` if the service tests exist; otherwise add coverage in a new `test/services/library/remote_playlist_sync_service_test.dart`.

### Task 1: Coordinator Contract and Tests

**Files:**
- Create: `lib/providers/library_invalidation_coordinator.dart`
- Create: `test/providers/library_invalidation_coordinator_test.dart`

- [ ] **Step 1: Write failing coordinator tests**

Create `test/providers/library_invalidation_coordinator_test.dart` with these tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/library_invalidation_coordinator.dart';
import 'package:fmp/services/library/playlist_mutation_service.dart';

void main() {
  group('LibraryInvalidationCoordinator', () {
    test('playlistChanged invalidates detail, cover, and all snapshots', () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.playlistChanged(7);

      expect(recorder.detailIds, [7]);
      expect(recorder.coverIds, [7]);
      expect(recorder.allPlaylistInvalidations, 1);
      expect(recorder.downloadCategoryInvalidations, 0);
    });

    test('playlistsChanged deduplicates playlist ids in first-seen order', () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.playlistsChanged([3, 3, 5, 3, 8], includeAll: false);

      expect(recorder.detailIds, [3, 5, 8]);
      expect(recorder.coverIds, [3, 5, 8]);
      expect(recorder.allPlaylistInvalidations, 0);
    });

    test('playlistMutationCompleted uses affected ids and cover flag', () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.playlistMutationCompleted(
        const PlaylistMutationResult(
          playlistId: 4,
          affectedPlaylistIds: [9, 4],
          addedTrackIds: [11],
          coverChanged: true,
          playlistChanged: true,
        ),
      );

      expect(recorder.detailIds, [4, 9]);
      expect(recorder.coverIds, [4, 9]);
      expect(recorder.allPlaylistInvalidations, 1);
    });

    test('downloadStateChanged derives category paths and refreshes playlists', () {
      final recorder = _InvalidationRecorder();
      final coordinator = recorder.createCoordinator();

      coordinator.downloadStateChanged(
        savePaths: ['/downloads/List A/Video 1/audio.m4a'],
        affectedPlaylistIds: [6, 6, 7],
      );

      expect(recorder.fileCacheInvalidations, 1);
      expect(recorder.downloadCategoryInvalidations, 1);
      expect(recorder.downloadCategoryTrackPaths, ['/downloads/List A']);
      expect(recorder.startedRefreshIds, [6, 7]);
      expect(recorder.coverIds, [6, 7]);
    });

    test('refreshLoadedPlaylistDetails logs failed silent refreshes', () async {
      final recorder = _InvalidationRecorder(failingRefreshIds: {5});
      final coordinator = recorder.createCoordinator();

      await coordinator.refreshLoadedPlaylistDetails([5], reason: 'test');

      expect(recorder.refreshIds, [5]);
      expect(recorder.loggedErrors.single.$1, contains('test'));
      expect(recorder.loggedErrors.single.$2, isA<StateError>());
    });
  });
}

class _InvalidationRecorder {
  _InvalidationRecorder({this.failingRefreshIds = const {}});

  final Set<int> failingRefreshIds;
  final detailIds = <int>[];
  final coverIds = <int>[];
  final downloadCategoryTrackPaths = <String>[];
  final refreshIds = <int>[];
  final startedRefreshIds = <int>[];
  final loggedErrors = <(String, Object)>[];
  int allPlaylistInvalidations = 0;
  int downloadCategoryInvalidations = 0;
  int fileCacheInvalidations = 0;

  LibraryInvalidationCoordinator createCoordinator() {
    return LibraryInvalidationCoordinator(
      invalidateAllPlaylists: () => allPlaylistInvalidations++,
      invalidatePlaylistDetail: detailIds.add,
      invalidatePlaylistCover: coverIds.add,
      invalidateDownloadedCategories: () => downloadCategoryInvalidations++,
      invalidateDownloadedCategoryTracks: downloadCategoryTrackPaths.add,
      invalidateFileExistsCache: () => fileCacheInvalidations++,
      refreshLoadedPlaylistDetail: (playlistId) async {
        refreshIds.add(playlistId);
        if (failingRefreshIds.contains(playlistId)) {
          throw StateError('refresh failed for $playlistId');
        }
      },
      startRefreshLoadedPlaylistDetail: (playlistId) {
        startedRefreshIds.add(playlistId);
      },
      logBackgroundError: (message, error, stackTrace) {
        loggedErrors.add((message, error));
      },
    );
  }
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `flutter test test/providers/library_invalidation_coordinator_test.dart`

Expected: FAIL because `library_invalidation_coordinator.dart` does not exist.

- [ ] **Step 3: Implement the coordinator and provider wiring**

Create `lib/providers/library_invalidation_coordinator.dart` with the tested API. Use this structure:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/logger.dart';
import '../services/library/playlist_mutation_service.dart';
import 'download/download_providers.dart';
import 'download/file_exists_cache.dart';
import 'playlist_provider.dart';

typedef LogBackgroundError = void Function(
  String message,
  Object error,
  StackTrace? stackTrace,
);

class LibraryInvalidationCoordinator {
  const LibraryInvalidationCoordinator({
    required this.invalidateAllPlaylists,
    required this.invalidatePlaylistDetail,
    required this.invalidatePlaylistCover,
    required this.invalidateDownloadedCategories,
    required this.invalidateDownloadedCategoryTracks,
    required this.invalidateFileExistsCache,
    required this.refreshLoadedPlaylistDetail,
    required this.startRefreshLoadedPlaylistDetail,
    required this.logBackgroundError,
  });

  final void Function() invalidateAllPlaylists;
  final void Function(int playlistId) invalidatePlaylistDetail;
  final void Function(int playlistId) invalidatePlaylistCover;
  final void Function() invalidateDownloadedCategories;
  final void Function(String categoryPath) invalidateDownloadedCategoryTracks;
  final void Function() invalidateFileExistsCache;
  final Future<void> Function(int playlistId) refreshLoadedPlaylistDetail;
  final void Function(int playlistId) startRefreshLoadedPlaylistDetail;
  final LogBackgroundError logBackgroundError;

  void playlistChanged(
    int playlistId, {
    bool tracksChanged = true,
    bool coverChanged = true,
    bool includeAll = true,
  }) {
    playlistsChanged(
      [playlistId],
      tracksChanged: tracksChanged,
      coverChanged: coverChanged,
      includeAll: includeAll,
    );
  }

  void playlistsChanged(
    Iterable<int> playlistIds, {
    bool tracksChanged = true,
    bool coverChanged = true,
    bool includeAll = true,
  }) {
    final ids = _dedupeInOrder(playlistIds);
    if (includeAll) {
      invalidateAllPlaylists();
    }
    for (final playlistId in ids) {
      if (tracksChanged) {
        invalidatePlaylistDetail(playlistId);
      }
      if (coverChanged) {
        invalidatePlaylistCover(playlistId);
      }
    }
  }

  void playlistMutationCompleted(PlaylistMutationResult result) {
    final ids = result.affectedPlaylistIds.isEmpty
        ? [result.playlistId]
        : [result.playlistId, ...result.affectedPlaylistIds];
    playlistsChanged(
      ids,
      tracksChanged: result.playlistChanged,
      coverChanged: result.coverChanged,
      includeAll: result.playlistChanged || result.coverChanged,
    );
  }

  void downloadStateChanged({
    Iterable<String> savePaths = const [],
    Iterable<String> categoryPaths = const [],
    Iterable<int> affectedPlaylistIds = const [],
    bool includeDownloadedCategories = true,
    bool fileExistsChanged = true,
  }) {
    if (fileExistsChanged) {
      invalidateFileExistsCache();
    }
    if (includeDownloadedCategories) {
      invalidateDownloadedCategories();
    }

    final derivedCategoryPaths = savePaths.map((path) => p.dirname(p.dirname(path)));
    for (final categoryPath in _dedupeInOrder([
      ...categoryPaths,
      ...derivedCategoryPaths,
    ])) {
      invalidateDownloadedCategoryTracks(categoryPath);
    }

    final playlistIds = _dedupeInOrder(affectedPlaylistIds);
    for (final playlistId in playlistIds) {
      startRefreshLoadedPlaylistDetail(playlistId);
    }
    playlistsChanged(
      playlistIds,
      tracksChanged: false,
      coverChanged: true,
      includeAll: false,
    );
  }

  Future<void> refreshLoadedPlaylistDetails(
    Iterable<int> playlistIds, {
    required String reason,
  }) async {
    for (final playlistId in _dedupeInOrder(playlistIds)) {
      try {
        await refreshLoadedPlaylistDetail(playlistId);
      } catch (error, stackTrace) {
        logBackgroundError(
          'Failed to refresh loaded playlist detail after $reason: $playlistId',
          error,
          stackTrace,
        );
      }
    }
  }

  void startRefreshLoadedPlaylistDetails(
    Iterable<int> playlistIds, {
    required String reason,
  }) {
    unawaited(refreshLoadedPlaylistDetails(playlistIds, reason: reason));
  }
}

final libraryInvalidationCoordinatorProvider =
    Provider<LibraryInvalidationCoordinator>((ref) {
  return LibraryInvalidationCoordinator(
    invalidateAllPlaylists: () => ref.invalidate(allPlaylistsProvider),
    invalidatePlaylistDetail: (playlistId) {
      ref.invalidate(playlistDetailProvider(playlistId));
    },
    invalidatePlaylistCover: (playlistId) {
      ref.invalidate(playlistCoverProvider(playlistId));
    },
    invalidateDownloadedCategories: () {
      ref.invalidate(downloadedCategoriesProvider);
    },
    invalidateDownloadedCategoryTracks: (categoryPath) {
      ref.invalidate(downloadedCategoryTracksProvider(categoryPath));
    },
    invalidateFileExistsCache: () => ref.invalidate(fileExistsCacheProvider),
    refreshLoadedPlaylistDetail: (playlistId) {
      return ref.read(playlistDetailProvider(playlistId).notifier).refreshTracks();
    },
    startRefreshLoadedPlaylistDetail: (playlistId) {
      ref.read(playlistDetailProvider(playlistId).notifier).refreshTracks();
    },
    logBackgroundError: (message, error, stackTrace) {
      AppLogger.error(message, error, stackTrace, 'LibraryInvalidation');
    },
  );
});

List<T> _dedupeInOrder<T>(Iterable<T> values) {
  final seen = <T>{};
  final result = <T>[];
  for (final value in values) {
    if (seen.add(value)) {
      result.add(value);
    }
  }
  return result;
}
```

- [ ] **Step 4: Run coordinator tests to verify they pass**

Run: `flutter test test/providers/library_invalidation_coordinator_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/library_invalidation_coordinator.dart test/providers/library_invalidation_coordinator_test.dart
git commit -m "feat(providers): add library invalidation coordinator"
```

### Task 2: Playlist Provider Migration

**Files:**
- Modify: `lib/providers/playlist_provider.dart:1-548`
- Modify: `test/providers/playlist_provider_phase2_test.dart:18-140`

- [ ] **Step 1: Update tests to use the coordinator instead of the playlist notifier helper**

In `test/providers/playlist_provider_phase2_test.dart`, add:

```dart
import 'package:fmp/providers/library_invalidation_coordinator.dart';
```

Replace the call in the first test:

```dart
notifier.invalidatePlaylistProviders(
  playlist.id,
  includeAllPlaylists: true,
);
```

with:

```dart
harness.container
    .read(libraryInvalidationCoordinatorProvider)
    .playlistChanged(playlist.id);
```

Replace the call in the second test:

```dart
notifier.invalidatePlaylistProviders(playlist.id);
```

with:

```dart
harness.container
    .read(libraryInvalidationCoordinatorProvider)
    .playlistChanged(playlist.id, includeAll: false);
```

- [ ] **Step 2: Run playlist provider tests to verify current migration target**

Run: `flutter test test/providers/playlist_provider_phase2_test.dart`

Expected: PASS before production changes because the new coordinator exists and invalidates the same providers.

- [ ] **Step 3: Migrate provider invalidation calls in `playlist_provider.dart`**

Add the import:

```dart
import 'library_invalidation_coordinator.dart';
```

Replace direct invalidation after `createPlaylist` with:

```dart
_ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged(
  [playlist.id],
  tracksChanged: false,
  coverChanged: false,
);
```

Replace direct invalidation after `updatePlaylist` with:

```dart
_ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  playlistId,
  tracksChanged: false,
  coverChanged: true,
);
```

Keep this existing file cache clear for rename/custom cover path effects:

```dart
_ref.read(fileExistsCacheProvider.notifier).clearAll();
```

Replace direct invalidation after `deletePlaylist` with:

```dart
_ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged(
  [playlistId],
  tracksChanged: false,
  coverChanged: false,
);
```

Replace direct invalidation after `duplicatePlaylist` with:

```dart
_ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged(
  [playlist.id],
  tracksChanged: false,
  coverChanged: true,
);
```

Delete the `invalidatePlaylistProviders` method from `PlaylistListNotifier` after all external call sites are migrated.

- [ ] **Step 4: Migrate `PlaylistDetailNotifier` mutations**

Replace each direct `_ref.invalidate(...)` block after successful mutation with coordinator calls:

For `addTrack`, `removeTrack`, and `removeTracks`:

```dart
_ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  playlistId,
  tracksChanged: false,
  coverChanged: true,
);
```

For `reorderTracks`:

```dart
_ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  playlistId,
  tracksChanged: false,
  coverChanged: true,
  includeAll: false,
);
```

Update `refreshTracks()` catch block from silent swallow to logged observable failure:

```dart
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to refresh loaded playlist tracks: $playlistId',
        error,
        stackTrace,
        'PlaylistDetail',
      );
    }
```

Add `AppLogger` through the existing `../core/logger.dart` import already present at the top of `playlist_provider.dart`? If not present after edits, add:

```dart
import '../core/logger.dart';
```

- [ ] **Step 5: Migrate `addTrackToPlaylistProvider` shortcut**

Replace:

```dart
ref.invalidate(allPlaylistsProvider);
ref.invalidate(playlistDetailProvider(params.playlistId));
ref.invalidate(playlistCoverProvider(params.playlistId));
```

with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  params.playlistId,
);
```

- [ ] **Step 6: Run playlist provider tests**

Run: `flutter test test/providers/playlist_provider_phase2_test.dart test/providers/library_invalidation_coordinator_test.dart`

Expected: PASS.

- [ ] **Step 7: Search for removed helper references**

Run: `git grep "invalidatePlaylistProviders" -- lib test`

Expected: no matches.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/playlist_provider.dart test/providers/playlist_provider_phase2_test.dart
git commit -m "refactor(providers): route playlist invalidation through coordinator"
```

### Task 3: Refresh and Remote Sync Side Effects

**Files:**
- Modify: `lib/providers/refresh_provider.dart:172-191`
- Modify: `lib/providers/remote_playlist_sync_provider.dart:12-66`
- Modify: `lib/services/library/remote_playlist_sync_service.dart:3-29`
- Test: `test/services/library/remote_playlist_sync_service_test.dart` or existing remote sync test file

- [ ] **Step 1: Write or update remote sync service tests for explicit fire-and-forget naming**

If `test/services/library/remote_playlist_sync_service_test.dart` does not exist, create it with this content:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_sync_service.dart';

void main() {
  group('RemotePlaylistSyncService', () {
    test('starts refresh for matching imported playlists only', () async {
      final startedIds = <int>[];
      final playlist = Playlist()
        ..id = 9
        ..name = 'Imported YouTube'
        ..sourceType = SourceType.youtube
        ..importUrl = 'https://www.youtube.com/playlist?list=PL123';
      final unrelated = Playlist()
        ..id = 10
        ..name = 'Imported Netease'
        ..sourceType = SourceType.netease
        ..importUrl = 'https://music.163.com/#/playlist?id=456';
      final service = RemotePlaylistSyncService(
        getImportedPlaylists: () async => [playlist, unrelated],
        startPlaylistRefresh: (playlist) => startedIds.add(playlist.id),
      );

      final matches = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.youtube,
        remotePlaylistIds: ['PL123'],
      );

      expect(matches.map((playlist) => playlist.id), [9]);
      expect(startedIds, [9]);
    });
  });
}
```

- [ ] **Step 2: Run remote sync test to verify it fails on old constructor name**

Run: `flutter test test/services/library/remote_playlist_sync_service_test.dart`

Expected: FAIL because `startPlaylistRefresh` is not a constructor parameter yet.

- [ ] **Step 3: Rename remote sync service callback**

In `lib/services/library/remote_playlist_sync_service.dart`, replace:

```dart
final void Function(Playlist playlist) refreshPlaylist;
```

with:

```dart
final void Function(Playlist playlist) startPlaylistRefresh;
```

Update the constructor and loop:

```dart
const RemotePlaylistSyncService({
  required this.getImportedPlaylists,
  required this.startPlaylistRefresh,
});
```

```dart
for (final playlist in matches) {
  startPlaylistRefresh(playlist);
}
```

- [ ] **Step 4: Route refresh success invalidation through coordinator**

In `lib/providers/refresh_provider.dart`, import:

```dart
import 'library_invalidation_coordinator.dart';
```

Replace:

```dart
_ref.invalidate(playlistDetailProvider(playlistId));
_ref.invalidate(playlistCoverProvider(playlistId));
_ref.invalidate(allPlaylistsProvider);
```

with:

```dart
_ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  playlistId,
);
```

- [ ] **Step 5: Make remote sync background refresh failures observable**

In `lib/providers/remote_playlist_sync_provider.dart`, add:

```dart
import '../core/logger.dart';
```

Replace the `RemotePlaylistSyncService` wiring with:

```dart
return RemotePlaylistSyncService(
  getImportedPlaylists: playlistRepository.getImported,
  startPlaylistRefresh: (playlist) {
    unawaited(
      ref
          .read(refreshManagerProvider.notifier)
          .refreshPlaylist(playlist)
          .catchError((error, stackTrace) {
        AppLogger.error(
          'Background imported playlist refresh failed: ${playlist.id}',
          error,
          stackTrace is StackTrace ? stackTrace : null,
          'RemotePlaylistSync',
        );
        return null;
      }),
    );
  },
);
```

The important behavior is that this remains fire-and-forget but the name and log make it observable.

- [ ] **Step 6: Run focused refresh/sync tests**

Run:

```bash
flutter test test/services/library/remote_playlist_sync_service_test.dart test/providers/refresh_provider_stale_cleanup_test.dart
```

Expected: PASS.

- [ ] **Step 7: Search for silent swallowed remote refresh errors**

Run: `git grep "catchError((_) => null" -- lib`

Expected: no matches in remote playlist sync code. If matches remain in unrelated code, do not expand scope; note them in the task handoff.

- [ ] **Step 8: Commit**

```bash
git add lib/providers/refresh_provider.dart lib/providers/remote_playlist_sync_provider.dart lib/services/library/remote_playlist_sync_service.dart test/services/library/remote_playlist_sync_service_test.dart
git commit -m "refactor(remote): name and log background playlist refresh"
```

### Task 4: Download Completion and Download UI Migration

**Files:**
- Modify: `lib/providers/download/download_event_handler.dart:7-73`
- Modify: `lib/providers/download/download_providers.dart:16-76`
- Modify: `test/providers/download/download_event_handler_test.dart:6-84`
- Modify: `lib/providers/startup_download_sync_provider.dart:1-46`
- Modify: `lib/ui/pages/library/downloaded_page.dart:32-72,455-469`
- Modify: `lib/ui/pages/library/downloaded_category_page.dart:739-752,1008-1020`
- Modify: `lib/ui/widgets/change_download_path_dialog.dart:216-222`

- [ ] **Step 1: Update download event handler tests for one invalidation entry point**

In `test/providers/download/download_event_handler_test.dart`, replace the completion test setup with:

```dart
final markedPaths = <String>[];
final removedProgressTaskIds = <int>[];
final changedDownloads = <({List<String> savePaths, List<int> playlistIds})>[];
final shownFailures = <DownloadFailureEvent>[];
final handler = DownloadEventHandler(
  markFileExisting: markedPaths.add,
  removeProgress: removedProgressTaskIds.add,
  downloadStateChanged: ({
    required savePaths,
    required affectedPlaylistIds,
  }) {
    changedDownloads.add((
      savePaths: savePaths.toList(),
      playlistIds: affectedPlaylistIds.toList(),
    ));
  },
  showFailure: shownFailures.add,
  debounceDuration: const Duration(milliseconds: 1),
);
```

Replace completion expectations with:

```dart
expect(markedPaths, ['/downloads/Playlist A/Video 1/audio.m4a']);
expect(removedProgressTaskIds, [7]);
expect(changedDownloads, hasLength(1));
expect(changedDownloads.single.savePaths, [
  '/downloads/Playlist A/Video 1/audio.m4a',
]);
expect(changedDownloads.single.playlistIds, [11]);
expect(shownFailures, isEmpty);
```

Update the failure test constructor similarly and expect `changedDownloads` is empty.

- [ ] **Step 2: Run download event handler test to verify it fails**

Run: `flutter test test/providers/download/download_event_handler_test.dart`

Expected: FAIL because `DownloadEventHandler` still requires `invalidateCategories`, `invalidateCategoryTracks`, and `refreshPlaylist`.

- [ ] **Step 3: Change `DownloadEventHandler` constructor and batching**

In `lib/providers/download/download_event_handler.dart`, remove `package:path/path.dart` import and replace constructor fields:

```dart
required this.downloadStateChanged,
```

Add field:

```dart
final void Function({
  required Iterable<String> savePaths,
  required Iterable<int> affectedPlaylistIds,
}) downloadStateChanged;
```

Replace pending state:

```dart
final Set<int> _pendingPlaylistIds = <int>{};
final List<String> _pendingSavePaths = <String>[];
```

Update `handleCompletion`:

```dart
_pendingSavePaths.add(event.savePath);
final playlistId = event.playlistId;
if (playlistId != null) {
  _pendingPlaylistIds.add(playlistId);
}
```

Update `flushInvalidations`:

```dart
if (_pendingSavePaths.isEmpty && _pendingPlaylistIds.isEmpty) return;

downloadStateChanged(
  savePaths: List.unmodifiable(_pendingSavePaths),
  affectedPlaylistIds: List.unmodifiable(_pendingPlaylistIds),
);
_pendingSavePaths.clear();
_pendingPlaylistIds.clear();
```

- [ ] **Step 4: Wire download provider to the coordinator**

In `lib/providers/download/download_providers.dart`, replace imports:

```dart
import '../library_invalidation_coordinator.dart';
```

Remove direct import of `playlist_provider.dart show playlistDetailProvider` if no longer needed.

Replace `DownloadEventHandler` invalidation callbacks with:

```dart
downloadStateChanged: ({
  required savePaths,
  required affectedPlaylistIds,
}) {
  ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
        savePaths: savePaths,
        affectedPlaylistIds: affectedPlaylistIds,
      );
},
```

Keep `markFileExisting`, `removeProgress`, `showFailure`, and `debounceDuration` unchanged.

- [ ] **Step 5: Migrate startup download sync**

In `lib/providers/startup_download_sync_provider.dart`, replace playlist/download invalidation imports with:

```dart
import 'library_invalidation_coordinator.dart';
```

After sync:

```dart
final coordinator = ref.read(libraryInvalidationCoordinatorProvider);
coordinator.downloadStateChanged(fileExistsChanged: added > 0 || removed > 0);
```

Remove the manual `downloadedCategoriesProvider`, `fileExistsCacheProvider`, `playlistListProvider`, and `allPlaylistsProvider` invalidation block.

This intentionally refreshes downloaded categories every startup scan and refreshes file cache only when changes occurred.

- [ ] **Step 6: Migrate downloaded page sync and delete category**

In `lib/ui/pages/library/downloaded_page.dart`, import:

```dart
import '../../../providers/library_invalidation_coordinator.dart';
```

Remove direct imports of `file_exists_cache.dart` and `playlist_provider.dart` if no longer used.

Replace the `_syncLocalFiles` invalidation block with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
  fileExistsChanged: added > 0 || removed > 0,
);
```

Replace `_deleteCategory` direct invalidation block with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
  categoryPaths: [category.folderPath],
  affectedPlaylistIds: result.affectedPlaylistIds,
);
```

- [ ] **Step 7: Migrate downloaded category page deletion flows**

In `lib/ui/pages/library/downloaded_category_page.dart`, import:

```dart
import '../../../providers/library_invalidation_coordinator.dart';
```

Remove direct imports of `file_exists_cache.dart` and `playlist_provider.dart` if unused after edits.

Replace `_deleteAllDownloads` invalidation block with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
  categoryPaths: [folderPath],
  affectedPlaylistIds: result.affectedPlaylistIds,
);
```

Replace `_deleteDownload` invalidation block with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
  categoryPaths: [folderPath],
  fileExistsChanged: false,
);
```

Use `fileExistsChanged: false` here because this path currently only clears database download paths and the already-scanned category providers need refreshing; it does not update `FileExistsCache` today.

- [ ] **Step 8: Migrate change download path dialog**

In `lib/ui/widgets/change_download_path_dialog.dart`, import the coordinator:

```dart
import '../../providers/library_invalidation_coordinator.dart';
```

Replace direct invalidation around existing lines 216-222 with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).downloadStateChanged(
  affectedPlaylistIds: affectedPlaylistIds,
);
```

Keep the existing file move/path-change domain behavior unchanged.

- [ ] **Step 9: Run download-focused tests**

Run:

```bash
flutter test test/providers/download/download_event_handler_test.dart test/providers/library_invalidation_coordinator_test.dart
```

Expected: PASS.

- [ ] **Step 10: Search for remaining downloaded-provider direct invalidations in migrated paths**

Run:

```bash
git grep -n "downloadedCategoriesProvider\|downloadedCategoryTracksProvider\|fileExistsCacheProvider\|refreshTracks()" -- lib/providers lib/ui/pages/library lib/ui/widgets/change_download_path_dialog.dart
```

Expected: remaining matches are provider definitions, watches, reads for non-invalidation purposes, or intentional cache APIs such as `markAsExisting`/`clearAll`. Direct invalidation in the migrated download mutation paths should be gone.

- [ ] **Step 11: Commit**

```bash
git add lib/providers/download/download_event_handler.dart lib/providers/download/download_providers.dart lib/providers/startup_download_sync_provider.dart lib/ui/pages/library/downloaded_page.dart lib/ui/pages/library/downloaded_category_page.dart lib/ui/widgets/change_download_path_dialog.dart test/providers/download/download_event_handler_test.dart
git commit -m "refactor(download): centralize download invalidation effects"
```

### Task 5: Import and Add-to-Playlist UI Migration

**Files:**
- Modify: `lib/ui/pages/library/widgets/import_playlist_dialog.dart:498-518`
- Modify: `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:459-560`
- Modify: `lib/ui/pages/library/import_preview_page.dart:295-299`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:1163`
- Modify: `lib/ui/pages/settings/widgets/account_playlists_sheet.dart:286`
- Modify: `lib/ui/pages/settings/settings_page.dart:2158`

- [ ] **Step 1: Migrate import playlist dialog invalidation**

In `lib/ui/pages/library/widgets/import_playlist_dialog.dart`, import:

```dart
import '../../../../providers/library_invalidation_coordinator.dart';
```

Replace:

```dart
ref.invalidate(allPlaylistsProvider);
ref.invalidate(playlistDetailProvider(result.playlist.id));
ref.invalidate(playlistCoverProvider(result.playlist.id));
```

with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  result.playlist.id,
);
```

- [ ] **Step 2: Migrate add-to-playlist dialog create flow**

In `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart`, import:

```dart
import '../../../providers/library_invalidation_coordinator.dart';
```

Replace:

```dart
ref.invalidate(allPlaylistsProvider);
```

inside the new-playlist creation branch with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged(
  [playlist.id],
  tracksChanged: false,
  coverChanged: false,
);
```

- [ ] **Step 3: Migrate add-to-playlist dialog update flow**

Replace each:

```dart
ref.read(playlistListProvider.notifier).invalidatePlaylistProviders(playlistId);
```

with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  playlistId,
  includeAll: false,
);
```

Replace final:

```dart
ref.invalidate(allPlaylistsProvider);
```

with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged([
  ...toAdd,
  ...toRemove,
]);
```

If `playlistListProvider` import becomes unused, remove it.

- [ ] **Step 4: Migrate import preview page**

In `lib/ui/pages/library/import_preview_page.dart`, import the coordinator. Replace the current `playlistListProvider.notifier.invalidatePlaylistProviders(... includeAllPlaylists: true)` call with:

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  playlist.id,
);
```

Use the actual local playlist variable name at the call site. Do not alter import preview save/match behavior.

- [ ] **Step 5: Migrate remaining direct playlist snapshot invalidations**

For each listed file, import the coordinator and replace direct playlist invalidation with a semantically equivalent coordinator call:

`lib/ui/pages/library/playlist_detail_page.dart:1163`

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(
  widget.playlistId,
  tracksChanged: false,
  coverChanged: true,
  includeAll: false,
);
```

`lib/ui/pages/settings/widgets/account_playlists_sheet.dart:286`

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged(
  [playlist.id],
  tracksChanged: false,
  coverChanged: false,
);
```

`lib/ui/pages/settings/settings_page.dart:2158`

```dart
ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged(
  const [],
  tracksChanged: false,
  coverChanged: false,
);
```

If a file lacks `WidgetRef ref` at the call site, use the existing local `ref` object from the surrounding `ConsumerWidget`/`ConsumerState`; do not introduce global state.

- [ ] **Step 6: Search for direct playlist provider invalidation in widgets**

Run:

```bash
git grep -n "ref.invalidate(allPlaylistsProvider\|ref.invalidate(playlistDetailProvider\|ref.invalidate(playlistCoverProvider\|invalidatePlaylistProviders" -- lib/ui lib/providers
```

Expected: no matches except provider definitions or lines not reachable from mutation side effects. If any mutation-side matches remain, migrate them to `libraryInvalidationCoordinatorProvider`.

- [ ] **Step 7: Run focused UI/provider tests**

Run:

```bash
flutter test test/providers/playlist_provider_phase2_test.dart test/providers/library_invalidation_coordinator_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/pages/library/widgets/import_playlist_dialog.dart lib/ui/widgets/dialogs/add_to_playlist_dialog.dart lib/ui/pages/library/import_preview_page.dart lib/ui/pages/library/playlist_detail_page.dart lib/ui/pages/settings/widgets/account_playlists_sheet.dart lib/ui/pages/settings/settings_page.dart
git commit -m "refactor(ui): use coordinator for playlist invalidation"
```

### Task 6: Documentation and Final Verification

**Files:**
- Modify: `CLAUDE.md`
- Inspect: `lib/providers/library_invalidation_coordinator.dart`

- [ ] **Step 1: Update project guidance**

In `CLAUDE.md`, add `libraryInvalidationCoordinatorProvider` to the Riverpod provider list near the playlist/search providers:

```markdown
- `libraryInvalidationCoordinatorProvider` - Central UI/provider-layer invalidation coordinator for playlist/detail/cover/download side effects
```

Add a short rule under Riverpod rules:

```markdown
- Mutation side effects that need playlist/detail/cover/download provider invalidation should go through `libraryInvalidationCoordinatorProvider`; UI widgets should not manually guess related provider families.
- Fire-and-forget imported playlist refresh must use the named remote sync path and log background failures with `AppLogger`.
```

- [ ] **Step 2: Run broad invalidation search**

Run:

```bash
git grep -n "ref.invalidate(allPlaylistsProvider\|ref.invalidate(playlistDetailProvider\|ref.invalidate(playlistCoverProvider\|ref.invalidate(downloadedCategoriesProvider\|ref.invalidate(downloadedCategoryTracksProvider\|ref.invalidate(fileExistsCacheProvider\|catchError((_) => null\|catch (_)" -- lib
```

Expected:
- Direct invalidation matches should be in `library_invalidation_coordinator.dart`, provider definitions, or non-mutation refresh UI such as a user pull-to-refresh.
- `catchError((_) => null)` should not remain in remote playlist sync.
- `catch (_)` matches may exist outside Phase 3 scope. Do not broaden the phase; note unrelated matches in the final handoff.

- [ ] **Step 3: Run focused tests**

Run:

```bash
flutter test test/providers/library_invalidation_coordinator_test.dart test/providers/playlist_provider_phase2_test.dart test/providers/download/download_event_handler_test.dart test/services/library/remote_playlist_sync_service_test.dart test/providers/refresh_provider_stale_cleanup_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run analyzer**

Run: `flutter analyze`

Expected: PASS with no issues.

- [ ] **Step 5: Run full test suite**

Run: `flutter test`

Expected: PASS. Pub advisory decode warnings may appear, but they are not failures if tests pass.

- [ ] **Step 6: Commit documentation and cleanup**

```bash
git add CLAUDE.md
git commit -m "docs: document library invalidation coordinator"
```

- [ ] **Step 7: Final review checklist**

Before reporting completion, verify:

```bash
git status --short
git log --oneline -6
```

Expected:
- Working tree clean.
- Commits from Tasks 1-6 are present.
- No push was performed.

## Rollback Notes

- The coordinator is provider-layer only; repositories and services must not import Riverpod or the coordinator.
- If a UI/provider migration causes regressions, revert only the affected migration commit and keep the coordinator contract commit. The old direct invalidation pattern remains straightforward to reintroduce temporarily.
- If remote background refresh logging becomes too noisy, adjust the log message/tag or deduplicate in the provider layer; do not return to silent `.catchError((_) => null)`.

## Self-Review

- Spec coverage: Phase 3 acceptance criteria are covered by the coordinator, migrated import/refresh/remote-sync/local edit/download call sites, and explicit fire-and-forget logging.
- Placeholder scan: No `TBD`, `TODO`, or unspecified test steps remain.
- Type consistency: Method names are consistent across tasks: `playlistChanged`, `playlistsChanged`, `playlistMutationCompleted`, `downloadStateChanged`, `refreshLoadedPlaylistDetails`, and `startRefreshLoadedPlaylistDetails`.
