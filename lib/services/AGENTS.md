# lib/services AGENTS.md

Service-layer rules. Audio is in `lib/services/audio/AGENTS.md`; source
adapters, stream resolution and the auth/header policy are in
`lib/data/sources/AGENTS.md`.

## Download System

- Path deduplication is by `savePath`, not `trackId`. Verify the file exists
  before saving the downloaded path.
- Downloads run in an isolate on **all** platforms and keep progress in memory
  first. That avoids Windows PostMessage queue overflow and Isar watch churn
  while keeping the main isolate responsive. Progress is flushed to Isar on
  completion, pause, failure and app disposal; pause/failure paths must preserve
  the latest pending in-memory tuple before clearing task state.
- Audio, metadata, cover and avatar live inside each video folder. The three
  shared names are constants in `lib/core/constants/download_filenames.dart` —
  the writer and every scanner depend on that contract. The multi-page metadata
  name and the audio extension are deliberately **not** constants; see the
  file's own header.
- Download path components, including a restored `Track.sourceId`, must be
  sanitized before path construction. Write/delete paths must stay inside the
  configured base, and an existing destination file is a conflict, not something
  to overwrite.
- Isolate media downloads apply both a connection timeout and a receive/idle
  timeout, so a stalled response cannot hold a slot forever.
- Do not rely on `DownloadService` Dio defaults for source-specific headers.

Auth and header boundary:

- `DownloadService` resolves streams through `StreamResolutionService` with
  `StreamResolutionPurpose.download`. Metadata detail and image header policy
  use the narrow `DownloadSourceAuthContext`.
- The download isolate builds media headers through the pure `MediaHandoff`
  module for **each redirect hop**, and must not use Riverpod, account services
  or `SourceAuthContext`. `MediaHandoff` also owns resumed-download `Range`
  headers. Full policy: `lib/data/sources/AGENTS.md` § Auth For Playback And
  Headers.
- Android custom download directories need `MANAGE_EXTERNAL_STORAGE` on
  Android 11+. Permission checks use the app-owned MethodChannel in
  `StoragePermissionService`, **not** `permission_handler` — that package would
  make Windows builds register `permission_handler_windows` and trip the system
  location indicator.

## Update System

- Downloads write to a `.part` file first, validate the GitHub asset size and
  the SHA-256 entry from the release's checksum manifest, then rename.
- Android install checks `canRequestPackageInstalls` through the app-owned
  `com.personal.fmp/platform` MethodChannel first. Do not add
  `permission_handler` for this path either.
- Windows installed builds update through the Inno installer; portable builds
  through a generated VBS/BAT helper that must wait for the old process, back up
  the app directory, use `robocopy`, and attempt rollback on failure.
- Startup cleanup may delete **only** FMP update artifacts in the temp
  directory.

## Lyrics System

Auto-match order is in `LyricsAutoMatchService.tryAutoMatch()`. The rules around
it:

- `disabledLyricsSources` are skipped, and the default disables lrclib for
  auto-match. Direct source and original-ID fetches respect the enabled set too.
  With every source disabled, auto-match is a no-op — but manual search still
  offers all filters.
- Requests send the title plus optional `uploader` context. **`uploader` is not
  the song artist.** Regex fallback must not treat a Bilibili UP name or a
  YouTube channel name as one, for any source.
- After a *valid* AI parse fails to find lyrics, regex fallback is not used.
  AI unavailable/config/connection/invalid/no-response may fall back to regex;
  valid no-selection or unknown-candidate results may not.
- `allowPlainLyricsAutoMatch` defaults to `false`, so auto-match accepts only
  synced lyrics unless enabled, and advanced mode hides plain-only candidates.
- Title parses are cached in `LyricsTitleParseCache` for the current run only.

The desktop lyrics popup uses an independent Flutter engine and a
hide-instead-of-destroy lifecycle. Window lifecycle operations must be
coalesced so rapid repeated open calls cannot create orphan child windows.

## Account System

Credential parse/load failures must log fixed sanitized messages only. Never
pass raw secure-storage JSON, cookie strings, token-bearing exceptions or
`FormatException` source snippets into `AppLogger`.

All three services reach secure storage through `SecureKeyValueStore`
(`lib/core/secure_key_value_store.dart`), never `FlutterSecureStorage`
directly. The wrapper turns platform failures into `SecureStorageUnavailable`,
carrying the operation and platform code but not the message, which can name a
key alias or a path. **"Cannot read the credential" is not "there is no
credential":** Android Keystore can fail to decrypt after a device restore and
Windows DPAPI after a profile rebuild. `_loadCredentials` degrades to logged out
and logs a fixed message rather than letting the exception out —
`SourceAuthContext` and both Dio interceptors sit on that path, so an escaping
exception turns every API request into an error. It does not latch: a transient
failure is retried on the next call.

FMP pins `flutter_secure_storage` to 10.x. v10 re-encrypts Android credentials
on first read, and 11.x removes the 9.x ciphers it migrates from. **A bump to
11.x is a release-sequencing decision, not a routine version bump.** A user who
never runs a shipped 10.x build loses their stored credentials on reaching 11.x,
and FMP updates in-app in a way that lets users skip versions, so "10.x was
released once" is not "every install has migrated". It degrades to a forced
re-login rather than a crash only because of the guard above.

## Backup System

Backup is a portable JSON data transfer, not a full app clone. It deliberately
excludes downloaded media, transient download tasks, play queue state, secure
credentials and device-specific paths and audio devices.

When adding durable user-facing fields to backed-up models, update
`backup_data.dart`, the `BackupService` export/import mapping and its test. Bump
`kBackupVersion` when the exported shape changes while keeping older backups
readable through defaults, and keep `validateBackupData()` aligned so an
unsupported future backup fails before the preview step.
`settings_backup_coverage_static_rule_test.dart` fails when a persisted
`Settings` column reaches neither `SettingsBackup` nor the named exclusion list.

**Import is atomic.** Parsing, per-item `try`/`catch` and skip decisions stay in
`BackupService` and touch nothing. Every survivor is written by
`BackupRepository.writeImport` inside a single `writeTxn`, so a failure part way
through rolls the whole import back and throws — the UI shows the failure rather
than a dialog claiming counts nobody wrote. Isar rejects a nested `writeTxn`
from a Zone check, which is why `PlaylistMutationRepository` exposes
`addTracksInTxn`.

## Log Persistence

`AppLogger` writes through `LogFileSink` (`lib/core/log_file_sink.dart`),
rotating across three files.

- What lands on disk is the same `redactSensitive()` output the in-memory buffer
  holds — `_log` redacts before it buffers, so there is no second path to audit.
- The sink can only open after `WidgetsFlutterBinding.ensureInitialized()`,
  while `main.dart` installs its error handlers before that. `attachFileSink`
  therefore flushes the existing buffer first; do not "simplify" that away, it
  is what keeps startup logs.
- Writes are queued and failures are swallowed. Logging must never be a source
  of app failure.

## Radio Ownership

Radio distinguishes retained context (`hasCurrentStation`) from active ownership
of the shared player (`hasActivePlaybackOwnership`). Home "Now Playing" uses
retained context for tap actions. `RadioController.play()` must pause music
before setting radio loading state. Timed live-status refresh is owned by
`RadioRefreshService`; UI pages must not create their own periodic refresh
timers. That service is the one request stream that runs for as long as the
app is open, so it backs off exponentially on a Bilibili risk-control code and
stops ticking while the app is in the background (#95); only the timer obeys
both, a user-triggered refresh does not.

Radio intentionally consumes the shared `audioServiceProvider` and calls the
backend directly, while ownership hooks keep `AudioController` from reacting to
radio events. The one end reason that still reaches `AudioController` during
radio is `OutputDeviceFailed` — see `lib/services/audio/AGENTS.md`.

System media controls are **not** part of that exception. `RadioController`
reaches the notification and SMTC through `nowPlayingPublisherProvider` like
everything else, claiming `PlaybackCapabilities.liveRadio` so the skip controls
are withdrawn rather than left pointing at null callbacks.

## Windows Sub-Windows

`desktop_multi_window` sub-windows are registered by
`RegisterPluginsForSubWindow()` in `windows/runner/flutter_window.cpp`, which
excludes `tray_manager` and `hotkey_manager` because their global static C++
channels would overwrite the main window. When adding a plugin, check for global
static channel variables before registering it in a sub-window.

Global system hotkeys must require at least one modifier. Validate that in the
model/import path, not only in the recording dialog, because a backup can
contain raw `hotkeyConfig` JSON.

## Image Thumbnail Optimization

`ThumbnailUrlUtils` (`lib/core/utils/`) rewrites image URLs per platform.

- Platform detection must parse the URL **host** and match an exact
  host/subdomain, not search the whole URL string. A proxy or a path containing
  a CDN's name is not that platform's CDN.
- Candidate selection uses the semantic image component's explicit
  `targetDisplaySize`, not device DPR. Decode and disk-cache sizing still use
  the real DPR. UI call sites pass semantic variants, never raw target sizes —
  see `lib/ui/AGENTS.md` § Image Components.
- **YouTube video thumbnails**: adapters must store `hqdefault.jpg` as the
  canonical URL so the multi-tier candidate system works while stored metadata
  stays stable. Display may use **only** the 16:9 candidates; the 4:3 tiers can
  contain black bars. Candidate format is preserved from the canonical URL —
  some videos have no WebP thumbnails at all, so converting causes cascading
  404s.

Disk cache resize differs by path. The main display path stores raw downloaded
bytes: URL tier selection already bounds the download size, and a disk resize
would double-store the original plus a re-encoded copy. Only the precache path
resizes on disk.
