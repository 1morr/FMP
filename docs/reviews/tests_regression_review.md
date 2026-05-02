# Tests and Regression Risk Review

Scope: playlist/library/remote sync behavior, recent remote playlist selection/removal/sync tests, async provider invalidation, import failure paths, partial playlists, and mixed source selections. Production code was not modified.

## Executive summary

The repository has useful coverage for recent low-level helpers and some important async race paths. Strong examples include playlist provider invalidation behavior in `test/providers/playlist_provider_phase2_test.dart:25`, refresh cancellation/stale cleanup in `test/providers/refresh_provider_stale_cleanup_test.dart:33`, and focused remote action service tests in `test/services/library/remote_playlist_actions_service_test.dart:7`.

The main regression risk is that the newest remote playlist behavior is mostly protected at the pure-helper or service-callback layer, while the source-specific dialog state machines and provider integration remain lightly tested. Several tests also verify source-file structure rather than user-visible behavior, so they can pass while the real flow regresses.

## Findings

### P0 - Imported playlist refresh can prune local playlists after partial upstream data, but no test proves the safe behavior

`ImportService.refreshPlaylist()` builds `newTrackIds` from the parsed/expanded result and then treats every old ID not in that set as removed from the remote playlist (`lib/services/import/import_service.dart:509`, `lib/services/import/import_service.dart:558`, `lib/services/import/import_service.dart:596`). Per-track save failures are collected into `errors` and the refresh still proceeds (`lib/services/import/import_service.dart:518`, `lib/services/import/import_service.dart:550`).

Existing refresh tests cover cancellation rollback and stale cleanup well (`test/providers/refresh_provider_stale_cleanup_test.dart:33`, `test/providers/refresh_provider_stale_cleanup_test.dart:94`), but they do not cover partial parser results, track detail failures, or per-track save failures during refresh. That leaves a data-loss regression gap: a refactor could preserve the current behavior where an incomplete upstream response removes local tracks, or make it worse, without a failing test.

Recommended tests:
- Refresh an imported playlist with existing tracks when the source returns a partial list because one page/detail fetch fails; assert old tracks are not pruned unless the refresh is known complete.
- Inject a repository/save failure for one refreshed track; assert the playlist does not commit a partial `trackIds` replacement or explicitly documents/validates the partial-commit policy.
- Cover source-specific partials: Bilibili multipage expansion, YouTube paged playlist fetch, and Netease batch song detail.

### P1 - Remote add-to-playlist dialogs share complex duplicated state machines, but tests only cover helpers/structure

The three remote add dialogs each implement membership loading, partial-selection toggling, submit batching, error handling, and local refresh sync separately:

- Bilibili compute/submit/local sync: `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:256`, `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:264`, `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:318`
- YouTube compute/submit: `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:283`, `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:291`
- Netease compute/submit: `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:245`, `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:253`

Current tests validate the shared pure helper (`test/services/library/remote_playlist_selection_changes_test.dart:5`) and that Bilibili was split into another file (`test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart:6`), but they do not drive the actual dialog behavior.

Missing regression coverage:
- Partial playlist tri-state transitions: partial -> selected should add only missing tracks; selected -> unselected should remove all selected tracks; deselected partial -> selected should clear the deselection marker.
- Existing-track skipping by playlist: Bilibili `_existingTrackIdsByFolder`, YouTube `_existingTrackIdsByPlaylist`, and Netease `missingRemoteTrackIds()` should all be verified through submit behavior, not only through the helper.
- Newly created remote playlists are selected and submitted correctly for all sources.
- Error on one remote operation leaves the dialog open, clears submitting/progress state, and does not trigger local sync.

A source-neutral “remote playlist edit plan” would make these tests much smaller and would reduce the duplicated code paths that currently need independent widget tests.

### P1 - Mixed-source remote routing is only tested as a filter helper, not as UI behavior

`showAddToRemotePlaylistDialogMulti()` splits selected tracks by source and sequentially invokes the source-specific dialogs (`lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart:21`, `lib/ui/widgets/dialogs/add_to_remote_playlist_dialog.dart:34`). Playlist detail actions filter selected tracks to logged-in sources before opening the remote dialog (`lib/ui/pages/library/playlist_detail_page.dart:607`, `lib/ui/pages/library/playlist_detail_page.dart:1349`).

`filterLoggedInRemoteTracks()` has one focused test for not requiring the first track to be logged in (`test/services/library/remote_playlist_track_filter_test.dart:6`), but there is no widget/provider test that verifies the user-visible behavior for a mixed Bilibili/YouTube/Netease selection.

Recommended tests:
- Multi-select with logged-in YouTube and Netease but logged-out Bilibili opens only the YouTube/Netease routes and returns success if either succeeds.
- All selected tracks logged out shows the login toast and does not exit selection mode.
- Empty or unsupported selection returns false without opening a dialog.

These tests will be easier after extracting the source split/order decision from the dialog function into a pure planner.

### P1 - Remote removal local-sync integration only has a happy-path service test

`RemotePlaylistRemovalSyncService.syncAfterRemoval()` always removes local tracks and triggers a refresh when given any removed IDs (`lib/services/library/remote_playlist_removal_sync_service.dart:13`). The UI calls it only after remote removal returns true (`lib/ui/pages/library/playlist_detail_page.dart:699`, `lib/ui/pages/library/playlist_detail_page.dart:708`, `lib/ui/pages/library/playlist_detail_page.dart:1804`, `lib/ui/pages/library/playlist_detail_page.dart:1813`).

Tests cover a simple service happy path (`test/services/library/remote_playlist_removal_sync_service_test.dart:7`) and source-specific callback dispatch (`test/services/library/remote_playlist_actions_service_test.dart:7`), but not the UI/provider boundary.

Missing regression coverage:
- `removeTracksFromRemote()` returns false: local playlist is not changed, selection mode remains understandable, and no success toast appears.
- Remote service throws source-specific exceptions: local removal is skipped and the mapped error message is shown.
- Partial removals, especially YouTube tracks with missing `setVideoId`, do not remove local tracks that were not actually removed remotely (`lib/services/library/remote_playlist_actions_service.dart:64`).
- `removedTrackIds.isEmpty` is a no-op (`lib/services/library/remote_playlist_removal_sync_service.dart:17`).

### P1 - Remote sync provider behavior is best-effort and unawaited, but only the pure matching service is tested

`remotePlaylistSyncServiceProvider` triggers playlist refresh with `unawaited(...catchError((_) => null))` (`lib/providers/remote_playlist_sync_provider.dart:17`). The pure `RemotePlaylistSyncService` tests verify URL matching and callback invocation (`test/services/library/remote_playlist_sync_service_test.dart:8`), but there is no provider-level test proving that a remote edit eventually invalidates playlist detail/cover providers through `RefreshManagerNotifier` (`lib/providers/refresh_provider.dart:184`).

Recommended tests:
- Remote add/remove calls `refreshMatchingImportedPlaylists()` and eventually invalidates `playlistDetailProvider`/`playlistCoverProvider` for matching imported playlists.
- Refresh failure is intentionally swallowed and does not roll back the remote update result, while still surfacing enough diagnostic state/logging.
- Duplicate remote IDs and duplicate local imported playlists do not trigger duplicate refreshes unless that is intended.

### P1 - Source-specific remote account service branches are under-tested

YouTube playlist service tests currently cover count text parsing only (`test/services/account/youtube_playlist_service_test.dart:5`). The higher-risk behavior is pagination and edit response handling: `getSetVideoId()`, `getVideoIdsInPlaylist()`, and `_browsePlaylistPages()` (`lib/services/account/youtube_playlist_service.dart:143`, `lib/services/account/youtube_playlist_service.dart:161`, `lib/services/account/youtube_playlist_service.dart:182`).

Netease playlist service exposes testable helpers and permission remapping (`lib/services/account/netease_playlist_service.dart:215`, `lib/services/account/netease_playlist_service.dart:238`, `lib/services/account/netease_playlist_service.dart:249`, `lib/services/account/netease_playlist_service.dart:295`) but has no dedicated playlist-service tests. Bilibili favorites has no tests around cached `bilibiliAid`, batch removal resource formatting, or API error mapping (`lib/services/account/bilibili_favorites_service.dart:190`, `lib/services/account/bilibili_favorites_service.dart:223`).

Recommended tests:
- YouTube paginated browse finds video IDs/setVideo IDs across continuation pages and handles later-page failure according to the documented partial-result policy.
- Netease `normalizeTrackIds()` dedupes/trims, `getTrackIdsInPlaylist()` intersects targets, and non-owned delete failures map to `PERMISSION_DENIED`.
- Bilibili `getVideoAid()` uses cached IDs and writes fetched AIDs back to persisted tracks; `batchRemoveFromFolder()` sends `aid:2` resources.

### P2 - Several tests are brittle source-structure assertions rather than behavior tests

Examples:
- `test/services/library/playlist_service_transaction_source_test.dart:1` reads `playlist_service.dart` and asserts strings like `_isar.writeTxn`.
- `test/ui/widgets/dialogs/add_to_remote_playlist_dialog_structure_test.dart:6` checks imports/class names.
- `test/ui/pages/settings/account_management_page_test.dart:6` parses source blocks rather than pumping the account-management page.
- `test/ui/ui_consistency_phase1_test.dart:34` relies on regexes over widget source.

These tests are useful as temporary guardrails, but they are easy to break with harmless refactors and easy to satisfy while behavior regresses. Prefer behavior tests with fakes for user-visible outcomes. If a structural rule is genuinely required, centralize it as a small static-analysis/lint-style test with clear naming so it does not look like behavioral coverage.

### P2 - Playlist provider optimistic mutations need rollback/error tests beyond invalidation rules

`PlaylistDetailNotifier` performs optimistic add/remove/reorder updates and rolls back through `loadPlaylist()` on failure (`lib/providers/playlist_provider.dart:411`, `lib/providers/playlist_provider.dart:435`, `lib/providers/playlist_provider.dart:460`, `lib/providers/playlist_provider.dart:488`). Existing tests cover invalidation semantics (`test/providers/playlist_provider_phase2_test.dart:25`) and one library page reorder rollback (`test/ui/pages/library/library_page_reorder_test.dart:38`), but not add/remove provider rollback with service exceptions.

Recommended tests:
- `addTrack()` optimistic append rolls back and sets `error` when service fails.
- `removeTrack()` and `removeTracks()` restore count/tracks after failure.
- `getAllTracks()` returns all pages when `hasMore` is true, so play-all/add-all actions are not limited to the first page.

## Recommended focused tests before future refactors

1. Imported playlist refresh atomicity: partial upstream result, parser exception after initial data, and per-track save failure.
2. Remote add dialog behavior through a shared planner/controller: partial selection, existing-track skip, create-and-select, submit failure.
3. Remote removal UI/provider integration: false return, source exceptions, partial YouTube removal, no local mutation on remote failure.
4. Remote sync provider integration: matching imported playlists trigger refresh manager invalidations; refresh failures are intentionally best-effort.
5. Source service fixtures: YouTube continuation pages, Netease permission remap and ID normalization, Bilibili AID cache and batch remove payload.
6. Playlist detail optimistic rollback and paginated all-tracks behavior.

## What to simplify first

1. Extract a source-neutral remote playlist edit planner from the three add dialogs. It should compute selected/original/partial transitions, missing IDs, and submit operations. Keep source services as adapters.
2. Extract remote add/remove local-sync orchestration out of widgets into testable services. Widgets should only collect confirmation and display results.
3. Consolidate Isar/Riverpod test harness setup. Many tests duplicate temp Isar initialization and cleanup; shared builders would make provider regression tests cheaper.
4. Replace source-text structure tests with behavior tests or a clearly named static rule suite.
5. Define the refresh partial-failure policy explicitly, then encode it in tests before changing import/refresh internals.
