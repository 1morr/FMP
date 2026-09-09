# lib/ui AGENTS.md

UI guidance for Flutter pages, widgets, layouts, and windows.

## Desktop Layout Persistence

The desktop shell's rail-expanded flag, detail-panel expanded flag and panel
width live in `Settings` and are read/written through
`layoutSettingsProvider` (`lib/providers/settings/layout_settings_provider.dart`).
`_ExpandedLayoutState` holds no copy of them — it reads the provider.

Panel width is written on drag **end**, not on every drag update: the update
path only calls `previewDetailPanelWidth`, which touches memory. Keep it that
way, or a resize writes hundreds of transactions.

**The stored width is not the rendered width.** The panel's upper bound is a
fraction of the window (`AppLayout.detailPanelMaxFor`), which the database
layer cannot see, so `repairSettingsInvariants` only rejects garbage — it
clamps to `[detailPanelMin, detailPanelStoredMax]` rather than resetting to the
default, because resetting throws away a width the user actually chose. Render
and drag both go through `AppLayout.detailPanelWidthFor`; if they ever use
different bounds, the handle drags to a width that cannot be drawn.

`detailPanelExpanded` defaults to **false** for new rows: the panel is
offered from `WindowClass.expanded` (840dp) upward, where it would take 40% of
the content. Existing rows keep whatever they stored, and the v0 migration
still rescues pre-Phase-3 rows to `true` — those users did have it open.

These three **are** in the backup (`6efcefc7`). They were dropped silently on
every import at first, with nothing in the code saying that was deliberate, so
they are now restored unconditionally rather than gated on `Platform.isWindows`
— `_ExpandedLayout` is picked by a width breakpoint, so an Android tablet in
the wide layout uses them too. `customDownloadDir` and `preferredAudioDevice*`
remain excluded: those name a path and a device on one machine.

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
components or core image services, never at page call sites.

Only part of that rule is machine-checked:
`test/ui/static_rules/ui_consistency_static_rule_test.dart` sweeps every UI file
for `ImageTargetSizes.thumbnail` and for direct `ImageLoadingService.loadAvatar(`
calls. The other tiers (`medium` / `high` / `highest`) are asserted only against
a fixed list of named widget files, so a new page using them directly would pass
CI. `lib/ui/pages`, `lib/ui/layouts` and `lib/ui/windows` currently hold zero
`ImageTargetSizes.` references — the convention holds by review, not by test.

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

## Error Presentation

**A raw exception never reaches the screen.** `e.toString()` in a toast, a
`Text`, or an i18n template's `error:` slot shows the user an untranslated Dart
or platform message — at worst literally `Exception: <server text>`. Map it
first:

| Where the exception is caught | Use |
|---|---|
| A UI handler that shows a toast | `ToastService.failure(context, e, tag: '…')` — maps *and* logs the original |
| A provider or notifier writing `state.error` | `failureMessage(e, stack, 'what failed', tag: '…')` (`lib/core/errors/user_message.dart`) |
| A `build` method rendering an `AsyncValue` error | `userMessageFor(error)` — mapping only, never log here |

`userMessageFor` knows `SourceApiException` (delegating to `sourceErrorReason`,
the one `SourceErrorKind` switch), unwrapped `DioException`, the `dart:io`
network and path exceptions and `TimeoutException`; everything else becomes
"an error occurred". Add a type there rather than special-casing a call site.

**The original always goes to `AppLogger`, never `debugPrint`** — only
`AppLogger` reaches the in-app log page, which is the one place a user can read
it back. Log where the exception is caught, not in `build`: a build branch runs
again on every rebuild.

**An async error branch must not render as nothing.** A section that vanishes
reads as "I have no data". Use `ErrorDisplay(compact: true, …)` with an
`onRetry` that invalidates the provider. Covers and avatars are the exception:
a placeholder is what a missing cover looks like, so keep it and log in the
provider that produced the error.

Both rules are machine-checked by
`test/ui/static_rules/error_presentation_static_rule_test.dart`. The
i18n-template rule scans all of `lib/`, not just `lib/ui` — the leak this round
actually shipped was in `lib/services/search/search_service.dart`.

Two deliberate exceptions, both outside `lib/ui`: `lib/app.dart` shows the raw
error on the pre-`runApp` init failure screen (the app has not started, so the
log page is unreachable and that text is the user's only clue — issue #37), and
`log_viewer_page.dart` renders `entry.error` because it *is* the log viewer.

## Accessibility

`lib/ui` is not accessible by default — assume a hand-rolled control is
invisible to a screen reader until you have proved otherwise in the semantics
tree.

- **A hand-rolled control needs explicit `Semantics`.** A bare `GestureDetector`
  produces a tap node with no role and no label, and a `CustomPaint` + `onPan`
  produces nothing at all. `IconButton`'s `tooltip:` already covers the icon
  buttons; the gap is the custom widgets.
- **A control that cannot be made 48dp still needs a non-tap route.** The mini
  player's seek bar is 2dp tall on touch (it only expands on mouse hover) and
  cannot grow without covering the player. It is exposed as
  `Semantics(container: true, slider: true, …)` with `onIncrease`/`onDecrease`,
  which are not subject to the tap-target size rule — and both of its
  `GestureDetector`s set `excludeFromSemantics: true` so no 2dp tap node
  survives. `container: true` matters: without it the annotations merge into
  the enclosing button node and you get one node that is both a button and a
  slider.
- **Announce a position, not a percentage.** Progress controls format their
  `value`/`increasedValue`/`decreasedValue` with `DurationFormatter` — the
  player page's `Slider` does the same through `semanticFormatterCallback`.
  "50%" tells the user nothing about where a seek lands.
- `test/ui/widgets/mini_player_accessibility_test.dart` renders the real
  semantics tree and asserts `meetsGuideline(androidTapTargetGuideline)` and
  `labeledTapTargetGuideline`. Both were verified to fail against a deliberate
  regression (a 20dp tap target, and a removed label). Extend that file rather
  than asserting on source text — the older `*_phase4_test.dart` files compare
  source strings, which cannot see the semantics tree at all.

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
- **Layout decides how the rankings are arranged, never which ones appear.**
  `buildHomeRankingLayoutPlan` returns every source that has data, chunked
  into rows of `columnsFor(width)`; a source that does not fit wraps
  to the next row. It used to `take(maxSources)`, which silently hid a source
  the user had enabled whenever the content container narrowed — opening the
  detail panel on a 1280dp tablet was enough. No setting caps the number of
  rankings, so nothing may drop one. Pad the last row to `columns` slots so
  its cards stay aligned with the row above.
- Playback auth toggles (`Settings.useAuthForPlay(sourceId)`, one row per
  source) belong in Audio Settings because they control stream resolution
  behavior. Keep Account pages focused on login/account state; do not
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
- **Responsive layout asks two different questions**, and
  `lib/core/constants/breakpoints.dart` answers them with two different APIs.
  Never hardcode a width literal, and never use one answer for the other
  question — mixing them is what caused P0-1 (widening the detail panel made a
  ranking source vanish).

  | Question | API | Values |
  |---|---|---|
  | What does the **window** chrome look like? | `WindowClass.of(width)`, `.atLeast(...)` | `compact` <600 (bottom nav), `medium` 600–839 (rail), `expanded` 840–1199 / `large` 1200–1599 / `extraLarge` >=1600 (collapsible rail + optional detail panel) |
  | How many columns fit in **this container**? | `columnsFor(containerWidth)` | one column per 400dp, capped at 3 |

  `responsive_scaffold.dart` picks the chrome from `MediaQuery` (the window);
  content inside measures its own `LayoutBuilder` constraints. A 1280dp window
  hands the ranking section roughly 950dp once the rail and detail panel take
  their share, so the container legitimately answers "2" where the window says
  `large` — that is correct, just never let a content-level answer *remove*
  content. There is deliberately no `LayoutType`/`isMobile`/`isTablet`/
  `isDesktop`: naming window sizes after hardware violates Flutter's *Avoid
  checking for hardware types*, and a 600dp desktop window is not a tablet.
  For OS-level desktop checks use `isDesktopPlatform`
  (`lib/core/utils/platform_utils.dart`) — do not repeat
  `Platform.isWindows || Platform.isMacOS || Platform.isLinux` or
  `defaultTargetPlatform` chains per file.

## UI Constants

Prefer shared constants from `lib/core/constants/ui_constants.dart` for repeated
or design-system values: `AppRadius`, `AppSpacing` (the 4/8/12/16/24/32 scale),
`AnimationDurations`, `AppSizes`, `ToastDurations`, `DebounceDurations`,
`AppShadows`
(`heroCover(colorScheme)` — the 120x120 hero-cover shadow token), and
`kGrayscaleColorMatrix` / `kGrayscaleColorFilter` (REC.709 luma grayscale for
desaturating cover art; the matrix is the testable source of truth, the
`ColorFilter` is what call sites consume).

Small local layout/animation literals are fine when they are one-off
measurements tied to a single widget interaction. Promote them when reused, part
of the design system, or needed across pages.

Layout sizes live in `lib/core/constants/app_layout.dart` (`AppLayout`), which
is kept free of Flutter imports so the data and migration layers can share the
detail-panel bounds with the shell. Rail widths, panel bounds, the pane spacer
and the player content/cover caps belong there, not in a page.

`AppSpacing` is **not** swept over the existing `EdgeInsets` literals:
a zero-behaviour-change diff across 260 call sites buries
real changes, and 76% of those values are already on the scale. Use it in new
code and in files you are already editing.

`AppRadius.borderRadiusXl` and similar values are `static final`, not `const` —
do not use them in `const` contexts.

## Database Viewer Maintenance

When adding, removing, or changing an Isar collection, persisted field, embedded
object, or schema registration, update
`lib/data/database/database_catalog.dart` so schema registration and the
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
- Settings is the sixth navigation destination, one above M3's suggested five.
  It was moved out once (`14c6608c`) and put back: a settings entry that scrolls
  away on phones and sits unlabelled in the rail cost more than the wider tabs
  bought. Each destination carries its own `path`, and `navIndexForLocation`
  derives the highlight from the URL — do not reintroduce positional switch
  statements in `app_shell.dart`.
- PlayHistoryPage keeps its own multi-select app bar: its selection is id-based
  (`Set<int>` history-row ids, where duplicate tracks are distinct rows) and
  cannot reuse the `Track`-based `SelectionModeAppBar` without breaking delete
  semantics.

Multi-select pages must wrap their scaffold in
`PopScope(canPop: !isSelectionMode, ...)` so the system back button exits
selection mode instead of leaving the page.

## Player Layout

- `player_page.dart` picks between three layouts through the pure
  `resolvePlayerLayout(size, hasLyrics:)`; keep the decision there rather than
  inlining conditions in `build`, and test it directly.
  `narrow` is the single-column cover/lyrics long-press toggle. `wideSplit`
  puts cover art left and lyrics right — keep track info, progress bar and
  playback controls in the left column below the cover so the lyrics column can
  use the full content height. `wideSingle` is a wide window whose track has no
  lyrics: it reuses the narrow content centred inside
  `AppLayout.playerContentMaxWide`, because a fixed `flex: 7` lyrics column
  gave 58% of the screen to one "no lyrics" line. Both dimensions matter — a
  wide but short window (landscape phone) stays `narrow`.
  Whether the lyrics pane has anything to show is
  `lyricsPaneHasContentProvider`; its branches must stay in step with
  `lyrics_display.dart`, or the layout opens a column that renders empty.
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

Anything a user can see is not verified until it has been seen. Root
`AGENTS.md` requires an on-device check on the Android emulator for UI changes;
`.claude/skills/verify-on-device/SKILL.md` is the procedure.
