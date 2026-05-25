# lib/ui AGENTS.md

UI guidance for Flutter pages, widgets, layouts, and windows.

## Image Components

- Song cover -> `TrackThumbnail` / `TrackCover`
- Avatar -> `ImageLoadingService.loadAvatar()`
- Other images -> `ImageLoadingService.loadImage()`
- Never use `Image.network()` or `Image.file()` directly.
- Pass `width`/`height` or `targetDisplaySize` to `loadImage()` so thumbnail URL
  optimization selects reliable sizes and image decoding can use bounded cache
  dimensions for both network and local files.

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

When adding, removing, or changing an Isar collection, persisted field, embedded
object, or schema registration in `database_provider.dart`, update
`lib/ui/pages/settings/database_viewer_page.dart` in the same change so the
developer database viewer remains complete.
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

## Verification

For UI changes, run focused tests under `test/ui` when available, then
`flutter analyze` for broader static coverage.
