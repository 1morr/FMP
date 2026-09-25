# Research: Providers + UI layer conventions (lib/providers, lib/ui, lib/i18n, app/main)

- **Query**: Actual coding patterns a new contributor must follow in `lib/providers/`, `lib/ui/`, `lib/i18n/`, `lib/app.dart`, `lib/main.dart`, `breakpoints.dart`, and tests under `test/providers`, `test/ui`.
- **Scope**: internal
- **Date**: 2026-09-25
- **Already documented elsewhere (link, don't restate)**: `AGENTS.md` (verification table, boundaries, static-rule list), `docs/development.md` §響應式版面配置 + §架構地圖, `docs/troubleshooting.md` (Windows AXTree / Slider / Tooltip), `.claude/skills/verify-on-device/SKILL.md`.
- Versions (pubspec): `flutter_riverpod ^3.4.3`, `go_router ^18.0.1`, `slang ^4.19.2` / `slang_flutter ^4.19.0`, `equatable ^2.1.0`, `flutter_lints ^6.0.0`. **No** riverpod_generator / riverpod_annotation, **no** freezed, **no** hooks.

---

## 1. Riverpod

### 1.1 Provider kinds actually used (hand-written, no codegen)

Counted over `lib/` (top-level `final xxxProvider = ...`):

| Kind | Approx count | Typical use | Examples |
|---|---|---|---|
| `Provider<T>` | ~90 | Wrap a service/repository; derived "selector" values | `playlistServiceProvider` (`lib/providers/library/playlist_provider.dart:24`), `downloadServiceProvider` (`lib/providers/download/download_providers.dart`), `currentTrackProvider`/`queueControlStateProvider` (`lib/providers/audio/audio_player_selectors.dart`), `themeModeProvider` (`lib/providers/settings/theme_provider.dart`) |
| `NotifierProvider<N, S>` | ~35 | All mutable state | `themeProvider`, `layoutSettingsProvider`, `playlistListProvider`, `searchProvider`, `audioControllerProvider` |
| `NotifierProvider.family` | 2 | Per-id mutable state; id passed via **constructor** | `playlistDetailProvider` (`playlist_provider.dart:618`, `PlaylistDetailNotifier(this.playlistId)`), `importPlaylistProvider` (`lib/providers/library/import_playlist_provider.dart:241`) |
| `NotifierProvider.autoDispose` | 5 | Page-scoped state that must reset when page leaves | `playlistDetailSelectionProvider`/`exploreSelectionProvider`/`searchSelectionProvider` (`lib/providers/ui/selection_provider.dart:229-244`), `playHistoryPageProvider`, `lyricsSearchProvider` |
| `FutureProvider` (+`.family`, `.autoDispose`) | ~15 | One-shot snapshots; must be invalidated explicitly | `allPlaylistsProvider`, `playlistCoverProvider` (family int), `trackByIdProvider` (family), `downloadPathProvider`, `accountStatusCheckProvider`, `recentPlayHistoryProvider` (autoDispose) |
| `StreamProvider` (+`.autoDispose`) | 4 | Isar `watch*()` streams / event streams | `downloadTasksProvider`, `playHistorySnapshotProvider` (async* generator), `currentLyricsMatchProvider`, `toastStreamProvider` (`lib/core/services/toast_service.dart`) |
| `Provider.family` | ~6 | Narrowed per-key read of a wide state | `downloadTaskProgressProvider(taskId)`, `isLoggedInProvider(platform)`, `filePathExistsProvider(path)`, `isPlaylistRefreshingProvider(id)` |

- **Not used, and gated**: `StateNotifier`, `StateProvider`, `ChangeNotifierProvider`, `AsyncNotifier`, `StreamNotifier`. `docs/development.md` states "Riverpod 3 的 Notifier / FutureProvider / StreamProvider，沒有 StateNotifier". Gate: `test/providers/static_rules/riverpod3_static_rule_test.dart` → `lib does not import the riverpod legacy barrel` (regex `package:(?:flutter_|hooks_)?riverpod/legacy\.dart`).
- Loading/error state inside `Notifier`s is modelled as fields (`isLoading`, `error`) in a plain state class, **not** `AsyncNotifier` (e.g. `PlaylistListState`, `PlaylistDetailState`, `SearchState`, `ThemeState.isLoading`).
- Notifier constructor wiring: `NotifierProvider<X, S>(X.new)` everywhere. Dependencies come from `ref.watch(...)` inside `build()`, never constructor params (except family id). Evidence: `test/support/audio_controller_harness.dart:20-26` and `test/providers/search_pagination_stale_test.dart` comment "`SearchNotifier` 以前吃兩個建構子參數；`Notifier.new` 不吃，所以兩個相依都從 container 進去".

### 1.2 Naming & location

- Every provider variable ends in `Provider`; notifier class `XxxNotifier`, state class `XxxState` (`ThemeNotifier`/`ThemeState`, `LayoutSettingsNotifier`/`LayoutSettingsState`, `PlaylistDetailNotifier`/`PlaylistDetailState`). A few notifiers are named after the thing (`DownloadProgressState extends Notifier<Map...>`, `FileExistsCacheEpoch`) — minority.
- File per feature in `lib/providers/<feature>/<name>_provider.dart`; features: `account, audio, download, library, lyrics, search, settings, system, ui`. The subdirectory name is a **feature identity** for `test/support/layer_boundary_static_rule_test.dart` (rule B: new cross-feature import edge must be added to `_knownFeatureEdges` with a reason; `services/<x>` and `providers/<x>` count as the same feature).
- Exceptions (co-located with their service, repeated pattern): `queueStateProvider` (`lib/services/audio/queue_state.dart`), `radioControllerProvider` & friends (`lib/services/radio/radio_controller.dart`), `rankingCacheServiceProvider` (`lib/services/cache/ranking_cache_service.dart`), `connectivityProvider` (`lib/services/network/connectivity_service.dart`), repository providers in `lib/data/database/repository_providers.dart`, `databaseProvider` in `lib/data/database/database_provider.dart`, `toastServiceProvider` in `lib/core/services/toast_service.dart`. One-off: `networkBannerVisibleProvider` declared in a widget file `lib/ui/widgets/feedback/network_status_banner.dart`.
- AGENTS.md boundary: `audioControllerProvider` + providers building its collaborators live in `lib/providers/audio/audio_controller_provider.dart`; `neteaseSourceProvider` is the lyrics-layer source.
- Provider files re-export types UI needs so pages import one file: `playlist_provider.dart` `export ... show PlaylistUpdateResult`; `download_providers.dart` re-exports `download_scanner.dart`, `DownloadResult`, `trackRepositoryProvider`.

### 1.3 Wrapping services & repositories

Pattern (repeated ≥10×): `Provider<Service>((ref) { deps = ref.watch(repoProvider)...; final s = Service(...); ref.onDispose(s.dispose); return s; })`.
- `downloadServiceProvider` (`download_providers.dart`): watches repos, `sourceManagerProvider`, `streamResolutionServiceProvider`, `sourceAuthContextProvider`; subscribes to service streams and cancels all in `ref.onDispose`.
- `lrclibSourceProvider`/`neteaseSourceProvider`/`qqmusicSourceProvider`/`lyricsCacheServiceProvider` (`lib/providers/lyrics/lyrics_provider.dart:29-40`) — `ref.onDispose(source.dispose)` added by fix `491f76f9` ("singleton providers had no onDispose, so Dio connection pools ... were not cleaned up").
- Database access in a provider: `ref.watch(databaseProvider).requireValue` (12×) or `.value` + null check/throw `StateError('Database not initialized')` (10×, e.g. `playlistServiceProvider`). The DB future is resolved before any page builds because `FMPApp` renders a loading `MaterialApp` until `databaseProvider` has data (`lib/app.dart`).
- Coordinator-as-provider: `libraryInvalidationCoordinatorProvider` (`lib/providers/library/library_invalidation_coordinator.dart:147`) is a `Provider` returning an object of closures over `ref.invalidate(...)`. Gate: `test/support/call_site_ownership_static_rule_test.dart` row `playlist invalidation` — `ref.invalidate(allPlaylistsProvider|playlistDetailProvider|playlistCoverProvider|playlistCoverMapProvider)` may appear only in `library_invalidation_coordinator.dart` and `lib/ui/pages/home/home_page.dart` (home "retry" only reloads the list). Everyone else calls `ref.read(libraryInvalidationCoordinatorProvider).playlistChanged(...)` / `playlistMutationCompleted(...)`. History: `5f3bcb1b fix(ui): route playlist detail error retry through library invalidation coordinator`, `c5eaafff fix(providers): avoid creating playlist detail during invalidation`, test `test/providers/library_invalidation_coordinator_test.dart`, `test/providers/playlist_provider_invalidation_test.dart`.

### 1.4 Notifier `build()` idioms

- **Sync initial state + fire-and-forget async load**: `build()` stores deps, calls `_load()` (not awaited), returns an initial/`isLoading` state. `_load()` sets `state` after the await and checks `if (!ref.mounted) return;`.
  - `LayoutSettingsNotifier.build/_load` (`lib/providers/settings/layout_settings_provider.dart`), `ThemeNotifier` (`theme_provider.dart`, uses `preloadedThemeMode` from `main.dart` as first value to avoid flash), `LocaleNotifier` (`locale_provider.dart`).
- **Cannot write `state` synchronously inside `build()`**: `PlaylistDetailNotifier.build` uses `Future.microtask(loadPlaylist)` and returns `isLoading: true` (`playlist_provider.dart:320-328`, comment explains Riverpod blocks sync state writes in build).
- **Subscriptions opened in `build()` are paired with `ref.onDispose` in the same build** because `build()` re-runs on dependency change and the Notifier *instance is kept* (`PlaylistListNotifier.build`, `playlist_provider.dart:80-86`: "訂閱與建立它的那一次 build 成對：`ref.onDispose` 在 rebuild 之前也會跑"). Test: `test/providers/notifier_rebuild_test.dart` (header: Riverpod 3 Notifier keeps instance across rebuild unlike StateNotifier; every rewritten notifier needs a "rebuild keeps state and side effects correct" test).
- **`ref.mounted` after every await that touches `ref`/`state`**: 56 occurrences. Fix `a43fddbe fix(providers): keep ref usable across every await in provider bodies` — "3.x throws UnmountedRefException unconditionally ... Prefer hoisting the read above the await ... guard with mounted only where the read genuinely has to happen afterwards." Also `0e673337 fix(playlist): add mounted checks...`.
- **No touching other providers from lifecycle callbacks** (`ref.onDispose` etc.): Riverpod 3 forbids `state =`/`invalidate` there. Workaround: `scheduleMicrotask(progressState.clear)` in `downloadServiceProvider`'s onDispose, and `clear()` guards `ref.mounted` (`download_providers.dart:~105-150`). Commit `11ed8dc3 refactor(providers): rewrite the remaining feature notifiers`.
- **Stale async result guards** (request id / generation counter) — repeated: `SearchNotifier` `if (!ref.mounted || requestId != _searchRequestId) return;` (`lib/providers/search/search_provider.dart:276,300,651,660`), `RefreshManagerNotifier._nextRefreshGeneration` (`refresh_provider.dart:290`), `HomeRankingSettingsNotifier._sourceOrderGeneration`, `TrackDetailNotifier` compares `_currentTrack?.groupKey == trackKey`. Tests: `test/providers/search_pagination_stale_test.dart`, `track_detail_refresh_stale_test.dart`, `refresh_provider_stale_cleanup_test.dart`, `lyrics_content_cache_race_test.dart`. Fix commits `d6b0f8f4 fix: prevent stale async side effects`, `3010e56e fix(lyrics): prevent stale lyrics cache writes`.
- **Errors stored in state are already user-facing sentences**: catch blocks do `state = state.copyWith(error: failureMessage(e, stack, 'createPlaylist failed', tag: 'Playlist'))` (`playlist_provider.dart` many; `failureMessage` at `lib/core/errors/user_message.dart:97` logs original + returns translated `userMessageFor`). Fix `5e9d2929 fix(providers): map errors before they reach the UI` ("Nine providers stored e.toString()"). UI then renders `state.error!` directly (`cover_picker_dialog.dart:147` comment "state.error 已經是 provider 映射過的一句話").
- **FutureProvider that feeds a placeholder must log in the provider, not in the UI error branch** (branch reruns every rebuild): `playlistCoverProvider` / `playlistCoverMapProvider` (`playlist_provider.dart:~630-660`) `AppLogger.warning(...)` then `Error.throwWithStackTrace(e, stack)`. From `609cc41c`.

### 1.5 `ref.watch` / `ref.read` / `ref.listen` conventions

Counts in `lib/providers`+`lib/ui`+`app.dart`: `ref.watch` 344, `ref.read` 284, `ref.listen` 17, `ref.listenManual` 3, `ref.invalidate` 34, `ref.onDispose` 18, `ref.keepAlive` 1.

- `ref.watch` in `build()`/provider bodies; `ref.read(xProvider.notifier).method()` in callbacks (36 UI call sites of `ref.read(audioControllerProvider.notifier)`; e.g. `ranking_track_tile.dart` `onTap: () => ref.read(audioControllerProvider.notifier).playTemporary(track)`).
- **Narrow watches**: `ref.watch(p.select((s) => s.field))` (35 hits / 13 UI files, e.g. `home_page.dart:904`, `radio_player_page.dart:43`, `network_status_banner.dart:27`) or a derived narrow provider (`audio_player_selectors.dart`: `currentTrackProvider`, `queueProvider`, `queueControlStateProvider`, `playbackSpeedProvider`; `theme_provider.dart`: `themeModeProvider`, `primaryColorProvider`; `downloadTaskProgressProvider(taskId)`).
  - **Gated**: `test/ui/static_rules/watch_scope_static_rule_test.dart` — whole `ref.watch(X)` forbidden anywhere in `lib/` for `_narrowOnly` = `audioControllerProvider` (progress updates several times/s), `rankingCacheServiceProvider`, `searchSelectionProvider`, `playlistDetailSelectionProvider`, `downloadProgressStateProvider`. `.select`, `.notifier`, `ref.read` allowed. Add to `_narrowOnly` with a reason.
  - Derived selector state classes need value equality so `select`/derived providers filter: `DesktopAudioDeviceState`, `QueueControlState` are `@immutable` with hand-written `==`/`hashCode` (`audio_player_selectors.dart`).
- **`ref.listen` in `build()` for side effects (toasts)**: `home_page.dart:126` and `radio_page.dart:32` — `ref.listen<RadioState>(radioControllerProvider, (prev, next) { if (next.error != null && next.error != prev?.error) ToastService.error(context, next.error!); })`. `AppShell` listens to `toastStreamProvider` (`app_shell.dart:44`) — background services push toasts via `ref.read(toastServiceProvider).showMessage(...)` and the shell renders them.
- **`ref.listenManual` in `initState`** of `ConsumerStatefulWidget`, stored in a `ProviderSubscription` field and closed in dispose: `import_playlist_dialog.dart:114`, `account_playlists_sheet.dart:262`, `lyrics_display.dart:75`.
- **Providers listening to providers**: `trackDetailProvider` listens to `currentTrackProvider` (`track_detail_provider.dart:57`), `windowsDesktopServiceProvider` listens to `audioControllerProvider` (`windows_desktop_provider.dart:18`).
- **Riverpod 3 pauses `ref.watch` of consumers hidden behind an opaque route** (e.g. the full-screen `PlayerPage` pushed on root navigator). Therefore side-effect/background providers are anchored in `FMPApp.build` (`lib/app.dart`, above `MaterialApp`, no `TickerMode` ancestor). **Gated**: `riverpod3_static_rule_test.dart` `side-effect providers stay anchored above MaterialApp` — the set of providers watched in `FMPApp.build` must equal `_anchoredProviders` (currently 14: `databaseProvider, themeProvider, localeProvider, playbackSettingsProvider, refreshSettingsProvider, autoRefreshServiceProvider, accountStatusCheckProvider, accountSessionExpiryWatcherProvider, startupDownloadSyncProvider, windowsDesktopServiceProvider, minimizeToTrayProvider, globalHotkeysEnabledProvider, launchAtStartupProvider, hotkeyConfigProvider`), each with a reason. Adding a new background provider = watch it in `FMPApp.build` + add to that map. Related fix `cad58df5 fix(settings): apply the saved refresh intervals at startup`.
- **Invalidation/refresh**: explicit `ref.invalidate(x)` for snapshot `FutureProvider`s (UI retry: `onRetry: () => ref.invalidate(allPlaylistsProvider)` in `home_page.dart:331`); library mutations go through the coordinator (1.3). `playlistListProvider` is live (Isar `watchAll()`), `allPlaylistsProvider` is a snapshot needing invalidation (dartdoc on `PlaylistListNotifier`).
- **Retry disabled globally**: `ProviderScope(retry: (retryCount, error) => null, ...)` in `lib/main.dart:268` (comment: Riverpod 3 default auto-retries 10× ~38 s; FMP has explicit retry layers; `UnmountedRefException` would be retried). Widget tests that assert an error branch must pass the same `retry:` (`test/ui/pages/settings/download_manager_error_state_test.dart`).

### 1.6 autoDispose policy (observed)

- Default is **keep-alive** (no autoDispose) for settings/services/global state.
- `autoDispose` used for page-scoped UI state (selection providers, `playHistoryPageProvider`, `lyricsSearchProvider`) and page-only derived data (`filteredPlayHistoryProvider`, `groupedPlayHistoryProvider`, `playHistoryStatsProvider`, lyrics `parsedLyricsProvider`, `currentLyricsLineIndexProvider`, `lyricsMatchForTrackProvider`). Private helpers may be `_`-prefixed (`_currentLyricsExternalIdProvider` in `lyrics_provider.dart`).

---

## 2. State classes

- **Hand-written immutable classes with `const` constructor + `copyWith`** (19 files in `lib/providers` define `copyWith`). No freezed.
  - Nullable fields cleared via extra `bool clearX = false` flags: `ThemeState.copyWith(clearPrimaryColor:, clearFontFamily:)` (`theme_provider.dart`), `play_history_provider.dart:236-238`, `track_detail_provider.dart:29-30`.
  - Some `copyWith` reset `error` when omitted (`error: error` not `error ?? this.error`) — `PlaylistListState`, `PlaylistDetailState` (`playlist_provider.dart`). Read each class's `copyWith` before assuming semantics.
  - Named initial constructors: `const LayoutSettingsState.initial()`.
- **Equality**: three styles coexist:
  1. `extends Equatable` with `props` — `playlist_provider.dart`, `refresh_provider.dart`, `search_provider.dart`. **Gated**: `riverpod3_static_rule_test.dart` `every Equatable state lists all of its fields in props` (scans `lib/providers`; Riverpod 3 filters updates with `==`, a missing prop silently stops rebuilds).
  2. `@immutable` + manual `==`/`hashCode` — `audio_player_selectors.dart` (`DesktopAudioDeviceState`, `QueueControlState`), `selection_provider.dart`, `download_scanner.dart`.
  3. Plain class, identity equality — most settings states (`ThemeState`, `LayoutSettingsState`); every `state =` notifies.
- Collections in state are replaced, not mutated: `state = {...state, taskId: ...}` / `Map.from(state)..remove(id)` (`DownloadProgressState`); immutable previews `fix(cache): make ranking previews immutable 9fba0660`; `HomeRankingLayoutPlan` uses `List.unmodifiable` (`home_page.dart:62-68`).

### AsyncValue in UI

- `.when(data:, loading:, error:)` is the only form (19 uses / 13 files); **no** Dart-3 `switch` pattern matching on `AsyncValue` in `lib/ui` (tests do use `switch (x) { AsyncData(:final value) => ... }`, e.g. `download_manager_error_state_test.dart`). Other accessors: `.value`, `.hasValue`, `.isLoading`, `whenData` (97 hits / 38 files); `skipLoadingOnReload: true` in cover lookups (`home_page.dart:457`, `library_page.dart:267`).
- **Error branch must render something**: section-level → `ErrorDisplay(compact: true, message: userMessageFor(e), onRetry: () => ref.invalidate(...))` (`home_page.dart:326-333`, `downloaded_page.dart:99-103`, `download_manager_page.dart:91-96`); cover/avatar → placeholder allowed. **Gated**: `test/ui/static_rules/error_presentation_static_rule_test.dart` `an async error branch never renders as nothing` (forbids `error: (..) => SizedBox.shrink()` and `orElse: () => SizedBox.shrink()` in `lib/ui`). Loading branch may be `SizedBox.shrink()` or `LoadingPlaceholder`.
- Fix history: `609cc41c fix(ui): stop the covers and sections swallowing load errors`, `bcb76014 fix(ui): tell a failed track lookup apart from a loading one` (test `test/ui/pages/settings/download_manager_error_state_test.dart`).

---

## 3. Widgets

### 3.1 Widget kinds (counts in `lib/ui`)

`StatelessWidget` 106 / `ConsumerWidget` 67 / `ConsumerStatefulWidget` 50 / `StatefulWidget` 17 / `Consumer(` builder 8 / HookWidget 0.
- `ConsumerWidget` when only providers are read; `ConsumerStatefulWidget` when there are controllers, subscriptions (`listenManual`), or local async flows (`HomePage` is `ConsumerStatefulWidget` only for `ref.listen`, `home_page.dart:115-130`).
- **Split pages into independent `ConsumerWidget` sections to narrow rebuilds** — comments "独立 ConsumerWidget" in `home_page.dart` (`HomeRankingsSection`, `_RadioSection`, playlists/recent-plays sections). `track_detail_panel.dart` and `player_page.dart` do the same.
- Private widget classes `_Xxx` inside the page file are the norm (161 private widget classes in 56 files; `playlist_detail_page.dart` 5, `home_page.dart` 6). Page-local widgets that grow get their own file under `lib/ui/pages/<feature>/widgets/` (`library/widgets/*_dialog.dart`, `settings/widgets/*`). **One-off**: `settings_page.dart` uses `part 'widgets/settings_*.dart'` (7 part files) — the only `part` usage in `lib/ui`.
- Cross-page reusable widgets live in `lib/ui/widgets/<category>/`: `app_bars, controls, dialogs, feedback, images, indicators, layout, lyrics, menus, panels, player, radio, track_group, track_tiles`.
- `const` constructors with `super.key` everywhere; `prefer_const_constructors` + `prefer_const_declarations` enabled in `analysis_options.yaml`; also `always_use_package_imports`, `comment_references`, `deprecated_member_use_from_same_package`.
- `if (!mounted) return` (75) / `if (!context.mounted) return` (21) after every await in State/handlers. Fix `45f9f1fe fix: check mounted before setState in four async handlers`.
- **Pure top-level layout functions** for testable layout decisions (repeated): `resolvePlayerLayout(Size, {hasLyrics})` (`player_page.dart:74`, test `test/ui/pages/player/player_layout_test.dart`), `buildHomeRankingLayoutPlan(...)` (`home_page.dart:~83`, test `test/ui/pages/home/home_ranking_sources_test.dart`). Commit `4a23ae86` "resolvePlayerLayout is a pure function ... testable without pumping the page".

### 3.2 Shared widgets to reuse (usage counts = files in `lib/ui`)

| Need | Use | Where | Notes |
|---|---|---|---|
| Destructive confirm | `showConfirmDestructiveDialog(...) → Future<bool?>` (12) | `widgets/dialogs/confirm_destructive_dialog.dart` | FilledButton + `colorScheme.error`; `26077371` migrated clear-queue to it |
| Error / empty state | `ErrorDisplay` (+ `.network/.server/.notFound/.permission/.empty`, `compact:`) (13); `LoadingPlaceholder` (9) | `widgets/feedback/error_display.dart` | Fits short windows (`_shortHeight = 400`, fix `84b19374`) |
| Toast | `ToastService.success/show/error/warning/showWithAction(context, msg)`; exceptions via `ToastService.failure(context, e, stackTrace:, tag:)` | `lib/core/services/toast_service.dart` (`failure` at :188) | Only SnackBar builder in app; background code uses `toastServiceProvider` stream; capture `ScaffoldMessenger` before popping a dialog → `showSnackBarWithMessenger` (`change_download_path_dialog.dart:220`) |
| Semantic colors success/warning | `ToastService.successColor` / `warningColor` | same | "ColorScheme 沒有 success / warning 語意色" |
| Right-click menu | `ContextMenuRegion(menuBuilder:, onSelected:)` (11) | `widgets/menus/context_menu_region.dart` | |
| One action list → popup + long-press sheet | `MenuAction` + `buildMenuActionPopupEntries` / `buildMenuActionListTiles` (11) | `widgets/menus/menu_action.dart` | |
| Track actions | `TrackAction` enum, `TrackActionHandler`, `buildTrackActionPopupMenuEntries`, `buildTrackActionListTiles`, `handleAddToPlaylistSelection`, `showLyricsDisplayModeMenu` | `lib/ui/handlers/track_action_*.dart` | Shared by player page + detail panel (`806cdf06`) |
| Popup item with trailing icon | `PopupMenuRow` (not `ListTile`) | `widgets/menus/popup_menu_row.dart` | ListTile intrinsic width bug broke `1.0x` into 3 lines (`ddee98c9`) |
| Bottom sheet shell | `CappedDraggableSheet` (4), `SheetDragHandle` (6) | `widgets/layout/` | |
| Slider | `ScopedSlider` (6) | `widgets/controls/scoped_slider.dart` | gated, see §8 |
| Images | `TrackThumbnail`/`TrackCover(variant: TrackCoverVariant.x)` (14), `PlaylistCoverImage(variant:)` (12), `AvatarImage` (6), `RadioCoverImage`, `RecentPlayCoverImage` | `widgets/images/` | gated, see §8 |
| Indicators | `NowPlayingIndicator`, `SourceBadge`, `LiveBadge`, `VipBadge`, `PartNumberBadge`, `RefreshProgressIndicator` | `widgets/indicators/` | |
| App bars | `CollapsingHeroSliverAppBar`, `SelectionModeAppBar`; `CustomTitleBar` only in `app.dart` | `widgets/app_bars/` | `CustomTitleBar(` ownership gated (§8) |

- Dialog entry points: two coexisting conventions, both repeated — top-level `Future<T> showXxxDialog({...})` (`showAddToPlaylistDialog`, `showAddToBilibiliPlaylistDialog`, `showConfirmDestructiveDialog`, `showImportPreviewDialog`, `showLyricsSearchSheet`) and `static Future<T> show(BuildContext)` on the dialog class (`ChangeDownloadPathDialog.show`, `DownloadPathSetupDialog.show`, `UpdateDialog.show`, `AddRadioDialog.show`, `ColorPaletteButton`). Dialogs close with `Navigator.pop(context, result)` (90) / `Navigator.of(context).pop` (19); no `Navigator.push` in `lib/ui`.
- Accessibility: every `IconButton` has a `tooltip:` (91 of 98 `IconButton(` have one within 6 lines; fix `104bd8d3` "26 of 96 IconButtons had no tooltip and so no accessible name"); 48dp targets (`b1df272a`); no overflow at text scale 2.0 (`a35f675d`); `Semantics(container: true, child: routes)` around nested Navigators (`app.dart` `AppContentWrapper._routeSemantics`, `responsive_scaffold.dart:~120`, fix `1a0c317d`). Tests: `test/ui/layouts/nav_rail_semantics_test.dart`, `test/ui/widgets/mini_player_accessibility_test.dart`, `test/ui/windows/lyrics_window_semantics_test.dart`. **Not gated** by a static rule.
- `ListTile(leading: Row(...))` forbidden — gated (§8).
- Durations formatted via `DurationFormatter` (`5798d80f fix(ui): format every duration as 5:03`).

---

## 4. Responsive layout (real usage)

Authority: `lib/core/constants/breakpoints.dart` (`WindowClass.of(width)`, `.atLeast()`, `columnsFor(containerWidth)`), already explained in `docs/development.md` §響應式版面配置.

- `WindowClass.of(...)` — window skeleton only, fed from `MediaQuery`: `ResponsiveScaffold.build` (`lib/ui/layouts/responsive_scaffold.dart:118-141`, exhaustive `switch` → `_CompactLayout`/`_MediumLayout`/`_ExpandedLayout`), `player_page.dart:77` (`WindowClass.of(size.width).atLeast(WindowClass.expanded) && !isShort`), `radio_player_page.dart:52` (`atLeast(WindowClass.large)`), `mini_player_volume_control.dart:37` (`== WindowClass.compact`).
- `columnsFor(maxWidth)` — container columns, fed from `LayoutBuilder` constraints: only `home_page.dart:101` (`buildHomeRankingLayoutPlan`).
- Widgets inside panes measure themselves with `LayoutBuilder` (25 uses / 15 files), e.g. `ranking_track_tile.dart:74` comment: "視窗寬度只決定外框（`WindowClass`），內容一律量自己的 `LayoutBuilder`".
- `ResponsiveScaffold` uses `MediaQuery` not `LayoutBuilder` "来避免与 go_router Navigator 的布局冲突" (`responsive_scaffold.dart:117`). Tests must drive it via `tester.view.physicalSize` + `devicePixelRatio`, not `setSurfaceSize` (`test/ui/layouts/nav_labels_locale_test.dart` comment); pure widget tests elsewhere use `tester.binding.setSurfaceSize(...)` + `addTearDown(() => ...setSurfaceSize(null))`.
- Layout tokens: `AppLayout` (`lib/core/constants/app_layout.dart`: `railCollapsed 72`, `railExpanded 256`, `detailPanelMin/Default/MaxFraction`, `paneSpacer 24`, `playerCoverMax 420`, `playerContentMaxWide 720`, …) — "集中的理由 ... 同一個數字現在有兩個以上的消費者".
- Pitfall commits: `9557e03f fix(ui): stop the home rankings dropping a source when space is tight` (mixing window class with container width), `3cb9a95a fix(home): lay rankings out in one row or one per row`, `4a23ae86` (player layout answers to height + lyrics; height floor 520dp from Auxio), `044889e1`, `80469d92 fix(ui): keep the collapsed rail reachable in short windows`.
- Desktop layout state persists in `layoutSettingsProvider` (rail expanded, detail panel expanded/width); drag uses `previewDetailPanelWidth` (memory) then `commitDetailPanelWidth` (DB) (`layout_settings_provider.dart`).

---

## 5. Theme / tokens

- Colors: `final colorScheme = Theme.of(context).colorScheme;` at top of `build` (158×), text: `Theme.of(context).textTheme.xxx` (120× inline, 22× local var). 647 `colorScheme.` hits / 92 files. Theme built by `AppTheme.lightTheme/darkTheme({primaryColor, fontFamily})` from one `_theme(...)` description (`lib/ui/theme/app_theme.dart`; `09e95a0d refactor(theme): build light and dark from one description`). Preset seed colors `lib/ui/theme/theme_preset_colors.dart`. Tests `test/ui/theme/app_theme_test.dart`, `theme_preset_colors_test.dart`.
- Tokens in `lib/core/constants/ui_constants.dart`: `AppRadius` (`xs/sm/md/lg/xl/pill/sheet` + prebuilt `borderRadiusXx`; 111 hits / 59 files — only 1 file has a literal `BorderRadius.circular(<number>)`), `AnimationDurations` (`fastest..loop`; 36 hits; only 4 literal `Duration(milliseconds:` in `lib/ui`), `AppShadows.heroCover(colorScheme)`, `AppSizes` (thumbnail sizes, `playerMainButton`, `collapseThreshold`, `maxBottomSheetHeight`), `ImageTargetSizes` (only image widgets may reference — gated). `ToastDurations` in toast service.
- **Spacing is literal**: `EdgeInsets.*(<number>)` literals are normal (68 hits / 35 files; commit says ~260). `AppSpacing` scale was **deleted**: `aa0bdd28 refactor(ui): delete the unused AppSpacing scale` ("Zero callers ... Keeping a documented, tested, unreachable constant is worse ..."). Do not reintroduce a spacing scale without migrating callers.
- Hard-coded `Colors.*`: 85 hits / 30 files, mostly `Colors.transparent`, `Colors.white/black` on image/blur overlays (player backdrop, hero app bar, lyrics window, live badge), `Colors.red` for window close hover (`custom_title_bar.dart:147`) and live badge. Semantic surfaces use `colorScheme`. No static rule.
- Windows-only font list via `Platform.isWindows` in `AppTheme.availableFonts` (`app_theme.dart:71,97`).

---

## 6. i18n (slang)

- Config `slang.yaml`: `base_locale: zh-CN`, `namespaces: true`, `input_directory: lib/i18n`, pattern `.i18n.json`, output `lib/i18n/strings.g.dart`, `lazy: false` (reason in comment: Android/Windows can't defer-load; sync `LocaleSettings` API needs all locales). Generated `strings*.g.dart` are gitignored; regenerate with `dart run slang` (not build_runner; `slang_build_runner` intentionally not used, `pubspec.yaml:97-98`). CI order: `dart format` check → `build_runner build` → `dart run slang` → `flutter analyze` → tests (`.github/workflows/ci.yml:58-72`).
- Layout: one JSON per namespace per locale: `lib/i18n/{en,zh-CN,zh-TW}/<namespace>.i18n.json`; 38 namespaces, identical file sets in all three locales (e.g. `general`, `library`, `settings`, `player`, `nav`, `error`, `tray`, `lyrics`). Namespace names are camelCase and often page/widget-named (`playHistoryPage`, `searchPage`, `addToPlaylistDialog`, `refreshProgressIndicator`, `updateProvider`). Keys camelCase, nested objects allowed (`t.settings.launchAtStartup.portableHint`, `t.settings.downloadManager.trackLoadFailed`, `t.library.importPlaylist.importFailed`).
- Adding a key = add to all three locale files for that namespace, run `dart run slang`. `dart run slang analyze` on 2026-09-25 reported zero missing and zero unused-in-secondary keys (note: it **writes** `lib/i18n/_missing_translations.json` and `_unused_translations.json`; delete them afterwards). Dead keys are removed from all three locales (`806cdf06`).
- Parameters use slang `$name` interpolation: `"$n tracks"`, `"Load failed: $error"`, `"Scanning ($current/$total)..."` (`lib/i18n/en/library.i18n.json`). Called as `t.library.loadFailedWithError(error: userMessageFor(e))`. **No plural/`(plural)`/`one/other` forms and no rich text/context features in use.**
- Access: global `t` from `package:fmp/i18n/strings.g.dart` (115 files import it) is the norm in both UI and providers/services (`t.settings` 305, `t.library` 226, `t.general` 141 …). Exception, repeated in doc+test: subtrees that must rebuild when locale loads after first frame use `context.t` (slang "Method B") — `ResponsiveScaffold` layouts (`responsive_scaffold.dart:162`), `NavDestination.label` is `String Function(Translations t)` (`responsive_scaffold.dart:21-28`). Fix `9aab6282` (#112), test `test/ui/layouts/nav_labels_locale_test.dart`.
- Locale switch order: `LocaleSettings.instance.setLocaleSync(locale)` **before** `state = locale` so rebuilt widgets see the new global `t` (`LocaleNotifier`, `locale_provider.dart`). `main.dart:147` calls `LocaleSettings.useDeviceLocaleSync()` before anything reads `t.*` (fix in `104bd8d3`: Android notification channel was created with English fallback).
- **Error templates never receive raw exceptions** — gated (§8 `error_presentation_static_rule_test.dart` `no i18n error template is filled with raw exception text`, scans all of `lib/`).
- Lyrics sub-window (separate engine) cannot use slang; main window pushes translated strings through the channel (`lib/services/lyrics/lyrics_window_service.dart:358` `'waitingLyrics': t.lyrics.windowWaitingLyrics`) into `_LyricsWindowStrings.updateFrom` with zh-CN hard-coded defaults (`lib/ui/windows/lyrics_window.dart`). One-off by necessity.
- Language display names are hard-coded native names (`'简体中文'`, `'繁體中文'`, `'English'`) in `locale_provider.dart` — intentional one-off.

---

## 7. Routing (`lib/ui/router.dart`, go_router)

- Constants: `RoutePaths` (paths, plus `playlistDetailPath(int id)` builder) and `RouteNames` (names), both private-ctor classes. Every `GoRoute` sets both `path:` and `name:`.
- Single `appRouter` `GoRouter` with `rootNavigatorKey` + `shellNavigatorKey`. Top-level tabs inside a `ShellRoute` (builder `AppShell`) use `pageBuilder: NoTransitionPage(child: const XPage())`; pushed sub-pages use `builder:` (default transition + back button), e.g. `explore`, `history`, `settings/*`, `library/downloaded`, `library/:id`. Full-screen players (`/player`, `/radio-player`) are outside the shell with `parentNavigatorKey: rootNavigatorKey` and `_fullscreenPlayerPage` slide transition.
- Navigation calls: `context.go(RoutePaths.x)` for switching tabs (`app_shell.dart:38`, `home_page.dart:353`), `context.push(RoutePaths.x)` / `context.pushNamed(RouteNames.x)` for sub-pages (both styles used, ~35 call sites). Never string literals. Path params parsed in router (`int.tryParse(state.pathParameters['id'] ?? '') ?? 0`); object args via `state.extra as DownloadedCategory` (one route).
- Nav destinations table (`destinations` in `responsive_scaffold.dart`) carries `path`; index↔path mapping lives there only (comment: previously duplicated in two switches in `app_shell.dart`). Tests: `test/ui/layouts/nav_destinations_test.dart`. Fixes `72f3b6e1`, `73e222a1` (#80).
- Adding a route: add `RoutePaths` + `RouteNames` constants, `GoRoute` under the right parent, import page in `router.dart`.

---

## 8. Windows-only UI & platform checks

- Platform detection in UI: `Platform.isWindows/isAndroid` from `dart:io` (≈20 sites, e.g. `settings_page.dart:153` Windows-only desktop section, `app.dart` `AppContentWrapper`, `immersive_player_scaffold.dart:82` `DragToMoveArea`, login pages `Platform.isAndroid` for WebView) and `isDesktopPlatform` getter (`lib/core/utils/platform_utils.dart:7`) for "desktop" capability (`mini_player.dart:96`, `player_page.dart:276,283`, `radio_player_page.dart:64,71`, `horizontal_scroll_section.dart:51`). Audio layer uses `audioRuntimePlatformProvider` (overridable in tests) instead.
- Windows desktop providers are watched only under `if (Platform.isWindows)` in `FMPApp.build` (`windowsDesktopServiceProvider`, `minimizeToTrayProvider`, `globalHotkeysEnabledProvider`, `launchAtStartupProvider`, `hotkeyConfigProvider`). `windowsDesktopServiceProvider` is `Provider<WindowsDesktopService?>` (null off-Windows). Tray/hotkeys/SMTC logic lives in `lib/services/platform/windows_desktop_service.dart`, not UI.
- Title bar: `CustomTitleBar` is built once in `AppContentWrapper` (Windows) — gated by `call_site_ownership_static_rule_test.dart` row `custom title bar` (owners: `lib/app.dart`, `custom_title_bar.dart`); pages must not add another.
- Desktop lyrics window: `main(args)` routes `args.firstOrNull == 'multi_window'` → `lyricsWindowMain` (`lib/main.dart:95-98`); separate Flutter engine via `desktop_multi_window`, no ProviderScope/slang, communicates through `WindowMethodChannel` (`lyrics_window.dart:231`, `invokeMethod('playPause'|'next'|...)`). Sub-widgets in `lib/ui/windows/lyrics/`; tests `test/ui/windows/**`. Window hides instead of destroying on close (`docs/development.md`).
- Windows AXTree pitfalls (Slider/Tooltip/OverlayPortal) — see `docs/troubleshooting.md`; do not wrap `IconButton` in `Tooltip(...)`.

---

## 9. Rules gated by static-rule tests (relevant to this scope)

All use `stripDartComments` from `test/support/dart_source.dart` and each has a "synthesised violation is caught" + "comment/format does not count" detector group (two-way mutation).

| Rule | Test | Exception list / owner table |
|---|---|---|
| Only `lib/ui/widgets/images/*` call `ImageLoadingService.loadImage/loadAvatar/imageProviderCandidates/precacheImageCandidates`, `Image.network/file`, `CachedNetworkImage(Provider)`, `NetworkImage`, `FileImage`, or reference `ImageTargetSizes` (#107) | `test/ui/static_rules/ui_consistency_static_rule_test.dart` | `_imageApiOwners` map (exact equality: 5 image widget files → set of APIs each uses) |
| No `ListTile(... leading: Row(`  | same file | none |
| No raw `Slider(` / `Slider.adaptive(` / `RangeSlider(` outside `ScopedSlider` | `test/ui/static_rules/slider_overlay_static_rule_test.dart` | `_scopedSliderPath` only |
| No whole `ref.watch(X)` for wide providers | `test/ui/static_rules/watch_scope_static_rule_test.dart` | `_narrowOnly` map (5 providers + reason) |
| Async error branch never `SizedBox.shrink()`; no `e.toString()`/`${e}` into `t.x(error: ...)` (all `lib/`) nor into `ToastService.*(`/`ErrorDisplay(` (`lib/ui`) | `test/ui/static_rules/error_presentation_static_rule_test.dart` | none |
| `FMPApp.build` watch set == anchored providers; no legacy riverpod import; Equatable `props` complete | `test/providers/static_rules/riverpod3_static_rule_test.dart` | `_anchoredProviders` map (14 + reason) |
| `sourceManagerProvider` not referenced in `lib/ui/` except import dialog; `getVideoPages(`/`buildAuthHeaders(` never in `lib/ui/`; `CustomTitleBar(` only in app.dart; playlist provider invalidation only in coordinator + home page | `test/support/call_site_ownership_static_rule_test.dart` | `_table` owners per row |
| Source-id branching (`== SourceIds.x`, `case`, `=>`) outside `lib/data/sources` is budgeted per file | `test/support/source_branch_points_static_rule_test.dart` | `_budget` (UI: `account_playlists_sheet.dart` count 3). Related refactors `65ff8644`, `d9764b75`, `e52969fb` (ask capabilities / table by source id instead of naming a source) |
| `lib/core`/`lib/data` don't import providers/services; new feature→feature edge recorded | `test/support/layer_boundary_static_rule_test.dart` | `_lowerLayerExceptions`, `_knownFeatureEdges` |
| Every `Timer.periodic`/`Stream.periodic` listed | `test/support/periodic_timer_static_rule_test.dart` | `_timers` |
| `pumpEventQueue` only via `pump_until.dart` | `test/support/wait_convention_static_rule_test.dart` | `_allowedFiles` |
| Static-rule test naming/placement | `test/support/static_rule_placement_static_rule_test.dart` | — |

**Not gated** (convention only): IconButton tooltips, `ref.mounted` after await, `context.mounted`, use of `AppRadius`/`AnimationDurations`, `ErrorDisplay` vs custom error UI (only the silent-branch half is gated), dialog helper naming, `context.t` for locale-sensitive subtrees (behavioural test exists only for nav labels), AGENTS "UI calls AudioController not FmpAudioService" (grep shows 0 `FmpAudioService`/`audioServiceProvider` refs in `lib/ui`).

---

## 10. How provider/UI tests are written

- **Provider unit tests**: `ProviderContainer(overrides: [...])` (41) + `addTearDown(container.dispose)`/`tearDown`; e.g. `test/providers/notifier_rebuild_test.dart`, `search_pagination_stale_test.dart`. Read notifier via `container.read(p.notifier)`.
- **Widget tests**: wrap as `TranslationProvider(child: ProviderScope(overrides: [...], child: MaterialApp(home: X)))` (31 files use `TranslationProvider`; 32 set `LocaleSettings.setLocale(Sync)(AppLocale.en)` in `setUp`) and assert text via `t.xxx` / `AppLocale.en.translations`, not literals. `UncontrolledProviderScope(container: ...)` when the test also needs the container (5; `ranking_ui_state_consumption_test.dart`).
- **Override styles**: `xProvider.overrideWithValue(v)` (32) for plain values/services (`currentTrackProvider.overrideWithValue(null)`, `showRadioPlaybackUiProvider.overrideWithValue(false)` to keep MiniPlayer inert); `overrideWith(...)` (85) for FutureProvider/StreamProvider bodies and for Notifiers via **test subclasses that override `build()`** — `_FixedLayoutSettings extends LayoutSettingsNotifier` (`test/ui/layouts/nav_rail_semantics_test.dart:100`), `_FixedQueueState`, `_ResultsSearchNotifier`, `_StaticAccountNotifier`, `_StubLaunchAtStartup`, `_ScriptedLyricsSearchNotifier`, `_IdlePlayHistoryPage`, `_TestAudioController extends AudioController` (`mini_player_accessibility_test.dart:208`). Family overrides per key: `trackByIdProvider(42).overrideWith(...)`.
- **Fakes** (`test/support/fakes/`): `FakeSettingsRepository` (in-memory `get/update` over a `FakeIsar`), `FakeIsar`, `FakeAudioService`, `FakeSecureKeyValueStore`, `FakeSourceAuthContext`, `secure_storage_channel.dart`, `count_waiters.dart`. Other helpers: `test/support/audio_controller_harness.dart` (`buildTestAudioController`, `buildTestAudioControllerIn` → provider overrides), `now_playing.dart` (`testNowPlayingPublisher`), `isar_test_harness.dart` (`initializeIsarForTests`; real Isar opened under `.dart_tool` inside `tester.runAsync`, closed with `deleteFromDisk: true` — `download_manager_error_state_test.dart`), `audio_settings_notifier.dart`.
- **Waiting**: `pumpUntil(condition, reason:)` for a condition false on entry, `drainEventQueue(reason:)` to assert absence (`test/support/pump_until.dart`; #43, #55) — gated. Widget tests otherwise use `tester.pump()` / `pump(Duration)` / `pumpAndSettle`.
- **Semantics tests**: `tester.ensureSemantics()` + `semantics.dispose()` in `nav_rail_semantics_test.dart`, `mini_player_accessibility_test.dart`, `custom_title_bar_test.dart`, `lyrics_window_semantics_test.dart`, `comment_pager_test.dart`.
- **Golden tests: none** (`matchesGoldenFile` not found in `test/`).
- Tests that pinned a defect are rewritten, not kept (`9557e03f`, `5e9d2929` commit bodies). Test layout mirrors `lib/ui` (`test/ui/pages/<feature>/`, `test/ui/widgets/<category>/`), though several widget tests sit flat in `test/ui/widgets/`.
- Locale-dependent tests: include a guard test that the two locales actually differ so the widget test can't pass vacuously (`nav_labels_locale_test.dart`).

---

## 11. app.dart / main.dart specifics

- `main.dart`: `runZonedGuarded` body; `LocaleSettings.useDeviceLocaleSync()` first; `_preloadSettings()` reads Isar before `runApp` to set `preloadedThemeMode/PrimaryColor/FontFamily` globals (consumed by `FMPApp` loading/error apps and `ThemeNotifier.build`); `runApp(ProviderScope(retry: ..., child: TranslationProvider(child: const FMPApp())))`; `_appStarted = true` right after (errors before that show `StartupFailureApp`, `lib/ui/startup_failure_app.dart`, fix `ad01c84d`). Background init via `addPostFrameCallback` (radio refresh service).
- `FMPApp` (`ConsumerWidget`): `databaseProvider.when(loading: MaterialApp(spinner), error: MaterialApp(message), data: MaterialApp.router(...))`; watches anchored providers (§1.5); `builder: (context, child) => AppContentWrapper(child: child)` adds Windows title bar + `NetworkStatusBanner` + route semantics container above all routes including the full-screen player.

## Caveats / Not Found

- No codegen, freezed, hooks, golden tests, or slang plurals found — reported as absent, not as rules.
- Two dialog-entry conventions and two navigation styles (`push(RoutePaths)` vs `pushNamed(RouteNames)`) coexist; no documented preference found.
- `settings_page.dart` `part` files and `networkBannerVisibleProvider` in a widget file are one-offs.
- Counts are grep-based approximations (multi-line declarations may be slightly under/over-counted).
- Side effect during research: running `dart run slang analyze --help` executed analyze and created `lib/i18n/_missing_translations.json` / `_unused_translations.json`; both were deleted immediately (git status clean for `lib/`).
