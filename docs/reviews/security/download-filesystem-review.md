# Download / Filesystem Security Review

Scope: `DownloadService`, `DownloadPathManager`, downloaded metadata/images,
Android storage permission, Windows download/scanning isolates, and related
download providers. Descriptive notes from `AGENTS.md`,
`docs/reviews/security/*`, and `.serena/memories/download_system.md` were used
as questions only; conclusions below are based on code references.

## Valid findings

### FMP-DL-01 - Medium - Netease cover download can leak `MUSIC_U` to an untrusted image URL

**Evidence**

- `Settings.useNeteaseAuthForPlay` defaults to `true`, and cover download
  defaults to `coverOnly`: `lib/data/models/settings.dart:153`,
  `lib/data/models/settings.dart:275`, `lib/data/models/settings.dart:587`.
- Netease auth headers include the raw cookie:
  `lib/core/utils/auth_headers_utils.dart:24`,
  `lib/core/utils/auth_headers_utils.dart:27`.
- `SourceHttpPolicy.mediaHeaders()` copies `Cookie` into Netease media/image
  headers: `lib/data/sources/source_http_policy.dart:54`.
- `buildDownloadImageHeaders()` reuses `mediaHeaders()`:
  `lib/services/download/download_media_headers.dart:14`.
- `_saveMetadata()` downloads `track.thumbnailUrl` with those image headers:
  `lib/services/download/download_service.dart:1176`,
  `lib/services/download/download_service.dart:1237`,
  `lib/services/download/download_service.dart:1241`.
- A backup import can persist an arbitrary `thumbnailUrl` into a `Track`:
  `lib/services/backup/backup_data.dart:229`,
  `lib/services/backup/backup_data.dart:238`,
  `lib/services/backup/backup_service.dart:362`,
  `lib/services/backup/backup_service.dart:370`.

**Attack or failure scenario**

A user imports a crafted backup containing a valid Netease `sourceId` but an
attacker-controlled `thumbnailUrl`, then downloads the track with default
Netease auth-for-play and default cover download enabled. `_startDownload()`
resolves the Netease stream with the user's account and later `_saveMetadata()`
requests the attacker URL while sending the `Cookie` header. This can expose
`MUSIC_U` or related Netease cookies to a non-Netease host. Dio redirect
handling may also carry manually supplied headers unless explicitly stripped.

**Recommended fix**

Split image headers from media headers. `buildDownloadImageHeaders()` should not
include cookies by default. If a source genuinely needs authenticated image
requests, enforce a host allowlist before adding credentials and strip
credential headers on redirects or cross-origin final URLs.

### FMP-DL-02 - Medium - Restored or corrupted `sourceId` can place task paths outside the download base

**Evidence**

- `computeDownloadPath()` sanitizes `playlistName` and title, but concatenates
  raw `track.sourceId` into the path segment:
  `lib/services/download/download_path_utils.dart:29`,
  `lib/services/download/download_path_utils.dart:35`,
  `lib/services/download/download_path_utils.dart:47`.
- `addTracksDownload()` computes and persists `savePath` before stream
  resolution: `lib/services/download/download_service.dart:433`,
  `lib/services/download/download_service.dart:440`,
  `lib/services/download/download_service.dart:483`.
- Backup import restores `sourceId` without source-specific validation:
  `lib/services/backup/backup_data.dart:231`,
  `lib/services/backup/backup_service.dart:362`.
- Cancel/clear paths delete `task.savePath` and its parent if empty without
  checking containment under the configured base directory:
  `lib/services/download/download_service.dart:555`,
  `lib/services/download/download_service.dart:566`,
  `lib/services/download/download_service.dart:1074`,
  `lib/services/download/download_service.dart:1093`,
  `lib/services/download/download_service.dart:1116`.
- The download isolate also writes to the supplied `savePath` without a
  containment check: `lib/services/download/download_service.dart:1514`.

**Attack or failure scenario**

A crafted backup or corrupted local DB row can set `sourceId` to a Windows
absolute path or to segments containing separators. Because `p.join()` treats
absolute path segments specially on Windows and filesystem APIs resolve `..`,
the stored `savePath` can point outside the selected FMP directory. Even if
stream resolution later fails, the non-completed task remains cancellable; when
the user cancels or clears the queue, `_deleteTaskFiles()` can delete an
existing file at that outside `savePath` and remove an empty outside directory.
Normal source adapters appear to use safe IDs, so this is mainly a restored
backup/corrupt-database boundary issue.

**Recommended fix**

Sanitize `sourceId` with the same filename rules used for titles, or better,
use a source-specific safe ID encoder. After path construction, canonicalize the
base directory and candidate path and reject any candidate outside the base
before saving tasks, starting downloads, deleting files, or syncing paths.

### FMP-DL-03 - Low - Existing files at the computed destination can be overwritten

**Evidence**

- Downloads always write to a fixed temp path beside the destination:
  `lib/services/download/download_service.dart:728`,
  `lib/services/download/download_service.dart:730`.
- The isolate opens the temp file with `FileMode.write` when not resuming:
  `lib/services/download/download_service.dart:1514`,
  `lib/services/download/download_service.dart:1516`.
- Completion renames the temp file to `savePath` without first checking whether
  the final destination already exists and belongs to this task:
  `lib/services/download/download_service.dart:847`,
  `lib/services/download/download_service.dart:848`.
- Deduplication only checks existing `DownloadTask.savePath` rows, not arbitrary
  files already present on disk:
  `lib/services/download/download_service.dart:448`,
  `lib/data/repositories/download_repository.dart:47`.

**Attack or failure scenario**

If a user-selected download directory already contains a manually created file
at the deterministic FMP destination, a new download can replace or fail over
that file depending on platform rename semantics. A remote content owner cannot
choose the platform `sourceId` freely, but remote titles and user playlist
layout influence the destination enough that this is a realistic local data-loss
case in shared download directories.

**Recommended fix**

Before spawning the isolate and again before final rename, check whether
`savePath` exists. If it exists and is not the current task's known file, either
skip as already downloaded after validating expected metadata, create a unique
suffix, or fail with a user-visible conflict.

### FMP-DL-04 - Low - Windows reserved device names are not rejected by filename sanitization

**Evidence**

- `sanitizeFileName()` replaces path separators and Windows-illegal punctuation,
  trims whitespace, strips trailing dots, and bounds length:
  `lib/services/download/download_path_utils.dart:70`,
  `lib/services/download/download_path_utils.dart:84`,
  `lib/services/download/download_path_utils.dart:89`,
  `lib/services/download/download_path_utils.dart:95`.
- It does not reject reserved Windows basenames such as `CON`, `PRN`, `AUX`,
  `NUL`, `COM1`-`COM9`, and `LPT1`-`LPT9`.
- Those sanitized names are used for playlist folders and video folders:
  `lib/services/download/download_path_utils.dart:29`,
  `lib/services/download/download_path_utils.dart:35`.
- Download startup creates directories recursively:
  `lib/services/download/download_service.dart:733`,
  `lib/services/download/download_service.dart:735`.

**Attack or failure scenario**

A remote title or user playlist named `CON`, `AUX`, or similar can produce a
path that is syntactically invalid on Windows even after the current sanitizer.
This does not create path traversal, but it can make affected downloads fail
reliably on Windows.

**Recommended fix**

After trimming and dot removal, compare the basename case-insensitively against
the Windows reserved-device list. Prefix or suffix reserved names, for example
`_CON`, before length limiting.

## Checked and safe items

- Playlist names and titles are protected against direct separator traversal:
  `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, and `|` are replaced before joining
  paths: `lib/services/download/download_path_utils.dart:70`.
- Metadata, cover, and avatar filenames are fixed inside `p.dirname(audioPath)`;
  remote metadata fields do not choose output filenames:
  `lib/services/download/download_service.dart:1224`,
  `lib/services/download/download_service.dart:1228`,
  `lib/services/download/download_service.dart:1240`,
  `lib/services/download/download_service.dart:1256`.
- Metadata is written with `jsonEncode()`, so remote description/comment text is
  not string-concatenated into JSON syntax:
  `lib/services/download/download_service.dart:1182`,
  `lib/services/download/download_service.dart:1230`.
- Normal source adapters produce constrained IDs: Bilibili URL parsing accepts
  `BV[a-zA-Z0-9]{10}` and validates the same form, Netease IDs are numeric, and
  YouTube IDs are obtained through `youtube_explode_dart`/InnerTube fields:
  `lib/data/sources/bilibili_source.dart:166`,
  `lib/data/sources/bilibili_source.dart:173`,
  `lib/data/sources/netease_source.dart:52`,
  `lib/data/sources/youtube_source.dart:145`,
  `lib/data/sources/youtube_source.dart:885`.
- Android custom directory selection requests the app-owned storage permission
  path before file picking, and the native channel maps Android 11+ to
  `MANAGE_EXTERNAL_STORAGE`: `lib/services/download/download_path_manager.dart:31`,
  `lib/services/storage_permission_service.dart:85`,
  `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt:73`,
  `android/app/src/main/AndroidManifest.xml:22`.
- Desktop/custom directory selection verifies writability with a test file
  before saving: `lib/services/download/download_path_manager.dart:42`,
  `lib/services/download/download_path_manager.dart:56`,
  `lib/services/download/download_path_manager.dart:66`.
- The downloaded-category UI passes `category.folderPath` generated by the
  scanner, not a route parameter, into destructive category deletion:
  `lib/ui/pages/library/downloaded_page.dart:250`,
  `lib/ui/pages/library/downloaded_page.dart:252`,
  `lib/ui/pages/library/downloaded_page.dart:455`.
- Windows/main download work uses an isolate and bounded progress messages; the
  isolate receives a precomputed path and headers but no independent user input:
  `lib/services/download/download_service.dart:769`,
  `lib/services/download/download_service.dart:1431`,
  `lib/services/download/download_service.dart:1464`.

## Instruction docs accuracy notes

- `lib/services/AGENTS.md` matches code for save-path deduplication, existence
  check before persisting completed download paths, isolate-based downloads,
  image/media header helpers, Android storage permission channel, and default
  Android `Music/FMP` fallback behavior.
- `.serena/memories/download_system.md` correctly describes the current folder
  layout and the in-video-folder `avatar.jpg` path, but its statement that
  `_saveMetadata()` downloads avatars should be read with the code caveat that
  `videoDetail` is currently fetched only for Bilibili and YouTube in
  `DownloadService`: `lib/services/download/download_service.dart:858`,
  `lib/services/download/download_service.dart:868`,
  `lib/services/download/download_service.dart:1251`.
- `docs/reviews/security/threat-model.md` accurately identifies download path
  construction, metadata image writes, and source-aware headers as relevant
  trust boundaries; the findings above are direct instances of those modeled
  risks.
