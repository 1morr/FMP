# YouTube Mix Shorthand Import Design

## Goal

Allow the music library playlist import dialog to create a YouTube Mix playlist from shorthand input such as:

```text
mix:dvgZkm1xWPE
```

The shorthand should behave like importing the equivalent YouTube Mix URL, while keeping the existing Mix playlist creation and playback behavior.

## Current State

`ImportPlaylistDialog` accepts URLs and detects whether they are internal sources or external playlist sources. Internal sources are imported through `ImportPlaylistNotifier.importFromUrl()`, which delegates to `ImportService.importFromUrl()`.

`ImportService.importFromUrl()` currently recognizes YouTube Mix only after the input is detected as a YouTube URL and `YouTubeSource.isMixPlaylistUrl(url)` returns true. Existing Mix import then calls `YouTubeSource.getMixPlaylistInfo()` and saves a `Playlist` with `isMix`, `mixPlaylistId`, and `mixSeedVideoId`.

`YouTubeSource.fetchMixTracks()` already supports loading Mix tracks with a `playlistId` and `currentVideoId`. `AudioController.playMixPlaylist()` already handles Mix playback, persistence, duplicate filtering, and loading more tracks at the queue end.

## Chosen Approach

Normalize `mix:<videoId>` shorthand in the import service layer and teach the import dialog to recognize it as YouTube.

This is preferred because:

- It reuses the existing YouTube Mix import pipeline.
- It keeps UI behavior consistent with normal YouTube playlist import.
- It makes shorthand work for any caller of `ImportService.importFromUrl()`, not just the library dialog.
- It avoids adding a parallel Mix import method.

## User-Facing Behavior

The import dialog accepts these forms:

```text
mix:dvgZkm1xWPE
MIX:dvgZkm1xWPE
  mix:dvgZkm1xWPE  
```

The prefix is case-insensitive and surrounding whitespace is ignored. The value after `mix:` is treated as a YouTube video id seed.

For future compatibility, the shorthand validator should not require exactly 11 characters. It should accept a non-empty id made of YouTube id characters:

```regex
^[A-Za-z0-9_-]+$
```

A reasonable upper length limit, such as 64 characters, should be used to reject clearly invalid input. Final validity is determined by the existing YouTube Mix fetch path.

## Data Flow

1. `ImportPlaylistDialog._onUrlChanged()` trims the input and checks for `mix:` shorthand before source URL detection.
2. When shorthand is detected and syntactically valid, the dialog sets the detected source to internal YouTube so the YouTube icon and internal import controls appear.
3. The text field validator accepts valid shorthand and rejects invalid shorthand before import starts.
4. `_startInternalImport()` passes the original trimmed shorthand to the import notifier.
5. `ImportService.importFromUrl()` normalizes valid shorthand to the equivalent YouTube Mix URL:

   ```text
   https://www.youtube.com/watch?v=<videoId>&list=RD<videoId>
   ```

6. Existing source detection sees the normalized value as YouTube.
7. Existing Mix import uses `YouTubeSource.isMixPlaylistUrl()`, `getMixPlaylistInfo()`, and `_importMixPlaylist()`.
8. The saved playlist uses the normalized YouTube Mix URL as `sourceUrl`, so importing the same Mix through shorthand and full URL maps to the same imported playlist record.

## Error Handling

- Empty `mix:` input is rejected by the dialog validator.
- `mix:` values containing characters outside `[A-Za-z0-9_-]` are rejected by the dialog validator.
- Very long values above the chosen upper limit are rejected by the dialog validator.
- YouTube API failures, unavailable seeds, and parse failures reuse the existing Mix import error flow.
- If the same Mix playlist already exists, the existing `getBySourceUrl()` behavior updates it instead of creating a duplicate.

## Implementation Boundaries

In scope:

- Add small shorthand parsing/normalization helpers near the existing import flow.
- Update `ImportPlaylistDialog` detection and validation.
- Update `ImportService.importFromUrl()` to normalize before detecting the source.
- Add or update tests for shorthand behavior.

Out of scope:

- No changes to Mix playback behavior.
- No changes to YouTube playlist parsing beyond shorthand normalization.
- No new database fields or migrations.
- No support for arbitrary YouTube search queries in the import box.

## Validation

Automated validation should cover:

- `mix:dvgZkm1xWPE` imports as a Mix playlist.
- `MIX:dvgZkm1xWPE` and whitespace-padded input work.
- Invalid shorthand is rejected.
- Normalized `sourceUrl` is used for persistence and duplicate detection.

Run `flutter analyze`. Run focused tests around import service/dialog logic if suitable tests already exist or can be added without excessive scaffolding.
