# UI and Riverpod State Patterns Review

Scope: Flutter UI under `lib/ui`, Riverpod providers used by those screens, and cross-cutting UI conventions called out in `CLAUDE.md`. I did not modify production code.

## Summary

The UI already follows several important conventions well:

- UI playback calls consistently go through `AudioController`; I did not find direct UI usage of `AudioService`, `JustAudioService`, or `MediaKitAudioService`.
- Direct `Image.network()` / `Image.file()` usage is absent. `TrackThumbnail`, `TrackCover`, and `ImageLoadingService` are used consistently, and sampled `loadImage()` calls include explicit sizing.
- Most AppBar action lists with trailing `IconButton`s already include `const SizedBox(width: 8)`.
- The main list/grid screens generally use stable `ValueKey`s for track/list items.

The best simplification opportunities are around duplicated action/menu flows, inconsistent mutation ownership between UI and providers, and repeated loading/error UI.

## Findings

### P1: Track action menus are partially centralized but still duplicated across screens

`TrackActionHandler` centralizes the core actions (`play`, `play_next`, `add_to_queue`, `add_to_playlist`, `matchLyrics`, `add_to_remote`) in `lib/ui/handlers/track_action_handler.dart:96`, but each page still rebuilds the same menu entries, handler adapter, toast callbacks, and dialog callbacks.

Examples:

- Home ranking tile builds the menu and callback boilerplate in `lib/ui/pages/home/home_page.dart:939` and `lib/ui/pages/home/home_page.dart:984`.
- Explore ranking tile repeats the same menu and callback boilerplate in `lib/ui/pages/explore/explore_page.dart:371` and `lib/ui/pages/explore/explore_page.dart:398`.
- Downloaded track tile repeats most of it, with local delete as an extra action, in `lib/ui/pages/library/downloaded_category_page.dart:843` and `lib/ui/pages/library/downloaded_category_page.dart:942`.
- Playlist detail track tile repeats it again with download/remove/remote-remove extras in `lib/ui/pages/library/playlist_detail_page.dart:1673`.
- Search multi-page handling bypasses the shared handler and reimplements add-next/add-queue/add-playlist/remote logic for groups in `lib/ui/pages/search/search_page.dart:864` and `lib/ui/pages/search/search_page.dart:1438`.

Why it matters:

- New track actions require edits in many widgets.
- The same action can behave subtly differently depending on page. For example, grouped search and playlist actions manually loop tracks while single-track actions use `TrackActionHandler`.
- Menu entry labels/icons and context-menu/PopupMenuButton parity are easy to drift.

Recommendation:

- Promote `TrackActionHandler` into a UI-facing coordinator/hook such as `TrackActionsController` or `TrackActionDelegate` that owns:
  - standard menu entry construction,
  - login checks,
  - default toast callbacks,
  - add-to-playlist / lyrics / remote dialog launching,
  - single-track and multi-track variants.
- Let screens pass only context-specific extra actions (`download`, `delete`, `remove_from_playlist`) and page-specific track collections.

### P1: Playlist mutations are split between UI code, services, repositories, and notifiers

There are two playlist state patterns in use:

- `playlistListProvider` is watch-driven and exposes mutation/invalidation helpers in `lib/providers/playlist_provider.dart:64` and `lib/providers/playlist_provider.dart:176`.
- `playlistDetailProvider` owns optimistic detail updates and rollback in `lib/providers/playlist_provider.dart:411`, `lib/providers/playlist_provider.dart:436`, `lib/providers/playlist_provider.dart:460`, and `lib/providers/playlist_provider.dart:488`.

However, several UI paths still mutate through lower-level services/repositories directly and then manually invalidate providers:

- `AddToPlaylistDialog` calls `playlistServiceProvider` and `trackRepositoryProvider` directly, then invalidates detail providers inside loops in `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:527`, `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:536`, and `lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:540`.
- `PlaylistCardActions` reads `playlistServiceProvider` to fetch all tracks before queueing in `lib/ui/widgets/playlist_card_actions.dart:19` and `lib/ui/widgets/playlist_card_actions.dart:43`.
- `LibraryPage` persists reorder by calling `playlistServiceProvider` directly in `lib/ui/pages/library/library_page.dart:227`.
- Download cleanup deletes files and clears a track repository field directly from UI in `lib/ui/pages/library/downloaded_category_page.dart:1008`.
- Remote favorites sync code reaches into `trackRepositoryProvider` and `playlistServiceProvider` from the dialog in `lib/ui/widgets/dialogs/add_to_bilibili_playlist_dialog.dart:318`.
- Account playlist import reads `playlistRepositoryProvider` directly in `lib/ui/pages/settings/widgets/account_playlists_sheet.dart:174`.

Why it matters:

- Provider invalidation becomes caller-dependent. Some paths call `invalidatePlaylistProviders`, some call `ref.invalidate(allPlaylistsProvider)`, and some update only local state.
- Rollback/error semantics are inconsistent: provider-owned mutations roll back on failure, while service-owned UI paths generally log, partially continue, or only toast.
- UI widgets contain business/data orchestration that is harder to test and duplicate across dialogs/pages.

Recommendation:

- Move user-intent mutations into notifiers/services with one public UI entry point per flow:
  - add/remove tracks to local playlists,
  - reorder playlists,
  - delete downloaded track(s),
  - sync local imported playlists after remote edits.
- Keep provider invalidation inside those entry points. UI should call a notifier/service method and display the returned result.
- For playlist detail, prefer `playlistDetailProvider(...).notifier` for local playlist mutations so optimistic updates and rollback remain consistent.

### P1: Download service lifecycle and UI watching are easy to over-couple

`downloadServiceProvider` creates and initializes `DownloadService`, subscribes to progress/failure/completion streams, and owns event side effects in `lib/providers/download/download_providers.dart:38`. This is useful, but some UI widgets watch the service even though service identity is enough for command callbacks:

- `DownloadManagerPage` watches `downloadServiceProvider` at page build in `lib/ui/pages/settings/download_manager_page.dart:17`.
- Every `_DownloadTaskTile` also watches it in `lib/ui/pages/settings/download_manager_page.dart:324`.

Why it matters:

- Watching a command-only service makes rebuild dependencies less explicit. The visual state already comes from `downloadTasksProvider`, `downloadTaskProgressProvider`, and `trackByIdProvider`.
- It encourages UI to call service commands directly (`pauseTask`, `resumeTask`, `retryTask`, `cancelTask`) instead of a small command notifier facade.

Recommendation:

- Use `ref.read(downloadServiceProvider)` in button callbacks, or introduce a `downloadCommandsProvider`/notifier that exposes pause/resume/retry/cancel/clear operations.
- Keep progress/list state in the existing stream/state providers and keep imperative service access out of build methods.

### P1: Async UI code has mostly good mounted checks, but navigation/dialog usage is inconsistent

Good patterns are present:

- `DownloadedPage._syncLocalFiles` checks `mounted` after awaited dialog and provider work in `lib/ui/pages/library/downloaded_page.dart:32`.
- `ChangeDownloadPathDialog._onContinue` checks `mounted` after file picker and before navigation in `lib/ui/widgets/change_download_path_dialog.dart:190`.
- `DownloadPathSetupDialog._selectPath` checks `mounted` after directory selection in `lib/ui/widgets/download_path_setup_dialog.dart:59`.

But there are inconsistent cases:

- `ContextMenuRegion._showContextMenu` awaits `showMenu` and then calls `onSelected(result)` without checking whether the source context is still mounted in `lib/ui/widgets/context_menu_region.dart:27`. The callback frequently uses the original widget context for dialogs/toasts.
- `SearchPage._LocalGroupTile._handleMenuAction` calls `showAddToPlaylistDialog(context: context, tracks: group.tracks)` without a `context.mounted` guard in the `add_to_playlist` branch, while neighboring branches do guard in `lib/ui/pages/search/search_page.dart:1474`.
- `AccountManagementPage._verifyAllAccounts` sets `_isVerifying = true` before its `try/finally`, but has no `catch` toast/error path if account verification throws in `lib/ui/pages/settings/account_management_page.dart:122`.

Recommendation:

- Adopt a small rule for async UI helpers: after every `await` before using `context`, `Navigator`, `ScaffoldMessenger`, or `ref`-triggered UI callbacks, guard with `if (!mounted)` / `if (!context.mounted) return`.
- Update `ContextMenuRegion` to avoid dispatching selection after disposal.
- Keep dialog/toast launching behind shared action helpers where possible, reducing repeated mounted checks.

### P2: Loading/error/empty UI has multiple hand-rolled variants

There is a good reusable `ErrorDisplay`, but many pages still build bespoke loading/error/empty states:

- Search results hand-build loading, error, and retry UI in `lib/ui/pages/search/search_page.dart:420`.
- Playlist detail hand-builds initial loading/error states in `lib/ui/pages/library/playlist_detail_page.dart:166` and uses separate track loading/empty states later in `lib/ui/pages/library/playlist_detail_page.dart:236`.
- Downloaded category hand-builds loading and error sliver states in `lib/ui/pages/library/downloaded_category_page.dart:168`.
- Database viewer repeats `FutureBuilder` loading logic per collection, e.g. `lib/ui/pages/settings/database_viewer_page.dart:147`.
- Home intentionally hides some async failures with `SizedBox.shrink()` in `lib/ui/pages/home/home_page.dart:261` and `lib/ui/pages/home/home_page.dart:541`, while other pages show retry UI.

Why it matters:

- Error/retry UX differs by screen for similar `AsyncValue` states.
- Loading guards are mostly correct (`isLoading && data.isEmpty`), but the rule is manually reimplemented.
- Repeated state UI increases page size and makes skeleton/empty-state improvements expensive.

Recommendation:

- Add reusable helpers/widgets for common patterns:
  - `AsyncValueView<T>` for simple Future/Stream provider screens,
  - `SliverAsyncState` for sliver pages,
  - a shared `LoadingEmptyErrorState` wrapper for notifier states with `isLoading`, `error`, and data emptiness.
- Decide which home sections should silently hide failures versus show compact retry rows, and encode that as an explicit reusable option.

### P2: `ListTile.leading` still contains `Row` in several places

Project guidance says to avoid `Row` inside `ListTile.leading` because it can cause layout jitter. Remaining examples:

- `LibraryPage` AppBar leading uses `Row` in `lib/ui/pages/library/library_page.dart:55`. This is an AppBar leading rather than a ListTile leading, but it still mixes two actions into the leading slot and requires custom `leadingWidth`.
- `ImportPreviewDialog` list items use `Row` inside `ListTile.leading` in `lib/ui/pages/library/import_preview_page.dart:488` and `lib/ui/pages/library/import_preview_page.dart:719`.
- Lyrics source settings reorder rows use `Row` inside `ListTile.leading` in `lib/ui/pages/settings/lyrics_source_settings_page.dart:353`.

Recommendation:

- For `ListTile` rows that need checkbox + thumbnail or drag handle + icon, prefer a flat `InkWell`/`Padding`/`Row` layout like the ranking tiles, or constrain the leading width explicitly with a fixed-size wrapper.
- For the library AppBar leading actions, consider moving one action into `actions` or a shared `AppBarLeadingActions` widget to avoid custom leading layout.

### P2: Key usage is good in main lists but spotty in secondary lists

Good examples:

- Explore ranking list uses `ValueKey('${track.sourceId}_${track.pageNum}')` in `lib/ui/pages/explore/explore_page.dart:216`.
- Playlist detail groups use stable group/page keys in `lib/ui/pages/library/playlist_detail_page.dart:369` and `lib/ui/pages/library/playlist_detail_page.dart:418`.
- Downloaded categories use `ValueKey(categories[index].folderPath)` in `lib/ui/pages/library/downloaded_page.dart:151`.

Potential gaps:

- Search history `ListView.builder` returns `ListTile`s without keys in `lib/ui/pages/search/search_page.dart:387`.
- Download manager rows and task tiles are built without row/task keys in `lib/ui/pages/settings/download_manager_page.dart:121` and `lib/ui/pages/settings/download_manager_page.dart:263`.
- Several dialog playlist lists use dynamic state and selections; keys would make reorder/insert/remove behavior safer.

Recommendation:

- Standardize a `ValueKey` rule for any builder over mutable domain entities, not just main music lists.
- Use task IDs for download task tiles and history IDs for search/history rows.

### P2: Ranking cache provider exposes mutable service state outside Riverpod state

The ranking cache service stores mutable lists and `isInitialLoading`, then providers yield from `service.stateChanges` in `lib/providers/popular_provider.dart:133` and `lib/providers/popular_provider.dart:261`. UI also reads `cacheService.isInitialLoading` directly from the service in `lib/ui/pages/home/home_page.dart:92`.

Why it matters:

- The state is split between an imperative service and stream providers. The UI must know which fields are reactive and which are snapshots.
- Errors are only logged inside the service (`lib/services/cache/ranking_cache_service.dart:143` and `lib/services/cache/ranking_cache_service.dart:162`), so UI sections often cannot distinguish empty data from failed refresh.

Recommendation:

- Wrap ranking cache in a single Riverpod state object per source (`tracks`, `isInitialLoading`, `isRefreshing`, `lastError`, `lastUpdated`) instead of exposing service fields directly.
- Keep the background refresh implementation inside the service if desired, but publish immutable state through a notifier/provider.

## What to simplify first

1. Build a shared track action/menu coordinator around `TrackActionHandler`, then migrate Home, Explore, Search, Playlist Detail, Downloaded, and History tiles to it.
2. Move playlist and download mutations out of UI widgets into notifier/service facades that own invalidation and rollback semantics.
3. Introduce reusable loading/error/empty wrappers for `AsyncValue` and sliver pages.
4. Fix the remaining `ListTile.leading` row layouts and add keys to mutable secondary lists.
5. Convert ranking cache state from service-field snapshots to immutable Riverpod state.
