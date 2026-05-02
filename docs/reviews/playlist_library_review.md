# Playlist and Library Flow Logic Review

Date: 2026-05-02

Scope: playlist detail and library pages, local/imported playlist behavior, direct remote add/remove/sync flows for Bilibili/YouTube/Netease, external import preview, playlist mutation providers, and related action/dialog helpers.

No production code was changed for this review.

## Summary

The playlist/library flows work through a mix of UI notifiers, services, repositories, and source-specific dialogs. The biggest simplification opportunity is to move playlist membership mutations and remote playlist membership edits behind a smaller set of domain-level result objects. Today, the same concerns appear in several places: track lookup/create, playlist `trackIds` mutation, `Track.playlistInfo` repair, orphan cleanup, cover refresh, provider invalidation, remote partial success, and user feedback.

## P0 findings

None found in this pass.

## P1 findings

### P1. Playlist membership mutation logic is duplicated across local add/remove, direct import, refresh, and remote removal sync

Evidence:
- `PlaylistService` already has transactional add/remove/reorder logic, duplicate detection, metadata merge, orphan cleanup, and cover repair in `lib/services/library/playlist_service.dart:287`, `lib/services/library/playlist_service.dart:349`, `lib/services/library/playlist_service.dart:517`, and `lib/services/library/playlist_service.dart:555`.
- `ImportService.importFromUrl()` reimplements track lookup/linking and playlist `trackIds` updates instead of using the same mutation path in `lib/services/import/import_service.dart:269` through `lib/services/import/import_service.dart:331`.
- `ImportService.refreshPlaylist()` reimplements a full replacement algorithm plus orphan cleanup in `lib/services/import/import_service.dart:501` through `lib/services/import/import_service.dart:602`.
- The local add-to-playlist dialog calls `PlaylistService` directly in nested loops and handles invalidation itself in `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:511` through `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:560`.
- Remote removal sync is wired to a UI notifier instead of a domain service in `lib/providers/remote_playlist_sync_provider.dart:31` through `lib/providers/remote_playlist_sync_provider.dart:35`.

Why it matters: every new flow must remember the same invariants: update both `Playlist.trackIds` and `Track.playlistInfo`, merge metadata, remove orphan tracks, update covers, and invalidate the right providers. This makes behavior drift likely.

Recommendation: extract one domain mutation API, for example `PlaylistMembershipService`, with operations like `addTracks()`, `removeTracks()`, `replaceTracksFromRemoteRefresh()`, and `reorderTracks()`. Return a `PlaylistMutationResult` containing affected playlist IDs, removed track IDs, cover changes, and counts. UI/providers can then perform one standard invalidation step.

### P1. Remote removal can silently no-op or remove local tracks that were not actually removed remotely

Evidence:
- `RemotePlaylistActionsService.removeTracksFromRemote()` filters to tracks whose `sourceType` matches the imported playlist source in `lib/services/library/remote_playlist_actions_service.dart:45` through `lib/services/library/remote_playlist_actions_service.dart:47`.
- YouTube removal skips tracks when `getYoutubeSetVideoId()` returns null, but only returns a single boolean `removedAny` in `lib/services/library/remote_playlist_actions_service.dart:64` through `lib/services/library/remote_playlist_actions_service.dart:74`.
- The playlist detail page removes all requested local track IDs after any successful remote removal in `lib/ui/pages/library/playlist_detail_page.dart:699` through `lib/ui/pages/library/playlist_detail_page.dart:711` and `lib/ui/pages/library/playlist_detail_page.dart:1804` through `lib/ui/pages/library/playlist_detail_page.dart:1816`.
- If the remote service returns `false`, the UI just returns without feedback in `lib/ui/pages/library/playlist_detail_page.dart:706` and `lib/ui/pages/library/playlist_detail_page.dart:1811`.

Edge cases: partial YouTube playlist membership, mixed-source/corrupt imported playlists, a track whose set-video ID cannot be resolved, or source URL parse failure. The user may see nothing happen, or local state may remove tracks that remain remote until a later refresh restores them.

Recommendation: replace the boolean return with `RemotePlaylistEditResult`, including `removedTrackIds`, `skippedTrackIds`, `failedTrackIds`, and a user-facing reason. Local removal should apply only to confirmed remote removals. Show a toast for skipped/no-op cases.

### P1. Source-specific remote add/remove/sync flows are structurally the same but behave differently on partial failure

Evidence:
- Bilibili performs special local removal before refresh in `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:318` through `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:368`.
- YouTube and Netease only ask `RemotePlaylistSyncService` to refresh matching imported playlists in `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:335` through `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:344` and `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:290` through `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:299`.
- Each source dialog performs nested remote calls and then catches a single exception at the end, without syncing any remote operations that may already have succeeded: Bilibili in `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:277` through `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:316`, YouTube in `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:304` through `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:363`, and Netease in `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:267` through `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:318`.
- The provider implementation of `refreshPlaylist` is `unawaited`, so `await refreshMatchingImportedPlaylists()` waits only for matching, not for the actual local refresh to finish, in `lib/providers/remote_playlist_sync_provider.dart:17` through `lib/providers/remote_playlist_sync_provider.dart:22`.

Recommendation: introduce a common remote playlist membership controller with per-source adapters. It should collect per-track/per-playlist successes, enqueue refresh for changed remote playlists even after partial failure, and report a partial-success summary. Rename the current refresh trigger to make it clear whether it enqueues or awaits refresh.

### P1. The local add-to-playlist dialog has read-time database side effects

Evidence:
- `_initializeSelection()` calls `trackRepo.getOrCreate(track)` while merely computing preselected playlists in `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:58` through `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:71`.
- `TrackRepository.getOrCreate()` writes a new `Track` when none exists in `lib/data/repositories/track_repository.dart:275` through `lib/data/repositories/track_repository.dart:323`.

Edge case: opening the add-to-playlist sheet for a search result and cancelling can create an orphan track record before the user commits any change.

Recommendation: use a pure lookup for initialization, such as `getBySourceIdAndCid()`, and call `getOrCreate()` only in the submit path after the user confirms.

## P2 findings

### P2. Playlist and track action menus are duplicated across context menus, bottom sheets, selection mode, groups, and single rows

Evidence:
- Library playlist card context menu and long-press bottom sheet duplicate the same item list and action dispatch in `lib/ui/pages/library/library_page.dart:484` through `lib/ui/pages/library/library_page.dart:646`.
- Playlist detail selection mode manually implements add-to-queue, play-next, add-to-playlist, add-to-remote, download, and delete in `lib/ui/pages/library/playlist_detail_page.dart:458` through `lib/ui/pages/library/playlist_detail_page.dart:635`.
- Group actions duplicate similar track-list actions in `lib/ui/pages/library/playlist_detail_page.dart:1299` through `lib/ui/pages/library/playlist_detail_page.dart:1454`.
- Single-row actions partially use `TrackActionHandler`, but only after handling download/remove cases locally in `lib/ui/pages/library/playlist_detail_page.dart:1615` through `lib/ui/pages/library/playlist_detail_page.dart:1773`.

Recommendation: define action descriptors once (`id`, label, icon, availability predicate, handler). Render the descriptors into a popup menu, bottom sheet, or selection toolbar. Extend `TrackActionHandler` or add a `TrackListActionHandler` so single, group, and selection actions share behavior.

### P2. Local vs imported playlist capabilities are mostly consistent, but the rules are embedded in several UI branches

Evidence:
- Selection actions are assembled inline from `isImported`/`isMix` in `lib/ui/pages/library/playlist_detail_page.dart:201` through `lib/ui/pages/library/playlist_detail_page.dart:210`.
- Single-row menu rules repeat related checks in `lib/ui/pages/library/playlist_detail_page.dart:1628` through `lib/ui/pages/library/playlist_detail_page.dart:1659`.
- Add-to-local-playlist excludes imported playlists in `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:252` through `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:253`.
- Imported playlist refresh/auth settings are exposed separately in `lib/ui/pages/library/widgets/create_playlist_dialog.dart:117` through `lib/ui/pages/library/widgets/create_playlist_dialog.dart:135`.

Recommendation: add a small `PlaylistCapabilities` model derived from `Playlist` (`canLocalRemoveTracks`, `canRemoteRemoveTracks`, `canDownload`, `canRefresh`, `canReorderTracks`, `canAddToImportedPlaylist`). UI should consume capabilities instead of repeating conditions.

### P2. Provider invalidation responsibility is scattered and easy to miss

Evidence:
- `PlaylistListNotifier.invalidatePlaylistProviders()` exists in `lib/providers/playlist_provider.dart:176` through `lib/providers/playlist_provider.dart:190`.
- Other flows still manually invalidate combinations of `allPlaylistsProvider`, `playlistDetailProvider`, and `playlistCoverProvider`, for example internal import in `lib/ui/pages/library/widgets/import_playlist_dialog.dart:515` through `lib/ui/pages/library/widgets/import_playlist_dialog.dart:518`, refresh manager in `lib/providers/refresh_provider.dart:184` through `lib/providers/refresh_provider.dart:187`, import preview in `lib/ui/pages/library/import_preview_page.dart:293` through `lib/ui/pages/library/import_preview_page.dart:298`, and add-to-playlist in `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:540` through `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:560`.

Recommendation: make mutation methods return affected playlist IDs and route every mutation through one invalidation helper. Keep `playlistListProvider` watch-driven, but standardize snapshot/detail/cover invalidation.

### P2. Mixed-source remote add works, but user feedback is weak

Evidence:
- Mixed selections are filtered to logged-in source types in `lib/services/library/remote_playlist_track_filter.dart:3` through `lib/services/library/remote_playlist_track_filter.dart:9` and then passed onward in `lib/ui/pages/library/playlist_detail_page.dart:608` through `lib/ui/pages/library/playlist_detail_page.dart:622`.
- `showAddToRemotePlaylistDialogMulti()` splits tracks by source and opens Bilibili, YouTube, and Netease sheets sequentially in `lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart:21` through `lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart:52`.

Edge case: a mixed selection with some logged-out sources silently drops those tracks if at least one source is logged in. The user then sees several sequential sheets without a single summary of what was included, skipped, or failed.

Recommendation: show a preflight summary grouped by source, including skipped logged-out tracks. After sequential dialogs, show one result summary.

### P2. “All tracks” means different things in different playlist-detail controls

Evidence:
- Detail page play/shuffle buttons call `getAllTracks()` to include lazily unloaded tracks in `lib/ui/pages/library/playlist_detail_page.dart:1070` through `lib/ui/pages/library/playlist_detail_page.dart:1095`.
- Selection-mode “select all” uses only the currently loaded `allTracks` list passed to the app bar in `lib/ui/pages/library/playlist_detail_page.dart:757` through `lib/ui/pages/library/playlist_detail_page.dart:788`.
- Library playlist card actions load the full playlist directly via `PlaylistCardActions` in `lib/ui/widgets/playlist_card_actions.dart:19` through `lib/ui/widgets/playlist_card_actions.dart:58`.

Recommendation: either label selection as “select loaded” for paginated playlists, or provide a real full-playlist selection path. Use one helper for full playlist retrieval.

## What to simplify first

1. Centralize local playlist membership mutations and provider invalidation. This removes the most duplication and gives imports, refresh, add-to-playlist, and remote sync the same invariants.
2. Replace boolean remote edit results with structured results, then sync only confirmed successes and report no-op/skipped cases.
3. Extract a shared remote playlist sheet/controller with source adapters for Bilibili, YouTube, and Netease. Keep source-specific API details in adapters, not UI widgets.
4. Consolidate playlist/detail menu actions into shared action descriptors and list-action handlers.

## Concrete edge cases to test after simplification

- Open add-to-playlist for a search result, cancel, and verify no orphan `Track` is created.
- Remove multiple YouTube tracks where one has no `setVideoId`; verify only confirmed removals are removed locally and skipped tracks are reported.
- Add/remove a mixed Bilibili/YouTube/Netease selection with one logged-out source; verify skipped tracks are visible to the user.
- Trigger a remote edit that fails halfway; verify successful remote changes still enqueue refresh and the toast reports partial completion.
- Refresh an imported playlist while its detail page is open and paginated; verify detail, cover, count, and library card all converge without manual reload.
