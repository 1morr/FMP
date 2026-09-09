# lib/ui AGENTS.md

Pages, widgets, layouts and windows.

Layout reasoning lives with the code that implements it: `breakpoints.dart` for
the two responsive questions, `app_layout.dart` for panel and player bounds,
`player_page.dart` for the three player layouts, `immersive_player_scaffold.dart`
for the shared fullscreen shell. Read those rather than a second copy here.

## Widget Directory Layout

Shared widgets live in semantic subdirectories under `lib/ui/widgets/` — image
widgets in `images/`, the rest by role — and `lib/providers/` has the same
shape; neither directory holds a loose `.dart` file. Use `rg`/`ls` for the
inventory. This is a convention, not a test: a directory listing frozen into an
assertion goes stale on the first legitimate new subdirectory.

Several widgets already serve two callers that do not look related, so they are
easy to rewrite by accident: the library hero header (`app_bars/`), the
add-to-remote dialog bodies (`dialogs/`), everything under `lyrics/` (shared
with the desktop sub-window) and everything under `player/` (shared by both
fullscreen players and both mini players). `rg` for a widget before writing one.

Do not re-add a private immersive `Stack`, alpha constants, AppBar overlay,
volume menu or device menu to either player page.

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

Page code passes **semantic variants**, not raw `targetDisplaySize`. Never infer
image quality from `width`/`height` — those are layout-only. Use
`ImageTargetSizes` only inside image components or core image services, never at
page call sites.

Only part of that is machine-checked: `ui_consistency_static_rule_test.dart`
sweeps every UI file for `ImageTargetSizes.thumbnail` and direct
`ImageLoadingService.loadAvatar(` calls, while the other tiers are asserted only
against a fixed list of named widget files. A new page using them directly would
pass CI. `lib/ui/pages`, `layouts` and `windows` currently hold zero
`ImageTargetSizes.` references — that convention holds by review, not by test.

Current tier mapping:

| Tier | Used for |
|------|----------|
| `low` (80) | downloaded metadata avatars only |
| `thumbnail` (160) | UI avatars, list-track tiles, radio compact images |
| `medium` (400) | card-size covers ~100–140dp |
| `high` (720) | ~200dp playlist cards, player blurred backdrops, downloaded metadata covers |
| `fullscreen` (960) | large panel/detail-dialog covers ~460dp, radio hero |
| `highest` (1280) | player cover art, radio fullscreen cover, playlist-detail hero |

Downloaded metadata images use the same semantics. Do not introduce a separate
download image quality enum unless product requirements diverge.

`ImageLoadingService` uses `MediaQuery.devicePixelRatio` for decode and
disk-cache sizing **only** — candidate selection is the semantic widget's target
size. URL rules: `lib/services/AGENTS.md` § Image Thumbnail Optimization.

## Error Presentation

**A raw exception never reaches the screen.** `e.toString()` in a toast, a
`Text`, or an i18n template's `error:` slot shows an untranslated Dart or
platform message — at worst literally `Exception: <server text>`. Map it first:

| Where the exception is caught | Use |
|---|---|
| A UI handler showing a toast | `ToastService.failure(context, e, tag: '…')` — maps *and* logs the original |
| A provider/notifier writing `state.error` | `failureMessage(e, stack, 'what failed', tag: '…')` |
| A `build` rendering an `AsyncValue` error | `userMessageFor(error)` — mapping only, never log here |

`userMessageFor` knows `SourceApiException` (delegating to `sourceErrorReason`,
the one `SourceErrorKind` switch), unwrapped `DioException`, the `dart:io`
network and path exceptions, and `TimeoutException`; everything else becomes "an
error occurred". Add a type there rather than special-casing a call site.

**The original always goes to `AppLogger`, never `debugPrint`** — only
`AppLogger` reaches the in-app log page, the one place a user can read it back.
Log where the exception is caught, not in `build`: a build branch runs again on
every rebuild.

**An async error branch must not render as nothing.** A section that vanishes
reads as "I have no data". Use `ErrorDisplay(compact: true, …)` with an `onRetry`
that invalidates the provider. Covers and avatars are the exception — a
placeholder is what a missing cover looks like — so keep it and log in the
provider that produced the error.

Both rules are machine-checked by `error_presentation_static_rule_test.dart`.
The i18n-template rule scans all of `lib/`, not just `lib/ui`: the leak that
actually shipped was in a service.

Two deliberate exceptions, both outside `lib/ui`: `lib/app.dart` shows the raw
error on the init-failure screen (the log page is unreachable while startup
providers are still failing, so that text is the user's only clue), and
`log_viewer_page.dart` renders `entry.error` because it *is* the log viewer.
Neither covers an exception thrown before `runApp()` — that case still has no
window at all (issue #37).

## Accessibility

`lib/ui` is not accessible by default — assume a hand-rolled control is
invisible to a screen reader until you have proved otherwise in the semantics
tree.

- **A hand-rolled control needs explicit `Semantics`.** A bare `GestureDetector`
  produces a tap node with no role and no label, and a `CustomPaint` with a pan
  handler produces nothing at all. `IconButton`'s `tooltip:` already covers the
  icon buttons; the gap is the custom widgets.
- **A control that cannot be 48dp still needs a non-tap route.** The mini
  player's seek bar is 2dp tall on touch and cannot grow without covering the
  player, so it is exposed as a slider with `onIncrease`/`onDecrease`, which are
  not subject to the tap-target size rule — and its `GestureDetector`s set
  `excludeFromSemantics: true` so no 2dp tap node survives. `container: true`
  matters: without it the annotations merge into the enclosing button node and
  you get one node that is both a button and a slider.
- **Announce a position, not a percentage** — progress controls format with
  `DurationFormatter`, because "50%" says nothing about where a seek lands.
- `mini_player_accessibility_test.dart` renders the real semantics tree and was
  verified against a deliberate regression. Extend it rather than asserting on
  source text, which cannot see the tree at all.

## Track Actions

- Common track actions go through the shared builders and dispatch through
  `TrackActionCoordinator`; page-specific actions are appended locally rather
  than duplicating the common set. Multi-select overflow menus use
  `buildSelectionMenuEntries()`, which backs both selection bars.
- Destructive menu entries render in `colorScheme.error`.
- When the same actions appear in both a context menu and a long-press sheet,
  define them once as `List<MenuAction>` and render via the shared builders —
  the two surfaces drifted apart when they were written separately.

## Toast, Dialogs And Refresh

- All snackbars go through `ToastService`; never call
  `ScaffoldMessenger.showSnackBar` directly. `buildSnackBar()` is the single
  construction entry. **Do not pass `duration` for ordinary toasts** — the type
  decides, which keeps timing uniform. Reserve the override for long-read
  content and add a comment when you use it.
- Delete/clear confirmations use `showConfirmDestructiveDialog()`. Do not
  hand-roll AlertDialogs with a plain or primary-coloured confirm button for
  destructive actions.
- Cross-family invalidation goes through
  `libraryInvalidationCoordinatorProvider`, never a hand-listed set of
  providers.

## Watch Scope

Long-list rows are keyed by stable source/task/group identity, not by index, so
insertion and progress updates do not churn element state. "Is this track
playing" compares source identity for the same reason — use a stronger key
(`groupKey`, downloaded path) where the page has one.

## Settings And Home Rankings

- **Layout decides how the rankings are arranged, never which ones appear.**
  `buildHomeRankingLayoutPlan` returns every source that has data, chunked into
  rows; a source that does not fit wraps to the next row. It used to
  `take(maxSources)`, which silently hid a source the user had enabled whenever
  the content container narrowed — opening the detail panel on a 1280dp tablet
  was enough. No setting caps the number of rankings, so nothing may drop one.
- Keep malformed empty settings from producing an empty header, and keep the
  settings UI from disabling the final enabled source.
- Playback auth toggles belong in Audio Settings because they control stream
  resolution. Keep Account pages focused on login state.
- `settings_page.dart` owns the top-level layout; feature tiles stay in its
  `part` files. Promote reusable widgets to `lib/ui/widgets/`.

## Layout Conventions

- **AppBar actions**: end the list with `const SizedBox(width: 8)` when the last
  action is an `IconButton`. `PopupMenuButton` has built-in padding.
- **ListTile performance**: avoid `Row` inside `ListTile.leading` — it causes
  layout jitter. Use flat `InkWell` + `Padding` + `Row`. Enforced by
  `ui_consistency_static_rule_test.dart`.
- **Never hardcode a width literal, and never answer one responsive question
  with the other's API.** `WindowClass.of(width)` describes the *window* chrome;
  `columnsFor(containerWidth)` describes how many columns fit *this container*.
  `responsive_scaffold.dart` picks chrome from `MediaQuery`; content measures
  its own `LayoutBuilder`. A content-level answer may rearrange content, never
  remove anything the user can no longer reach — a ranking source, a list row, a
  destination. Secondary decoration *on* a row may step aside: `RankingTrackTile`
  drops the play-count group below its own threshold width, because the
  alternative was an overflow stripe and a two-character artist name (#85). The
  number comes back the moment there is room, and the row itself never moves.
- **The collapsed navigation rail scrolls.** Six destinations with
  `labelType: all` plus the expand button need about 540dp; a landscape phone
  gives about 411dp and Windows' minimum window is 500dp. `CollapsedNavRail`
  (`responsive_scaffold.dart`, shared by the tablet and desktop-collapsed
  layouts) uses `NavigationRail.scrollable` with the expand button as a pinned
  `leading`. Do not put it back into an outer `Column` + `Expanded`: that pushes
  Settings — the one destination with no other entry point — off-screen
  entirely, which is a functional failure, not a visual one (#84).
- There is deliberately no `LayoutType`/`isMobile`/`isTablet`/`isDesktop`:
  naming window sizes after hardware violates Flutter's *Avoid checking for
  hardware types*, and a 600dp desktop window is not a tablet. For OS-level
  desktop checks use `isDesktopPlatform` — do not repeat `Platform.isWindows ||
  …` or `defaultTargetPlatform` chains per file.

## UI Constants

Prefer the shared constants in `lib/core/constants/ui_constants.dart` for
repeated or design-system values, and `app_layout.dart` (kept free of Flutter
imports so the data and migration layers can share the panel bounds) for layout
sizes. Rail widths, panel bounds, the pane spacer and the player caps belong
there, not in a page.

Small local layout/animation literals are fine when they are one-off
measurements tied to a single widget interaction. There is deliberately **no**
spacing scale constant: one existed, nothing in `lib/` ever called it, and the
260 `EdgeInsets` literals stayed as they were. Do not reintroduce one without
migrating the call sites in the same change.

`AppRadius.borderRadiusXl` and similar are `static final`, not `const` — do not
use them in `const` contexts.

## Page Conventions

These are deliberate — do not "fix" them:

- HomePage is intentionally an AppBar-less dashboard; the other five top-level
  destinations have titled AppBars.
- ExplorePage is a pushed sub-page entered from Home; the bottom-nav highlight
  staying on Home while inside it is intended, same as PlayHistoryPage.
- Settings is the sixth navigation destination, one above M3's suggested five.
  It was moved out once (`14c6608c`) and put back: a settings entry that scrolls
  away on phones and sits unlabelled in the rail cost more than the wider tabs
  bought. Each destination carries its own `path` and `navIndexForLocation`
  derives the highlight from the URL — do not reintroduce positional switch
  statements in `app_shell.dart`.
- PlayHistoryPage keeps its own multi-select app bar: its selection is id-based
  (duplicate tracks are distinct rows) and cannot reuse the `Track`-based
  `SelectionModeAppBar` without breaking delete semantics.

Multi-select pages wrap their scaffold in `PopScope(canPop: !isSelectionMode)`
so the system back button exits selection mode instead of leaving the page.

## Desktop Sub-Windows

Sub-window UI is built from public, data-injected leaf widgets under
`lib/ui/windows/<feature>/`, not inlined into a giant `State`. Keep every
`window_manager` / `desktop_multi_window` side effect injected as a callback so
the leaves can be pumped in `flutter_test` without the plugin engine.
`lib/ui/windows/lyrics/` is the pattern.

## Database Viewer

Changing an Isar collection, persisted field, embedded object or schema
registration means updating `database_catalog.dart` — registration and the
developer viewer read the same catalog, and `database_viewer_page.dart` stays a
generic shell over it.
