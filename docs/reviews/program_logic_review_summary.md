# Program Logic Review Summary

Date: 2026-05-02

This document summarizes the multi-agent review of FMP's current program logic, with emphasis on keeping playlist, library, UI, provider, data access, and cross-source behavior simple and unified.

## Source review documents

- `docs/reviews/architecture_services_review.md`
- `docs/reviews/playlist_library_review.md`
- `docs/reviews/ui_riverpod_review.md`
- `docs/reviews/performance_data_review.md`
- `docs/reviews/tests_regression_review.md`

No production code was changed by this review pass.

## Executive summary

The overall structure is workable and already has useful separation in several important places: playback goes through `AudioController`, source exceptions share a base type, playlist providers contain some centralized invalidation helpers, and recent remote playlist helper extraction reduced source-specific drift.

The remaining complexity is concentrated in a few repeated cross-cutting flows:

1. Playlist membership synchronization is implemented in too many layers.
2. Remote playlist add/remove flows are structurally similar across Bilibili, YouTube, and Netease, but still live mostly inside source-specific UI widgets.
3. Provider invalidation and refresh side effects are caller-dependent.
4. Track action/menu behavior is repeated across pages, groups, selection mode, context menus, and bottom sheets.
5. Several heavy data paths still use per-item queries/writes or broad snapshots.
6. Test coverage protects recent pure helpers, but not enough full flow behavior around partial refresh, remote edit integration, and provider/UI boundaries.

## Highest priority finding

### P0: Imported playlist refresh partial-failure policy is not safely covered

The tests review identified the strongest risk: imported playlist refresh can treat a partial upstream result as the complete desired playlist and then prune local tracks that are absent from that partial result.

Relevant areas:

- `lib/services/import/import_service.dart:509`
- `lib/services/import/import_service.dart:558`
- `lib/services/import/import_service.dart:596`

The underlying design issue overlaps with the architecture and playlist reviews: `ImportService.refreshPlaylist()` owns remote parsing, local track creation/update, playlist replacement, removed-track detection, and orphan cleanup. That makes partial failures harder to reason about.

Recommended immediate action before refactoring:

- Define the refresh policy explicitly:
  - either refresh is atomic and should not commit partial results,
  - or partial commits are intentional and must never prune tracks unless the remote result is known complete.
- Add regression tests for:
  - partial upstream playlist data,
  - per-track save/detail failure,
  - Bilibili multipage expansion failure,
  - YouTube paged playlist failure,
  - Netease batch detail failure.

## Cross-agent consensus themes

### 1. Centralize playlist membership mutation

Multiple reviewers independently found that playlist membership rules are duplicated across:

- `PlaylistService`
- `ImportService.importFromUrl()`
- `ImportService.refreshPlaylist()`
- `AddToPlaylistDialog`
- remote removal sync wiring
- playlist detail notifier/provider invalidation paths

Current repeated responsibilities include:

- finding or creating tracks by source identity,
- merging metadata,
- updating `Playlist.trackIds`,
- updating `Track.playlistInfo`,
- removing orphans,
- updating covers,
- invalidating detail/list/cover providers.

Recommended simplification:

Create one domain-level playlist membership API, for example `PlaylistMembershipService` or expanded `PlaylistService` methods:

- `addTracks(playlistId, tracks)`
- `removeTracks(playlistId, trackIds)`
- `replaceTracksFromRemoteRefresh(playlistId, desiredTracks, policy)`
- `reorderTracks(playlistId, orderedTrackIds)`

Return a structured `PlaylistMutationResult` with affected playlist IDs, changed cover flags, added/skipped/removed counts, and confirmed removed track IDs. Provider invalidation should consume this result through one standard path.

### 2. Extract a source-neutral remote playlist edit planner/controller

The three remote add dialogs share the same conceptual state machine:

- load writable remote playlists,
- compute full/partial membership,
- track selected/original/deselected partial IDs,
- skip existing remote tracks,
- submit add/remove operations,
- refresh matching imported playlists,
- report success/failure.

But the behavior is still duplicated in:

- `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart`
- `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart`
- `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart`

Recommended simplification:

- Extract a pure `RemotePlaylistEditPlanner` for selection transitions and missing-track computation.
- Extract a testable `RemotePlaylistEditController` that takes source adapters.
- Keep source-specific API calls in adapters, not in widgets.
- Use a structured result instead of booleans:
  - `addedTrackIds`
  - `removedTrackIds`
  - `skippedTrackIds`
  - `failedTrackIds`
  - `changedRemotePlaylistIds`
  - user-facing summary/reason.

This also addresses the playlist review finding that current remote removal can return only `true/false`, making partial YouTube removal ambiguous.

### 3. Standardize provider invalidation and refresh side effects

Invalidation currently appears in several forms:

- `PlaylistListNotifier.invalidatePlaylistProviders()`
- direct `ref.invalidate(allPlaylistsProvider)` calls
- direct `playlistDetailProvider` / `playlistCoverProvider` invalidation
- refresh manager success invalidation
- download completion invalidation
- unawaited remote playlist refresh sync

Recommended simplification:

Create a small UI/provider-layer invalidation coordinator, for example:

- `playlistChanged(playlistId, {tracksChanged, coverChanged, includeAll})`
- `playlistsChanged(playlistIds, {coverChanged, includeAll})`
- `downloadStateChanged(trackIds or savePaths)`

Then route playlist add/remove/import/refresh/download/remote-sync mutations through it. This keeps repositories/services free of Riverpod while making UI refresh behavior consistent.

### 4. Unify track action/menu behavior

Track actions are partly centralized in `TrackActionHandler`, but menu construction and multi-track behavior still repeat across:

- Home
- Explore
- Search
- Playlist detail
- Downloaded pages
- Library playlist cards
- context menus
- bottom sheets
- selection toolbars

Recommended simplification:

Promote action handling into a reusable track action coordinator:

- standard action descriptors: id, label, icon, availability predicate, handler,
- single-track and multi-track handlers,
- source login filtering,
- default toast/dialog behavior,
- page-specific extra actions such as download, delete, remove from playlist.

Screens should render descriptors into popup menus, context menus, bottom sheets, or selection bars instead of manually rebuilding action lists.

### 5. Batch heavy data paths

Performance review found no P0 performance issue, but several P1/P2 opportunities:

- batch track identity resolution instead of per-track lookup loops,
- batch import/refresh writes with `putAll()` where possible,
- make play history query-driven instead of snapshot/full-scan driven,
- add selected-track batch download enqueue,
- optimize local download sync by batching DB reads/writes,
- reduce playlist cover N+1 DB/filesystem work,
- batch or cache YouTube remote removal playlist scans.

Best first performance refactor:

Create a shared batch track identity resolver returning a map by source identity. Use it in playlist add, import, refresh, download sync, and future remote reconciliation work.

### 6. Replace duplicated source policy and error classification

Architecture review found repeated policy logic around:

- Dio/network error classification,
- source exception categories,
- string-based network checks,
- media headers,
- auth headers,
- source referers/user agents,
- raw `Dio()` construction.

Recommended simplification:

- Add a shared `AppErrorKind` enum used by `SourceApiException`, `ErrorHandler`, and playback retry/skip decisions.
- Add a small `SourceHttpPolicy` for API/media/auth headers and user-agent constants.
- Keep source-specific codes/details for diagnostics, but make app behavior depend on shared semantic kinds.

## Recommended implementation order

1. Add tests for imported playlist refresh partial-failure policy.
2. Extract playlist membership mutation into one domain API.
3. Route import and refresh persistence through that API.
4. Introduce structured remote playlist edit results.
5. Extract a source-neutral remote playlist edit planner/controller.
6. Centralize provider invalidation from playlist/download/remote-sync mutations.
7. Build a shared track action/menu coordinator.
8. Add batch track identity resolver and batch selected-download enqueue.
9. Convert play history to query-driven/paginated providers.
10. Centralize source HTTP policy and app error kind classification.

## Suggested near-term test plan

Before making major refactors, add focused tests for:

- imported playlist refresh with partial upstream data,
- refresh per-track save/detail failure,
- add-to-playlist dialog cancel creating no orphan track,
- remote add partial selection and existing-track skip through the planner/controller,
- remote removal false/partial/exception behavior,
- mixed-source remote add routing and skipped logged-out source feedback,
- remote sync provider integration with refresh manager invalidation,
- playlist detail optimistic rollback for add/remove/reorder,
- full-playlist vs loaded-page selection semantics.

## Final recommendation

Start with playlist membership and refresh atomicity. That area has the highest overlap across correctness, simplification, performance, and testing. Once playlist mutation has one canonical path, the remote edit controller, provider invalidation coordinator, and action/menu unification can be layered on top with much lower risk.
