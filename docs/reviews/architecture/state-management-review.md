# State Management Review

## Findings

### P1 - Search clear does not cancel in-flight search requests

理由：`SearchNotifier.search()` uses `_searchRequestId` to suppress stale async results, but only increments it for non-empty searches. The empty-query branch resets state without cancelling the previous request, and `clear()` also only replaces state. Because the UI clear button calls `clear()`, a slow search can complete after the user clears the box and repopulate results.

風險：Search UI can show stale online/local results under an empty query or after the user has intentionally cleared state. This is a user-visible stale state bug, not just a cosmetic loading issue.

建議方向：Add a small cancellation method, for example `_cancelSearch() => _searchRequestId++`, and call it from `clear()` and the empty-query branches of `search()` / `searchLiveRooms()`. Keep the existing request-id checks; add a focused notifier test where a delayed search future completes after `clear()`.

### P1 - FileExistsCache invalidation contract can leave local file state stale

理由：Single-track delete in the downloaded category page deletes files in an isolate, clears the DB download path, then calls `downloadStateChanged(fileExistsChanged: false)`. That skips `FileExistsCache` invalidation even though files were removed. A nearby audio-stream path removal handles the same cache concern explicitly by removing each path from `fileExistsCacheProvider`.

風險：Widgets using `TrackThumbnail`, local avatar lookup, or `filePathExistsProvider` can keep believing a deleted file exists, or fail to re-preload paths after a cache reset. This can surface as stale local covers/avatars or missing local images until another cache-changing event happens.

建議方向：For delete flows, either pass removed `savePaths` through `downloadStateChanged()` with `fileExistsChanged: true`, or explicitly remove every deleted path from `fileExistsCacheProvider.notifier`. Separately, make cache reset bump the same generation watched by preload gates; `ref.invalidate(fileExistsCacheProvider)` currently resets the notifier without necessarily changing `fileExistsCacheEpochProvider`.

### P2 - Batch add/remove dialog invalidates changed playlists more than once

理由：`AddToPlaylistDialog` performs remove/add mutations in loops and calls `playlistChanged(playlistId, includeAll: false)` after each successful playlist. After both loops, it calls `playlistsChanged([...toAdd, ...toRemove])`, which invalidates the same detail/cover providers again.

風險：For multi-playlist edits, the same provider families can be invalidated twice per changed playlist, creating extra FutureProvider churn and duplicate detail/cover reloads. It is unlikely to corrupt state, but it increases flicker and makes refresh ownership harder to reason about.

建議方向：Accumulate successfully changed playlist IDs and call `libraryInvalidationCoordinatorProvider.playlistsChanged()` once after the loops. Keep per-playlist mutation error handling; the fix is to consolidate invalidation, not to redesign the dialog.

### No finding - Current provider style is internally consistent

理由：The reviewed codebase consistently uses Riverpod 2.x `StateNotifierProvider`, `FutureProvider`, `StreamProvider`, selector providers, and provider families. I found no `NotifierProvider` or `AsyncNotifierProvider` usage, so there is no mixed-generation Riverpod API problem to fix.

風險：Migrating this area to `Notifier` / `AsyncNotifier` now would introduce broad churn without reducing the concrete stale-state issues above.

建議方向：Do not run a broad Riverpod migration. Fix the targeted request-cancellation and invalidation-contract issues first.

## Evidence

- `lib/providers/search_provider.dart:228` resets state for an empty query before any request-id increment.
- `lib/providers/search_provider.dart:240` increments `_searchRequestId` only for non-empty video searches.
- `lib/providers/search_provider.dart:264` and `lib/providers/search_provider.dart:284` rely on that request id to suppress stale video-search completion.
- `lib/providers/search_provider.dart:528` starts `clear()`, and `lib/providers/search_provider.dart:529` replaces state without incrementing `_searchRequestId`.
- `lib/providers/search_provider.dart:601` has the same empty-query reset pattern for live-room search, while `lib/providers/search_provider.dart:611` increments the request id only afterward.
- `lib/ui/pages/search/search_page.dart:115` wires the clear button to `ref.read(searchProvider.notifier).clear()`.

- `lib/ui/pages/library/downloaded_category_page.dart:27` defines the isolate deletion helper.
- `lib/ui/pages/library/downloaded_category_page.dart:37` deletes the audio file.
- `lib/ui/pages/library/downloaded_category_page.dart:63` can delete the now-empty parent directory.
- `lib/ui/pages/library/downloaded_category_page.dart:914` passes `track.allDownloadPaths` to the delete helper.
- `lib/ui/pages/library/downloaded_category_page.dart:917` clears the DB download path.
- `lib/ui/pages/library/downloaded_category_page.dart:921` calls the library invalidation coordinator, but `lib/ui/pages/library/downloaded_category_page.dart:923` sets `fileExistsChanged: false`.
- `lib/services/audio/audio_provider.dart:3076` also uses `fileExistsChanged: false` for removed paths, but `lib/services/audio/audio_provider.dart:3079` explicitly removes each path from `fileExistsCacheProvider`.
- `lib/providers/library_invalidation_coordinator.dart:97` invalidates file-existence state when `fileExistsChanged` is true.
- `lib/providers/library_invalidation_coordinator.dart:166` implements that by invalidating `fileExistsCacheProvider`.
- `lib/providers/download/file_exists_cache.dart:144` updates the cache epoch only from `_updateState()`, and `lib/providers/download/file_exists_cache.dart:236` defines the separate `fileExistsCacheEpochProvider`.
- `lib/ui/widgets/track_detail_panel.dart:768` gates avatar preload by path set and epoch, `lib/ui/widgets/track_detail_panel.dart:772` returns early when both match, and `lib/ui/widgets/track_detail_panel.dart:805` watches the epoch.
- `lib/ui/pages/library/playlist_detail_page.dart:113` reads the cache epoch for initial preload, and `lib/ui/pages/library/playlist_detail_page.dart:165` watches it during build.

- `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:557` reads `playlistServiceProvider` for mutation.
- `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:562` reads `trackRepositoryProvider` to resolve existing tracks.
- `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:579` invalidates each successful removal playlist.
- `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:592` invalidates each successful add playlist.
- `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:599` invalidates all changed playlists again.
- `lib/providers/library_invalidation_coordinator.dart:41` shows `playlistChanged()` delegates to `playlistsChanged()`, and `lib/providers/library_invalidation_coordinator.dart:55` is the bulk invalidation entry point.

- `lib/services/audio/AGENTS.md:28` says UI playback controls must call `AudioController`, and `rg` found `audioServiceProvider` usage only in `lib/services/radio/radio_controller.dart:1124` outside UI, matching the documented radio exception.
- `docs/development.md:10` describes Riverpod 2.x with `StateNotifier`, `FutureProvider`, and `StreamProvider`; the current provider declarations match that description.

## Risk

The highest practical risk is stale user-visible state after asynchronous work completes out of order. Search already has the correct request-id pattern, but the cancellation surface is incomplete.

The second risk is inconsistent ownership of file-existence state. `libraryInvalidationCoordinatorProvider` is the right module, but the current interface mixes provider invalidation, direct cache mutation, and a separate epoch provider. That makes some call sites skip cache invalidation accidentally and some preload gates miss cache resets.

The duplicate invalidation issue is lower severity. It wastes work and makes refresh behavior noisy, but it does not appear to lose data because mutations still go through `PlaylistService` and coordinator calls.

## Suggested direction

1. Patch `SearchNotifier` narrowly: increment the request generation for `clear()` and empty-query resets, then test delayed completion after clear.
2. Tighten `FileExistsCache` ownership through the coordinator. Prefer one contract: either all file mutations pass exact removed/added paths to the coordinator, or the coordinator exposes explicit `pathsRemoved` / `pathsAdded` behavior that updates cache, downloaded `FutureProvider`s, and loaded playlist details together.
3. Consolidate `AddToPlaylistDialog` invalidation to one coordinator call after successful mutations. Do not move the whole dialog flow unless future changes add more batch business rules.
4. Keep the existing `StateNotifierProvider` style for now. A Riverpod API migration would be broad and does not directly address the stale-state defects found here.

不建議改的地方：

- Do not replace playlist/detail `StateNotifier` optimistic updates wholesale. `lib/providers/playlist_provider.dart:417`, `lib/providers/playlist_provider.dart:443`, `lib/providers/playlist_provider.dart:471`, and `lib/providers/playlist_provider.dart:503` already use optimistic updates with rollback via `loadPlaylist()`, matching `lib/providers/AGENTS.md:10`.
- Do not treat `lib/ui/pages/library/library_page.dart:64` or `lib/ui/pages/library/downloaded_category_page.dart:145` as coordinator violations by themselves. They are navigation/pull-to-refresh reads of `FutureProvider` data, not mutation side effects; `lib/ui/AGENTS.md:52` explicitly allows `RefreshIndicator` plus `ref.invalidate()`.
- Do not introduce an app-wide hidden source filter for search. The current search provider keeps source selection in page chips, which matches `lib/providers/AGENTS.md:24`.

## Instruction docs accuracy notes

- `AGENTS.md:117` through `AGENTS.md:129` accurately identifies Riverpod as the app state layer and names `libraryInvalidationCoordinatorProvider` as a key coordinator. The code contains that coordinator at `lib/providers/library_invalidation_coordinator.dart:149`.
- `lib/providers/AGENTS.md:9` through `lib/providers/AGENTS.md:13` accurately describe the current patterns: DB collection watchers, playlist detail `StateNotifier` with optimistic update, file-system `FutureProvider`, ranking cache state, and settings notifiers.
- `lib/providers/AGENTS.md:19` through `lib/providers/AGENTS.md:20` is directionally correct, but should eventually clarify the file-existence cache generation contract: invalidating `fileExistsCacheProvider` is not equivalent to notifying widgets gated on `fileExistsCacheEpochProvider`.
- `lib/ui/AGENTS.md:17` through `lib/ui/AGENTS.md:22` documents the intended FileExistsCache watch/read split. The code has evolved to use `.select(...)` and `fileExistsCacheEpochProvider` in some places, so the doc could mention that epoch-based preload gates must also be bumped by cache resets.
- `.serena/memories/refactoring_lessons.md:3` correctly warns that memories are supplemental, not complete current guidance. Its Riverpod notes at `.serena/memories/refactoring_lessons.md:20` through `.serena/memories/refactoring_lessons.md:30` still match the active rules.
- `docs/README.md:17` through `docs/README.md:20` accurately says `AGENTS.md` is authoritative, `docs/development.md` is onboarding, memories are narrow supplements, and archived refactoring notes are not current rules.
- `docs/development.md:10` and `docs/development.md:36` are accurate high-level descriptions. `docs/development.md:60` links to `../AGENTS.md#file-structure-highlights`, but the current root `AGENTS.md` does not have a `file-structure-highlights` anchor; this is a documentation link accuracy issue, not a state-management code issue.
