# lib/ui AGENTS.md

UI guidance for Flutter pages, widgets, layouts, and windows.

## Widget Directory Layout

Shared widgets live in semantic subdirectories under `lib/ui/widgets/`; do not
add new `.dart` files directly under `lib/ui/widgets/`. Current folders:
`app_bars`, `controls`, `dialogs`, `feedback`, `images`, `indicators`, `layout`,
`lyrics`, `menus`, `panels`, `player`, `radio`, `track_group`, `track_tiles`.
Use `rg`/`ls` for the current inventory rather than trusting a list here.

Widgets that are easy to accidentally duplicate — check these before writing a
new one:

- `CollapsingHeroSliverAppBar` (`app_bars/`) — the shared 280dp library hero
  header used by playlist-detail and downloaded-category pages.
- `remote_playlist_dialog_widgets.dart` (`dialogs/`) — `RemotePlaylistSheetBody`,
  `RemotePlaylistSelectionListView`, and `remotePlaylistSubmitButtonText` back
  all three add-to-remote dialogs.
- `lyrics/` — `LyricsTextMeasurer`, `LyricsOffsetBar`, `LyricsOffsetMath` are
  shared between the in-app player and the desktop lyrics sub-window.
- `MiniPlayerPlayPauseButton` / `MiniPlayerDesktopControls` (both mini players),
  `AudioStreamInfoSection` (player + detail panel), `RadioDetailBody` (radio
  sheet + detail panel).

## Image Components

Image components live under `lib/ui/widgets/images/`. **Never use
`Image.network()` or `Image.file()` directly.**

| Use | Widget |
|-----|--------|
| Song cover | `TrackThumbnail` / `TrackCover` |
| Playlist cover | `PlaylistCoverImage` |
| Radio/live cover | `RadioCoverImage` |
| Home recent-play cover | `RecentPlayCoverImage` |
| Avatar | `AvatarImage` |
| Anything else | a small semantic widget wrapping `ImageLoadingService` |

Page code passes **semantic variants**, not raw `targetDisplaySize`. That
belongs inside semantic image widgets and `ImageLoadingService`. Never infer
image quality from `width`/`height` — those are layout-only. Use
`ImageTargetSizes` (`lib/core/constants/ui_constants.dart`) only inside image
components or core image services, never at page call sites; this is enforced by
`test/ui/static_rules/ui_consistency_static_rule_test.dart`.

Current target-size mapping:

| Tier | Used for |
|------|----------|
| `low` (80) | downloaded metadata avatars only |
| `thumbnail` (160) | UI avatars, list-track tiles, radio compact images |
| `medium` (400) | card-size covers ~100–140dp (recent-play, radio station, playlist compact/dialog, card-size track covers) |
| `high` (720) | home/library playlist cards ~200dp, player blurred backdrops, downloaded metadata covers |
| `fullscreen` (960) | large panel/detail-dialog covers ~460dp, radio hero |
| `highest` (1280) | player cover art, radio fullscreen cover art, playlist-detail hero backgrounds |

Downloaded metadata images use the same semantics as UI (covers `high`, avatars
`low`). Do not introduce a separate download image quality enum unless product
requirements actually diverge.

Pipeline: semantic widget -> `ImageLoadingService` -> local file, then optimized
network URL candidates with source-specific headers, then placeholder. Network
images use `NetworkImageCacheService` for shared memory/disk cache.
`ImageLoadingService` uses the current `MediaQuery.devicePixelRatio` for decode
and disk-cache sizing **only** — URL candidate selection is controlled by the
semantic widget's target size. URL optimization rules live in
`lib/services/AGENTS.md` § Image Thumbnail Optimization.

File existence cache pattern:

```dart
ref.watch(fileExistsCacheProvider); // watch for changes
final cache = ref.read(fileExistsCacheProvider.notifier);
final localPath = track.getLocalCoverPath(cache);
```

Shared thumbnail widgets may use `.select(...)` to watch only the relevant local
path state.

## Provider Watch Scope

- Prefer `.select(...)` for UI needing only a few fields from a large state
  object, especially audio volume/device controls and ranking cache
  error/loading flags.
- Keep long-list rows keyed by stable source/task/group identity so insertions,
  expansion, progress updates, and section changes do not churn element state.
- Cache expensive derived lists inside a build method when the same getter is
  used several times in one frame; move it into provider/notifier state only
  after profiling shows the getter is a hot path.

## Play State

```dart
final currentTrack = ref.watch(currentTrackProvider);
final isPlaying = currentTrack != null &&
    currentTrack.sourceId == track.sourceId &&
    currentTrack.pageNum == track.pageNum;
```

Use a stronger key when the page has a more precise track identity, such as
`groupKey` or downloaded path.

## Track Actions

- Reference `ExplorePage` or `HomePage` `_handleMenuAction` for single-track
  menu flows.
- Common track actions must use `buildCommonTrackActionMenuItems()` /
  `buildTrackActionPopupMenuEntries()` and dispatch through
  `TrackActionCoordinator`.
- Page-specific actions (download, delete, remove-from-playlist,
  remove-from-remote, group actions) are appended/injected locally instead of
  duplicating the common queue/playlist/lyrics/remote actions.
- Destructive menu entries must render in `colorScheme.error`: use
  `buildDestructivePopupMenuItem()` (`lib/ui/handlers/track_action_menu.dart`)
  for one-offs, or `TrackActionMenuItem(destructive: true)` inside
  `buildTrackActionPopupMenuEntries(destructiveColor:)`.
- When the same actions appear in both a right-click context menu and a
  long-press bottom sheet, define them once as `List<MenuAction>`
  (`lib/ui/widgets/menus/menu_action.dart`) and render via
  `buildMenuActionPopupEntries()` / `buildMenuActionListTiles()`.
- Multi-select overflow menus use the shared `buildSelectionMenuEntries()`
  (`lib/ui/widgets/menus/selection_menu_items.dart`), which backs both
  `SelectionModeAppBar` and the playlist-detail selection bar.

## Toast / SnackBar

All snackbars go through `ToastService`
(`lib/core/services/toast_service.dart`). Never call
`ScaffoldMessenger.showSnackBar` directly from UI code.
`ToastService.buildSnackBar()` is the single construction entry (floating,
semantic type color, white icon/text); error/warning default to
`ToastDurations.long`, everything else to `ToastDurations.short`.

Do not pass `duration` for ordinary toasts — the type decides, which keeps
timing uniform across the app. Reserve the override for long-read content only
(e.g. the backup export path toast) and add a comment when you use it.
Background services emit through the toast stream; `AppShell` renders those with
the same builder.

## Destructive Confirmations

Delete/clear confirmations must use `showConfirmDestructiveDialog()`
(`lib/ui/widgets/dialogs/confirm_destructive_dialog.dart`), which renders the
confirm button as a `FilledButton` with `colorScheme.error`. Do not hand-roll
AlertDialogs with plain `TextButton` or primary-colored confirm buttons for
destructive actions.

## Refresh And Provider Invalidation

Use `RefreshIndicator` + `ref.invalidate()` or cache service refresh APIs.
Downloaded/library flows often use explicit invalidation/buttons instead of
pull-to-refresh; follow existing page behavior. Cross-family invalidation goes
through `libraryInvalidationCoordinatorProvider` — see `lib/providers/AGENTS.md`.

## Settings And Home Rankings

- Home ranking UI is source-configurable. Use
  `enabledHomeRankingSourceOrderProvider` for display order, keep malformed
  empty settings from producing an empty header, and keep the settings UI from
  disabling the final enabled ranking source.
- Playback auth toggles (`useBilibiliAuthForPlay`, `useYoutubeAuthForPlay`,
  `useNeteaseAuthForPlay`) belong in Audio Settings because they control stream
  resolution behavior. Keep Account pages focused on login/account state; do not
  add per-platform auth-for-play buttons there.
- `lib/ui/pages/settings/settings_page.dart` owns the top-level settings layout.
  Keep feature-specific tiles in its `part` files under
  `lib/ui/pages/settings/widgets/settings_*.dart`, grouped by section
  (`appearance`, `playback`, `cache`, `storage`, `desktop`, `backup`, `about`).
  Use this split for private settings-page-only widgets; promote reusable
  widgets to `lib/ui/widgets/`.

## Layout Conventions

- **AppBar actions**: end the list with `const SizedBox(width: 8)` when the last
  action is an `IconButton`. `PopupMenuButton` has built-in padding, so the
  spacer is optional there and should be used only when that app bar needs an
  explicit trailing gutter to match nearby actions.
- **ListTile performance**: avoid `Row` inside `ListTile.leading` — it causes
  layout jitter. Use flat `InkWell` + `Padding` + `Row` instead. Enforced by
  `test/ui/static_rules/list_tile_leading_static_rule_test.dart`; fix existing
  exceptions when touching the affected page unless there is a clear layout
  reason to keep them.
- **Responsive breakpoints** — source of truth
  `lib/core/constants/breakpoints.dart`: mobile `< 600dp` (bottom nav), tablet
  `600–1200dp` (side nav), desktop `>= 1200dp` (collapsible side nav + optional
  detail panel). Never hardcode `600`/`1200`; use `Breakpoints.isMobile` /
  `isTablet` / `isDesktop`. For OS-level desktop checks use `isDesktopPlatform`
  (`lib/core/utils/platform_utils.dart`) — do not repeat
  `Platform.isWindows || Platform.isMacOS || Platform.isLinux` or
  `defaultTargetPlatform` chains per file.

## UI Constants

Prefer shared constants from `lib/core/constants/ui_constants.dart` for repeated
or design-system values: `AppRadius`, `AnimationDurations`, `AppSizes`,
`ToastDurations`, `DebounceDurations`, `AppShadows`
(`heroCover(colorScheme)` — the 120x120 hero-cover shadow token), and
`kGrayscaleColorMatrix` / `kGrayscaleColorFilter` (REC.709 luma grayscale for
desaturating cover art; the matrix is the testable source of truth, the
`ColorFilter` is what call sites consume).

Small local layout/animation literals are fine when they are one-off
measurements tied to a single widget interaction. Promote them when reused, part
of the design system, or needed across pages.

`AppRadius.borderRadiusXl` and similar values are `static final`, not `const` —
do not use them in `const` contexts.

## Database Viewer Maintenance

When adding, removing, or changing an Isar collection, persisted field, embedded
object, or schema registration, update
`lib/providers/database/database_catalog.dart` so schema registration and the
developer database viewer stay in sync. Keep
`lib/ui/pages/settings/database_viewer_page.dart` as a generic catalog-backed
viewer shell. Settings persisted fields and debug getters should also be covered
by the coverage test:

```bash
flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart
```

## Page Conventions

These are deliberate — do not "fix" them:

- HomePage is intentionally an AppBar-less dashboard; the other five top-level
  destinations have titled AppBars.
- ExplorePage is a pushed sub-page (default slide transition, automatic back
  button) entered from Home; the bottom-nav highlight staying on Home while
  inside it is intended, same as PlayHistoryPage.
- PlayHistoryPage keeps its own multi-select app bar: its selection is id-based
  (`Set<int>` history-row ids, where duplicate tracks are distinct rows) and
  cannot reuse the `Track`-based `SelectionModeAppBar` without breaking delete
  semantics.

Multi-select pages must wrap their scaffold in
`PopScope(canPop: !isSelectionMode, ...)` so the system back button exits
selection mode instead of leaving the page.

## Player Layout

- `player_page.dart` uses a single-column cover/lyrics toggle on narrow layouts.
  On desktop widths it shows cover art left and lyrics right; keep track info,
  progress bar, and playback controls in the left column below the cover so the
  lyrics column can use the full content height.
- Player backgrounds use the current track cover as a single full-page blurred
  backdrop at all widths. Keep the player AppBar transparent and embedded inside
  the same immersive body `Stack`, with only its overlay/drag region above the
  shared backdrop. **Do not use `Scaffold.appBar` for these fullscreen player
  AppBars** — route transitions can expose separate Scaffold paint regions. When
  tracks change, keep the previous loaded backdrop visible until the next cover
  has been preloaded, to avoid flashing a placeholder background. The radio
  player uses the same behavior with the station cover.
- The fullscreen music and radio players share their immersive shell via
  `lib/ui/widgets/layout/immersive_player_scaffold.dart`
  (`ImmersivePlayerScaffold`): the full-page `Stack`, the floating transparent
  AppBar (with Windows drag region), the backdrop overlay tints, and the four
  overlay alpha constants live there. Each page supplies its `backdrop`
  (`TrackBlurredBackdrop` / `RadioBlurredBackdrop`), `appBarActions`, `body`,
  and `colorScheme`. Do not re-add a private immersive Stack, alpha constants,
  or AppBar overlay to either page.
- They also share controls via `lib/ui/widgets/player/`:
  `CompactVolumeControl`, `FmpAudioDeviceSelector`, `PlayerPlayPauseButton`, and
  `CoverArtContainer`. Change volume, audio-device, play/pause, and the
  cover-art frame there rather than re-adding private copies. The radio player
  exposes jump-to-latest (`RadioController.sync()`, `Icons.sync`) and reload
  (`RadioController.reload()`, `Icons.refresh`) as control-row buttons flanking
  play/pause; both disable on `isBuffering || isLoading || !isPlaying`.
- Both mini players share `MiniPlayerVolumeControl` (narrow popup + wide inline
  variants, same slider spec as `CompactVolumeControl`) and
  `FmpAudioDeviceSelector` driven by `desktopAudioDeviceStateProvider`. Do not
  re-add private volume/device menus. Music mini player control order matches
  the fullscreen player (shuffle, previous, play, next, loop).
- Both fullscreen players expose track/station info through a standalone AppBar
  info `IconButton`; do not tuck it back into the overflow menu. Control-row
  buttons should have tooltips.
- Fullscreen player routes in `lib/ui/router.dart` use the shared
  `_fullscreenPlayerPage` transition helper, so entry uses the slower settling
  curve while dismissal uses a fast reverse curve and clips blurred paint at the
  route boundary.
- The Windows custom title bar and network banner are owned by the app-level
  wrapper in `lib/app.dart`, not individual pages or responsive content layouts.

## Desktop Sub-Windows

Desktop sub-window UI (e.g. the lyrics window) is built from public,
data-injected leaf widgets under `lib/ui/windows/<feature>/` with widget tests,
instead of inlining build methods in a giant `State`. Keep all `window_manager` /
`desktop_multi_window` side effects and channel calls injected as callbacks so
the leaves can be pumped in `flutter_test` without the plugin engine. See
`lib/ui/windows/lyrics/` (empty / line / title-bar / single-line leaves, plus
`LyricsDisplayMode`) for the established pattern.

## Verification

Run focused tests under `test/ui` when available, then `flutter analyze` for
broader static coverage.
