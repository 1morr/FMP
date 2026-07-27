# lib/services AGENTS.md

Service-layer guidance. For audio-specific rules, also read
`lib/services/audio/AGENTS.md`. Source adapters, stream resolution, and the
auth/header policy live in `lib/data/sources/AGENTS.md`.

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
  `audio.m4a` / `P{NN}.m4a`, `metadata.json` / `metadata_P{NN}.json`,
  `cover.jpg`, `avatar.jpg`. Shared names are constants in
  `lib/core/constants/download_filenames.dart` — the writer
  (`DownloadService`) and every scanner/reader depend on that contract.
- Download path components, including restored `Track.sourceId`, must be
  sanitized before path construction. Write/delete paths must stay inside the
  configured download base, and existing destination files must be treated as a
  conflict rather than overwritten.
- Isolate media downloads must apply both connection timeout and receive/idle
  timeout so a stalled response cannot hold a download slot forever.
- Do not rely on `DownloadService` Dio defaults for source-specific headers.

Auth and header boundary:

- `DownloadService` resolves audio streams through `StreamResolutionService`
  with `StreamResolutionPurpose.download`. Download metadata detail and image
  header policy use the narrow `DownloadSourceAuthContext` interface implemented
  by `SourceAuthContext`.
- The download isolate must convert stream auth to Media Request Credentials
  through the pure `MediaHandoff` module for **each redirect hop**, and it must
  not use Riverpod, account services, or `SourceAuthContext`. `MediaHandoff`
  also owns resumed-download `Range` headers. Only allowlisted
  HTTPS Netease media URLs may receive `MUSIC_U`; Bilibili and YouTube account
  credentials must never reach media/CDN requests. Full policy:
  `lib/data/sources/AGENTS.md` § Auth For Playback And Headers.
- `DownloadService` still owns isolate download loops, progress, pause/failure
  state, and final path persistence.

Images and platform:

- Downloaded metadata cover/avatar images use
  `ThumbnailUrlUtils.getOptimizedUrlCandidates()` with `ImageTargetSizes.high`
  for covers and `ImageTargetSizes.low` for avatars before falling back through
  source-specific candidates. Keep avatar downloads small.
- Android custom download directories require storage permission
  (`MANAGE_EXTERNAL_STORAGE` on Android 11+). Default Android base dir is
  `Music/FMP` via external storage fallback logic.
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

Default auto-match source order is Netease -> QQ Music -> lrclib.
`disabledLyricsSources` are skipped; the default disables lrclib for auto-match.
Direct source/original-ID fetches also respect the enabled source set. If all
lyric sources are disabled, auto-match is a no-op. Manual lyrics search supports
All / Netease / QQ Music / lrclib filters regardless.

AI matching modes are `off`, AI title parsing, and AI advanced matching.

- Requests send the video/title string plus optional `uploader` context
  (currently `Track.artist`) to the configured OpenAI-compatible endpoint.
  `uploader` is **not** treated as the song artist.
- Regex fallback must not treat Bilibili UP names or YouTube channel/uploader
  names as song artists when the parser cannot extract one. Do not use
  `Track.artist` as a regex fallback artist for any source — Netease direct
  source and original-ID fetches should cover exact Netease IDs before regex
  fallback is needed.
- AI title parsing extracts search terms, then local source searches choose
  lyrics. After a valid AI parse fails to find lyrics, regex fallback is *not*
  used.
- AI advanced matching parses the title, collects filtered candidates using
  source priority and synced/plain settings, asks AI to select the closest
  acceptable same-song candidate, and saves known selected candidates regardless
  of confidence.
- AI unavailable/config/connection/invalid/no-response cases may fall back to
  regex; valid no-selection/unknown-candidate results may not.
- `allowPlainLyricsAutoMatch` defaults to `false`, so auto-match only accepts
  synced lyrics unless enabled, and advanced mode does not offer plain-only
  candidates when disabled.
- Successful title parses are stored in `LyricsTitleParseCache` for reuse during
  the current app run; the cache is cleared on startup.

The desktop lyrics popup window uses an independent Flutter engine and a
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

`SourceAuthContext` (`lib/services/account/`) owns the source auth gates. See
`lib/data/sources/AGENTS.md` for which purpose interface to depend on.

## Playlist Import

Supported link formats and the `ImportedTrack` -> `Track` ID mapping are owned by
`lib/data/sources/AGENTS.md` § External Playlist Import. Do not restate them here.

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
- `hasActivePlaybackOwnership` = actually controlling the player
- `isRadioPlayingProvider` exposes active ownership
- Home "Now Playing" uses retained context for tap actions
- `RadioController.play()` must pause music before setting radio loading state
- Timed live-status refresh is owned by `RadioRefreshService` and follows the
  user-configured interval; UI pages must not create their own periodic
  full-status refresh timers.

Radio intentionally consumes the shared `audioServiceProvider` and calls the
backend directly, while ownership hooks keep `AudioController` from reacting to
radio events.

## Windows Sub-Windows

`desktop_multi_window` sub-windows use `RegisterPluginsForSubWindow()`, which
excludes `tray_manager` and `hotkey_manager` because global static C++ channels
would overwrite the main window. When adding plugins, check for global static
channel variables before registering them in sub-windows.

Global system hotkeys must require at least one modifier. Validate this in the
model/import path, not only in the recording dialog, because backups can contain
raw `hotkeyConfig` JSON.

The repeated `Failed to update ui::AXTree` stderr spam is a known upstream
Flutter engine bug (`flutter/flutter#182444`), is benign, and must not be
"fixed". Causes, verified-false workarounds, and terminal-filtering options:
`docs/troubleshooting.md`.

## Image Thumbnail Optimization

`ThumbnailUrlUtils` (`lib/core/utils/`) optimizes image URLs by platform:

- Platform detection must parse the URL **host** and match an exact
  host/subdomain, not search the whole URL string. A proxy or path containing
  `ytimg.com`, `hdslb.com`, or `music.126.net` is not that platform's CDN.
- URL candidate selection uses the semantic image component's explicit
  `targetDisplaySize`, not device DPR. Decode and disk-cache sizing still use
  the real device DPR. UI call sites pass semantic image variants, never raw
  target sizes — see `lib/ui/AGENTS.md` § Image Components.
- Bilibili: width-only `@{size}w.jpg` suffix, after stripping any existing `@…`
  image suffix.
- YouTube avatar: `=s{size}` parameter. Netease: `?param={size}y{size}`.
- YouTube video thumbnails: all source adapters MUST store `hqdefault.jpg` as
  the canonical URL (not `highResUrl` / `maxresdefault`), so the multi-tier
  candidate system works while stored metadata stays stable. Display loading
  MUST only use the 16:9 candidates (`maxresdefault`, `mqdefault`); never
  display or fall back to `default`, `hqdefault`, or `sddefault`, because those
  4:3 tiers can contain black bars. Candidate format (JPG/WebP) is preserved
  from the canonical URL — some rare videos (e.g. `JqRggTDg5Bo`) have no WebP
  thumbnails at all, so format conversion would cause cascading 404s.

Disk cache resize differs by path. The main display path (the
`CachedNetworkImage` widget in `image_loading_service.dart`) stores raw
downloaded bytes — URL tier selection already bounds the download size, and a
disk resize would double-store the original plus a PNG-reencoded copy. Only the
`imageProviderCandidates` precache path resizes on disk, via
`_FmpImageCacheManager` (`ImageCacheManager` mixin) and `maxWidthDiskCache` /
`maxHeightDiskCache`.
