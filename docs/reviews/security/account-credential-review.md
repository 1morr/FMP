# Account / Credential Security Review

Scope: Bilibili, YouTube, and Netease login, cookie/token storage, SAPISIDHASH,
`MUSIC_U`, auth header use, logging, UI display, and error propagation.

## Valid findings

### Medium: Malformed secure-storage credential JSON can expose tokens through logs

The three account services store credential JSON in `FlutterSecureStorage`, then
parse it with `jsonDecode()` during credential load. If that stored value becomes
malformed while still containing credential text, `jsonDecode()` can throw a
`FormatException` whose string form includes the rejected source snippet. The
services pass that raw exception object into `AppLogger`, and the log viewer
renders/copies `entry.error.toString()`. This can expose `SESSDATA`,
`refreshToken`, YouTube cookies/SAPISID-derived material, or `MUSIC_U` through
console output and the in-app log detail UI after a storage corruption, partial
write, bad restore, or manual support/debug manipulation.

Affected load paths:

- `lib/services/account/bilibili_account_service.dart:546` reads the Bilibili
  credential JSON and `lib/services/account/bilibili_account_service.dart:549`
  parses it; parse failures are logged with the raw exception at
  `lib/services/account/bilibili_account_service.dart:554`.
- `lib/services/account/youtube_account_service.dart:514` reads the YouTube
  credential JSON and `lib/services/account/youtube_account_service.dart:517`
  parses it; parse failures are logged with the raw exception at
  `lib/services/account/youtube_account_service.dart:522`.
- `lib/services/account/netease_account_service.dart:391` reads the Netease
  credential JSON and `lib/services/account/netease_account_service.dart:397`
  parses it; parse failures are logged with the raw exception at
  `lib/services/account/netease_account_service.dart:403`.
- Stored values contain credential fields: Bilibili writes JSON at
  `lib/services/account/bilibili_account_service.dart:109`,
  `lib/services/account/bilibili_account_service.dart:111`, and includes
  `sessdata` / `refreshToken` at
  `lib/services/account/bilibili_credentials.dart:32`; YouTube writes JSON at
  `lib/services/account/youtube_account_service.dart:77`,
  `lib/services/account/youtube_account_service.dart:79`, and includes
  `SAPISID` / secure PSID cookies at
  `lib/services/account/youtube_credentials.dart:57`; Netease writes JSON at
  `lib/services/account/netease_account_service.dart:438`,
  `lib/services/account/netease_account_service.dart:440`, and includes
  `musicU` at `lib/services/account/netease_credentials.dart:30`.
- `AppLogger` stores the error object in the in-memory log entry at
  `lib/core/logger.dart:120`, prints it to debug output at
  `lib/core/logger.dart:151`, and the log viewer displays and copies
  `entry.error.toString()` at
  `lib/ui/pages/settings/log_viewer_page.dart:292` and
  `lib/ui/pages/settings/log_viewer_page.dart:314`.

## Checked and safe items

- Normal account metadata persistence does not store cookies or tokens in Isar:
  `Account` only contains platform, user ID/name/avatar, login state, timestamps,
  and VIP state at `lib/data/models/account.dart:15`.
- The developer database viewer displays only those non-secret `Account` fields,
  not secure-storage credentials, at
  `lib/ui/pages/settings/database_viewer_page.dart:1087`.
- Bilibili, YouTube, and Netease credentials are written to
  `FlutterSecureStorage`, not to the `Account` collection:
  `lib/services/account/bilibili_account_service.dart:109`,
  `lib/services/account/youtube_account_service.dart:77`, and
  `lib/services/account/netease_account_service.dart:438`.
- YouTube SAPISIDHASH is derived per request from the stored `SAPISID` and
  YouTube origin, rather than persisted as a long-lived derived header:
  `lib/services/account/youtube_credentials.dart:97`.
- Playback/download media headers are source-scoped. `SourceHttpPolicy` drops
  Bilibili and YouTube auth from media headers and only merges allowed Netease
  media auth keys at `lib/data/sources/source_http_policy.dart:33` and
  `lib/data/sources/source_http_policy.dart:54`; tests cover this boundary at
  `test/data/sources/source_http_policy_test.dart:7` and
  `test/data/sources/source_http_policy_test.dart:25`.
- The current playback path respects `useAuthForPlay()` before resolving media
  auth headers at `lib/services/audio/audio_stream_manager.dart:186` and
  `lib/services/audio/audio_stream_manager.dart:189`; stream selection and
  fallback do the same at
  `lib/services/audio/internal/audio_stream_delegate.dart:71` and
  `lib/services/audio/internal/audio_stream_delegate.dart:124`.
- YouTube authenticated source calls keep `Cookie` / `Authorization` on
  InnerTube API requests via `_innerTubeRequestOptions()` at
  `lib/data/sources/youtube_source.dart:49` and
  `lib/data/sources/youtube_source.dart:117`, not normal media headers.
- Netease source calls intentionally reduce incoming auth headers to only
  `Cookie` for source-owned API calls at `lib/data/sources/netease_source.dart:741`.
- Login UI error messages reviewed here do not directly interpolate cookie
  values; YouTube missing-cookie errors include names only at
  `lib/ui/pages/settings/youtube_login_page.dart:153`, and Bilibili/Netease
  WebView extraction paths pass cookie values directly to account services at
  `lib/ui/pages/settings/bilibili_login_page.dart:165` and
  `lib/ui/pages/settings/netease_login_page.dart:155`.
- Backup/export code does not include account credentials or the `Account`
  collection; `BackupData.toJson()` exports playlists, tracks, history,
  searches, radio stations, settings, and lyrics matches at
  `lib/services/backup/backup_data.dart:93`.

## Evidence

- Credential storage and parse evidence:
  `lib/services/account/bilibili_account_service.dart:109`,
  `lib/services/account/bilibili_account_service.dart:546`,
  `lib/services/account/bilibili_account_service.dart:549`,
  `lib/services/account/bilibili_account_service.dart:554`,
  `lib/services/account/youtube_account_service.dart:77`,
  `lib/services/account/youtube_account_service.dart:514`,
  `lib/services/account/youtube_account_service.dart:517`,
  `lib/services/account/youtube_account_service.dart:522`,
  `lib/services/account/netease_account_service.dart:438`,
  `lib/services/account/netease_account_service.dart:391`,
  `lib/services/account/netease_account_service.dart:397`,
  `lib/services/account/netease_account_service.dart:403`.
- Credential contents evidence:
  `lib/services/account/bilibili_credentials.dart:32`,
  `lib/services/account/youtube_credentials.dart:57`,
  `lib/services/account/netease_credentials.dart:30`.
- Log exposure evidence:
  `lib/core/logger.dart:120`, `lib/core/logger.dart:151`,
  `lib/ui/pages/settings/log_viewer_page.dart:292`,
  `lib/ui/pages/settings/log_viewer_page.dart:314`.
- Safe storage/UI/header boundary evidence:
  `lib/data/models/account.dart:15`,
  `lib/ui/pages/settings/database_viewer_page.dart:1087`,
  `lib/data/sources/source_http_policy.dart:33`,
  `lib/data/sources/source_http_policy.dart:54`,
  `test/data/sources/source_http_policy_test.dart:7`,
  `lib/services/audio/audio_stream_manager.dart:186`,
  `lib/services/audio/internal/audio_stream_delegate.dart:71`.

## Attack or failure scenario

1. A user has valid Bilibili, YouTube, or Netease credentials stored in secure
   storage.
2. The stored JSON is corrupted or manually altered but still contains raw token
   text, for example during a failed restore, partial platform storage write, or
   support/debug manipulation.
3. App startup, account status check, stream resolution, import, or account UI
   calls `_loadCredentials()`.
4. `jsonDecode()` fails and the catch block logs the raw exception object.
5. `AppLogger` keeps the error in memory, prints it to debug output, and the
   log viewer can display or copy the raw exception text. If the exception text
   includes the malformed credential source, long-lived cookies such as
   `MUSIC_U` or Bilibili/YouTube session cookies are exposed outside secure
   storage.

## Recommended fix

- Replace raw exception logging in credential loaders with fixed, sanitized
  messages. Keep the parse failure type if needed, but do not pass the exception
  object or raw stored JSON into `AppLogger`.
- Consider deleting the bad secure-storage entry after a parse failure and
  marking the corresponding `Account` as logged out, so the app does not keep
  retrying and re-logging the same malformed secret.
- Add regression tests with malformed credential JSON containing sentinel token
  strings and assert that no `AppLogger` message or error field contains the
  sentinel.
- Longer term, add a logger redaction layer for common sensitive keys and
  patterns: `Cookie`, `Authorization`, `SESSDATA`, `bili_jct`, `refreshToken`,
  `SAPISID`, `__Secure-*`, and `MUSIC_U`.

## Instruction docs accuracy notes

- `lib/data/models/account.dart:9` says `Account` stores non-sensitive user
  information and cookies/tokens live in secure storage. Code verification
  supports this for the reviewed account model and services.
- `lib/services/AGENTS.md:79` describes Bilibili QR/WebView, YouTube WebView +
  SAPISIDHASH, and Netease QR/WebView + `MUSIC_U`; code verification supports
  those flows at `lib/ui/pages/settings/bilibili_login_page.dart:161`,
  `lib/ui/pages/settings/youtube_login_page.dart:87`,
  `lib/ui/pages/settings/netease_login_page.dart:147`, and
  `lib/services/account/youtube_credentials.dart:97`.
- `lib/data/sources/AGENTS.md:176` says media headers merge auth only for
  Netease. Code and tests support that at
  `lib/data/sources/source_http_policy.dart:54` and
  `test/data/sources/source_http_policy_test.dart:7`.
- Prior descriptive source-review notes about Netease playback ignoring
  `useNeteaseAuthForPlay` are no longer accurate against current code:
  playback now checks `useAuthForPlay()` before loading media auth headers at
  `lib/services/audio/audio_stream_manager.dart:186`.
