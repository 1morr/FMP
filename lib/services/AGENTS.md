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
- `DownloadService` resolves audio streams through `StreamResolutionService`
  with `StreamResolutionPurpose.download`; stream auth comes from
  `StreamResolutionService`, while download metadata detail and image header
  policy use the narrow `DownloadSourceAuthContext` interface implemented by
  `SourceAuthContext`.
- Download stream auth comes from `StreamResolutionService`; the download
  isolate must convert it to Media Request Credentials through the pure
  `MediaHandoff` module for each redirect hop. Only allowlisted HTTPS Netease
  media URLs may receive `MUSIC_U`; Bilibili and YouTube account credentials
  must never reach media/CDN requests.
- `DownloadService` still owns isolate download loops, progress, pause/failure
  state, and final path persistence. The isolate uses `MediaHandoff` for
  per-hop media headers and resumed-download `Range` headers; it must not use
  Riverpod, account services, or `SourceAuthContext`.
- Downloaded metadata cover/avatar images should use
  `ThumbnailUrlUtils.getOptimizedUrlCandidates()` with `ImageTargetSizes.high`
  for covers and `ImageTargetSizes.low` for avatars before falling back through
  source-specific candidates. Cover downloads use larger candidates than
  avatars; keep avatar downloads small.
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

## Update System

- In-app update downloads must write to a `.part` file first, validate the
  GitHub asset size and available `fmp-vX.Y.Z-checksums.sha256` SHA-256 entry,
  then rename to the final file path.
- Android APK installation must check `canRequestPackageInstalls` through the
  app-owned `com.personal.fmp/platform` MethodChannel before opening the APK.
  Do not add `permission_handler` for this path.
- Windows installed builds update through the Inno installer. Windows portable
  builds update through the generated VBS/BAT helper, which must wait for the
  old app process, back up the app directory, use `robocopy`, and attempt
  rollback on replacement failure.
- Startup cleanup may delete only FMP update artifacts in the temp directory:
  versioned `fmp-*.exe`/`fmp-*.zip`, updater scripts, and update staging dirs.

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

Bilibili medal wall radio import keeps credential ownership in
`BilibiliAccountService`, but live room lookup and `getRoomInfoOld` handling
belong in `BilibiliLiveClient`.

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
- Timed live-status refresh is owned by `RadioRefreshService` and follows the
  user-configured interval; UI pages should not create their own periodic
  full-status refresh timers.

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
- Platform detection must parse the URL host and match exact host/subdomain,
  not search the whole URL string. A proxy/path containing `ytimg.com`,
  `hdslb.com`, or `music.126.net` is not that platform's CDN.
- URL candidate selection should use the semantic image component's explicit
  `targetDisplaySize`, not device DPR. Decode and disk-cache sizing still use
  the real device DPR. UI page call sites should pass semantic image variants
  instead of raw target sizes.
- Bilibili: width-only `@{size}w.jpg` suffix after stripping any existing
  `@...` image suffix.
- YouTube video thumbnails: all source adapters MUST store `hqdefault.jpg` as
  the canonical URL (not `highResUrl` / `maxresdefault`). This ensures the
  multi-tier candidate system works correctly while keeping stored metadata
  stable. Display loading MUST only use 16:9 candidates (`maxresdefault` and
  `mqdefault`). Never display or fall back to `default`, `hqdefault`, or
  `sddefault`, because those 4:3 tiers can contain black bars. Candidate format
  (JPG/WebP) is preserved from the canonical URL to ensure reliability; some
  rare videos (e.g., JqRggTDg5Bo) have no WebP thumbnails at all, so format
  conversion would cause cascading 404s.
- YouTube avatar: `=s{size}` parameter.
- Netease: `?param={size}y{size}` parameter.

Disk cache resize is enabled via `_FmpImageCacheManager` (`ImageCacheManager`
mixin) so `maxWidthDiskCache` / `maxHeightDiskCache` constrain the stored file
size as well as the in-memory decode size.
