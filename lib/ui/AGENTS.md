# lib/ui AGENTS.md

UI guidance for Flutter pages, widgets, layouts, and windows.

## Widget Directory Layout

Shared widgets live in semantic subdirectories under `lib/ui/widgets/`; do not
add new `.dart` files directly under `lib/ui/widgets/`.

Current folders:
- `app_bars/` - app-level bars such as custom title bars and selection bars.
- `controls/` - reusable controls such as color pickers and compound toggles.
- `dialogs/` - shared dialog widgets.
- `feedback/` - error and app-status feedback surfaces.
- `images/` - semantic image loading widgets.
- `indicators/` - compact state indicators and badges.
- `layout/` - reusable layout sections.
- `lyrics/` - lyrics display and lyrics styling widgets.
- `menus/` - menu/action helpers.
- `panels/` - large persistent panels such as `TrackDetailPanel`.
- `player/`, `radio/`, `track_group/` - domain-specific widget groups.

## Image Components

Image components live under `lib/ui/widgets/images/`.

- Song cover -> `TrackThumbnail` / `TrackCover`
- Playlist cover -> `PlaylistCoverImage`
- Radio/live cover -> `RadioCoverImage`
- Home recent-play cover -> `RecentPlayCoverImage`
- Avatar -> `AvatarImage`
- Other images -> a small semantic widget wrapping `ImageLoadingService`.
- Never use `Image.network()` or `Image.file()` directly.
- Page code should pass semantic variants, not raw `targetDisplaySize`.
  `targetDisplaySize` belongs inside semantic image widgets and
  `ImageLoadingService`; never infer image quality from `width` or `height`,
  which are layout-only. Use `ImageTargetSizes` from
  `lib/core/constants/ui_constants.dart` only inside image components or core
  image services, not page call sites.
- Current target-size mapping: `low` is only for avatars through
  `AvatarImage`; `medium` is the default for compact non-avatar images;
  `high` is for home playlist/radio/recent-play cards, radio list pages,
  library pages, and player blurred backdrop preloading; `highest` is for
  player cover art, radio player cover art,
  playlist-detail backgrounds, and Detail Panel large images.
- Image pipeline: semantic image widget -> `ImageLoadingService` -> local file,
  then optimized network URL candidates with source-specific headers, then
  placeholder. Network images use `NetworkImageCacheService` for shared memory
  and disk cache management.
- Downloaded metadata images use the same `ImageTargetSizes` semantics as UI:
  covers use `high`, avatars use `low`. Do not introduce a separate download
  image quality enum unless the product requirements actually diverge.
- `ImageLoadingService` should use the current `MediaQuery.devicePixelRatio`
  for decode and disk-cache sizing only. URL candidate selection is controlled
  by the semantic widget's target size; use larger variants for covers and
  backgrounds that must stay sharp when scaled or blurred.

File existence cache pattern:

```dart
ref.watch(fileExistsCacheProvider); // watch for changes
final cache = ref.read(fileExistsCacheProvider.notifier);
final localPath = track.getLocalCoverPath(cache);
```

Shared thumbnail widgets may use `.select(...)` to watch only the relevant local
path state.

## Provider Watch Scope

- Prefer `.select(...)` for UI that only needs a few fields from a large state
  object, especially audio volume/device controls and ranking cache error/loading
  flags.
- Keep long-list rows keyed by stable source/task/group identity so insertions,
  expansion, progress updates, and section changes do not churn element state.
- Cache expensive derived lists inside a build method when the same getter is
  used multiple times in one frame; move it into provider/notifier state only
  after profiling shows the getter itself is a hot path.

## Play State

Default unified logic:

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
- Page-specific actions such as download, delete, remove-from-playlist,
  remove-from-remote, and group actions should be appended/injected locally
  instead of duplicating common queue/playlist/lyrics/remote actions.

## Refresh And Provider Invalidation

Use `RefreshIndicator` + `ref.invalidate()` or cache service refresh APIs.
Downloaded/library flows often use explicit invalidation/buttons instead of
pull-to-refresh; follow existing page behavior.

## Home Rankings

Home ranking UI is source-configurable. Use
`enabledHomeRankingSourceOrderProvider` for display order, keep malformed empty
settings from producing an empty header, and keep the settings UI from disabling
the final enabled ranking source.

## Settings Boundaries

Playback auth toggles (`useBilibiliAuthForPlay`, `useYoutubeAuthForPlay`,
`useNeteaseAuthForPlay`) belong in Audio Settings because they control stream
resolution behavior. Keep Account pages focused on login/account state and do
not add per-platform auth-for-play buttons there.

`lib/ui/pages/settings/settings_page.dart` owns the top-level settings page
layout. Keep feature-specific settings tiles in its `part` files under
`lib/ui/pages/settings/widgets/settings_*.dart`, grouped by section
(`appearance`, `playback`, `cache`, `storage`, `desktop`, `backup`, `about`).
Use this split for private settings-page-only widgets; promote reusable widgets
to `lib/ui/widgets/` instead.

## AppBar Actions

All `AppBar` actions lists should end with `const SizedBox(width: 8)` when the
last action is an `IconButton`. `PopupMenuButton` has built-in padding, so the
spacer is optional and should be used only when that app bar needs an explicit
trailing gutter to match nearby actions.

## ListTile Performance

Avoid `Row` inside `ListTile.leading`; it causes layout jitter. Use flat
`InkWell` + `Padding` + `Row` instead. Existing exceptions should be fixed when
touching the affected page unless there is a clear layout reason to keep them.

## UI Constants

Prefer shared constants from `lib/core/constants/ui_constants.dart` for repeated
or design-system values:
- `AppRadius`
- `AnimationDurations`
- `AppSizes`
- `ToastDurations`
- `DebounceDurations`

Small local layout/animation literals are acceptable when they are one-off
measurements tied to a single widget interaction. Promote them to
`ui_constants.dart` when reused, part of the design system, or needed across
pages.

`AppRadius.borderRadiusXl` and similar values are `static final`, not `const`;
do not use them in `const` contexts.

## Database Viewer Maintenance

When adding, removing, or changing an Isar collection, persisted field,
embedded object, or schema registration, update
`lib/providers/database/database_catalog.dart` so schema registration and the
developer database viewer stay in sync. Keep
`lib/ui/pages/settings/database_viewer_page.dart` as a generic catalog-backed
viewer shell.
Settings persisted fields and debug getters should also be covered by the
database viewer coverage test.

Run:

```bash
flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart
```

## Responsive Breakpoints

Source of truth: `lib/core/constants/breakpoints.dart`.

- Mobile: `< 600dp` (bottom navigation)
- Tablet: `600-1200dp` (side navigation)
- Desktop: `>= 1200dp` (collapsible side navigation + optional detail panel)

## Player Layout

- `lib/ui/pages/player/player_page.dart` should use a single-column cover/lyrics
  toggle on narrow layouts.
- On desktop widths, the player page should show cover art on the left and
  lyrics on the right. Keep track info, progress bar, and playback controls in
  the left column below the cover so the lyrics column can use the full content
  height.
- Player backgrounds should use the current track cover as a single full-page
  blurred backdrop on all widths. Keep the player AppBar transparent and embed
  it inside the same immersive body Stack, with only its overlay/drag region
  above that shared backdrop; do not use `Scaffold.appBar` for these fullscreen
  player AppBars because route transitions can expose separate Scaffold paint
  regions. When tracks change, keep the previous loaded backdrop visible until
  the next cover has been preloaded to avoid flashing a placeholder background.
- Radio player backgrounds should use the current station cover through the same
  single full-page blurred-backdrop behavior as the main player.
- Fullscreen player routes in `lib/ui/router.dart` should use the shared
  `_fullscreenPlayerPage` transition helper so entry uses the slower settling
  curve while dismissal uses a fast reverse curve and clips blurred paint at the
  route boundary.
- Windows custom title bar and network banner are owned by the app-level
  wrapper in `lib/app.dart`, not individual pages or responsive content layouts.

## Verification

For UI changes, run focused tests under `test/ui` when available, then
`flutter analyze` for broader static coverage.
