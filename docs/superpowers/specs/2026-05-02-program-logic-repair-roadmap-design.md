# Program Logic Repair Roadmap Design

Date: 2026-05-02

## Context

This design follows the multi-agent review documents in `docs/reviews/`. The user wants a complete repair roadmap for making the program logic simpler and more unified across playlist, library, remote playlist sync, UI actions, provider invalidation, performance/data access, and source policy.

The requested scope is a full roadmap, but not a full implementation plan for every phase. Each phase should be independently planned before implementation.

## Goals

- Prevent playlist data loss or incorrect pruning during imported playlist refresh.
- Centralize playlist membership mutation rules.
- Unify remote playlist add/remove/sync behavior across Bilibili, YouTube, and Netease.
- Standardize provider invalidation and background refresh side effects.
- Reduce duplicated track action/menu logic across UI pages.
- Batch heavy data access paths where they currently use per-item lookups or writes.
- Unify source HTTP/header policy and error classification.
- Keep changes incremental, test-first, and scoped by phase.

## Non-goals

- Do not implement all roadmap phases in one change.
- Do not perform broad unrelated UI redesign.
- Do not rewrite the audio system.
- Do not replace Riverpod, Isar, or the existing source architecture wholesale.
- Do not commit to final APIs for later phases before their detailed implementation plans are written.

## Strategy

Use a risk-first phased roadmap. Data correctness comes before UI simplification and performance cleanup. The highest-risk behavior is imported playlist refresh handling partial upstream data, so the first phase adds policy and tests before deeper refactoring.

Each phase follows this pattern:

1. Write or update focused tests for the behavior being protected.
2. Make the smallest production changes needed for that phase.
3. Run focused tests and `flutter analyze`.
4. Avoid unrelated refactors.
5. Update documentation only when the change affects documented architecture or behavior.

## Phase 0: Refresh partial failure policy and protective tests

### Purpose

Prevent imported playlist refresh from treating partial upstream data as a complete remote playlist and incorrectly pruning local tracks.

### Scope

- Define refresh outcomes explicitly:
  - complete success,
  - partial upstream failure,
  - per-track detail/save failure,
  - full failure.
- Define when local playlist replacement and pruning are allowed.
- Add tests for `ImportService.refreshPlaylist()` around partial data and failure cases.
- Cover the main source-specific partial scenarios:
  - Bilibili multipage expansion failure,
  - YouTube paged playlist fetch failure,
  - Netease batch song detail failure,
  - per-track persistence failure.

### Design decision

A refresh may only prune local tracks when the remote playlist result is known complete. If the remote data is partial or track persistence partially fails, the refresh must not remove existing local tracks based only on the partial result.

Partial additions may be allowed only when each added track was fully resolved and persisted. A partial refresh must report that pruning was skipped so callers and tests can distinguish it from a complete refresh.

### Acceptance criteria

- Partial upstream results do not remove existing local tracks that are absent from the partial result.
- Tests document whether partial additions are allowed while pruning is blocked.
- Later membership refactors have regression coverage for refresh safety.

## Phase 1: Centralize playlist membership mutation

### Purpose

Move repeated playlist mutation rules into one domain-level path.

### Scope

Centralize these responsibilities:

- track identity lookup or creation,
- metadata merge,
- `Playlist.trackIds` updates,
- `Track.playlistInfo` updates,
- removed-track cleanup,
- orphan cleanup,
- cover update metadata,
- mutation result reporting.

Candidate API shape:

- `addTracks(playlistId, tracks)`
- `removeTracks(playlistId, trackIds)`
- `replaceTracksFromRemoteRefresh(playlistId, desiredTracks, policy)`
- `reorderTracks(playlistId, orderedTrackIds)`

Return a structured `PlaylistMutationResult` with:

- affected playlist IDs,
- added count,
- skipped count,
- removed track IDs,
- skipped track IDs where relevant,
- cover changed flag,
- whether list/detail providers need refresh.

### Acceptance criteria

- Import, refresh, local add-to-playlist, and remote removal sync no longer hand-roll the same `trackIds` plus `playlistInfo` mutation logic.
- Existing playlist detail optimistic behavior does not regress.
- Mutation results are sufficient for later provider invalidation cleanup.

## Phase 2: Remote playlist edit result and planner/controller

### Purpose

Unify Bilibili, YouTube, and Netease remote playlist add/remove/sync behavior while keeping source API differences isolated.

### Scope

Introduce a source-neutral remote playlist edit planner/controller:

- `RemotePlaylistEditPlanner` computes selection transitions and missing tracks.
- `RemotePlaylistEditController` orchestrates remote submit operations and sync triggers.
- Source adapters perform platform-specific API calls.

The controller should return a structured result instead of a boolean:

- confirmed added track IDs,
- confirmed removed track IDs,
- skipped track IDs,
- failed track IDs,
- changed remote playlist IDs,
- user-facing summary metadata.

### Acceptance criteria

- Partial remote playlist add only adds missing tracks.
- Remote removal syncs only confirmed removals to local imported playlists.
- Mixed-source and logged-out skipped tracks are represented explicitly.
- Source-specific dialogs contain UI state and rendering, not duplicated edit orchestration.

## Phase 3: Provider invalidation and background refresh side effects

### Purpose

Make playlist, cover, detail, download, and remote-sync invalidation consistent and discoverable.

### Scope

Create a UI/provider-layer invalidation coordinator, for example:

- `playlistChanged(playlistId, {tracksChanged, coverChanged, includeAll})`
- `playlistsChanged(playlistIds, {coverChanged, includeAll})`
- `downloadStateChanged(trackIds or savePaths)`

Use mutation and edit results to drive invalidation. Clarify naming for fire-and-forget refresh versus awaited refresh. Ensure background refresh failures are logged or otherwise observable instead of being silently swallowed.

### Acceptance criteria

- Widgets no longer guess which playlist providers to invalidate after domain mutations.
- Import, refresh, remote sync, local playlist edits, and download completion use one invalidation entry point.
- Fire-and-forget refresh behavior is named and documented clearly.

## Phase 4: Track action and menu unification

### Purpose

Reduce duplicated action/menu logic across Home, Explore, Search, Playlist Detail, Downloaded, Library cards, context menus, bottom sheets, and selection toolbars.

### Scope

Build on `TrackActionHandler` with a UI-facing action coordinator.

Action descriptors should include:

- id,
- label,
- icon,
- availability predicate,
- handler,
- single-track or multi-track support,
- optional page-specific extension actions.

### Acceptance criteria

- Common actions are defined once and rendered in multiple UI surfaces.
- Queue, play-next, add-to-playlist, add-to-remote, and lyrics actions behave consistently across pages.
- Page-specific actions such as delete, download, or remove-from-playlist remain injectable without duplicating common actions.

## Phase 5: Performance and data batching

### Purpose

Replace repeated per-item data access with batch operations for large playlists and bulk actions.

### Scope

- Add a batch track identity resolver returning a map by source identity.
- Use batch identity lookup in playlist add, import, refresh, and download sync.
- Batch import/refresh writes where possible with `putAll()`.
- Add selected-track batch download enqueue.
- Reduce playlist cover N+1 DB/filesystem work.
- Treat play history query-driven pagination as its own follow-up sub-plan.

### Acceptance criteria

- Bulk track operations avoid N separate identity queries and N separate writes where a batch path is possible.
- Selected-track download reuses one base directory lookup, one existing-task lookup, and one priority calculation.
- Playlist cover loading for grids avoids one independent DB/filesystem chain per card where practical.

## Phase 6: Error, header, and source policy unification

### Purpose

Reduce drift in source-specific HTTP headers, auth/media policy, Dio construction, and error classification.

### Scope

- Define shared semantic error kinds such as network, timeout, rateLimited, unavailable, permissionDenied, loginRequired, geoRestricted, vipRequired, and unknown.
- Let source exceptions expose the shared kind while retaining source-specific codes for diagnostics.
- Replace string-based network detection with kind-based checks where possible.
- Introduce a small source HTTP/header policy for API headers, media headers, auth headers, referer/origin, and user-agent constants.
- Gradually replace repeated raw `Dio()` setup and header switches.

### Acceptance criteria

- Playback, download, import, and account services use consistent source header policy.
- Retry, skip, login-required, rate-limit, and unavailable decisions use shared error semantics.
- Source-specific diagnostics remain available.

## Phase 7: Secondary UI/Riverpod consistency cleanup

### Purpose

Clean up lower-risk inconsistencies after core data and remote flows are safer.

### Scope

- Reusable loading/error/empty UI wrappers.
- Remaining `ListTile.leading` Row cleanup.
- Stable keys for mutable secondary lists.
- Ranking cache state as immutable Riverpod state instead of mutable service snapshots.
- Replace brittle source-text tests with behavior tests or clearly named static rule tests.

### Acceptance criteria

- UI state handling has fewer hand-written variants.
- Secondary list behavior is more stable under insert/remove/reorder.
- Tests more often validate behavior rather than source text shape.

## Phase dependencies

- Phase 0 must come before Phase 1 because membership refactoring needs refresh safety tests.
- Phase 1 should come before Phase 2 and Phase 3 because remote sync and invalidation should consume structured playlist mutation results.
- Phase 2 should come before broad UI action cleanup because remote add/remove behavior needs stable APIs first.
- Phase 5 can start after Phase 1 creates shared mutation and identity boundaries, but play history pagination can be planned independently.
- Phase 6 can be done after Phase 0 or in parallel with later UI phases if kept small, but it should not block playlist correctness work.

## First detailed implementation plan

The first implementation plan should cover only Phase 0: refresh partial failure policy and protective tests.

That plan should specify:

- exact refresh policy,
- focused tests to add first,
- minimal production changes required to satisfy the tests,
- verification commands,
- rollback considerations.

## Risks

- Centralizing playlist mutation touches high-value code paths and must be protected by tests before broad migration.
- Remote playlist controller extraction can become too abstract if it tries to hide real source differences. Source adapters should stay simple and explicit.
- Invalidation coordination must remain UI/provider-layer only; repositories should not depend on Riverpod.
- Performance batching should not obscure error reporting for individual failed tracks.

## Success criteria for the full roadmap

- Imported playlist refresh cannot delete local tracks due only to partial upstream data.
- Playlist membership invariants are maintained by one canonical mutation path.
- Remote add/remove/sync flows return structured results and handle partial success consistently.
- Provider invalidation is driven by mutation results instead of scattered manual calls.
- Common track actions are defined once and reused across UI surfaces.
- Large playlist and bulk download operations use batch data paths.
- Source HTTP policy and error classification are consistent across playback, download, import, and account operations.
