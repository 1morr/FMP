# FMP 總體架構與代碼一致性審查總結

審查日期：2026-05-22

來源報告：

- `docs/reviews/architecture/instruction-corpus.md`
- `docs/reviews/architecture/audio-architecture-review.md`
- `docs/reviews/architecture/state-management-review.md`
- `docs/reviews/architecture/data-layer-review.md`
- `docs/reviews/architecture/reuse-and-simplification-review.md`
- `docs/reviews/architecture/async-race-review.md`
- `docs/reviews/architecture/documentation-alignment-review.md`

## Highest priority findings

1. **Audio backend error retry can overwrite a newer playback intent**

   Evidence: `AudioController._onAudioError()` captures `state.playingTrack` at
   `lib/services/audio/audio_provider.dart:2711`, then schedules retry work in
   `stop().then(...)` without checking whether the current track/request is still
   the same at `lib/services/audio/audio_provider.dart:2739` to
   `lib/services/audio/audio_provider.dart:2748`. This conflicts with the
   generation/current-track retry rule in `lib/services/audio/AGENTS.md:116`.

   Risk: an old backend network error can clear loading/playing state and retry
   an old track after the user has already started a new track.

   Suggested direction: add a local stale guard around the `stop()` completion
   and error branches using current track key plus play request/retry generation.
   Do not redesign the audio stack.

2. **Update check/download state lacks operation generation**

   Evidence: `UpdateNotifier.checkForUpdate()` writes state after
   `_service.checkForUpdate()` without an operation guard at
   `lib/providers/update_provider.dart:63` to
   `lib/providers/update_provider.dart:81`. `downloadAndInstall()` has the same
   issue for existing-file lookup, progress callback, download completion and
   catch branches at `lib/providers/update_provider.dart:85` to
   `lib/providers/update_provider.dart:138`.

   Risk: older update checks/download progress can overwrite newer check,
   reset, ready-to-install, or error state.

   Suggested direction: add a lightweight `_operationId` / `_isCurrentOperation`
   pattern to `UpdateNotifier`, including `reset()` and progress callbacks.
   Keep platform install/download behavior inside `UpdateService`.

3. **Search clear does not cancel in-flight search**

   Evidence: empty query reset returns before `_searchRequestId` increments at
   `lib/providers/search_provider.dart:228` to
   `lib/providers/search_provider.dart:230`; non-empty search relies on that id
   at `lib/providers/search_provider.dart:240`,
   `lib/providers/search_provider.dart:264`, and
   `lib/providers/search_provider.dart:284`. `clear()` only replaces state at
   `lib/providers/search_provider.dart:528` to
   `lib/providers/search_provider.dart:533`.

   Risk: a slow previous search can repopulate results after the user cleared
   the query.

   Suggested direction: increment/cancel the search generation in `clear()` and
   empty-query branches for both normal and live-room search.

4. **FileExistsCache invalidation contract can leave deleted local files cached**

   Evidence: single-track downloaded delete removes files at
   `lib/ui/pages/library/downloaded_category_page.dart:914`, clears DB state at
   `lib/ui/pages/library/downloaded_category_page.dart:917`, then calls
   `downloadStateChanged(fileExistsChanged: false)` at
   `lib/ui/pages/library/downloaded_category_page.dart:921` to
   `lib/ui/pages/library/downloaded_category_page.dart:924`.

   Risk: thumbnail/avatar/file-existence UI can continue believing deleted files
   exist, especially where preload gates watch `fileExistsCacheEpochProvider`.

   Suggested direction: either pass removed paths through the coordinator or
   explicitly remove them from `fileExistsCacheProvider`; make cache reset bump
   the same epoch watched by preload gates.

5. **Invalid download path cleanup silently drops playlist names**

   Evidence: `TrackRepository.cleanupInvalidDownloadPaths()` rebuilds
   `PlaylistDownloadInfo` at `lib/data/repositories/track_repository.dart:541`
   to `lib/data/repositories/track_repository.dart:556` but copies only
   `playlistId` and `downloadPath`. The model stores `playlistName` at
   `lib/data/models/track.dart:29`, and normal helpers preserve it at
   `lib/data/models/track.dart:132`, `lib/data/models/track.dart:139`,
   `lib/data/models/track.dart:197`, and `lib/data/models/track.dart:211`.

   Risk: cleanup can mutate persisted metadata and weaken name-first download
   path matching for renamed/imported playlists.

   Suggested direction: copy `info.playlistName` in every rebuild branch and add
   a focused repository regression test.

## Medium priority findings

- **Mix start lacks supersession during metadata fetch.** `startMixFromPlaylist()`
  awaits `fetcher(...)` at `lib/services/audio/audio_provider.dart:927` to
  `lib/services/audio/audio_provider.dart:930`, then enters `playMixPlaylist()`
  at `lib/services/audio/audio_provider.dart:936` without checking whether a
  newer playback intent replaced it. Add a request/generation guard before
  `playMixPlaylist()`.

- **Remote refresh lifecycle can outlive provider disposal.**
  `RefreshManagerNotifier.dispose()` cancels subscriptions but does not cancel
  active import services; see `docs/reviews/architecture/async-race-review.md`
  for `lib/providers/refresh_provider.dart:313` to
  `lib/providers/refresh_provider.dart:322`. Add `cancelImport()` / dispose for
  active services and a disposed/generation guard for `AutoRefreshService`.

- **Old playlist import matching can overwrite newer operations.**
  `PlaylistImportNotifier` uses `_importCancelled` rather than an operation id
  (`lib/providers/playlist_import_provider.dart:107` to
  `lib/providers/playlist_import_provider.dart:124`), while the newer
  `ImportPlaylistNotifier` already has `_operationId` at
  `lib/providers/import_playlist_provider.dart:62` to
  `lib/providers/import_playlist_provider.dart:96`. Reuse the newer pattern.

- **Playlist detail download flows duplicate queue setup and result mapping.**
  Download path setup is repeated at
  `lib/ui/pages/library/playlist_detail_page.dart:292` to
  `lib/ui/pages/library/playlist_detail_page.dart:297`,
  `lib/ui/pages/library/playlist_detail_page.dart:1322` to
  `lib/ui/pages/library/playlist_detail_page.dart:1327`, and
  `lib/ui/pages/library/playlist_detail_page.dart:1620` to
  `lib/ui/pages/library/playlist_detail_page.dart:1625`. Group download loops
  through `addTrackDownload()` at
  `lib/ui/pages/library/playlist_detail_page.dart:1339` to
  `lib/ui/pages/library/playlist_detail_page.dart:1355` despite an existing
  batch path. Extract a small preflight/result helper and use
  `addTracksDownload()` for group downloads.

- **Search multi-part actions reimplement common action semantics.**
  Search uses common menu builders around
  `lib/ui/pages/search/search_page.dart:1155` to
  `lib/ui/pages/search/search_page.dart:1158`, but separate action switches
  still duplicate common multi-track behavior. Route group actions through
  `TrackActionCoordinator.handleMulti()` or a thin local group helper.

- **Database viewer misses schema-visible fields and has weak field coverage.**
  `Settings.allowPlainLyricsAutoMatch` exists at `lib/data/models/settings.dart:184`
  but is absent from the viewer/test. `PlayQueue.isNotEmpty` is also
  schema-visible but not displayed. Add the missing fields and strengthen
  `test/ui/pages/settings/database_viewer_page_coverage_test.dart`.

- **Batch add/remove playlist dialog invalidates providers more than needed.**
  The dialog invalidates each playlist during loops and then invalidates changed
  playlists again. Consolidate to one coordinator call after successful mutations.

- **Radio manual live-status refresh can remain loading on thrown errors.**
  Wrap the refresh in `try/finally` and restore `isRefreshingStatus` with
  `mounted` checks.

## Low priority cleanup opportunities

- Extract shared Set-Cookie header parsing for Bilibili/Netease account services.
  Keep Netease response-body cookie fallback local to Netease.

- Extract only the OpenAI-compatible lyrics AI transport/config shell shared by
  `AiTitleParser` and `AiLyricsSelector`; do not merge prompts or response
  parsers.

- Add a small local helper in `lyrics_search_sheet.dart` only when touching that
  file; the duplicate invalidation triplet is too small for a cross-system
  coordinator today.

- Update comments around identical download media/image header wrappers if
  helpful; keep both policy-named functions.

## Cross-cutting inconsistencies

- **Most async modules have a good generation pattern, but a few flows do not.**
  Audio playback, search, lyrics search and download mostly use request ids,
  generations, mounted/disposed guards and stream subscription cleanup. Update,
  old playlist import, Mix start and refresh disposal are the outliers.

- **Provider invalidation ownership is mostly clear, but file-existence state has
  two channels.** `libraryInvalidationCoordinatorProvider` centralizes playlist,
  cover and downloaded provider invalidation, while `FileExistsCache` also has
  direct mutations plus `fileExistsCacheEpochProvider`. The cache contract should
  be tightened before more UI preloading code depends on it.

- **UI playback boundary is intact.** `lib/ui` did not show direct
  `audioServiceProvider` / backend use in the reviewed search. The only backend
  exception is radio, which is documented in `lib/services/AGENTS.md:99` to
  `lib/services/AGENTS.md:100`. The developer YouTube stream test uses
  `media_kit` directly at `lib/ui/pages/debug/youtube_stream_test_page.dart:2`
  and is reachable through developer options at
  `lib/ui/pages/settings/developer_options_page.dart:54` to
  `lib/ui/pages/settings/developer_options_page.dart:60`; treat it as a debug
  tool exception, not normal playback architecture.

- **Some UI common-action seams are deep enough, but search group actions are
  still local duplicates.** `TrackActionCoordinator` has leverage for common
  track actions; search multi-part behavior should reuse it instead of lowering
  the rule.

## Documentation inaccuracies

- `docs/development.md:60` links to `../AGENTS.md#file-structure-highlights`,
  but root `AGENTS.md` has `## Key Paths` at `AGENTS.md:161`, not that anchor.
  Link file structure to `AGENTS.md#key-paths` and provider rules to
  `../lib/providers/AGENTS.md`.

- `.serena/memories/ui_coding_patterns.md` is too broad for a memory and
  conflicts with `lib/ui/AGENTS.md` on UI constants: memory says new code must
  not use hard-coded values at `.serena/memories/ui_coding_patterns.md:698`,
  while scoped UI rules allow one-off local literals at
  `lib/ui/AGENTS.md:71` to `lib/ui/AGENTS.md:82`.

- `.serena/memories/code_style.md` mixes style notes with architecture rules
  already covered by `AGENTS.md`, `lib/data/AGENTS.md`, and
  `lib/providers/AGENTS.md`. Keep style details; replace architecture duplicates
  with links.

- `docs/development.md` route summary omits settings subroutes such as
  `/settings/user-guide` and account login pages registered in
  `lib/ui/router.dart:220`, `lib/ui/router.dart:251`,
  `lib/ui/router.dart:256`, and `lib/ui/router.dart:261`.

- `lib/data/AGENTS.md` could clarify that `LyricsTitleParseCache` is a registered
  Isar collection but behaves as an ephemeral runtime cache because startup
  migration clears it.

## Suggested implementation order

1. Fix correctness races with focused tests: audio backend error stale guard,
   update operation generation, search clear cancellation.
2. Fix persisted/local-state integrity: `playlistName` preservation in invalid
   download cleanup, then FileExistsCache invalidation/epoch behavior.
3. Fix lifecycle stale work: refresh manager disposal, auto refresh guard, old
   playlist import operation ids, radio refresh `try/finally`.
4. Tighten observability: database viewer missing fields and coverage test.
5. Simplify duplicated UI/service logic: playlist detail download helper, search
   group action reuse, account cookie parser, lyrics AI chat transport helper.
6. Clean documentation drift: dead anchor, `.serena/memories/` trimming, route
   summary update.

## Findings that require tests

- Audio backend error stale guard: add a fake backend with delayed `stop()` and
  verify old retry does not mutate new playback state.
- Mix start supersession: delayed Mix fetch followed by a newer playback intent
  should not enter Mix mode.
- Update provider generation: reversed completion order and reset/progress
  callback cases should keep only the latest operation.
- Search clear cancellation: delayed search completion after `clear()` should
  not repopulate results.
- FileExistsCache delete path: deleting a downloaded track should invalidate or
  update file-existence state and bump any epoch used by preload gates.
- Invalid download cleanup: `cleanupInvalidDownloadPaths()` must preserve
  `PlaylistDownloadInfo.playlistName`.
- Refresh disposal: active import services should receive cancellation on
  provider dispose; completed stale import work should not write DB/UI state.
- Old playlist import notifier: reversed `importAndMatch()` / `manualSearch()`
  completion should keep the latest operation and matching row identity.
- Database viewer coverage: include `allowPlainLyricsAutoMatch`, `isNotEmpty`,
  and preferably schema-derived tokens.

## Findings that require instruction docs or human docs update

- `docs/development.md:60` dead anchor and provider link.
- `docs/development.md` settings route table.
- `.serena/memories/ui_coding_patterns.md` trimming and UI constants conflict.
- `.serena/memories/code_style.md` trimming to style-only guidance.
- Optional: `lib/data/AGENTS.md` note for ephemeral `LyricsTitleParseCache`.
- Optional: `lib/ui/AGENTS.md` clarification that debug-only stream test pages
  are not normal playback controls, if future reviews keep flagging it.

## Areas not recommended for change

- Do not introduce a new global UI playback facade. `AudioController` already
  hides backend, queue, temporary playback, retry, mobile notification and SMTC
  details behind a useful interface; an extra pass-through layer would not fix
  the identified races.

- Do not migrate Riverpod providers broadly to `Notifier` / `AsyncNotifier`.
  The concrete issues are stale request ids and invalidation contracts, not the
  provider API generation.

- Do not add migration repair for `allowPlainLyricsAutoMatch`; its business
  default is `false`, matching Isar's bool upgrade default.

- Do not rewrite `database_provider.dart`; schema registration, DB path,
  legacy-file movement and migration entry point match current instructions.

- Do not add a global image facade. Current app code centralizes image loading
  through `TrackThumbnail`, `TrackCover` and `ImageLoadingService`, and direct
  `Image.network()` / `Image.file()` was not found in app code.

- Do not collapse source error mapping into a broad factory now. Current
  source-specific mappings preserve platform semantics while sharing
  `SourceApiException` and `SourceHttpPolicy`.

- Do not merge download media/image header wrapper names solely because their
  implementation is currently identical; the names carry policy intent for
  audio media vs metadata image downloads.

- Do not import `docs/history/refactoring-log.md` back into current rules.
  It is explicitly archived background, not current implementation guidance.
