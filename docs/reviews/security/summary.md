# FMP Security Review Summary

Scope: repository-wide security and privacy review for FMP. Subreports:

- `docs/reviews/security/account-credential-review.md`
- `docs/reviews/security/network-headers-review.md`
- `docs/reviews/security/download-filesystem-review.md`
- `docs/reviews/security/database-local-data-review.md`
- `docs/reviews/security/webview-import-review.md`
- `docs/reviews/security/desktop-windows-review.md`
- `docs/reviews/security/security-docs-alignment-review.md`

The review first built the instruction/document corpus and threat model in
`docs/reviews/security/instruction-document-corpus.md` and
`docs/reviews/security/threat-model.md`. Descriptive docs were treated as review
questions, not as proof; the findings below survived code-based validation.

## Valid Findings Only

### FMP-SEC-01 - Medium - Netease `MUSIC_U` can be sent to non-allowlisted media/image URLs

Attack or failure scenario: a malicious or compromised Netease response, poisoned
local `Track`, or crafted backup can leave a Netease track with an attacker
controlled audio, cover, or avatar URL. With Netease auth-for-play enabled by
default, FMP builds credential-bearing headers from `SourceType.netease` and
sends `Cookie: MUSIC_U=...` to that URL without checking scheme or host.

Affected files and lines:

- `lib/data/models/settings.dart:275`, `lib/data/models/settings.dart:587`
- `lib/core/utils/auth_headers_utils.dart:24`, `lib/core/utils/auth_headers_utils.dart:27`
- `lib/data/sources/source_http_policy.dart:33`, `lib/data/sources/source_http_policy.dart:54`
- `lib/services/audio/audio_stream_manager.dart:121`, `lib/services/audio/audio_stream_manager.dart:184`, `lib/services/audio/audio_stream_manager.dart:191`
- `lib/services/download/download_media_headers.dart:14`, `lib/services/download/download_media_headers.dart:18`
- `lib/services/download/download_service.dart:702`, `lib/services/download/download_service.dart:764`, `lib/services/download/download_service.dart:1176`, `lib/services/download/download_service.dart:1241`, `lib/services/download/download_service.dart:1257`
- `lib/data/sources/netease_source.dart:140`, `lib/data/sources/netease_source.dart:397`, `lib/data/sources/netease_source.dart:444`
- `lib/services/backup/backup_data.dart:238`, `lib/services/backup/backup_service.dart:370`

Recommended fix: make credential-bearing media headers URL-aware. Require
`https` and an explicit Netease media host allowlist before adding `Cookie`, do
not include cookies in image headers by default, and strip credentials on
redirects or final URLs outside the allowlist.

Tests needed: yes. Add playback/download/header tests for attacker-controlled
Netease cover/avatar URLs, non-allowlisted audio URLs, `http://` URLs, and
credential-stripping redirects.

### FMP-SEC-02 - Medium - Restored `sourceId` can place download task paths outside the download base

Attack or failure scenario: a crafted backup restores a `Track.sourceId` with
path separators or an absolute Windows path. `computeDownloadPath()` sanitizes
playlist/title but interpolates raw `sourceId`; the task `savePath` can point
outside the configured base. Even if stream resolution fails, cancelling or
clearing the task can delete `savePath` and its empty parent directory.

Affected files and lines:

- `lib/services/download/download_path_utils.dart:23`, `lib/services/download/download_path_utils.dart:35`, `lib/services/download/download_path_utils.dart:47`
- `lib/services/backup/backup_data.dart:231`, `lib/services/backup/backup_service.dart:363`
- `lib/services/download/download_service.dart:440`, `lib/services/download/download_service.dart:483`
- `lib/services/download/download_service.dart:1074`, `lib/services/download/download_service.dart:1093`, `lib/services/download/download_service.dart:1116`
- `lib/services/download/download_service.dart:1514`

Recommended fix: sanitize or encode `sourceId` before path construction, then
canonicalize both base and candidate paths and reject any write/delete/sync path
outside the configured base directory.

Tests needed: yes. Add backup restore and download-task tests for `../`,
backslash, and drive-prefixed `sourceId` values, including cancel/clear behavior.

### FMP-SEC-03 - Medium - Playlist import can request local/LAN URLs before host validation

Attack or failure scenario: a user pastes a crafted import URL such as
`http://127.0.0.1:8080/?x=spotify.link` or a real short link that redirects to a
local/LAN target. Platform detection uses `String.contains()`, then short-link
resolvers issue GET/HEAD requests to the original URL or follow redirects before
enforcing host allowlists. No account cookies were found on this path, so the
impact is local/LAN probing or triggering GET/HEAD side effects.

Affected files and lines:

- `lib/services/import/playlist_import_service.dart:136`, `lib/services/import/playlist_import_service.dart:200`
- `lib/data/sources/playlist_import/spotify_playlist_source.dart:21`, `lib/data/sources/playlist_import/spotify_playlist_source.dart:72`, `lib/data/sources/playlist_import/spotify_playlist_source.dart:74`, `lib/data/sources/playlist_import/spotify_playlist_source.dart:77`
- `lib/data/sources/playlist_import/qq_music_playlist_source.dart:19`, `lib/data/sources/playlist_import/qq_music_playlist_source.dart:98`, `lib/data/sources/playlist_import/qq_music_playlist_source.dart:100`, `lib/data/sources/playlist_import/qq_music_playlist_source.dart:103`
- `lib/data/sources/playlist_import/netease_playlist_source.dart:22`, `lib/data/sources/playlist_import/netease_playlist_source.dart:72`, `lib/data/sources/playlist_import/netease_playlist_source.dart:74`, `lib/data/sources/playlist_import/netease_playlist_source.dart:88`
- `lib/data/sources/netease_source.dart:55`, `lib/data/sources/netease_source.dart:58`, `lib/data/sources/netease_source.dart:718`, `lib/data/sources/netease_source.dart:729`

Recommended fix: parse URLs with `Uri`, require `http`/`https`, compare
normalized hosts against exact allowlists before network requests, manually
validate each redirect target, and reject loopback/private/link-local IP ranges.

Tests needed: yes. Add import detection and resolver tests for substring-host
spoofing and redirects to `127.0.0.1`, RFC1918, link-local, and non-platform
hosts.

### FMP-SEC-04 - Medium - Malformed secure-storage credential JSON can expose tokens through logs

Attack or failure scenario: secure storage is corrupted or manually altered
while still containing credential text. `jsonDecode()` throws a
`FormatException` that can include the rejected source snippet. The account
services pass the raw exception to `AppLogger`; the in-app log viewer displays
and copies `entry.error.toString()`, potentially exposing `SESSDATA`,
YouTube cookies/SAPISID material, or `MUSIC_U`.

Affected files and lines:

- `lib/services/account/bilibili_account_service.dart:546`, `lib/services/account/bilibili_account_service.dart:549`, `lib/services/account/bilibili_account_service.dart:554`
- `lib/services/account/youtube_account_service.dart:514`, `lib/services/account/youtube_account_service.dart:517`, `lib/services/account/youtube_account_service.dart:522`
- `lib/services/account/netease_account_service.dart:391`, `lib/services/account/netease_account_service.dart:397`, `lib/services/account/netease_account_service.dart:403`
- `lib/core/logger.dart:120`, `lib/core/logger.dart:150`, `lib/core/logger.dart:152`
- `lib/ui/pages/settings/log_viewer_page.dart:292`, `lib/ui/pages/settings/log_viewer_page.dart:314`

Recommended fix: log sanitized fixed parse-failure messages, not raw exception
objects. Consider clearing the malformed secure-storage entry and marking the
account logged out. Add a logger redaction layer for cookie/token key names.

Tests needed: yes. Add malformed credential JSON tests containing sentinel token
strings and assert `AppLogger` entries and copied log text do not contain them.

### FMP-SEC-05 - Medium - Release docs expose Android signing secrets through command lines and temp files

Attack or failure scenario: a maintainer follows the docs with real passwords.
The keystore passwords can land in shell history, process listings, terminal
logs, or agent transcripts. The base64 keystore copy in `%TEMP%` remains unless
manually removed. Together these can allow signing update-compatible APKs.

Affected files and lines:

- `docs/build-guide.md:74`, `docs/build-guide.md:80`, `docs/build-guide.md:81`
- `docs/build-and-release.md:27`, `docs/build-and-release.md:32`, `docs/build-and-release.md:33`
- `docs/build-and-release.md:77`, `docs/build-and-release.md:81`, `docs/build-and-release.md:82`
- `.github/workflows/build.yml:56`, `.github/workflows/build.yml:57`, `.github/workflows/build.yml:58`
- `android/app/build.gradle.kts:11`, `android/app/build.gradle.kts:39`, `android/app/build.gradle.kts:41`, `android/app/build.gradle.kts:44`

Recommended fix: replace command-line password examples with interactive or
stdin/body-file workflows, use `gh secret set ... --body-file -`, delete
`$env:TEMP\ks.txt` after upload, and explicitly warn not to paste signing
secrets or encoded keystores into logs, issues, or agent reports.

Tests needed: no product tests. Documentation review plus `git diff --check` is
sufficient.

### FMP-SEC-06 - Medium - VM Service / Isar debug docs omit sensitive-token and export boundaries

Attack or failure scenario: an agent copies a VM Service URI/token or Isar
export/query output into a report or support transcript. The token grants local
debug API access while the process runs, and Isar exports can disclose search
queries, play history, local paths, account metadata, and settings.

Affected files and lines:

- `docs/debugging-with-vm-service.md:37`, `docs/debugging-with-vm-service.md:43`, `docs/debugging-with-vm-service.md:44`
- `docs/debugging-with-vm-service.md:453`, `docs/debugging-with-vm-service.md:465`, `docs/debugging-with-vm-service.md:468`
- `docs/debugging-with-vm-service.md:633`, `docs/debugging-with-vm-service.md:638`
- `lib/providers/database_provider.dart:27`, `lib/providers/database_provider.dart:32`, `lib/providers/database_provider.dart:34`, `lib/providers/database_provider.dart:38`
- `lib/data/models/search_history.dart:10`, `lib/data/models/play_history.dart:13`, `lib/data/models/play_history.dart:25`, `lib/data/models/settings.dart:130`, `lib/data/models/settings.dart:224`

Recommended fix: add a sensitive debug data section stating that VM Service
URLs/tokens and Isar outputs must be treated as secrets, redacted before
sharing, scoped to the minimum collection/query, and cleaned up from temp files.

Tests needed: no product tests. Documentation review plus `git diff --check` is
sufficient.

### FMP-SEC-07 - Low - Existing files at computed download destinations can be overwritten

Attack or failure scenario: a selected download directory already contains a
manual file at FMP's deterministic destination. The download isolate writes a
temp file and completion renames it to `savePath` without first checking whether
the final file exists and belongs to the task, causing local data loss or
platform-specific rename failures.

Affected files and lines:

- `lib/services/download/download_service.dart:448`, `lib/services/download/download_service.dart:764`, `lib/services/download/download_service.dart:847`, `lib/services/download/download_service.dart:848`
- `lib/services/download/download_service.dart:1514`, `lib/services/download/download_service.dart:1516`

Recommended fix: before starting the isolate and before final rename, detect an
existing `savePath`. Either treat it as already downloaded after metadata
validation, create a unique suffix, or fail with a visible conflict.

Tests needed: yes. Add tests for pre-existing destination files and resume/temp
file behavior.

### FMP-SEC-08 - Low - Imported hotkey config can register bare system-wide keys

Attack or failure scenario: a crafted backup enables global hotkeys and imports
a binding with `keyId` but `modifiers: []`. The normal UI only saves recorded
hotkeys with modifiers, but backup restore persists raw `hotkeyConfig`; provider
load then registers bare keys such as `A`, `Space`, or arrows as system-scope
hotkeys.

Affected files and lines:

- `lib/services/backup/backup_service.dart:650`, `lib/services/backup/backup_service.dart:660`
- `lib/providers/hotkey_config_provider.dart:29`, `lib/providers/hotkey_config_provider.dart:31`, `lib/providers/hotkey_config_provider.dart:72`
- `lib/data/models/hotkey_config.dart:44`, `lib/data/models/hotkey_config.dart:70`, `lib/data/models/hotkey_config.dart:75`, `lib/data/models/hotkey_config.dart:92`
- `lib/services/platform/windows_desktop_service.dart:303`, `lib/services/platform/windows_desktop_service.dart:313`
- `lib/ui/pages/settings/settings_page.dart:1938`

Recommended fix: enforce hotkey validation in `HotkeyConfig` and backup import,
not only the recording dialog. Require at least one modifier for configured
system hotkeys and clear invalid imported bindings.

Tests needed: yes. Add `HotkeyConfig.fromJsonString` tests and backup import
tests for modifierless bindings.

### FMP-SEC-09 - Low - Concurrent lyrics popup opens can orphan a sub-window

Attack or failure scenario: two rapid open calls can both pass
`_controller == null` before `WindowController.create` assigns the retained
controller. Multiple child engines can be created, but only the latest
controller is tracked, leaving an orphan lyrics window sharing the same channel
and capable of sending playback/style commands until process exit.

Affected files and lines:

- `lib/services/lyrics/lyrics_window_service.dart:76`, `lib/services/lyrics/lyrics_window_service.dart:80`, `lib/services/lyrics/lyrics_window_service.dart:92`, `lib/services/lyrics/lyrics_window_service.dart:108`, `lib/services/lyrics/lyrics_window_service.dart:332`
- `lib/ui/widgets/track_detail_panel.dart:582`, `lib/ui/widgets/track_detail_panel.dart:593`

Recommended fix: serialize `LyricsWindowService` lifecycle operations with an
`_opening` future or operation chain, set pending state before
`WindowController.create`, and coalesce concurrent open calls.

Tests needed: yes. Add a fake-controller lifecycle test proving concurrent
`open()` calls create at most one child window.

### FMP-SEC-10 - Low - Windows reserved device names are not rejected by filename sanitization

Attack or failure scenario: a remote title or user playlist named `CON`, `PRN`,
`AUX`, `NUL`, `COM1`, or `LPT1` can create a syntactically invalid Windows path
after current sanitization. This is not traversal, but it can make affected
downloads fail reliably on Windows.

Affected files and lines:

- `lib/services/download/download_path_utils.dart:29`, `lib/services/download/download_path_utils.dart:35`
- `lib/services/download/download_path_utils.dart:70`, `lib/services/download/download_path_utils.dart:89`, `lib/services/download/download_path_utils.dart:95`, `lib/services/download/download_path_utils.dart:100`
- `lib/services/download/download_service.dart:733`, `lib/services/download/download_service.dart:735`

Recommended fix: after trimming and trailing-dot removal, compare each basename
case-insensitively against Windows reserved device names and prefix/suffix them
before length limiting.

Tests needed: yes. Add sanitizer tests for reserved device names and trailing
extensions such as `CON.txt`.

## False Positives / Explicitly Checked But Not Vulnerable

- Account credentials are not persisted in Isar or displayed by the database
  viewer. `Account` stores platform/user metadata only, while Bilibili,
  YouTube, Netease, and lyrics AI secrets use secure storage.
- The developer database viewer shows local app-state details but not secure
  account tokens or the lyrics AI API key. The missing route-level developer
  guard is optional hardening, not a current token leak.
- Backup export excludes account credentials, download tasks, raw local download
  paths, and `Track.audioUrl`.
- WebView login cookie extraction uses fixed platform URLs and persists selected
  required cookies rather than whole WebView cookie jars; cleanup exists for
  Bilibili, YouTube, and Netease login pages.
- Bilibili and YouTube media/download headers do not carry account cookies or
  authorization headers; the cross-domain credential finding is Netease-specific.
- Netease playlist short URL resolution does not send account cookies in the
  reviewed import path; its risk is local/LAN request reachability, not credential
  exfiltration.
- Normal source adapters produce constrained IDs: Bilibili validates BV IDs,
  Netease IDs are numeric, and YouTube IDs come from source libraries/API data.
  The path traversal finding is tied to backup/corrupted local data.
- Windows sub-window plugin registration is selective and excludes tray/hotkey
  plugins from child windows; no arbitrary external cross-window command channel
  was found.
- Windows update ZIP extraction already rejects absolute paths, drive-prefixed
  paths, and `..` traversal before writing extracted files.

## Security-Related Documentation Inaccuracies

- Release docs currently teach command-line signing secrets and leave a base64
  keystore copy in temp files. This is a valid security documentation finding
  and should be fixed in `docs/build-guide.md` and
  `docs/build-and-release.md`.
- VM Service docs describe token extraction and Isar export commands but do not
  warn that VM Service URLs/tokens and Isar exports are sensitive local data.
- Header/download instructions accurately say only Netease media requests merge
  auth, but they do not require a URL host/scheme allowlist before attaching
  `MUSIC_U`, and they do not distinguish image requests from media requests.
- Playlist import docs mention short URL resolution but do not state that
  user-supplied URLs and every redirect destination must be host-validated and
  private-address-filtered before network requests.
- Windows plugin docs are conservative and mostly accurate, but the exact
  `hotkey_manager` rationale appears stale for the checked dependency version.
  The safer instruction remains: keep global hotkey ownership main-window-only
  and inspect static/global channel ownership before adding sub-window plugins.

## Review Artifacts

- Instruction/document corpus: `docs/reviews/security/instruction-document-corpus.md`
- Threat model: `docs/reviews/security/threat-model.md`
- Runtime inventory and coverage ledger: `docs/reviews/security/runtime-inventory.md`
