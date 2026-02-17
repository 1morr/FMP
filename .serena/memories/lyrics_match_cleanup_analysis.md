# LyricsMatch Cleanup Analysis

## Current State: ORPHAN LYRICS_MATCH RECORDS EXIST

When playlists or tracks are deleted, **LyricsMatch records are NOT cleaned up**. This creates orphan records in the database.

## Data Model Relationships

### Track Model
- **Unique Key**: `Track.uniqueKey` = `"${sourceType}:${sourceId}"` or `"${sourceType}:${sourceId}:${cid}"` (for multi-page videos)
- **Playlist Association**: `Track.playlistInfo` (List<PlaylistDownloadInfo>)
  - Each PlaylistDownloadInfo contains: playlistId, playlistName, downloadPath
- **Deletion Logic**: Track is deleted when `playlistInfo.isEmpty` (no longer belongs to any playlist)

### LyricsMatch Model
- **Unique Key**: `LyricsMatch.trackUniqueKey` (indexed, unique, replace: true)
- **Relationship**: Keyed by `Track.uniqueKey`, NOT by Track.id
- **Current Cleanup**: NONE - no deletion when Track is deleted

## Deletion Scenarios Creating Orphans

### 1. Playlist Deletion (`PlaylistService.deletePlaylist()`)
**File**: `lib/services/library/playlist_service.dart` (lines 199-251)

```dart
Future<void> deletePlaylist(int playlistId) async {
  // Gets all tracks in playlist
  final tracks = await _trackRepository.getByIds(trackIds);
  
  for (final track in tracks) {
    track.removeFromPlaylist(playlistId);
    
    // Track deleted if playlistInfo becomes empty
    if (track.playlistInfo.isEmpty) {
      toDelete.add(track.id);
    }
  }
  
  // Batch delete orphan tracks
  await _isar.tracks.deleteAll(toDelete);
  // ❌ NO CLEANUP OF LYRICS_MATCH RECORDS
}
```

**Impact**: When a track is deleted, its LyricsMatch record remains in DB with orphan `trackUniqueKey`

### 2. Track Removal from Playlist (`PlaylistService.removeTrackFromPlaylist()`)
**File**: `lib/services/library/playlist_service.dart` (lines 346-376)

```dart
Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
  track.removeFromPlaylist(playlistId);
  
  if (track.playlistInfo.isEmpty) {
    await _trackRepository.delete(trackId);
    // ❌ NO CLEANUP OF LYRICS_MATCH RECORDS
  }
}
```

### 3. Batch Track Removal (`PlaylistService.removeTracksFromPlaylist()`)
**File**: `lib/services/library/playlist_service.dart` (lines 379-423)

Same issue - tracks deleted without cleaning up LyricsMatch records.

## Orphan Cleanup Mechanisms (Existing)

### 1. Download Path Cleanup
**File**: `lib/data/repositories/track_repository.dart` (lines 459-521)

```dart
Future<int> cleanupInvalidDownloadPaths() async {
  // Clears non-existent download paths from Track.playlistInfo
  // Called at app startup
}
```

### 2. Orphan Track Cleanup
**File**: `lib/data/repositories/track_repository.dart` (lines 523-571)

```dart
Future<int> deleteOrphanTracks({List<int> excludeTrackIds = const []}) async {
  // Deletes Track records where:
  // - Not in current queue (excludeTrackIds)
  // - playlistInfo contains only entries with playlistId <= 0
  // Called in QueueManager.initialize()
  // ❌ STILL NO CLEANUP OF LYRICS_MATCH RECORDS
}
```

## Problem Summary

| Scenario | Track Deleted? | LyricsMatch Cleaned? | Result |
|----------|---|---|---|
| Delete playlist | ✅ Yes (if orphan) | ❌ No | Orphan LyricsMatch |
| Remove track from playlist | ✅ Yes (if orphan) | ❌ No | Orphan LyricsMatch |
| Batch remove tracks | ✅ Yes (if orphan) | ❌ No | Orphan LyricsMatch |
| App startup cleanup | ✅ Yes (orphans) | ❌ No | Orphan LyricsMatch |

## Recommended Solution

### Option 1: Cleanup During Deletion (Recommended)
Add LyricsMatch cleanup to `PlaylistService` methods:

```dart
// In deletePlaylist(), after deleting tracks:
for (final track in tracks) {
  await _lyricsRepository.delete(track.uniqueKey);
}

// In removeTrackFromPlaylist(), when deleting track:
if (track.playlistInfo.isEmpty) {
  await _lyricsRepository.delete(track.uniqueKey);
  await _trackRepository.delete(trackId);
}
```

**Pros**: 
- Immediate cleanup, no orphans created
- Minimal performance impact (one extra DB operation per deleted track)

**Cons**:
- Requires modifying multiple methods
- Adds dependency on LyricsRepository to PlaylistService

### Option 2: Batch Cleanup at App Startup
Add to `QueueManager.initialize()` after `deleteOrphanTracks()`:

```dart
// Delete LyricsMatch records for non-existent tracks
final allTracks = await _trackRepository.getAll();
final validKeys = allTracks.map((t) => t.uniqueKey).toSet();

final allMatches = await _lyricsRepository.getAll();
for (final match in allMatches) {
  if (!validKeys.contains(match.trackUniqueKey)) {
    await _lyricsRepository.delete(match.trackUniqueKey);
  }
}
```

**Pros**:
- Single cleanup point
- No changes to deletion logic

**Cons**:
- Orphans exist until app restart
- Requires iterating all LyricsMatch records (potentially slow)

### Option 3: Hybrid Approach (Best)
- **Immediate**: Clean up during deletion (Option 1)
- **Fallback**: Batch cleanup at startup (Option 2) for safety

## Implementation Notes

### LyricsRepository Methods Needed
```dart
// Already exists:
Future<void> delete(String trackUniqueKey) async {
  await _isar.writeTxn(() async {
    await _isar.lyricsMatchs
        .where()
        .trackUniqueKeyEqualTo(trackUniqueKey)
        .deleteAll();
  });
}

// May need to add:
Future<List<LyricsMatch>> getAll() async {
  return _isar.lyricsMatchs.where().findAll();
}
```

### Track.uniqueKey Format
- Single-page: `"youtube:dQw4w9WgXcQ"`
- Multi-page: `"bilibili:BV1xx411c7mD:12345"`

The LyricsMatch.trackUniqueKey must match exactly for cleanup to work.

## Files to Modify

1. `lib/services/library/playlist_service.dart` - Add LyricsMatch cleanup to deletion methods
2. `lib/data/repositories/lyrics_repository.dart` - Add `getAll()` method if needed
3. `lib/services/audio/queue_manager.dart` - Add batch cleanup at startup (optional)

## Testing Considerations

1. Delete playlist with downloaded tracks → verify LyricsMatch cleaned
2. Remove track from playlist → verify LyricsMatch cleaned
3. Batch remove tracks → verify all LyricsMatch cleaned
4. App restart → verify no orphan LyricsMatch records
5. Multi-page video deletion → verify all page variants cleaned
