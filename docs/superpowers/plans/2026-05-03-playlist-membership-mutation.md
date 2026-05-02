# Playlist Membership Mutation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize playlist membership mutations so import, refresh, local playlist edits, and remote removal sync all use one canonical path for `Playlist.trackIds` and `Track.playlistInfo`.

**Architecture:** Add a domain service, `PlaylistMutationService`, below `PlaylistService` and `ImportService`. It owns track identity lookup/creation, metadata merge, ordered playlist membership updates, reverse `Track.playlistInfo` updates, removed-track cleanup, orphan cleanup, default-cover updates, and structured mutation results. Existing UI/provider APIs stay stable; they delegate to the mutation service and continue doing optimistic UI/invalidation until Phase 3 replaces that with a coordinator.

**Tech Stack:** Flutter/Dart, Riverpod, Isar, `flutter_test`, existing repository/service patterns.

---

## Scope and non-goals

Implement only Phase 1 from `docs/superpowers/specs/2026-05-02-program-logic-repair-roadmap-design.md`.

In scope:
- Create `PlaylistMutationService` and `PlaylistMutationResult`.
- Move local add/remove/reorder/delete/duplicate membership rules from `PlaylistService` into the mutation service.
- Move import and refresh membership replacement rules from `ImportService` into the mutation service.
- Preserve Phase 0 partial-refresh safety: pruning only happens when remote source data is complete and every refreshed track persisted.
- Return mutation metadata that later provider invalidation work can consume.
- Remove unused low-level `PlaylistRepository` membership helpers after callers migrate.

Out of scope:
- Do not build the Phase 2 remote edit planner/controller.
- Do not build the Phase 3 invalidation coordinator.
- Do not redesign playlist detail UI.
- Do not batch every source identity lookup beyond what is needed for this refactor; broad performance batching remains Phase 5.

## Current mutation map

- `lib/services/import/import_service.dart:178-344` imports tracks and hand-rolls existing/new track association, `playlist.trackIds`, cover, and `lastRefreshed`.
- `lib/services/import/import_service.dart:441-631` refreshes imported playlists, calculates pruning, repairs reverse associations, removes stale tracks, deletes orphans, and merges partial refresh results.
- `lib/services/library/playlist_service.dart:224-280` deletes a playlist and cleans reverse track associations/orphans.
- `lib/services/library/playlist_service.dart:282-432` adds one or many tracks and duplicates identity/metadata merge logic.
- `lib/services/library/playlist_service.dart:514-635` removes/reorders tracks and updates default cover.
- `lib/services/library/playlist_service.dart:711-757` duplicates a playlist and adds reverse membership to copied tracks.
- `lib/data/repositories/playlist_repository.dart:52-110` exposes direct `trackIds` helpers that bypass `Track.playlistInfo`.
- `lib/providers/playlist_provider.dart:411-499` keeps optimistic UI behavior and calls `PlaylistService`.
- `lib/providers/remote_playlist_sync_provider.dart:27-37` remote removal sync delegates local removal through playlist detail notifier.

## File structure

- Create: `lib/services/library/playlist_exceptions.dart`
  - Holds playlist service exceptions shared by `PlaylistService` and `PlaylistMutationService` without circular imports.
- Create: `lib/services/library/playlist_mutation_service.dart`
  - Owns canonical membership mutations and mutation result types.
- Modify: `lib/services/library/playlist_service.dart`
  - Keep public playlist management API; delegate membership operations to `PlaylistMutationService`.
  - Retain non-membership concerns such as playlist naming, download folder rename behavior, cover reading, pagination, and list sorting.
  - Export `PlaylistUpdateResult` and playlist exceptions so existing imports keep working.
- Modify: `lib/services/import/import_service.dart`
  - Keep source parsing/progress/cancellation/auth logic; delegate import/refresh membership writes to `PlaylistMutationService`.
- Modify: `lib/providers/playlist_provider.dart`
  - Construct `PlaylistMutationService` and inject it into `PlaylistService`.
- Modify: `lib/providers/import_playlist_provider.dart`
  - Inject `PlaylistMutationService` into `ImportService`.
- Modify: `lib/providers/refresh_provider.dart`
  - Inject `PlaylistMutationService` into refresh `ImportService` instances.
- Modify: `lib/data/repositories/playlist_repository.dart`
  - Remove unused direct membership helpers after migration.
- Test: `test/services/library/playlist_mutation_service_test.dart`
  - Direct domain tests for add/remove/reorder/replace/delete/duplicate behavior.
- Modify tests:
  - `test/services/library/playlist_service_bidirectional_test.dart`
  - `test/services/library/playlist_service_transaction_source_test.dart`
  - `test/services/import/import_service_refresh_partial_test.dart`
  - `test/services/import/import_service_phase4_test.dart`
  - Provider tests only if constructor wiring requires harness changes.

---

### Task 1: Create mutation result contract and add-track mutation path

**Files:**
- Create: `lib/services/library/playlist_exceptions.dart`
- Create: `lib/services/library/playlist_mutation_service.dart`
- Test: `test/services/library/playlist_mutation_service_test.dart`

- [ ] **Step 1: Write failing add/repair tests**

Create `test/services/library/playlist_mutation_service_test.dart` with the same Isar setup pattern used by `test/services/library/playlist_service_bidirectional_test.dart`. Include these first tests:

```dart
test('addTracks creates tracks and writes both membership sides', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final playlist = await _createPlaylist(harness, 'Canonical Add');

  final result = await harness.mutations.addTracks(
    playlist.id,
    [_track('a', 'A'), _track('b', 'B')],
  );

  final savedPlaylist = await harness.playlists.getById(playlist.id);
  final savedTracks = await harness.tracks.getBySourceIds(['a', 'b']);
  expect(result.playlistId, playlist.id);
  expect(result.addedCount, 2);
  expect(result.skippedCount, 0);
  expect(result.removedCount, 0);
  expect(result.coverChanged, isTrue);
  expect(savedPlaylist!.trackIds, savedTracks.map((track) => track.id).toList());
  for (final track in savedTracks) {
    expect(track.belongsToPlaylist(playlist.id), isTrue);
    expect(track.playlistInfo.single.playlistName, 'Canonical Add');
  }
});

test('addTracks repairs missing playlist or track side without duplicates', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final playlist = await _createPlaylist(harness, 'Repair');
  final track = await harness.tracks.save(_track('repair', 'Repair'));
  playlist.trackIds = [track.id];
  await harness.playlists.save(playlist);

  final result = await harness.mutations.addTracks(playlist.id, [track]);

  final savedPlaylist = await harness.playlists.getById(playlist.id);
  final savedTrack = await harness.tracks.getById(track.id);
  expect(result.addedCount, 0);
  expect(result.repairedCount, 1);
  expect(savedPlaylist!.trackIds, [track.id]);
  expect(savedTrack!.playlistInfo.where((info) => info.playlistId == playlist.id), hasLength(1));
});
```

The harness should expose `isar`, `PlaylistRepository`, `TrackRepository`, and `PlaylistMutationService`.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart
```

Expected: fails because `package:fmp/services/library/playlist_mutation_service.dart` does not exist.

- [ ] **Step 3: Add result types and canonical add implementation**

Create `lib/services/library/playlist_exceptions.dart`:

```dart
import 'package:fmp/i18n/strings.g.dart';

class PlaylistNameExistsException implements Exception {
  final String name;
  const PlaylistNameExistsException(this.name);

  @override
  String toString() => t.importSource.playlistNameExists(name: name);
}

class PlaylistNotFoundException implements Exception {
  final int playlistId;
  const PlaylistNotFoundException(this.playlistId);

  @override
  String toString() =>
      t.importSource.playlistIdNotFound(id: playlistId.toString());
}
```

Create `lib/services/library/playlist_mutation_service.dart` with these public types and the `addTracks` implementation. Move the identity/metadata helpers from `PlaylistService` into this service instead of duplicating them.

```dart
import 'package:isar/isar.dart';

import '../../core/logger.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import 'playlist_exceptions.dart';

class PlaylistMutationResult {
  final int playlistId;
  final List<int> affectedPlaylistIds;
  final List<int> addedTrackIds;
  final List<int> repairedTrackIds;
  final List<int> skippedTrackIds;
  final List<int> removedTrackIds;
  final List<int> deletedTrackIds;
  final List<int> updatedTrackIds;
  final List<String> errors;
  final bool playlistChanged;
  final bool coverChanged;
  final bool pruningSkipped;

  const PlaylistMutationResult({
    required this.playlistId,
    this.affectedPlaylistIds = const [],
    this.addedTrackIds = const [],
    this.repairedTrackIds = const [],
    this.skippedTrackIds = const [],
    this.removedTrackIds = const [],
    this.deletedTrackIds = const [],
    this.updatedTrackIds = const [],
    this.errors = const [],
    this.playlistChanged = false,
    this.coverChanged = false,
    this.pruningSkipped = false,
  });

  int get addedCount => addedTrackIds.length;
  int get repairedCount => repairedTrackIds.length;
  int get skippedCount => skippedTrackIds.length;
  int get removedCount => removedTrackIds.length;
  bool get hasErrors => errors.isNotEmpty;
}

class RemoteRefreshMutationPolicy {
  final bool sourceDataComplete;
  final String? platformCoverUrl;

  const RemoteRefreshMutationPolicy({
    required this.sourceDataComplete,
    this.platformCoverUrl,
  });
}

class PlaylistMutationService with Logging {
  PlaylistMutationService({
    required Isar isar,
  }) : _isar = isar;

  final Isar _isar;

  Future<PlaylistMutationResult> addTrack(int playlistId, Track track) {
    return addTracks(playlistId, [track]);
  }

  Future<PlaylistMutationResult> addTracks(
    int playlistId,
    List<Track> tracks,
  ) async {
    final candidateTracks = _dedupeTracksByUniqueKey(tracks);
    if (candidateTracks.isEmpty) {
      return PlaylistMutationResult(playlistId: playlistId);
    }

    final addedTrackIds = <int>[];
    final repairedTrackIds = <int>[];
    final skippedTrackIds = <int>[];
    final updatedTrackIds = <int>[];
    var playlistChanged = false;
    var coverChanged = false;

    await _isar.writeTxn(() async {
      final playlist = await _isar.playlists.get(playlistId);
      if (playlist == null) {
        throw PlaylistNotFoundException(playlistId);
      }

      final now = DateTime.now();
      final trackIds = List<int>.from(playlist.trackIds);
      final existingTrackIds = trackIds.toSet();
      final wasEmpty = trackIds.isEmpty;
      Track? firstAddedPlaylistTrack;

      for (final inputTrack in candidateTracks) {
        final existingTrack = await _findTrackByIdentity(inputTrack);
        final trackToSave = existingTrack ?? inputTrack;
        final metadataChanged = existingTrack != null &&
            _mergeTrackMetadataIfNeeded(existingTrack, inputTrack);
        final trackLinked = trackToSave.belongsToPlaylist(playlistId);
        final playlistLinked = existingTrack != null &&
            existingTrackIds.contains(trackToSave.id);

        if (trackLinked && playlistLinked && !metadataChanged) {
          skippedTrackIds.add(trackToSave.id);
          continue;
        }

        if (!trackLinked) {
          trackToSave.addToPlaylist(playlistId, playlistName: playlist.name);
        }
        if (existingTrack == null || !trackLinked || metadataChanged) {
          trackToSave.updatedAt = now;
          trackToSave.id = await _isar.tracks.put(trackToSave);
          updatedTrackIds.add(trackToSave.id);
        }

        if (!playlistLinked && existingTrackIds.add(trackToSave.id)) {
          trackIds.add(trackToSave.id);
          firstAddedPlaylistTrack ??= trackToSave;
          addedTrackIds.add(trackToSave.id);
          playlistChanged = true;
        } else {
          repairedTrackIds.add(trackToSave.id);
        }
      }

      if (playlistChanged) {
        playlist.trackIds = trackIds;
        if (wasEmpty && !playlist.hasCustomCover) {
          final newCoverUrl = firstAddedPlaylistTrack?.thumbnailUrl;
          if (playlist.coverUrl != newCoverUrl) {
            playlist.coverUrl = newCoverUrl;
            coverChanged = true;
          }
        }
        playlist.updatedAt = now;
        await _isar.playlists.put(playlist);
      }
    });

    return PlaylistMutationResult(
      playlistId: playlistId,
      affectedPlaylistIds: [playlistId],
      addedTrackIds: addedTrackIds,
      repairedTrackIds: repairedTrackIds,
      skippedTrackIds: skippedTrackIds,
      updatedTrackIds: updatedTrackIds,
      playlistChanged: playlistChanged,
      coverChanged: coverChanged,
    );
  }

  Future<Track?> _findTrackByIdentity(Track track) {
    if (track.cid == null) {
      return _isar.tracks
          .where()
          .sourceIdEqualTo(track.sourceId)
          .filter()
          .sourceTypeEqualTo(track.sourceType)
          .findFirst();
    }

    return _isar.tracks
        .where()
        .sourceIdEqualTo(track.sourceId)
        .filter()
        .sourceTypeEqualTo(track.sourceType)
        .and()
        .cidEqualTo(track.cid)
        .findFirst();
  }

  List<Track> _dedupeTracksByUniqueKey(List<Track> tracks) {
    final keyToIndex = <String, int>{};
    final uniqueTracks = <Track>[];

    for (final track in tracks) {
      final key = track.uniqueKey;
      final existingIndex = keyToIndex[key];
      if (existingIndex == null) {
        keyToIndex[key] = uniqueTracks.length;
        uniqueTracks.add(track);
      } else if (_hasMoreCompleteTrackData(
        track,
        uniqueTracks[existingIndex],
      )) {
        uniqueTracks[existingIndex] = track;
      }
    }

    return uniqueTracks;
  }

  bool _hasMoreCompleteTrackData(Track a, Track b) {
    return _trackCompletenessScore(a) > _trackCompletenessScore(b);
  }

  int _trackCompletenessScore(Track track) {
    var score = 0;
    if (track.audioUrl != null && track.audioUrl!.isNotEmpty) score += 10;
    if (track.thumbnailUrl != null) score += 5;
    if (track.durationMs != null && track.durationMs! > 0) score += 3;
    if (track.artist != null && track.artist!.isNotEmpty) score += 2;
    return score;
  }

  bool _mergeTrackMetadataIfNeeded(Track target, Track incoming) {
    var changed = false;

    if (incoming.audioUrl != null && incoming.audioUrl!.isNotEmpty) {
      if (target.audioUrl == null ||
          target.audioUrl!.isEmpty ||
          !target.hasValidAudioUrl) {
        target.audioUrl = incoming.audioUrl;
        target.audioUrlExpiry = incoming.audioUrlExpiry;
        changed = true;
      }
    }
    if (target.thumbnailUrl == null && incoming.thumbnailUrl != null) {
      target.thumbnailUrl = incoming.thumbnailUrl;
      changed = true;
    }
    if (target.durationMs == null && incoming.durationMs != null) {
      target.durationMs = incoming.durationMs;
      changed = true;
    }
    if (target.artist == null && incoming.artist != null) {
      target.artist = incoming.artist;
      changed = true;
    }

    return changed;
  }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart
```

Expected: the new add/repair tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/library/playlist_exceptions.dart lib/services/library/playlist_mutation_service.dart test/services/library/playlist_mutation_service_test.dart
git commit -m "feat(playlist): add membership mutation service"
```

### Task 2: Move local playlist add/remove/reorder/delete/duplicate into mutation service

**Files:**
- Modify: `lib/services/library/playlist_mutation_service.dart`
- Modify: `lib/services/library/playlist_service.dart`
- Modify: `test/services/library/playlist_mutation_service_test.dart`
- Modify: `test/services/library/playlist_service_bidirectional_test.dart`
- Modify: `test/services/library/playlist_service_transaction_source_test.dart`

- [ ] **Step 1: Add failing mutation-service tests for local operations**

Append these tests to `test/services/library/playlist_mutation_service_test.dart`:

```dart
test('removeTracks removes playlist side and deletes only orphan tracks', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final first = await _createPlaylist(harness, 'First');
  final second = await _createPlaylist(harness, 'Second');
  final orphan = await harness.tracks.save(_track('orphan', 'Orphan'));
  final shared = await harness.tracks.save(_track('shared', 'Shared'));
  await harness.mutations.addTracks(first.id, [orphan, shared]);
  await harness.mutations.addTrack(second.id, shared);

  final result = await harness.mutations.removeTracks(
    first.id,
    [orphan.id, shared.id],
  );

  final savedFirst = await harness.playlists.getById(first.id);
  final savedShared = await harness.tracks.getById(shared.id);
  expect(result.removedTrackIds, [orphan.id, shared.id]);
  expect(result.deletedTrackIds, [orphan.id]);
  expect(savedFirst!.trackIds, isEmpty);
  expect(await harness.tracks.getById(orphan.id), isNull);
  expect(savedShared!.belongsToPlaylist(first.id), isFalse);
  expect(savedShared.belongsToPlaylist(second.id), isTrue);
});

test('reorderTracks stores requested order and reports cover changes', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final playlist = await _createPlaylist(harness, 'Reorder');
  final first = _track('first', 'First')..thumbnailUrl = 'https://img/first.jpg';
  final second = _track('second', 'Second')..thumbnailUrl = 'https://img/second.jpg';
  await harness.mutations.addTracks(playlist.id, [first, second]);
  final savedBefore = await harness.playlists.getById(playlist.id);

  final result = await harness.mutations.reorderTracks(
    playlist.id,
    [savedBefore!.trackIds.last, savedBefore.trackIds.first],
  );

  final savedAfter = await harness.playlists.getById(playlist.id);
  expect(savedAfter!.trackIds, [savedBefore.trackIds.last, savedBefore.trackIds.first]);
  expect(result.playlistChanged, isTrue);
  expect(result.coverChanged, isTrue);
  expect(savedAfter.coverUrl, 'https://img/second.jpg');
});

test('deletePlaylist removes playlist and cleans reverse associations', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final first = await _createPlaylist(harness, 'Delete Me');
  final second = await _createPlaylist(harness, 'Keep Me');
  final orphan = await harness.tracks.save(_track('delete-orphan', 'Delete Orphan'));
  final shared = await harness.tracks.save(_track('delete-shared', 'Delete Shared'));
  await harness.mutations.addTracks(first.id, [orphan, shared]);
  await harness.mutations.addTrack(second.id, shared);

  final result = await harness.mutations.deletePlaylist(first.id);

  expect(result.deletedTrackIds, [orphan.id]);
  expect(await harness.playlists.getById(first.id), isNull);
  expect(await harness.tracks.getById(orphan.id), isNull);
  final savedShared = await harness.tracks.getById(shared.id);
  expect(savedShared!.belongsToPlaylist(first.id), isFalse);
  expect(savedShared.belongsToPlaylist(second.id), isTrue);
});

test('duplicatePlaylist creates new playlist and reverse membership', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final original = await _createPlaylist(harness, 'Original');
  await harness.mutations.addTracks(
    original.id,
    [_track('copy-me', 'Copy Me')],
  );

  final duplicate = await harness.mutations.duplicatePlaylist(
    original.id,
    Playlist()
      ..name = 'Copy'
      ..createdAt = DateTime.now(),
  );

  final copiedTrack = await harness.tracks.getBySourceId('copy-me', SourceType.youtube);
  expect(duplicate.trackIds, [copiedTrack!.id]);
  expect(copiedTrack.belongsToPlaylist(original.id), isTrue);
  expect(copiedTrack.belongsToPlaylist(duplicate.id), isTrue);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart
```

Expected: fails because `removeTracks`, `reorderTracks`, `deletePlaylist`, and `duplicatePlaylist` are not implemented.

- [ ] **Step 3: Implement local mutation methods**

Add these methods to `PlaylistMutationService`:

```dart
Future<PlaylistMutationResult> removeTrack(int playlistId, int trackId) {
  return removeTracks(playlistId, [trackId]);
}

Future<PlaylistMutationResult> removeTracks(
  int playlistId,
  List<int> trackIds,
) async {
  if (trackIds.isEmpty) {
    return PlaylistMutationResult(playlistId: playlistId);
  }

  final removedTrackIds = <int>[];
  final deletedTrackIds = <int>[];
  final updatedTrackIds = <int>[];
  var playlistChanged = false;
  var coverChanged = false;

  await _isar.writeTxn(() async {
    final playlist = await _isar.playlists.get(playlistId);
    if (playlist == null) return;

    final removeSet = trackIds.toSet();
    final nextTrackIds = List<int>.from(playlist.trackIds)
      ..removeWhere((id) {
        final removed = removeSet.contains(id);
        if (removed) removedTrackIds.add(id);
        return removed;
      });

    if (removedTrackIds.isEmpty) return;

    final oldCoverUrl = playlist.coverUrl;
    playlist.trackIds = nextTrackIds;
    playlist.updatedAt = DateTime.now();
    await _refreshDefaultCoverInTxn(playlist);
    coverChanged = oldCoverUrl != playlist.coverUrl;
    await _isar.playlists.put(playlist);
    playlistChanged = true;

    final tracks = (await _isar.tracks.getAll(removedTrackIds)).whereType<Track>().toList();
    final tracksToUpdate = <Track>[];
    for (final track in tracks) {
      track.removeFromPlaylist(playlistId);
      if (track.playlistInfo.isEmpty) {
        deletedTrackIds.add(track.id);
      } else {
        track.updatedAt = DateTime.now();
        tracksToUpdate.add(track);
        updatedTrackIds.add(track.id);
      }
    }
    if (deletedTrackIds.isNotEmpty) {
      await _isar.tracks.deleteAll(deletedTrackIds);
    }
    if (tracksToUpdate.isNotEmpty) {
      await _isar.tracks.putAll(tracksToUpdate);
    }
  });

  return PlaylistMutationResult(
    playlistId: playlistId,
    affectedPlaylistIds: [playlistId],
    removedTrackIds: removedTrackIds,
    deletedTrackIds: deletedTrackIds,
    updatedTrackIds: updatedTrackIds,
    playlistChanged: playlistChanged,
    coverChanged: coverChanged,
  );
}

Future<PlaylistMutationResult> reorderTracks(
  int playlistId,
  List<int> orderedTrackIds,
) async {
  var playlistChanged = false;
  var coverChanged = false;

  await _isar.writeTxn(() async {
    final playlist = await _isar.playlists.get(playlistId);
    if (playlist == null) return;
    final oldCoverUrl = playlist.coverUrl;
    playlist.trackIds = List<int>.from(orderedTrackIds);
    playlist.updatedAt = DateTime.now();
    await _refreshDefaultCoverInTxn(playlist);
    coverChanged = oldCoverUrl != playlist.coverUrl;
    await _isar.playlists.put(playlist);
    playlistChanged = true;
  });

  return PlaylistMutationResult(
    playlistId: playlistId,
    affectedPlaylistIds: [playlistId],
    playlistChanged: playlistChanged,
    coverChanged: coverChanged,
  );
}

Future<PlaylistMutationResult> deletePlaylist(int playlistId) async {
  final deletedTrackIds = <int>[];
  final updatedTrackIds = <int>[];

  await _isar.writeTxn(() async {
    final playlist = await _isar.playlists.get(playlistId);
    if (playlist == null) return;
    final tracks = (await _isar.tracks.getAll(playlist.trackIds)).whereType<Track>().toList();
    final tracksToUpdate = <Track>[];
    for (final track in tracks) {
      track.removeFromPlaylist(playlistId);
      if (track.playlistInfo.isEmpty) {
        deletedTrackIds.add(track.id);
      } else {
        track.updatedAt = DateTime.now();
        tracksToUpdate.add(track);
        updatedTrackIds.add(track.id);
      }
    }
    await _isar.playlists.delete(playlistId);
    if (deletedTrackIds.isNotEmpty) {
      await _isar.tracks.deleteAll(deletedTrackIds);
    }
    if (tracksToUpdate.isNotEmpty) {
      await _isar.tracks.putAll(tracksToUpdate);
    }
  });

  return PlaylistMutationResult(
    playlistId: playlistId,
    affectedPlaylistIds: [playlistId],
    deletedTrackIds: deletedTrackIds,
    updatedTrackIds: updatedTrackIds,
    playlistChanged: true,
  );
}

Future<Playlist> duplicatePlaylist(int originalPlaylistId, Playlist copy) async {
  await _isar.writeTxn(() async {
    final original = await _isar.playlists.get(originalPlaylistId);
    if (original == null) {
      throw PlaylistNotFoundException(originalPlaylistId);
    }
    copy
      ..description = original.description
      ..coverUrl = original.coverUrl
      ..hasCustomCover = original.hasCustomCover
      ..trackIds = List<int>.from(original.trackIds)
      ..updatedAt = DateTime.now();
    copy.id = await _isar.playlists.put(copy);

    final copiedTracks =
        (await _isar.tracks.getAll(copy.trackIds)).whereType<Track>().toList();
    for (final track in copiedTracks) {
      track.addToPlaylist(copy.id, playlistName: copy.name);
      track.updatedAt = DateTime.now();
    }
    if (copiedTracks.isNotEmpty) {
      await _isar.tracks.putAll(copiedTracks);
    }
  });
  return copy;
}

Future<void> _refreshDefaultCoverInTxn(
  Playlist playlist, {
  String? platformCoverUrl,
}) async {
  if (playlist.hasCustomCover) return;
  final oldCoverUrl = playlist.coverUrl;
  if (platformCoverUrl != null) {
    playlist.coverUrl = platformCoverUrl;
  } else if (playlist.trackIds.isNotEmpty) {
    final firstTrack = await _isar.tracks.get(playlist.trackIds.first);
    playlist.coverUrl = firstTrack?.thumbnailUrl;
  } else {
    playlist.coverUrl = null;
  }
  if (oldCoverUrl != playlist.coverUrl) {
    logDebug('Updated playlist cover for "${playlist.name}" to: ${playlist.coverUrl}');
  }
}
```

- [ ] **Step 4: Refactor `PlaylistService` to delegate local mutations**

Modify `lib/services/library/playlist_service.dart`:

1. Import `playlist_mutation_service.dart` and `playlist_exceptions.dart`.
2. Add a constructor dependency:

```dart
final PlaylistMutationService _mutationService;

PlaylistService({
  required PlaylistRepository playlistRepository,
  required TrackRepository trackRepository,
  required SettingsRepository settingsRepository,
  required Isar isar,
  PlaylistMutationService? mutationService,
})  : _playlistRepository = playlistRepository,
      _trackRepository = trackRepository,
      _settingsRepository = settingsRepository,
      _isar = isar,
      _mutationService = mutationService ??
          PlaylistMutationService(
            isar: isar,
          );
```

3. Replace `deletePlaylist`, `addTrackToPlaylist`, `addTracksToPlaylist`, `removeTrackFromPlaylist`, `removeTracksFromPlaylist`, and `reorderPlaylistTracks` bodies with delegation while preserving method signatures:

```dart
Future<void> deletePlaylist(int playlistId) async {
  await _mutationService.deletePlaylist(playlistId);
}

Future<PlaylistMutationResult> addTrackToPlaylist(int playlistId, Track track) {
  return _mutationService.addTrack(playlistId, track);
}

Future<PlaylistMutationResult> addTracksToPlaylist(
  int playlistId,
  List<Track> tracks,
) {
  return _mutationService.addTracks(playlistId, tracks);
}

Future<PlaylistMutationResult> removeTrackFromPlaylist(
  int playlistId,
  int trackId,
) {
  return _mutationService.removeTrack(playlistId, trackId);
}

Future<PlaylistMutationResult> removeTracksFromPlaylist(
  int playlistId,
  List<int> trackIds,
) {
  return _mutationService.removeTracks(playlistId, trackIds);
}

Future<PlaylistMutationResult> reorderPlaylistTracks(
  int playlistId,
  int oldIndex,
  int newIndex,
) async {
  final playlist = await _playlistRepository.getById(playlistId);
  if (playlist == null) {
    return PlaylistMutationResult(playlistId: playlistId);
  }
  final trackIds = List<int>.from(playlist.trackIds);
  final trackId = trackIds.removeAt(oldIndex);
  final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
  trackIds.insert(insertIndex, trackId);
  return _mutationService.reorderTracks(playlistId, trackIds);
}
```

4. Replace `duplicatePlaylist` transaction body with:

```dart
final copy = Playlist()
  ..name = newName
  ..sortOrder = nextSortOrder
  ..createdAt = DateTime.now();

return _mutationService.duplicatePlaylist(playlistId, copy);
```

5. Remove now-unused private helpers from `PlaylistService`: `_findTrackByIdentity`, `_dedupeTracksByUniqueKey`, `_hasMoreCompleteTrackData`, `_trackCompletenessScore`, `_mergeTrackMetadataIfNeeded`, and `_updateDefaultCover`.

6. Move `PlaylistNameExistsException` and `PlaylistNotFoundException` definitions out of `playlist_service.dart` into `playlist_exceptions.dart`, then export them from `playlist_service.dart`:

```dart
export 'playlist_exceptions.dart';
```

- [ ] **Step 5: Update transaction source tests**

Modify `test/services/library/playlist_service_transaction_source_test.dart` so it verifies delegation instead of requiring service-level transactions:

```dart
test('removeTrackFromPlaylist delegates to mutation service', () {
  final body = _methodBody(source, 'removeTrackFromPlaylist');

  expect(body, contains('_mutationService.removeTrack('));
  expect(body, isNot(contains('_isar.writeTxn')));
  expect(body, isNot(contains('_playlistRepository.removeTrack(')));
});

test('removeTracksFromPlaylist delegates to mutation service', () {
  final body = _methodBody(source, 'removeTracksFromPlaylist');

  expect(body, contains('_mutationService.removeTracks('));
  expect(body, isNot(contains('_isar.writeTxn')));
  expect(body, isNot(contains('_playlistRepository.removeTracks(')));
});
```

- [ ] **Step 6: Run local mutation tests**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart test/services/library/playlist_service_bidirectional_test.dart test/services/library/playlist_service_transaction_source_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/services/library/playlist_exceptions.dart lib/services/library/playlist_mutation_service.dart lib/services/library/playlist_service.dart test/services/library/playlist_mutation_service_test.dart test/services/library/playlist_service_bidirectional_test.dart test/services/library/playlist_service_transaction_source_test.dart
git commit -m "refactor(playlist): centralize local membership mutations"
```

### Task 3: Move import creation membership into mutation service

**Files:**
- Modify: `lib/services/import/import_service.dart`
- Modify: `lib/providers/import_playlist_provider.dart`
- Modify: `test/services/import/import_service_phase4_test.dart`
- Modify: `test/services/import/import_service_refresh_partial_test.dart`
- Test: `test/services/library/playlist_mutation_service_test.dart`

- [ ] **Step 1: Add import-oriented mutation tests**

Append this test to `test/services/library/playlist_mutation_service_test.dart`:

```dart
test('addTracks returns skipped count for already fully linked tracks', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final playlist = await _createPlaylist(harness, 'Skip Existing');
  final track = _track('skip-me', 'Skip Me');

  final first = await harness.mutations.addTracks(playlist.id, [track]);
  final second = await harness.mutations.addTracks(playlist.id, [track]);

  final savedPlaylist = await harness.playlists.getById(playlist.id);
  expect(first.addedCount, 1);
  expect(second.addedCount, 0);
  expect(second.skippedCount, 1);
  expect(savedPlaylist!.trackIds, hasLength(1));
});
```

- [ ] **Step 2: Run import-adjacent tests before refactor**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart test/services/import/import_service_phase4_test.dart
```

Expected: current tests pass before the import refactor.

- [ ] **Step 3: Inject mutation service into `ImportService`**

Modify `lib/services/import/import_service.dart`:

1. Add import:

```dart
import '../library/playlist_mutation_service.dart';
```

2. Add field and constructor parameter:

```dart
final PlaylistMutationService _mutationService;

ImportService({
  required SourceManager sourceManager,
  required PlaylistRepository playlistRepository,
  required TrackRepository trackRepository,
  required Isar isar,
  PlaylistMutationService? mutationService,
  BilibiliAccountService? bilibiliAccountService,
  YouTubeAccountService? youtubeAccountService,
  NeteaseAccountService? neteaseAccountService,
})  : _sourceManager = sourceManager,
      _playlistRepository = playlistRepository,
      _trackRepository = trackRepository,
      _isar = isar,
      _mutationService = mutationService ??
          PlaylistMutationService(
            isar: isar,
          ),
      _bilibiliAccountService = bilibiliAccountService,
      _youtubeAccountService = youtubeAccountService,
      _neteaseAccountService = neteaseAccountService;
```

- [ ] **Step 4: Replace import loop membership writes**

In `importFromUrl`, keep the parsing/progress/cancellation loop, but collect tracks to import and call the mutation service once.

Replace the per-track `existing`/`save`/`playlist.trackIds` write block with:

```dart
final tracksToImport = <Track>[];
for (int i = 0; i < expandedTracks.length; i++) {
  if (_isCancelled) {
    if (isNewPlaylist) {
      _cancelledPlaylistId = playlist.id;
    }
    throw ImportException(t.importSource.cancelled);
  }

  final track = expandedTracks[i];
  _updateProgress(current: i + 1, currentItem: track.title);
  tracksToImport.add(track);
}

final mutationResult = await _mutationService.addTracks(
  playlist.id,
  tracksToImport,
);
addedCount = mutationResult.addedCount + mutationResult.repairedCount;
skippedCount = mutationResult.skippedCount;
errors.addAll(mutationResult.errors);
playlist = (await _playlistRepository.getById(playlist.id)) ?? playlist;
```

Keep `addedCount`, `skippedCount`, and `errors` variables so `ImportResult` construction remains stable.

- [ ] **Step 5: Keep import cover and refreshed metadata behavior**

After mutation, keep this existing behavior:

```dart
await _updatePlaylistCover(playlist, result.coverUrl, playlist.trackIds);
playlist.lastRefreshed = DateTime.now();
await _playlistRepository.save(playlist);
```

This keeps platform cover priority in `ImportService`; default cover for local adds stays in mutation service.

- [ ] **Step 6: Update provider construction**

Modify `lib/providers/import_playlist_provider.dart` to construct and pass `PlaylistMutationService`:

```dart
final isar = await ref.read(databaseProvider.future);
final mutationService = PlaylistMutationService(
  isar: isar,
);

return ImportService(
  sourceManager: sourceManager,
  playlistRepository: playlistRepository,
  trackRepository: trackRepository,
  isar: isar,
  mutationService: mutationService,
  bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
  youtubeAccountService: ref.read(youtubeAccountServiceProvider),
  neteaseAccountService: ref.read(neteaseAccountServiceProvider),
);
```

Add the import:

```dart
import '../services/library/playlist_mutation_service.dart';
```

- [ ] **Step 7: Run import creation tests**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart test/services/import/import_service_phase4_test.dart test/providers/import_playlist_provider_phase2_test.dart
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add lib/services/import/import_service.dart lib/providers/import_playlist_provider.dart test/services/library/playlist_mutation_service_test.dart
git commit -m "refactor(import): use playlist mutation service for imports"
```

### Task 4: Move refresh replacement and pruning policy into mutation service

**Files:**
- Modify: `lib/services/library/playlist_mutation_service.dart`
- Modify: `lib/services/import/import_service.dart`
- Modify: `lib/providers/refresh_provider.dart`
- Modify: `test/services/library/playlist_mutation_service_test.dart`
- Modify: `test/services/import/import_service_refresh_partial_test.dart`

- [ ] **Step 1: Add direct refresh replacement tests**

Append these tests to `test/services/library/playlist_mutation_service_test.dart`:

```dart
test('replaceTracksFromRemoteRefresh prunes stale tracks only on complete refresh', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final playlist = await _createPlaylist(harness, 'Refresh Complete');
  await harness.mutations.addTracks(
    playlist.id,
    [_track('keep', 'Keep'), _track('stale', 'Stale')],
  );

  final result = await harness.mutations.replaceTracksFromRemoteRefresh(
    playlist.id,
    [_track('keep', 'Keep'), _track('new', 'New')],
    const RemoteRefreshMutationPolicy(sourceDataComplete: true),
  );

  final savedPlaylist = await harness.playlists.getById(playlist.id);
  expect(result.pruningSkipped, isFalse);
  expect(result.addedCount, 1);
  expect(result.removedCount, 1);
  expect(await harness.tracks.getBySourceId('stale', SourceType.youtube), isNull);
  final savedTracks = await harness.tracks.getByIds(savedPlaylist!.trackIds);
  expect(savedTracks.map((track) => track.sourceId), ['keep', 'new']);
});

test('replaceTracksFromRemoteRefresh preserves stale tracks on partial refresh', () async {
  final harness = await _createHarness();
  addTearDown(harness.dispose);
  final playlist = await _createPlaylist(harness, 'Refresh Partial');
  await harness.mutations.addTracks(
    playlist.id,
    [_track('keep', 'Keep'), _track('stale', 'Stale')],
  );

  final result = await harness.mutations.replaceTracksFromRemoteRefresh(
    playlist.id,
    [_track('keep', 'Keep'), _track('new', 'New')],
    const RemoteRefreshMutationPolicy(sourceDataComplete: false),
  );

  final savedPlaylist = await harness.playlists.getById(playlist.id);
  final savedTracks = await harness.tracks.getByIds(savedPlaylist!.trackIds);
  expect(result.pruningSkipped, isTrue);
  expect(result.removedCount, 0);
  expect(savedTracks.map((track) => track.sourceId), ['keep', 'stale', 'new']);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart
```

Expected: fails because `replaceTracksFromRemoteRefresh` is not implemented.

- [ ] **Step 3: Implement refresh replacement method**

Add this method to `PlaylistMutationService`:

```dart
Future<PlaylistMutationResult> replaceTracksFromRemoteRefresh(
  int playlistId,
  List<Track> refreshedTracks,
  RemoteRefreshMutationPolicy policy,
) async {
  final candidateTracks = _dedupeTracksByUniqueKey(refreshedTracks);
  final addedTrackIds = <int>[];
  final repairedTrackIds = <int>[];
  final skippedTrackIds = <int>[];
  final removedTrackIds = <int>[];
  final deletedTrackIds = <int>[];
  final updatedTrackIds = <int>[];
  final errors = <String>[];
  var persistenceComplete = true;
  var playlistChanged = false;
  var coverChanged = false;

  await _isar.writeTxn(() async {
    final playlist = await _isar.playlists.get(playlistId);
    if (playlist == null) {
      throw PlaylistNotFoundException(playlistId);
    }

    final originalTrackIds = List<int>.from(playlist.trackIds);
    final originalTrackIdSet = originalTrackIds.toSet();
    final refreshedTrackIds = <int>[];
    final refreshedTrackIdSet = <int>{};
    final now = DateTime.now();

    for (final incomingTrack in candidateTracks) {
      try {
        final existingTrack = await _findTrackByIdentity(incomingTrack);
        final trackToSave = existingTrack ?? incomingTrack;
        final metadataChanged = existingTrack != null &&
            _mergeTrackMetadataIfNeeded(existingTrack, incomingTrack);
        final trackLinked = trackToSave.belongsToPlaylist(playlistId);
        final playlistLinked = existingTrack != null &&
            originalTrackIdSet.contains(trackToSave.id);

        if (!trackLinked) {
          trackToSave.addToPlaylist(playlistId, playlistName: playlist.name);
        }
        if (existingTrack == null || !trackLinked || metadataChanged) {
          trackToSave.updatedAt = now;
          trackToSave.id = await _isar.tracks.put(trackToSave);
          updatedTrackIds.add(trackToSave.id);
        }

        if (refreshedTrackIdSet.add(trackToSave.id)) {
          refreshedTrackIds.add(trackToSave.id);
        }
        if (!playlistLinked) {
          addedTrackIds.add(trackToSave.id);
        } else if (!trackLinked || metadataChanged) {
          repairedTrackIds.add(trackToSave.id);
        } else {
          skippedTrackIds.add(trackToSave.id);
        }
      } catch (error) {
        persistenceComplete = false;
        errors.add('${incomingTrack.title}: $error');
      }
    }

    final canPrune = policy.sourceDataComplete && persistenceComplete;
    final nextTrackIds = canPrune
        ? refreshedTrackIds
        : _mergePreservingExistingTrackOrder(originalTrackIds, refreshedTrackIds);

    if (canPrune) {
      removedTrackIds.addAll(
        originalTrackIdSet.difference(refreshedTrackIdSet),
      );
      final removedTracks =
          (await _isar.tracks.getAll(removedTrackIds)).whereType<Track>().toList();
      final tracksToUpdate = <Track>[];
      for (final track in removedTracks) {
        track.removeFromPlaylist(playlistId);
        if (track.playlistInfo.isEmpty) {
          deletedTrackIds.add(track.id);
        } else {
          track.updatedAt = now;
          tracksToUpdate.add(track);
          updatedTrackIds.add(track.id);
        }
      }
      if (deletedTrackIds.isNotEmpty) {
        await _isar.tracks.deleteAll(deletedTrackIds);
      }
      if (tracksToUpdate.isNotEmpty) {
        await _isar.tracks.putAll(tracksToUpdate);
      }
    }

    final oldCoverUrl = playlist.coverUrl;
    playlist.trackIds = nextTrackIds;
    playlist.lastRefreshed = now;
    playlist.updatedAt = now;
    await _refreshDefaultCoverInTxn(
      playlist,
      platformCoverUrl: policy.platformCoverUrl,
    );
    coverChanged = oldCoverUrl != playlist.coverUrl;
    await _isar.playlists.put(playlist);
    playlistChanged = true;
  });

  return PlaylistMutationResult(
    playlistId: playlistId,
    affectedPlaylistIds: [playlistId],
    addedTrackIds: addedTrackIds,
    repairedTrackIds: repairedTrackIds,
    skippedTrackIds: skippedTrackIds,
    removedTrackIds: removedTrackIds,
    deletedTrackIds: deletedTrackIds,
    updatedTrackIds: updatedTrackIds,
    errors: errors,
    playlistChanged: playlistChanged,
    coverChanged: coverChanged,
    pruningSkipped: !(policy.sourceDataComplete && persistenceComplete),
  );
}

List<int> _mergePreservingExistingTrackOrder(
  List<int> existingTrackIds,
  List<int> refreshedTrackIds,
) {
  final merged = List<int>.from(existingTrackIds);
  final seen = merged.toSet();
  for (final trackId in refreshedTrackIds) {
    if (seen.add(trackId)) {
      merged.add(trackId);
    }
  }
  return merged;
}
```

- [ ] **Step 4: Replace refresh loop writes in `ImportService`**

In `refreshPlaylist`, keep source parsing, Bilibili expansion, source completeness, progress, and cancellation checks. Replace the existing save/prune/update block from original-track calculation through playlist save with:

```dart
final mutationResult = await _mutationService.replaceTracksFromRemoteRefresh(
  playlist.id,
  expandedTracks,
  RemoteRefreshMutationPolicy(
    sourceDataComplete: sourceDataComplete,
    platformCoverUrl: result.coverUrl,
  ),
);
_throwIfCancelled();

final refreshedPlaylist = await _playlistRepository.getById(playlist.id) ?? playlist;
_updateProgress(status: ImportStatus.completed);

return ImportResult(
  playlist: refreshedPlaylist,
  addedCount: mutationResult.addedCount + mutationResult.repairedCount,
  skippedCount: mutationResult.skippedCount,
  removedCount: mutationResult.removedCount,
  pruningSkipped: mutationResult.pruningSkipped,
  errors: mutationResult.errors,
);
```

Remove `_mergePreservingExistingTrackOrder` from `ImportService`; it belongs in `PlaylistMutationService` now.

- [ ] **Step 5: Update refresh provider construction**

Modify `lib/providers/refresh_provider.dart` to import and pass `PlaylistMutationService`:

```dart
import '../services/library/playlist_mutation_service.dart';
```

Before constructing `ImportService`:

```dart
final mutationService = PlaylistMutationService(
  isar: isar,
);
```

Pass it:

```dart
mutationService: mutationService,
```

- [ ] **Step 6: Run refresh policy tests**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart test/services/import/import_service_refresh_partial_test.dart test/providers/refresh_provider_stale_cleanup_test.dart
```

Expected: all tests pass, including Phase 0 partial-pruning tests.

- [ ] **Step 7: Commit**

```bash
git add lib/services/library/playlist_mutation_service.dart lib/services/import/import_service.dart lib/providers/refresh_provider.dart test/services/library/playlist_mutation_service_test.dart test/services/import/import_service_refresh_partial_test.dart
git commit -m "refactor(refresh): centralize remote playlist replacement"
```

### Task 5: Wire providers, remove bypass helpers, and verify integration

**Files:**
- Modify: `lib/providers/playlist_provider.dart`
- Modify: `lib/providers/import_playlist_provider.dart`
- Modify: `lib/providers/refresh_provider.dart`
- Modify: `lib/data/repositories/playlist_repository.dart`
- Modify: `test/services/library/playlist_service_transaction_source_test.dart`

- [ ] **Step 1: Wire `PlaylistService` provider through mutation service**

Modify `lib/providers/playlist_provider.dart`:

```dart
import '../services/library/playlist_mutation_service.dart';
```

Then update `playlistServiceProvider`:

```dart
final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final playlistRepo = ref.watch(playlistRepositoryProvider);
  final trackRepo = ref.watch(trackRepositoryProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  final db = ref.watch(databaseProvider).valueOrNull;
  if (db == null) {
    throw StateError('Database not initialized');
  }
  final mutationService = PlaylistMutationService(
    isar: db,
  );
  return PlaylistService(
    playlistRepository: playlistRepo,
    trackRepository: trackRepo,
    settingsRepository: settingsRepo,
    isar: db,
    mutationService: mutationService,
  );
});
```

If Tasks 3 and 4 already added equivalent import-provider and refresh-provider wiring, keep those changes and do not create duplicate variables.

- [ ] **Step 2: Remove repository membership bypass helpers**

Delete these methods from `lib/data/repositories/playlist_repository.dart`:

```dart
Future<void> addTrack(int playlistId, int trackId)
Future<void> addTracks(int playlistId, List<int> trackIds)
Future<void> removeTrack(int playlistId, int trackId)
Future<void> removeTracks(int playlistId, List<int> trackIds)
Future<void> reorderTracks(int playlistId, List<int> newOrder)
```

Keep `updateLastRefreshed`, `updateSortOrders`, and read helpers.

- [ ] **Step 3: Update source-shape tests to prevent bypass regressions**

Append to `test/services/library/playlist_service_transaction_source_test.dart`:

```dart
test('PlaylistRepository no longer exposes direct membership mutators', () {
  final repositorySource =
      File('lib/data/repositories/playlist_repository.dart').readAsStringSync();

  expect(repositorySource, isNot(contains('Future<void> addTrack(')));
  expect(repositorySource, isNot(contains('Future<void> addTracks(')));
  expect(repositorySource, isNot(contains('Future<void> removeTrack(')));
  expect(repositorySource, isNot(contains('Future<void> removeTracks(')));
  expect(repositorySource, isNot(contains('Future<void> reorderTracks(')));
});
```

- [ ] **Step 4: Run focused integration tests**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart test/services/library/playlist_service_bidirectional_test.dart test/services/library/playlist_service_transaction_source_test.dart test/services/import/import_service_refresh_partial_test.dart test/services/import/import_service_phase4_test.dart test/services/library/remote_playlist_removal_sync_service_test.dart test/providers/playlist_provider_phase2_test.dart test/providers/import_playlist_provider_phase2_test.dart test/providers/refresh_provider_stale_cleanup_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/providers/playlist_provider.dart lib/providers/import_playlist_provider.dart lib/providers/refresh_provider.dart lib/data/repositories/playlist_repository.dart test/services/library/playlist_service_transaction_source_test.dart
git commit -m "refactor(playlist): remove repository membership bypasses"
```

### Task 6: Final verification and review readiness

**Files:**
- No production file changes expected unless verification exposes issues.

- [ ] **Step 1: Run the full focused verification set**

Run:

```bash
flutter test test/services/library/playlist_mutation_service_test.dart test/services/library/playlist_service_bidirectional_test.dart test/services/library/playlist_service_transaction_source_test.dart test/services/import/import_service_refresh_partial_test.dart test/services/import/import_service_phase4_test.dart test/services/library/remote_playlist_removal_sync_service_test.dart test/services/library/remote_playlist_actions_service_test.dart test/services/library/remote_playlist_sync_service_test.dart test/providers/playlist_provider_phase2_test.dart test/providers/import_playlist_provider_phase2_test.dart test/providers/refresh_provider_stale_cleanup_test.dart
```

Expected: all tests pass.

- [ ] **Step 2: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Inspect mutation bypasses**

Run:

```bash
git grep -n "playlist\.trackIds\|addToPlaylist\|removeFromPlaylist\|PlaylistRepository.*addTrack\|PlaylistRepository.*removeTrack" -- lib test
```

Expected: remaining `playlist.trackIds` reads are allowed; writes should be in `PlaylistMutationService`, playlist creation/setup tests, and non-membership metadata code. Remaining `addToPlaylist`/`removeFromPlaylist` production calls should be in `PlaylistMutationService` and Track model methods only.

- [ ] **Step 4: Commit verification fixes only if needed**

If Step 1-3 reveal small missed migration issues, fix them and commit:

```bash
git add <changed-files>
git commit -m "fix(playlist): complete membership mutation migration"
```

Skip this commit if there are no changes.

## Self-review checklist

- Spec coverage:
  - `addTracks(playlistId, tracks)` is implemented by Task 1 and delegated by Task 2.
  - `removeTracks(playlistId, trackIds)` is implemented by Task 2.
  - `replaceTracksFromRemoteRefresh(playlistId, desiredTracks, policy)` is implemented by Task 4.
  - `reorderTracks(playlistId, orderedTrackIds)` is implemented by Task 2.
  - Track identity lookup/creation and metadata merge are centralized in `PlaylistMutationService` by Tasks 1-4.
  - `Playlist.trackIds` and `Track.playlistInfo` writes are centralized by Tasks 2-5.
  - Removed-track cleanup and orphan cleanup are centralized by Tasks 2 and 4.
  - Cover update metadata is returned in `PlaylistMutationResult.coverChanged` by Tasks 1, 2, and 4.
  - Mutation results include affected playlist IDs, added/skipped/removed IDs, deleted/updated IDs, `coverChanged`, and `pruningSkipped`.
- Placeholder scan: no `TBD`, `TODO`, or vague implementation placeholders remain.
- Type consistency: `PlaylistMutationResult`, `RemoteRefreshMutationPolicy`, and `PlaylistMutationService` names are used consistently across tasks.

## Rollback considerations

- Each task commits independently. If import/refresh behavior regresses, revert Task 4 first; local playlist operations from Tasks 1-2 can remain isolated.
- If provider construction regresses, revert Task 5 and keep the fallback constructor path in `PlaylistService` and `ImportService` until wiring is corrected.
- Do not remove Phase 0 tests; they are the regression guard for partial refresh pruning.
