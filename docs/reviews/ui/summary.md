# FMP UI / UX Review Summary

## Review corpus

This review treated the following as normative requirements unless current code
or a more specific `AGENTS.md` contradicted them:

- `AGENTS.md`: architecture boundaries, documentation maintenance, verification,
  and hard UI boundaries such as not bypassing `AudioController`.
- `lib/ui/AGENTS.md`: image components, common track actions, AppBar trailing
  spacing, `ListTile.leading` layout, UI constants, database viewer coverage,
  and responsive breakpoints.
- `lib/services/audio/AGENTS.md`: audio UI control boundary, queue state,
  progress seek behavior, mute/progress rules.
- `lib/providers/AGENTS.md`: loading guards, provider invalidation,
  `libraryInvalidationCoordinatorProvider`, ranking immutable state, search
  source chip ownership.
- `lib/data/AGENTS.md`, `lib/data/sources/AGENTS.md`, `lib/services/AGENTS.md`:
  persisted models, stable keys, auth-for-play defaults, download, lyrics,
  import, account, and radio behavior.

These were treated as descriptive and verified against code before use:

- `docs/README.md`, `docs/development.md`, `docs/build-guide.md`,
  `docs/build-and-release.md`, `docs/debugging-with-vm-service.md`, and
  `README.md`.
- `.serena/memories/*.md`, which are supplemental only. Several entries are
  stale or stricter than the current `AGENTS.md` rules.
- `docs/agents/` does not exist. `docs/history/refactoring-log.md` is archived
  background and was not used as current guidance.

Detailed subreports:

- `docs/reviews/ui/player-ui-review.md`
- `docs/reviews/ui/library-playlist-ui-review.md`
- `docs/reviews/ui/search-explore-home-review.md`
- `docs/reviews/ui/settings-account-review.md`
- `docs/reviews/ui/component-consistency-review.md`
- `docs/reviews/ui/ux-flow-review.md`
- `docs/reviews/ui/ui-docs-alignment-review.md`

## Follow-up fix status

The implementation pass after this review addressed the actionable findings
listed below while keeping the original review evidence in this document:

- Queue display now consumes queue-specific state instead of deriving queue
  order from `PlayerState`.
- Home ranking keeps already available source ranking data visible during
  loading.
- Playlist/downloaded UI now uses file-existence cache state for downloaded
  badges and single-track deletion invalidation.
- Search source chips now filter visible local results, and Bilibili multi-page
  rows surface common track actions plus loading errors.
- Search/downloaded dynamic rows now have stable keys.
- Download path setup, account status checks, Bilibili login, and manual lyrics
  save/remove flows now surface user-visible error or saving states.
- Auth-for-play controls are exposed from Audio Settings and documented as an
  Audio Settings boundary rather than an Account-page action.
- Playlist card actions, playlist-detail group actions, and remote playlist
  dialog selection UI now reuse shared menu/widget helpers where applicable.
- UI/documentation alignment notes for routes, responsive layout, ranking state,
  UI constants, and auth-for-play placement have been updated.

## UI consistency issues

| Type | Severity | Finding | Evidence | Suggested direction |
|------|----------|---------|----------|---------------------|
| bug | Medium | Queue UI reads queue fields directly from `PlayerState` instead of the queue-specific state layer. | `lib/ui/pages/queue/queue_page.dart:234`; queue state contract in `lib/services/audio/audio_provider.dart:54`, `lib/services/audio/audio_provider.dart:115`, `lib/services/audio/audio_provider.dart:3059`, `lib/services/audio/audio_provider.dart:3115`; test in `test/services/audio/audio_queue_state_provider_test.dart:50`. | Move QueuePage reads to `queueStateProvider` / queue selectors and keep mutations through `audioControllerProvider.notifier`. |
| UX issue | Medium | Home ranking shows a full spinner while `isInitialLoading` is true even if one ranking source already has tracks. | `lib/ui/pages/home/home_page.dart:151`; ranking state writes source lists separately in `lib/services/cache/ranking_cache_service.dart:50`. | Show full loading only when no ranking data exists; render available source cards with inline loading for pending sources. |
| UX issue | Medium | Playlist detail download badges trust DB `downloadPath` without checking actual file existence. | `lib/ui/pages/library/playlist_detail_page.dart:1214`, `lib/ui/pages/library/playlist_detail_page.dart:1516`; cache preload currently covers covers at `lib/ui/pages/library/playlist_detail_page.dart:124`. | Gate downloaded badges through `FileExistsCache.exists()` and preload audio download paths. |
| code style | Low | Search local group rows and live room rows lack stable keys. | `lib/ui/pages/search/search_page.dart:491`, `lib/ui/pages/search/search_page.dart:708`. | Add `ValueKey` from group identity and live room id. |
| code style | Low | Downloaded category track rows and group columns lack stable keys. | `lib/ui/pages/library/downloaded_category_page.dart:489`, `lib/ui/pages/library/downloaded_category_page.dart:513`. | Key rows by source type, source id, page/cid, and download path; key groups by `groupKey`. |
| refactor opportunity | Low | `LyricsDisplay` resets local state inside `build()`. | `lib/ui/widgets/lyrics_display.dart:165`. | Move match-change reset to a lifecycle/listener helper so future state changes do not grow build-time side effects. |

## UX friction points

| Type | Severity | Finding | Evidence | Suggested direction |
|------|----------|---------|----------|---------------------|
| bug | High | Deleting a single downloaded track can delete files without clearing the persisted track download path, and it suppresses file cache refresh. | `lib/ui/pages/library/downloaded_category_page.dart:910`, `lib/providers/download/download_scanner.dart:90`, `lib/ui/pages/library/downloaded_category_page.dart:921`. | Delete through a service that resolves persisted tracks by source/path identity, then notify `libraryInvalidationCoordinatorProvider` with file-existence changes. |
| UX issue | High | Search source chips filter online search only; local playlist results can still show other sources. | `lib/ui/pages/search/search_page.dart:464`, `lib/providers/search_provider.dart:254`, `lib/services/search/search_service.dart:173`, `lib/data/repositories/track_repository.dart:170`. | Decide and document semantics; if chip means visible source, pass source filters into local search or filter local results in UI. |
| UX issue | Medium | Expanded Bilibili multi-P page rows lose common actions such as add to playlist, lyrics match, and remote add. | `lib/ui/pages/search/search_page.dart:846`, `lib/ui/pages/search/search_page.dart:938`, `lib/ui/pages/search/search_page.dart:1243`. | Expose page-level common actions or clearly label parent actions as applying to all parts. |
| UX issue | Medium | Bilibili multi-P loading failure is silent. | `lib/ui/pages/search/search_page.dart:813`, `lib/ui/pages/search/search_page.dart:825`. | Preserve an error state and show retry/toast feedback. |
| UX issue | Medium | First-download path selection can fail silently outside the explicit permission path. | `lib/ui/widgets/download_path_setup_dialog.dart:64`, `lib/ui/widgets/download_path_setup_dialog.dart:79`, `lib/services/download/download_path_manager.dart:39`, `lib/services/download/download_path_manager.dart:66`. | Differentiate cancel, permission denial, picker failure, and settings save failure in the dialog. |
| UX issue | Medium | Account status checks can show success even when per-source verification errors are only logged. | `lib/ui/pages/settings/account_management_page.dart:107`, `lib/providers/account_provider.dart:179`. | Return per-platform status/error summary and show partial-failure feedback. |
| UX issue | Medium | Auth-for-play settings exist in the model/backend but have no normal Settings/Account/Audio Settings UI entry. | `lib/data/models/settings.dart:231`, `lib/providers/audio_settings_provider.dart:8`, `test/ui/pages/settings/account_management_page_test.dart:21`. | Add a secondary settings area or document that these toggles are intentionally not user-facing. |
| UX issue | Medium | Bilibili login error handling is inconsistent across WebView cookie save, QR polling, and user-info refresh. | `lib/ui/pages/settings/bilibili_login_page.dart:161`, `lib/ui/pages/settings/bilibili_login_page.dart:167`, `lib/ui/pages/settings/bilibili_login_page.dart:267`, `lib/ui/pages/settings/bilibili_login_page.dart:272`. | Add unified try/catch/onError handling and reset-to-retry UI states. |
| UX issue | Low | Manual lyrics save/remove has no saving state or visible write error path. | `lib/ui/pages/lyrics/lyrics_search_sheet.dart:155`, `lib/ui/pages/lyrics/lyrics_search_sheet.dart:172`, `lib/providers/lyrics_provider.dart:423`. | Add `_isSaving`, disable repeated taps, and surface persistence errors. |

## Component reuse opportunities

| Type | Severity | Finding | Evidence | Suggested direction |
|------|----------|---------|----------|---------------------|
| refactor opportunity | Medium | Home and Library duplicate playlist card actions and dispatch. | `lib/ui/pages/library/library_page.dart:530`, `lib/ui/pages/library/library_page.dart:595`, `lib/ui/pages/home/home_page.dart:1213`, `lib/ui/pages/home/home_page.dart:1278`. | Introduce shared playlist action definitions and a dispatcher/coordinator. |
| refactor opportunity | Low | The same playlist actions are separately encoded for popup menus and bottom sheets. | `lib/ui/pages/library/library_page.dart:530`, `lib/ui/pages/library/library_page.dart:620`, `lib/ui/pages/home/home_page.dart:1213`, `lib/ui/pages/home/home_page.dart:1304`. | Convert one action list into both popup entries and bottom-sheet rows. |
| refactor opportunity | Medium | Remote add-to-playlist dialogs duplicate source-independent header, playlist row, and selection UI. | `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:402`, `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:538`, `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:427`, `lib/ui/widgets/dialogs/add_to_youtube_playlist_dialog.dart:562`, `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:389`, `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:525`. | Extract shared remote playlist selection widgets; keep source-specific id/service logic outside. |
| refactor opportunity | Low | Playlist detail group header duplicates common track actions and dispatch. | `lib/ui/pages/library/playlist_detail_page.dart:1254`, `lib/ui/pages/library/playlist_detail_page.dart:1304`, `lib/ui/pages/library/playlist_detail_page.dart:1392`. | Build common multi-track actions through shared menu helpers and append group-only actions locally. |

## Violations of instruction docs UI rules

- `lib/services/audio/AGENTS.md` expects queue UI to use provider/controller
  state rather than deriving queue order manually. `QueuePage` currently reads
  queue fields directly from `PlayerState` at `lib/ui/pages/queue/queue_page.dart:234`
  despite the queue provider contract in `lib/services/audio/audio_provider.dart:115`.
- `lib/providers/AGENTS.md` says source chips own source selection and a source
  chip queries only that source. Online search follows this, but visible local
  results do not: `lib/ui/pages/search/search_page.dart:464`,
  `lib/providers/search_provider.dart:254`.
- `lib/ui/AGENTS.md` and `.serena/memories/download_system.md` describe the
  `FileExistsCache` pattern for local file state. Playlist detail download badges
  bypass the existence check at `lib/ui/pages/library/playlist_detail_page.dart:1214`;
  single downloaded-track delete also suppresses file cache refresh at
  `lib/ui/pages/library/downloaded_category_page.dart:921`.
- `lib/data/AGENTS.md` requires stable keys for list/grid items. Search local
  group/live rows and downloaded category rows are missing keys at
  `lib/ui/pages/search/search_page.dart:491`, `lib/ui/pages/search/search_page.dart:708`,
  `lib/ui/pages/library/downloaded_category_page.dart:489`, and
  `lib/ui/pages/library/downloaded_category_page.dart:513`.
- `lib/ui/AGENTS.md` requires common track actions to use shared builders and
  `TrackActionCoordinator`. Most single-track flows comply, but playlist detail
  group header actions still hand-roll common actions at
  `lib/ui/pages/library/playlist_detail_page.dart:1254`.

No violations were found for direct `Image.network()` / `Image.file()` use in UI,
`ListTile.leading` containing `Row`, AppBar trailing spacing in the settings
scope, or database viewer collection coverage. Static tests under
`test/ui/static_rules` currently pass.

## Documentation inaccuracies

| Type | Severity | Finding | Evidence | Suggested direction |
|------|----------|---------|----------|---------------------|
| docs issue | Low | `docs/development.md` route table omits current settings child routes. | `docs/development.md:127`, `lib/ui/router.dart:51`, `lib/ui/router.dart:218`. | Update the route table or label it as a summary with `RoutePaths` as source of truth. |
| docs issue | Medium | `lib/ui/AGENTS.md` describes desktop as fixed three-column layout, while implementation has an optional detail panel. | `lib/ui/AGENTS.md:100`, `lib/ui/layouts/responsive_scaffold.dart:217`, `docs/development.md:132`. | Align `lib/ui/AGENTS.md` with the "collapsible side nav + optional detail panel" wording. |
| docs issue | Medium | `.serena/memories/ui_coding_patterns.md` still describes ranking as `CacheService + StreamProvider`. | `.serena/memories/ui_coding_patterns.md:224`, `lib/providers/AGENTS.md:7`, `lib/services/cache/ranking_cache_service.dart:20`, `test/ui/pages/ranking_ui_state_consumption_test.dart:78`. | Remove or update the stale memory; current rule is immutable `RankingCacheState` through `StateNotifierProvider`. |
| docs issue | Low | `.serena/memories/ui_coding_patterns.md` UI constants rules are stricter than current AGENTS and include stale constants. | `.serena/memories/ui_coding_patterns.md:680`, `.serena/memories/ui_coding_patterns.md:704`, `lib/ui/AGENTS.md:69`, `lib/core/constants/ui_constants.dart:18`. | Shrink or update the memory so it does not compete with scoped UI guidance. |
| docs issue | Low | `ListTile.leading Row` guidance is correct, but naive `leading: Row` searches can flag valid `AppBar.leading`. | `lib/ui/AGENTS.md:63`, `lib/ui/pages/library/library_page.dart:56`. | Keep static rules scoped to `ListTile(...)` blocks or AST checks. |
| docs issue | Low | Auth-for-play UI intent is undocumented. | `lib/data/sources/AGENTS.md:122`, `lib/data/models/settings.dart:231`, `test/ui/pages/settings/account_management_page_test.dart:21`. | Document whether playback auth toggles are intentionally hidden or add a user-facing settings entry. |

## Suggested quick wins

- Change Home ranking loading guard so existing ranking data remains usable:
  `lib/ui/pages/home/home_page.dart:151`.
- Add stable keys for search local group/live rows and downloaded category rows:
  `lib/ui/pages/search/search_page.dart:491`,
  `lib/ui/pages/search/search_page.dart:708`,
  `lib/ui/pages/library/downloaded_category_page.dart:489`,
  `lib/ui/pages/library/downloaded_category_page.dart:513`.
- Add visible errors for Bilibili multi-P loading and first-download path setup:
  `lib/ui/pages/search/search_page.dart:813`,
  `lib/ui/widgets/download_path_setup_dialog.dart:79`.
- Add saving/error UI for manual lyrics match save/remove:
  `lib/ui/pages/lyrics/lyrics_search_sheet.dart:155`,
  `lib/ui/pages/lyrics/lyrics_search_sheet.dart:172`.
- Update low-risk docs: `docs/development.md:127`, `lib/ui/AGENTS.md:100`,
  `.serena/memories/ui_coding_patterns.md:224`,
  `.serena/memories/ui_coding_patterns.md:680`.

## Suggested larger improvements

- Migrate QueuePage to queue-specific providers/selectors and add a regression
  test that it does not read queue data directly from `PlayerState`:
  `lib/ui/pages/queue/queue_page.dart:234`.
- Repair downloaded single-track deletion through a service-level persisted-track
  identity/path lookup and cache invalidation:
  `lib/ui/pages/library/downloaded_category_page.dart:910`.
- Define and implement source-chip semantics for local results:
  `lib/providers/search_provider.dart:254`,
  `lib/services/search/search_service.dart:173`.
- Add or document auth-for-play UI:
  `lib/data/models/settings.dart:231`,
  `lib/providers/audio_settings_provider.dart:8`.
- Extract shared playlist action and remote playlist selection components:
  `lib/ui/pages/library/library_page.dart:530`,
  `lib/ui/pages/home/home_page.dart:1213`,
  `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:402`.
- Normalize Bilibili multi-P page actions with common track action handling:
  `lib/ui/pages/search/search_page.dart:1243`.

## Small changes

These should be small UI or documentation changes:

- Home ranking loading guard: `lib/ui/pages/home/home_page.dart:151`.
- Stable keys in search and downloaded category rows:
  `lib/ui/pages/search/search_page.dart:491`,
  `lib/ui/pages/search/search_page.dart:708`,
  `lib/ui/pages/library/downloaded_category_page.dart:489`.
- Inline/toast error feedback for multi-P loading, download path setup, Bilibili
  login failures, and lyrics save/remove:
  `lib/ui/pages/search/search_page.dart:813`,
  `lib/ui/widgets/download_path_setup_dialog.dart:79`,
  `lib/ui/pages/settings/bilibili_login_page.dart:161`,
  `lib/ui/pages/lyrics/lyrics_search_sheet.dart:155`.
- Documentation corrections:
  `docs/development.md:127`, `lib/ui/AGENTS.md:100`,
  `.serena/memories/ui_coding_patterns.md:224`.

## Architecture or test impact

These need focused tests and may touch shared behavior:

- QueuePage provider migration should be covered by queue UI/static tests and
  existing audio queue provider tests: `lib/ui/pages/queue/queue_page.dart:234`,
  `test/services/audio/audio_queue_state_provider_test.dart:50`.
- Downloaded single-track delete fix should cover persisted `downloadPath`,
  `FileExistsCache`, and provider invalidation behavior:
  `lib/ui/pages/library/downloaded_category_page.dart:910`.
- Local search source filtering changes visible search semantics and should
  extend search provider/UI tests:
  `lib/providers/search_provider.dart:254`,
  `test/providers/search_pagination_stale_test.dart:208`.
- Auth-for-play UI changes affect user-facing settings and source playback
  behavior; cover defaults, mutations, and source-specific explanations:
  `lib/data/models/settings.dart:231`,
  `test/data/models/audio_settings_defaults_test.dart:25`.
- Shared playlist action extraction and remote playlist dialog reuse should keep
  desktop popup, touch bottom sheet, partial selection, and remote service
  behavior covered:
  `lib/ui/pages/library/library_page.dart:530`,
  `lib/ui/pages/home/home_page.dart:1213`,
  `lib/ui/widgets/dialogs/add_to_netease_playlist_dialog.dart:389`.
