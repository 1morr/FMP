# Performance Review Instruction Corpus

This corpus is the shared documentation baseline for the performance review.
It separates instructions that should be treated as normative requirements from
descriptive implementation claims that must be checked against code before being
used as evidence.

## Discovered Current Instruction Sources

Normative agent/project instructions:

- `AGENTS.md`
- `CLAUDE.md` (`@AGENTS.md` import only)
- `lib/services/AGENTS.md`
- `lib/services/audio/AGENTS.md`
- `lib/data/AGENTS.md`
- `lib/data/sources/AGENTS.md`
- `lib/providers/AGENTS.md`
- `lib/ui/AGENTS.md`

Current project documentation referenced by `docs/README.md` and root docs:

- `README.md`
- `docs/README.md`
- `docs/development.md`
- `docs/build-guide.md`
- `docs/build-and-release.md`
- `docs/debugging-with-vm-service.md`

Supplemental Serena memories found under `.serena/memories/`:

- `.serena/memories/code_style.md`
- `.serena/memories/download_system.md`
- `.serena/memories/refactoring_lessons.md`
- `.serena/memories/ui_coding_patterns.md`
- `.serena/memories/update_system.md`

Absent or non-current instruction sources:

- `docs/agents/` is absent.
- `docs/history/refactoring-log.md` exists but `docs/README.md` and root
  `AGENTS.md` mark it as historical background only. It is not a current
  implementation authority unless a current instruction explicitly reflects it.

## Normative Requirements Relevant To Performance

Audio runtime:

- UI playback controls must call `AudioController`, not `FmpAudioService`
  directly.
- Radio is the intentional shared-backend exception and must coordinate
  ownership so `AudioController` ignores radio-owned backend events.
- Async playback paths outside `_executePlayRequest()` must increment the play
  request generation and check supersession after awaits.
- Runtime backend network errors should retry or refetch the current track URL
  from the saved position instead of blindly advancing the queue.
- Completion events from `media_kit` are not always natural song completion;
  retry should be considered when position is not close to duration.
- Desktop media_kit playback should keep `vid=no` and `sid=no` so muxed
  fallback streams do not decode video.
- Progress slider updates should seek only on `onChangeEnd`, not on every
  `onChanged`.

Download and network:

- Download path deduplication is by `savePath`, not `trackId`.
- Writes and deletes must stay inside the configured download base directory,
  and existing destination files are conflicts rather than overwrite targets.
- Audio, metadata image, cover, and avatar downloads must use the
  source-aware header helpers rather than relying on Dio defaults.
- Download progress should be kept in memory first and only written to Isar on
  completion, pause, or failure to avoid Windows PostMessage pressure and Isar
  watch churn.
- Windows downloads should run in an isolate.

Riverpod and UI rebuilds:

- DB collections with multiple writers should use Isar `watchAll()` plus
  `StateNotifier`; DB join queries should prefer `StateNotifier` plus
  optimistic update; file-system scans should use `FutureProvider` plus
  invalidation.
- Pages using `isLoading` must show loading only when `isLoading && data.isEmpty`.
- `FutureProvider` data sources must be invalidated after mutations.
- Playlist/detail/cover/download invalidation should go through
  `libraryInvalidationCoordinatorProvider`.
- Stream/Future UI that reloads because of user-sort/filter changes should keep
  previous data where appropriate to avoid visual flicker.
- List/grid rows should use stable identity keys.

Database:

- Runtime Isar files must open through `openFmpDatabase()` and live under the
  app documents directory's `FMP/` child folder.
- Schema or persisted default changes must update migration/default repair
  logic and database viewer coverage. This review makes no schema changes.
- `LyricsTitleParseCache` is a registered Isar collection but should be treated
  as an ephemeral runtime cache and cleared on startup.

Images and local files:

- UI should use `TrackThumbnail`, `TrackCover`, or `ImageLoadingService`, never
  direct `Image.network()` or `Image.file()`.
- `ImageLoadingService.loadImage()` callers should pass `width`/`height` or
  `targetDisplaySize` so platform thumbnail URL optimization can choose bounded
  sizes.
- `FileExistsCache` usage should watch the provider for invalidation, then read
  the notifier for cached path checks.
- `ThumbnailUrlUtils` is expected to optimize Bilibili, YouTube, and Netease
  image URLs by platform-specific size parameters.

UI scalability:

- Avoid composite `Row` widgets inside `ListTile.leading`; use a flat custom
  row layout when a list item needs rank plus thumbnail or other compound
  leading content.
- Repeated UI measurements and animation values should use shared constants
  when they are part of the design system or reused across pages.
- Responsive breakpoints come from `lib/core/constants/breakpoints.dart`.

## Descriptive Claims Requiring Code Verification

The following documentation statements are descriptive and were not treated as
facts until checked against implementation:

- Desktop `MediaKitAudioService` uses a 32 MB player buffer, 24 MB demuxer
  forward buffer, 8 MB back buffer, and 7200 s mpv cache/readahead.
- `JustAudioService.playUrl()` and `playFile()` should not wait on a long
  `just_audio.play()` call.
- Queue position persistence runs every 10 seconds and on seek.
- Windows downloads run in an isolate.
- Download progress is stored in memory and flushed to Isar only on terminal or
  paused states.
- `FileExistsCache` caches only existing paths and is capped at 5000 entries.
- Riverpod `FutureProvider` refreshes retain old data by default in relevant
  file-system flows.
- Isar collection providers use `watchAll()` where documentation claims they
  do.
- Playlist detail, downloaded pages, and search result pages use stable keys
  and bounded image sizes.
- Source-aware media and image headers are actually used by playback/download
  request paths.

## Review Evidence Rules

- Treat docs as requirements or claims, not as proof.
- For each issue, cite concrete code paths with line references.
- Classify each item as confirmed, suspected, or needs profiling.
- Prefer trigger scenarios that match real use: long playlists, long-running
  playback, bulk downloads, multi-source search, and desktop lyrics popup.
- Suggested fixes should identify the measurement needed before implementation
  when the impact depends on runtime data.
