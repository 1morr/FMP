# Performance and Data Access Review

Scope: reviewed repository/data-access code, Riverpod provider flows, import/refresh/download/lyrics/cache paths, and UI rebuild patterns. No production code was changed.

## Priority summary

- **P0:** None found.
- **P1:** Batch track identity lookups and import/refresh writes; stop history page/stats from full-snapshot scanning; add true batch download enqueue/sync paths.
- **P2:** Reduce playlist-cover N+1 I/O, search-history cleanup scans, remote playlist per-item API scans, and broad watch-derived rebuilds.

## Findings

### P1: Track identity lookup is duplicated and often per-item

**Where**
- `lib/services/library/playlist_service.dart:349` processes a batch but calls `_findTrackByIdentity()` for each candidate inside a write transaction; `_findTrackByIdentity()` itself is at `lib/services/library/playlist_service.dart:434`.
- `lib/services/import/import_service.dart:269` and `lib/services/import/import_service.dart:509` do the same per-track lookup/save pattern during import and refresh.
- `lib/data/repositories/track_repository.dart:62` has the reusable `getBySourceIdAndCid()` path, and the model already exposes generated identity keys at `lib/data/models/track.dart:269` and `lib/data/models/track.dart:273`.

**Why it matters**
Large playlist import, refresh, and bulk add flows perform N indexed queries, N object mutations, and often N writes. Some checks also use `playlist.trackIds.contains(...)` inside the loop (`lib/services/import/import_service.dart:296`, `lib/services/import/import_service.dart:528`), which makes the path drift toward O(n²) for large playlists.

**Recommendation**
Create one shared batch identity API, e.g. `getByUniqueKeys()` / `getBySourcePageKeys()`, returning `Map<String, Track>`. Use it from `PlaylistService.addTracksToPlaylist()`, `ImportService.importFromUrl()`, `ImportService.refreshPlaylist()`, download sync, and any future remote refresh flow. Accumulate changed tracks and save with one `putAll()` plus one playlist save.

### P1: Import and refresh still write one track at a time

**Where**
- New import loop: `lib/services/import/import_service.dart:269` through `lib/services/import/import_service.dart:324`.
- Refresh loop: `lib/services/import/import_service.dart:509` through `lib/services/import/import_service.dart:554`.
- Removed-track cleanup is already partially batched at `lib/services/import/import_service.dart:563`, which is a good pattern to reuse earlier in the method.

**Why it matters**
For Bilibili favorites and YouTube playlists, the expensive work is not just source parsing; persistence also scales linearly with await boundaries. Existing tracks are saved immediately after adding playlist membership (`lib/services/import/import_service.dart:299`, `lib/services/import/import_service.dart:531`, `lib/services/import/import_service.dart:538`), and new tracks are saved one at a time (`lib/services/import/import_service.dart:314`, `lib/services/import/import_service.dart:546`).

**Recommendation**
After source parsing/expansion, build:
1. a set of track identity keys,
2. a `Set<int>` for existing playlist membership,
3. `toPutTracks`, `newTrackIds`, `addedCount`, and `skippedCount` in memory,
4. one transaction that `putAll()`s changed tracks and saves the playlist.

This would also simplify the code by aligning import, refresh, and `PlaylistService.addTracksToPlaylist()` around the same batch helper.

### P1: Play history uses large snapshots and repeated full scans

**Where**
- `playHistorySnapshotProvider` loads a snapshot immediately and again on every Isar lazy change: `lib/providers/play_history_provider.dart:9` through `lib/providers/play_history_provider.dart:17`.
- That snapshot is capped at 1000 via `loadHistorySnapshot()`: `lib/data/repositories/play_history_repository.dart:253` through `lib/data/repositories/play_history_repository.dart:266`.
- Filter/sort/group then happens in memory: `lib/providers/play_history_provider.dart:81` through `lib/providers/play_history_provider.dart:101`, `lib/providers/play_history_provider.dart:112` through `lib/providers/play_history_provider.dart:167`, and `lib/providers/play_history_provider.dart:377` through `lib/providers/play_history_provider.dart:383`.
- Stats and counts scan all rows: `lib/data/repositories/play_history_repository.dart:29`, `lib/data/repositories/play_history_repository.dart:36`, `lib/data/repositories/play_history_repository.dart:197`, `lib/data/repositories/play_history_repository.dart:210`, and `lib/data/repositories/play_history_repository.dart:220`.

**Why it matters**
Every new history row can trigger a 1000-row reload plus in-memory filtering, grouping, and sorting. The stats card independently scans all history, so opening the history page duplicates work. Also, the UI can never show more than the snapshot limit without switching to a different provider path.

**Recommendation**
Make history page data query-driven and paginated instead of snapshot-driven:
- Persist and index a `trackKey` field or add a queryable composite identity for source/cid play counts.
- Use Isar queries for date/source/search filters and paging, rather than filtering a 1000-row snapshot.
- Compute stats from bounded date-range queries or maintain lightweight aggregate counters.
- Reserve full-history scans for explicit maintenance/export operations.

### P1: Selected-track download enqueue repeats path, task, and priority work per item

**Where**
- `DownloadService.addTrackDownload()` computes base dir, save path, existing task, next priority, and save per track: `lib/services/download/download_service.dart:363` through `lib/services/download/download_service.dart:416`.
- Playlist detail bulk selection calls it sequentially with `skipSchedule: true`: `lib/ui/pages/library/playlist_detail_page.dart:306` through `lib/ui/pages/library/playlist_detail_page.dart:323`.
- The service already has a more batched playlist path at `lib/services/download/download_service.dart:426` through `lib/services/download/download_service.dart:510`.

**Why it matters**
Bulk selected downloads can issue N `getDefaultBaseDir()`, N save-path lookups, N `getNextPriority()` queries, and N writes. This duplicates the batching already implemented for full-playlist downloads.

**Recommendation**
Add a `addTracksDownload(List<Track>, Playlist)` method that mirrors `addPlaylistDownload()`:
- get base dir once,
- compute all save paths once,
- query existing tasks once via `getTasksBySavePaths()`,
- compute base priority once,
- save new tasks with `saveTasks()`.

Then route selected-track downloads through the batch method.

### P1: Local download sync performs repeated DB reads/writes and has an O(n²) inner match

**Where**
- Folder scan and match loop: `lib/services/download/download_path_sync_service.dart:63` through `lib/services/download/download_path_sync_service.dart:87`.
- Per-file DB lookup: `lib/services/download/download_path_sync_service.dart:185` and `lib/services/download/download_path_sync_service.dart:231`.
- Per-track re-fetch and save: `lib/services/download/download_path_sync_service.dart:90` through `lib/services/download/download_path_sync_service.dart:148`.
- Full scan cleanup: `lib/services/download/download_path_sync_service.dart:151` through `lib/services/download/download_path_sync_service.dart:160`.
- Inner `indexWhere` calls `pathInfos.indexOf(p)` for each candidate: `lib/services/download/download_path_sync_service.dart:111` through `lib/services/download/download_path_sync_service.dart:113`.

**Why it matters**
The file scan is already I/O-heavy. Adding per-track DB round trips and repeated saves makes manual sync expensive for large download libraries. The `indexWhere(... indexOf(...))` pattern adds avoidable O(k²) work per track when multiple local paths exist.

**Recommendation**
Split sync into phases: scan all DTOs, batch-resolve track identities, compute all changed `playlistInfo` in memory, then `putAll()` changed tracks. Replace the `indexWhere/indexOf` match with an indexed loop or a playlist-name multimap.

### P2: Playlist cover providers create N+1 DB/file work across grids

**Where**
- `playlistCoverProvider` calls `getPlaylistCoverData()` per playlist: `lib/providers/playlist_provider.dart:522` through `lib/providers/playlist_provider.dart:526`.
- `getPlaylistCoverData()` fetches the playlist, maybe fetches the first track, then checks local cover files: `lib/services/library/playlist_service.dart:644` through `lib/services/library/playlist_service.dart:675`.
- Cards watch this provider in library/home/dialogs: `lib/ui/pages/library/library_page.dart:258`, `lib/ui/pages/library/library_page.dart:369`, `lib/ui/pages/home/home_page.dart:1210`, and `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:292`.

**Why it matters**
A grid with many playlists fans out into many FutureProviders, each doing DB and filesystem work. The project already has `FileExistsCache`, but this path uses direct `File.exists()` checks.

**Recommendation**
Either store the derived default cover fields on `Playlist`, or expose a single `playlistCoverMapProvider` that batches first-track lookup for visible playlists and uses `FileExistsCache` for local cover existence. This would also simplify invalidation after downloads/playlist edits.

### P2: Download task providers are broad and some helpers scan all tasks

**Where**
- `downloadTasksProvider` watches every task: `lib/providers/download/download_providers.dart:116` through `lib/providers/download/download_providers.dart:119`.
- Helper providers derive per-track state by scanning the whole list: `lib/providers/download/download_providers.dart:197` through `lib/providers/download/download_providers.dart:219`.
- Download manager rows fetch track metadata per task via `trackByIdProvider`: `lib/ui/pages/settings/download_manager_page.dart:326`.

**Why it matters**
This is acceptable while task counts are small, but if task indicators are added back to playlist/search rows, each visible row can scan the full task list. The manager page also fans out one DB get per task for title/artist.

**Recommendation**
Keep a derived `Map<int, DownloadTask>` / `Map<int, List<DownloadTask>>` provider keyed by track id, and batch-load task track metadata for the manager list.

### P2: Search history cleanup loads and deletes more than needed

**Where**
- Duplicate lookup and cleanup are in `SearchService._saveSearchHistory()`: `lib/services/search/search_service.dart:230` through `lib/services/search/search_service.dart:261`.
- `SearchHistory.query` is indexed but not unique: `lib/data/models/search_history.dart:10` through `lib/data/models/search_history.dart:16`.

**Why it matters**
The current cap is only 100, so this is not urgent. Still, every search loads all retained history and deletes overflow rows individually.

**Recommendation**
Make `query` unique with replace semantics, then delete overflow by querying ids after `offset(AppConstants.maxSearchHistoryCount)`, or keep the history table small with a repository method dedicated to capped insertion.

### P2: Remote playlist operations still have per-item API scans

**Where**
- YouTube remote removal calls `getYoutubeSetVideoId()` per selected track: `lib/services/library/remote_playlist_actions_service.dart:65` through `lib/services/library/remote_playlist_actions_service.dart:72`.
- `YouTubePlaylistService.getSetVideoId()` scans playlist pages to find one video: `lib/services/account/youtube_playlist_service.dart:143` through `lib/services/account/youtube_playlist_service.dart:156`.
- Netease membership checking loads each writable playlist detail in small batches: `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:97` through `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:145`.

**Why it matters**
Bulk remote edits can multiply network calls. Bilibili and Netease removal are already batched; YouTube can still scan the same playlist repeatedly.

**Recommendation**
For YouTube, fetch playlist contents once into `videoId -> setVideoId`, then submit one edit request with multiple remove actions if supported. For Netease add dialog, defer membership checks until the user selects/opens playlists, or cache playlist detail membership for the sheet lifetime.

### P2: Lyrics auto-match can repeat source searches across fallback paths

**Where**
- Source/query nested loop is at `lib/services/lyrics/lyrics_auto_match_service.dart:252` through `lib/services/lyrics/lyrics_auto_match_service.dart:293`.
- Advanced AI mode collects candidates by searching all enabled sources/query pairs: `lib/services/lyrics/lyrics_auto_match_service.dart:330` through `lib/services/lyrics/lyrics_auto_match_service.dart:365`.

**Why it matters**
The service correctly prevents concurrent matching per track (`lib/services/lyrics/lyrics_auto_match_service.dart:64`), and caches AI title parses. But failed source searches are not memoized across the current match attempt, so fallback paths can repeat equivalent searches when AI is unavailable or advanced selection falls back.

**Recommendation**
Add a per-attempt memo map keyed by `(source, trackName, artistName)` and share it between advanced AI candidate collection and regex fallback. Keep it local to one `tryAutoMatch()` call to avoid stale network data.

## What to simplify first

1. **Introduce one batch track identity resolver** and replace per-track `getBySourceIdAndCid()` loops in playlist add, import, refresh, and local download sync.
2. **Make play history query-driven** instead of snapshot-driven; persist/index a queryable track key and avoid full scans for counts/stats.
3. **Add batch download enqueue for selected tracks** by reusing the existing playlist-download batching strategy.
4. **Centralize playlist cover derivation** so grids do not spawn one DB/filesystem lookup chain per card.
5. **Batch remote YouTube playlist removals** after fetching playlist contents once.
