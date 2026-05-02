# Remote Playlist Sync Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make YouTube and Netease remote playlist edits trigger local imported playlist refreshes, matching Bilibili's in-app remote add behavior.

**Architecture:** Add a focused `RemotePlaylistSyncService` that maps platform remote playlist IDs to local imported `Playlist.sourceUrl` values and triggers background refresh callbacks. Wire Bilibili, YouTube, and Netease remote edit sheets through this shared service so successful remote changes refresh matching local imported playlists without blocking the UI.

**Tech Stack:** Flutter/Dart, Riverpod providers, Isar `Playlist` model, existing `RefreshManagerNotifier`, flutter_test.

---

## File Structure

- Create `lib/services/library/remote_playlist_sync_service.dart`: platform ID parsing, matching local imported playlists, background refresh trigger orchestration.
- Create `lib/providers/remote_playlist_sync_provider.dart`: Riverpod adapter from UI to `PlaylistService.getAllPlaylists()` and `RefreshManagerNotifier.refreshPlaylist()`.
- Modify `lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart`: keep Bilibili local removal behavior, use shared sync service for refresh triggering.
- Modify `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart`: trigger shared sync service after successful remote add/remove.
- Modify `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart`: trigger shared sync service after successful remote add/remove.
- Create `test/services/library/remote_playlist_sync_service_test.dart`: unit tests for matching and refresh triggering across Bilibili, YouTube, and Netease.

---

### Task 1: Add RemotePlaylistSyncService

**Files:**
- Create: `lib/services/library/remote_playlist_sync_service.dart`
- Test: `test/services/library/remote_playlist_sync_service_test.dart`

- [ ] **Step 1: Write the failing service tests**

Create `test/services/library/remote_playlist_sync_service_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_sync_service.dart';

void main() {
  group('RemotePlaylistSyncService', () {
    test('refreshes matching YouTube imported playlists only', () async {
      final refreshed = <int>[];
      final service = RemotePlaylistSyncService(
        getAllPlaylists: () async => [
          _playlist(1, SourceType.youtube, 'https://www.youtube.com/playlist?list=PL_MATCH'),
          _playlist(2, SourceType.youtube, 'https://www.youtube.com/playlist?list=PL_OTHER'),
          _playlist(3, SourceType.bilibili, 'https://space.bilibili.com/1/favlist?fid=123'),
        ],
        refreshPlaylist: (playlist) => refreshed.add(playlist.id),
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.youtube,
        remotePlaylistIds: ['PL_MATCH'],
      );

      expect(matched.map((p) => p.id), [1]);
      expect(refreshed, [1]);
    });

    test('parses Netease hash playlist URL and refreshes match', () async {
      final refreshed = <int>[];
      final service = RemotePlaylistSyncService(
        getAllPlaylists: () async => [
          _playlist(4, SourceType.netease, 'https://music.163.com/#/playlist?id=24680'),
        ],
        refreshPlaylist: (playlist) => refreshed.add(playlist.id),
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.netease,
        remotePlaylistIds: ['24680'],
      );

      expect(matched.map((p) => p.id), [4]);
      expect(refreshed, [4]);
    });

    test('parses Bilibili favorites URLs and skips mix playlists', () async {
      final refreshed = <int>[];
      final mix = _playlist(7, SourceType.youtube, 'https://www.youtube.com/playlist?list=PL_MIX')..isMix = true;
      final service = RemotePlaylistSyncService(
        getAllPlaylists: () async => [
          _playlist(5, SourceType.bilibili, 'https://space.bilibili.com/1/favlist?fid=13579'),
          _playlist(6, SourceType.bilibili, 'https://www.bilibili.com/medialist/detail/ml24680'),
          mix,
        ],
        refreshPlaylist: (playlist) => refreshed.add(playlist.id),
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.bilibili,
        remotePlaylistIds: ['13579', '24680'],
      );

      expect(matched.map((p) => p.id), [5, 6]);
      expect(refreshed, [5, 6]);
    });

    test('empty remote id set does not read or refresh playlists', () async {
      var readCalled = false;
      var refreshCalled = false;
      final service = RemotePlaylistSyncService(
        getAllPlaylists: () async {
          readCalled = true;
          return const [];
        },
        refreshPlaylist: (_) => refreshCalled = true,
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.youtube,
        remotePlaylistIds: ['', '   '],
      );

      expect(matched, isEmpty);
      expect(readCalled, isFalse);
      expect(refreshCalled, isFalse);
    });
  });
}

Playlist _playlist(int id, SourceType sourceType, String sourceUrl) {
  return Playlist()
    ..id = id
    ..name = 'Playlist $id'
    ..sourceUrl = sourceUrl
    ..importSourceType = sourceType;
}
```

- [ ] **Step 2: Run the service tests and verify RED**

Run:

```bash
flutter test test/services/library/remote_playlist_sync_service_test.dart
```

Expected: FAIL because `remote_playlist_sync_service.dart` does not exist.

- [ ] **Step 3: Implement the minimal service**

Create `lib/services/library/remote_playlist_sync_service.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/sources/bilibili_source.dart';

class RemotePlaylistSyncService {
  final Future<List<Playlist>> Function() getAllPlaylists;
  final void Function(Playlist playlist) refreshPlaylist;

  const RemotePlaylistSyncService({
    required this.getAllPlaylists,
    required this.refreshPlaylist,
  });

  Future<List<Playlist>> refreshMatchingImportedPlaylists({
    required SourceType sourceType,
    required Iterable<String> remotePlaylistIds,
  }) async {
    final remoteIds = remotePlaylistIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (remoteIds.isEmpty) return const [];

    final playlists = await getAllPlaylists();
    final matches = playlists.where((playlist) {
      if (playlist.importSourceType != sourceType) return false;
      if (playlist.isMix) return false;
      final sourceUrl = playlist.sourceUrl;
      if (sourceUrl == null || sourceUrl.isEmpty) return false;
      final remoteId = parseRemotePlaylistId(sourceType, sourceUrl);
      return remoteId != null && remoteIds.contains(remoteId);
    }).toList();

    for (final playlist in matches) {
      refreshPlaylist(playlist);
    }
    return matches;
  }

  @visibleForTesting
  static String? parseRemotePlaylistId(SourceType sourceType, String url) {
    switch (sourceType) {
      case SourceType.bilibili:
        return BilibiliSource.parseFavoritesId(url);
      case SourceType.youtube:
        final uri = Uri.tryParse(url);
        return uri?.queryParameters['list'];
      case SourceType.netease:
        final uri = Uri.tryParse(url);
        final id = uri?.queryParameters['id'];
        if (id != null && id.isNotEmpty) return id;
        final match = RegExp(r'/playlist[?/].*?(\d{5,})').firstMatch(url);
        return match?.group(1);
    }
  }
}
```

- [ ] **Step 4: Run the service tests and verify GREEN**

Run:

```bash
flutter test test/services/library/remote_playlist_sync_service_test.dart
```

Expected: PASS.

---

### Task 2: Add Riverpod Adapter

**Files:**
- Create: `lib/providers/remote_playlist_sync_provider.dart`

- [ ] **Step 1: Create provider adapter**

Create `lib/providers/remote_playlist_sync_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/library/remote_playlist_sync_service.dart';
import 'playlist_provider.dart';
import 'refresh_provider.dart';

final remotePlaylistSyncServiceProvider = Provider<RemotePlaylistSyncService>((ref) {
  final playlistService = ref.watch(playlistServiceProvider);
  return RemotePlaylistSyncService(
    getAllPlaylists: playlistService.getAllPlaylists,
    refreshPlaylist: (playlist) {
      unawaited(ref.read(refreshManagerProvider.notifier).refreshPlaylist(playlist));
    },
  );
});
```

- [ ] **Step 2: Run analyzer for provider imports**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors from `remote_playlist_sync_provider.dart`.

---

### Task 3: Wire Bilibili Remote Sheet to Shared Refresh Service

**Files:**
- Modify: `lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart:12-14,364-417`
- Test: `test/services/library/remote_playlist_sync_service_test.dart`

- [ ] **Step 1: Update imports**

Add this import near the other provider imports:

```dart
import '../../../providers/remote_playlist_sync_provider.dart';
```

- [ ] **Step 2: Replace Bilibili refresh trigger with shared service**

Inside `_syncLocalPlaylists`, keep the existing local removal loop. Replace only the direct refresh call block:

```dart
try {
  AppLogger.info('Triggering refresh for playlist "${playlist.name}"', 'RemoteFav');
  ref.read(refreshManagerProvider.notifier).refreshPlaylist(playlist);
} catch (e) {
  AppLogger.error('Failed to trigger refresh: $e', 'RemoteFav');
}
```

with this after the loop finishes:

```dart
await ref.read(remotePlaylistSyncServiceProvider).refreshMatchingImportedPlaylists(
      sourceType: SourceType.bilibili,
      remotePlaylistIds: changedFolderIds.map((id) => id.toString()),
    );
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
flutter test test/services/library/remote_playlist_sync_service_test.dart
```

Expected: PASS.

---

### Task 4: Wire YouTube Remote Sheet Refresh

**Files:**
- Modify: `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:8-10,287-332`

- [ ] **Step 1: Add provider import**

Add:

```dart
import '../../../providers/remote_playlist_sync_provider.dart';
```

- [ ] **Step 2: Trigger matching local refreshes after remote edits**

In `_submit`, after the loop that performs `addToPlaylist` and `removeFromPlaylist`, before the success Toast, insert:

```dart
await ref.read(remotePlaylistSyncServiceProvider).refreshMatchingImportedPlaylists(
      sourceType: SourceType.youtube,
      remotePlaylistIds: [...toAdd, ...toRemove],
    );
```

- [ ] **Step 3: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors in `add_to_youtube_playlist_dialog.dart`.

---

### Task 5: Wire Netease Remote Sheet Refresh

**Files:**
- Modify: `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:8-10,251-284`

- [ ] **Step 1: Add provider import**

Add:

```dart
import '../../../providers/remote_playlist_sync_provider.dart';
```

- [ ] **Step 2: Trigger matching local refreshes after remote edits**

In `_submit`, after NetEase add/remove loops and before the success Toast, insert:

```dart
await ref.read(remotePlaylistSyncServiceProvider).refreshMatchingImportedPlaylists(
      sourceType: SourceType.netease,
      remotePlaylistIds: [...toAdd, ...toRemove],
    );
```

- [ ] **Step 3: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors in `add_to_netease_playlist_dialog.dart`.

---

### Task 6: Full Verification

**Files:**
- Verify: `lib/services/library/remote_playlist_sync_service.dart`
- Verify: `lib/providers/remote_playlist_sync_provider.dart`
- Verify: all three remote dialog files

- [ ] **Step 1: Run focused test suite**

Run:

```bash
flutter test test/services/library/remote_playlist_sync_service_test.dart test/services/library/remote_playlist_actions_service_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 3: Manual behavior check**

Run the app, add a YouTube or Netease track to a remote playlist that is already imported locally, then return to the library page. Expected: the matching local playlist shows the refresh overlay/progress and updates after refresh completes. Add to a remote playlist not imported locally. Expected: no local playlist refresh starts.
