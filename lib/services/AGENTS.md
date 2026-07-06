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

## Backup System

Backup export/import is a portable JSON data transfer, not a full app clone.
It includes playlists, tracks needed by playlists, play/search history, radio
stations, lyrics matches, and portable settings. It intentionally excludes
downloaded media files, transient download tasks, play queue state, secure
storage credentials, and device-specific paths/audio devices.

When adding durable user-facing fields to backed-up models, update
`lib/services/backup/backup_data.dart`, `BackupService` export/import mapping,
and `test/services/backup/backup_service_test.dart`. Bump `kBackupVersion` when
the exported JSON shape changes, while keeping older backups readable through
defaults. Keep `BackupService.validateBackupData()` aligned with supported
versions and importable sections so unsupported future backups fail before the
preview/import step.

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

### Known benign runtime noise: `Failed to update ui::AXTree`

`flutter run -d windows` repeatedly logs
`[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: <N> will not be in the tree and is not the new root`.
This is a **known Flutter engine bug, not an FMP defect, and it is benign — do
not try to fix it.** Every claim below was verified against primary sources
(engine source, `flutter/flutter` GitHub, Flutter 3.44 release notes) in 2026-07.

- Engine behavior: `AccessibilityBridge::CommitUpdates()` cannot serialize a
  semantics-node reparent in a single update, so it does `FML_LOG(ERROR) ... ;
  return;`, drops that one update, and re-sends a corrected tree next frame. No
  crash, no functional impact. Tracked upstream by `flutter/flutter#182444`
  (ListView + Tooltip + OverlayPortal, Windows-only, OPEN as of 2026-07) and
  `flutter/flutter#188662` (bridge leaks its `AXTreeManager`). No Flutter
  version, including master, fixes it yet.
- Why FMP triggers it: each `desktop_multi_window` sub-window runs its own
  Flutter engine (its own `AccessibilityBridge`), and the custom / lyrics title
  bars use `IconButton` tooltips + `Semantics`/`ExcludeSemantics` — exactly the
  `#182444` reparent pattern. The package multiplies the surface area but is not
  itself the bug.
- Scope: the line is C++ `FML_LOG` on platform stderr. It never enters
  `AppLogger` / the in-app Log Viewer, and release builds show nothing (no
  attached console). It only clutters the dev terminal.

None of these "fix" it — do not do them:
- Upgrade Flutter, `desktop_multi_window`, or `window_manager` solely for this.
- Globally `setSemanticsEnabled(false)` on the main window (kills Narrator/NVDA
  a11y app-wide).
- Use the `FLUTTER_A11Y=off` env var or
  `FlutterWindows.instance?.setSemanticsEnabled(...)` — these are not real
  Flutter APIs (forum fabrication; no engine/framework reference exists).
- Wrap `IconButton` in a `Tooltip(child: ...)` — that is the OverlayPortal
  anti-pattern from `#182444`.

When you see it: ignore it. To reduce terminal noise:

```bash
# filter inline (Git Bash) — note this breaks flutter run hot-reload interactivity
flutter run -d windows 2>&1 | grep -vF "Failed to update ui::AXTree"
# PowerShell — set UTF-8 first or Chinese (zh) output becomes mojibake when
# GBK-decoded; same hot-reload caveat
[Console]::OutputEncoding = [Text.Encoding]::UTF8
flutter run -d windows 2>&1 | Select-String -NotMatch "Failed to update ui::AXTree"
# keep stdout/stdin interactive, send only stderr to a file
flutter run -d windows 2> run.log
```

In Windows PowerShell 5.1, Chinese output through the `Select-String` pipe shows
as mojibake (UTF-8 bytes decoded as the GBK/CP936 system code page); setting
`[Console]::OutputEncoding = [Text.Encoding]::UTF8` first fixes it (shown above).
PowerShell 7 (`pwsh`) defaults to UTF-8 and is unaffected.

VS Code's integrated terminal has no native "hide lines matching a pattern"
filter (verified through v1.107); use one of the pipes above, redirect stderr to
a file, or a capture-and-filter extension (e.g. *Better Terminal Logs*). The
*Filter Lines* extension only operates on editor documents, not the live
terminal, so it does not apply here.

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
