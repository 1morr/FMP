# lib/services AGENTS.md

Service-layer guidance. For audio-specific rules, also read
`lib/services/audio/AGENTS.md`.

## Download System

- Path deduplication is by `savePath`, not `trackId`.
- Verify the file exists before saving the downloaded path.
- Downloads run in an isolate on all platforms and progress is kept in memory
  first. This avoids Windows PostMessage queue overflow and Isar watch churn
  while keeping the main isolate responsive.
- Download progress is flushed to Isar on completion, pause, failure, and app
  disposal. Pause/failure paths must preserve the latest pending in-memory
  progress tuple before clearing task state.
- Audio, metadata, cover, and avatar live inside each video folder:
  - `audio.m4a` or `P{NN}.m4a`
  - `metadata.json` or `metadata_P{NN}.json`
  - `cover.jpg`
  - `avatar.jpg`
- Download path components, including restored `Track.sourceId`, must be
  sanitized before path construction. Write/delete paths must stay inside the
  configured download base, and existing destination files must be treated as a
  conflict rather than overwritten.
- Audio downloads and downloaded metadata images must use
  `buildDownloadMediaHeaders()` / `buildDownloadImageHeaders()` so Bilibili,
  YouTube, and Netease keep the correct source Referer/Origin/UA/auth policy.
  Media headers are URL-aware; only allowlisted HTTPS Netease media URLs may
  receive `MUSIC_U`, and image downloads must not include Netease cookies.
- Downloaded metadata cover/avatar images should use
  `ThumbnailUrlUtils.getOptimizedUrlCandidates()` with a bounded display size
  before falling back to the original URL. Cover downloads use larger candidates
  than avatars; keep avatar downloads small.
- Do not rely on `DownloadService` Dio defaults for source-specific headers.
- Isolate media downloads must apply both connection timeout and receive/idle
  timeout so a stalled response cannot hold a download slot forever.
- Android custom download directories require storage permission
  (`MANAGE_EXTERNAL_STORAGE` on Android 11+).
- Default Android base dir is `Music/FMP` via external storage fallback logic.
- Storage permission checks use the app-owned Android MethodChannel in
  `StoragePermissionService`, not `permission_handler`, so Windows builds do not
  register `permission_handler_windows` and trigger the system location
  indicator.

## Lyrics System

Auto-match priority in `LyricsAutoMatchService.tryAutoMatch()`:
1. Existing match -> use cache.
2. Netease source track -> direct lyrics fetch by `sourceId` without search.
3. Original platform ID direct fetch (`originalSongId` for Netease/QQ Music).
4. User-configured enabled source order from `Settings.lyricsSourcePriorityList`.
5. Manual lyrics search supports filters: All / Netease / QQ Music / lrclib.

Default auto-match source order is Netease -> QQ Music -> lrclib.
`disabledLyricsSources` are skipped; default disables lrclib for auto-match.
Direct source/original-ID lyric fetches also respect the enabled source set. If
all lyric sources are disabled, auto-match is a no-op.

AI matching modes:
- `off`
- AI title parsing
- AI advanced matching

Requests send the video/title string plus optional `uploader` context (currently
`Track.artist`) to the configured OpenAI-compatible endpoint; `uploader` is not
treated as the song artist.
Regex fallback must not treat Bilibili UP names or YouTube channel/uploader
names as song artists when the parser cannot extract an artist. Do not use
`Track.artist` as a regex fallback artist for any source; Netease direct source
and original-ID lyric fetches should cover exact Netease IDs before regex
fallback is needed.

AI title parsing extracts search terms, then local source searches choose
lyrics. After a valid AI parse fails to find lyrics, regex fallback is not used.
AI advanced matching parses the title, collects filtered candidates using source
priority and synced/plain settings, asks AI to select the closest acceptable
same-song candidate, and saves known selected candidates regardless of
confidence.

AI unavailable/config/connection/invalid/no-response cases can fall back to
regex. Valid no-selection/unknown-candidate results do not. `allowPlainLyricsAutoMatch`
defaults to `false`, so automatic matching only accepts synced lyrics unless
enabled, and advanced mode does not offer plain-only candidates when disabled.

Successful title parses are stored in `LyricsTitleParseCache` for reuse during
the current app run, and the cache is cleared on startup.

Desktop lyrics popup window uses an independent Flutter engine and
hide-instead-of-destroy lifecycle. Window lifecycle operations must be
coalesced/serialized so rapid repeated open calls cannot create orphan child
windows.

## Account System

| Platform | Login Method | Token |
|----------|-------------|-------|
| Bilibili | QR code / WebView cookie extraction | Cookie auto-refresh |
| YouTube | WebView cookie extraction | SAPISIDHASH |
| Netease | QR code / WebView cookie | MUSIC_U (long-lived) |

Credential parse/load failures must log fixed sanitized messages only. Do not
pass raw secure-storage JSON, cookie strings, token-bearing exceptions, or
`FormatException` source snippets into `AppLogger`.

## Playlist Import

External playlist import in search-match mode supports:
- Netease standard links / short links (`163cn.tv`)
- QQ Music multiple URL formats with `QQMusicSign`
- Spotify embed page parsing (`__NEXT_DATA__`), no auth needed

Imported tracks save original platform song ID for direct lyrics fetch:
- `ImportedTrack.sourceId` -> `Track.originalSongId`
- `ImportedTrack.source` -> `Track.originalSource`

## Radio Ownership

Radio distinguishes retained context from active ownership of the shared player:
- `hasCurrentStation` = retaining radio context
- `hasActivePlaybackOwnership` = actually controlling player
- `isRadioPlayingProvider` exposes active ownership
- Home "Now Playing" uses retained context for tap actions
- `RadioController.play()` must pause music before setting radio loading state

Radio intentionally consumes the shared `audioServiceProvider` and calls the
backend while ownership hooks keep `AudioController` from reacting to radio
events.

## Windows Sub-Windows

`desktop_multi_window` sub-windows use `RegisterPluginsForSubWindow()`, which
excludes `tray_manager` and `hotkey_manager` because global static C++ channels
would overwrite the main window. When adding plugins, check for global static
channel variables before registering them in sub-windows.

Global system hotkeys must require at least one modifier. Validate this in the
model/import path, not only in the recording dialog, because backups can contain
raw `hotkeyConfig` JSON.

## Image Thumbnail Optimization

`ThumbnailUrlUtils` optimizes image URLs by platform:
- Bilibili: width-only `@{size}w.jpg` suffix after stripping any existing
  `@...` image suffix.
- YouTube video thumbnails: all source adapters MUST store `hqdefault.jpg` as
  the canonical URL (not `highResUrl` / `maxresdefault`). This ensures the
  multi-tier candidate system works correctly — it generates higher-quality
  candidates (`sddefault` → `maxresdefault`) for large displays and
  lower-quality fallbacks (`mqdefault` → `default`) when the original is
  already the highest available tier. Original jpg/webp format is preserved.
- YouTube avatar: `=s{size}` parameter.
- Netease: `?param={size}y{size}` parameter.

Disk cache resize is enabled via `_FmpImageCacheManager` (`ImageCacheManager`
mixin) so `maxWidthDiskCache` / `maxHeightDiskCache` constrain the stored file
size as well as the in-memory decode size.
