# Database / Local Data Security Review

Date: 2026-05-24

Scope: Isar models, settings, account state, lyrics cache, history, download
tasks, backup/export surfaces, and the developer database/log viewers.

Method: I treated `docs/reviews/security/instruction-document-corpus.md` and
`docs/reviews/security/threat-model.md` as review seeds only, then verified the
claims against code. This report only records issues with a realistic local
data or credential exposure path.

## Valid findings

No valid findings.

I did not find a current path where the Isar database, database viewer, backup
export, lyrics cache, history, or download task storage exposes Bilibili,
YouTube, Netease, or OpenAI-compatible API credentials. Local plaintext storage
of non-credential app state is expected by the current client-side app threat
model and is listed below as checked/safe rather than as a finding.

## Checked and safe items

### Account credentials are not persisted in Isar or shown by the database viewer

Evidence:

- `lib/data/models/account.dart:7` to `lib/data/models/account.dart:10` says
  the `Account` collection is intended to store non-sensitive user information
  and that cookies/tokens live in `flutter_secure_storage`.
- `lib/data/models/account.dart:15` to `lib/data/models/account.dart:38`
  defines only `platform`, `userId`, `userName`, `avatarUrl`, login timestamps,
  `isLoggedIn`, and `isVip`.
- `lib/services/account/bilibili_account_service.dart:108` to
  `lib/services/account/bilibili_account_service.dart:112` writes Bilibili
  credential JSON to `FlutterSecureStorage`; `lib/services/account/bilibili_account_service.dart:560`
  to `lib/services/account/bilibili_account_service.dart:584` writes only
  non-secret account profile state to Isar.
- `lib/services/account/youtube_account_service.dart:77` to
  `lib/services/account/youtube_account_service.dart:83` writes YouTube
  credential JSON to `FlutterSecureStorage`; `lib/services/account/youtube_account_service.dart:527`
  to `lib/services/account/youtube_account_service.dart:551` writes only
  non-secret account profile state to Isar.
- `lib/services/account/netease_account_service.dart:437` to
  `lib/services/account/netease_account_service.dart:447` writes Netease
  credential JSON to secure storage and only `userId`/login state to Isar.
- `lib/ui/pages/settings/database_viewer_page.dart:1088` to
  `lib/ui/pages/settings/database_viewer_page.dart:1102` displays the same
  non-secret `Account` fields and does not read secure storage.

Attack or failure scenario considered:

A user opens the developer database viewer and inspects the `Account`
collection. The viewer can reveal profile identifiers and login status, but it
does not expose `SESSDATA`, Bilibili refresh token, YouTube cookies,
`SAPISIDHASH`, `MUSIC_U`, or the lyrics AI API key because those are not Isar
fields and the viewer does not query secure storage.

Recommended fix:

No product fix required for credential exposure. Keep future account credential
fields out of `Account` and add a database viewer coverage check if a sensitive
field is ever introduced.

### Lyrics AI API key is stored outside Isar and excluded from backup/viewer

Evidence:

- `lib/data/models/settings.dart:224` to `lib/data/models/settings.dart:231`
  stores only the AI endpoint, model, and timeout in `Settings`; no API key
  field is present.
- `lib/services/lyrics/lyrics_ai_config_service.dart:82` to
  `lib/services/lyrics/lyrics_ai_config_service.dart:94` reads/writes the API
  key through the secure key-value store under `lyrics_ai_api_key`.
- `lib/providers/audio_settings_provider.dart:130` to
  `lib/providers/audio_settings_provider.dart:148` loads only a boolean
  `lyricsAiApiKeyConfigured` into UI state.
- `lib/providers/audio_settings_provider.dart:284` to
  `lib/providers/audio_settings_provider.dart:289` saves the API key through
  `LyricsAiConfigService` and keeps only the configured boolean in Riverpod
  state.
- `lib/ui/pages/settings/database_viewer_page.dart:625` to
  `lib/ui/pages/settings/database_viewer_page.dart:632` shows AI mode,
  endpoint, model, and timeout, but not the API key.
- `lib/services/backup/backup_service.dart:229` to
  `lib/services/backup/backup_service.dart:232` exports endpoint/model/timeout
  only; `test/services/backup/backup_service_test.dart:397` to
  `test/services/backup/backup_service_test.dart:451` verifies backup export
  does not include `lyricsAiApiKey`.

Attack or failure scenario considered:

A user exports a backup or opens the database viewer after configuring an
OpenAI-compatible lyrics service. The endpoint and model are visible local
configuration, but the API key remains in secure storage and is not exported or
displayed.

Recommended fix:

No product fix required. If endpoint privacy becomes a concern, label it as
configuration metadata in UI/help text, but do not move it into secure storage
unless the app threat model changes.

### Lyrics match database records do not store lyrics content; file cache is bounded app cache

Evidence:

- `lib/data/models/lyrics_match.dart:5` to
  `lib/data/models/lyrics_match.dart:8` documents that Isar stores only the
  match relation and not lyrics content.
- `lib/data/models/lyrics_match.dart:13` to
  `lib/data/models/lyrics_match.dart:27` confirms the persisted fields are
  `trackUniqueKey`, `lyricsSource`, `externalId`, `offsetMs`, and `matchedAt`.
- `lib/services/lyrics/lyrics_cache_service.dart:61` to
  `lib/services/lyrics/lyrics_cache_service.dart:66` creates the lyrics content
  cache under the app cache directory's `lyrics` child folder.
- `lib/services/lyrics/lyrics_cache_service.dart:97` to
  `lib/services/lyrics/lyrics_cache_service.dart:115` writes fetched
  `LyricsResult` JSON to that cache, not to Isar.
- `lib/services/lyrics/lyrics_cache_service.dart:18` to
  `lib/services/lyrics/lyrics_cache_service.dart:19` sets bounded defaults
  of 50 files and 5 MB.
- `lib/services/lyrics/lyrics_cache_service.dart:198` to
  `lib/services/lyrics/lyrics_cache_service.dart:230` enforces file-count and
  size eviction.
- `lib/services/lyrics/lyrics_cache_service.dart:260` to
  `lib/services/lyrics/lyrics_cache_service.dart:263` base64-url encodes the
  track key before using it as a cache filename.

Attack or failure scenario considered:

The database viewer or backup export could have exposed full cached lyrics. In
the current code, Isar and backup store only source IDs and offsets; full lyrics
content is local cache data under the app cache directory with LRU bounds.

Recommended fix:

No product fix required for credential exposure. If lyrics text is later deemed
sensitive user data, add a privacy note and keep the cache clear control visible.

### Lyrics title parse cache is ephemeral and cleared at database startup

Evidence:

- `lib/data/models/lyrics_title_parse_cache.dart:5` to
  `lib/data/models/lyrics_title_parse_cache.dart:19` registers the parsed title
  cache as an Isar collection with parsed track/artist/provider/model metadata.
- `lib/providers/database_provider.dart:207` clears
  `lyricsTitleParseCaches` during database default initialization/migration.
- `lib/providers/database_provider.dart:328` to
  `lib/providers/database_provider.dart:334` runs `_migrateDatabase()` whenever
  `databaseProvider` opens the DB.
- `lib/ui/pages/settings/database_viewer_page.dart:1017` to
  `lib/ui/pages/settings/database_viewer_page.dart:1049` shows the cache in the
  viewer, but only for the current runtime after startup clearing.

Attack or failure scenario considered:

AI title parse metadata could persist indefinitely and disclose listening/title
context through the DB. The current startup clear path makes it runtime cache
data rather than durable user data.

Recommended fix:

No product fix required. Keep `lib/data/AGENTS.md` guidance accurate if this
cache ever becomes durable.

### Backup export excludes accounts, credentials, download tasks, and raw local download paths

Evidence:

- `lib/services/backup/backup_data.dart:20` to
  `lib/services/backup/backup_data.dart:39` defines backup categories as
  playlists, tracks, play history, search history, radio stations, settings,
  and lyrics matches. There is no accounts or download tasks category.
- `lib/services/backup/backup_data.dart:93` to
  `lib/services/backup/backup_data.dart:106` serializes only those categories.
- `lib/services/backup/backup_service.dart:127` to
  `lib/services/backup/backup_service.dart:147` exports track metadata but not
  `Track.audioUrl` or `playlistInfo.downloadPath`.
- `lib/services/backup/backup_service.dart:149` to
  `lib/services/backup/backup_service.dart:171` exports play/search history as
  user data, which is expected for an explicit backup.
- `lib/services/backup/backup_service.dart:192` to
  `lib/services/backup/backup_service.dart:253` exports settings, including AI
  endpoint/model but not API key.
- `lib/services/backup/backup_service.dart:691` preserves the current device's
  `customDownloadDir` during import rather than importing the backup path.

Attack or failure scenario considered:

An exported JSON backup could have become a credential leak if it included
accounts, secure-storage credentials, signed stream URLs, or absolute download
paths. Current export code does not include those fields. It intentionally
exports library/history/search/settings data because the user explicitly chose
backup export.

Recommended fix:

No product fix required. If download tasks are later added to backup, review
absolute path and transient URL fields before serializing them.

### Developer database viewer does not show tokens, but it does show local app-state details

Evidence:

- `lib/ui/pages/settings/database_viewer_page.dart:32` to
  `lib/ui/pages/settings/database_viewer_page.dart:43` lists all registered
  collections, including `Account`.
- `lib/ui/pages/settings/database_viewer_page.dart:121` to
  `lib/ui/pages/settings/database_viewer_page.dart:133` routes each selected
  collection to its viewer widget.
- `lib/ui/pages/settings/database_viewer_page.dart:181` to
  `lib/ui/pages/settings/database_viewer_page.dart:205` shows track `audioUrl`
  and download path metadata.
- `lib/ui/pages/settings/database_viewer_page.dart:507` shows
  `customDownloadDir`.
- `lib/ui/pages/settings/database_viewer_page.dart:804` to
  `lib/ui/pages/settings/database_viewer_page.dart:857` shows download task
  status, `savePath`, error message, and timestamps.
- `lib/ui/pages/settings/settings_page.dart:881` to
  `lib/ui/pages/settings/settings_page.dart:923` implements the seven-tap
  unlock flow.
- `lib/ui/pages/settings/settings_page.dart:989` to
  `lib/ui/pages/settings/settings_page.dart:1016` hides the settings-page
  developer entry until unlocked.
- `lib/ui/router.dart:233` to `lib/ui/router.dart:249` registers the developer
  options, database viewer, and log viewer routes without a router-level
  `developerOptionsProvider` guard.

Attack or failure scenario considered:

The database viewer aggregates local app-state details that are more verbose
than normal product pages, including search/history/download paths and transient
stream URLs. The normal UI entry is hidden behind the seven-tap developer
unlock, but the router itself does not enforce that state. I am not classifying
this as a valid security finding because the viewer currently does not expose
credentials, the app has no verified external deep-link route to this page, and
the local user already controls the app data directory under the stated threat
model.

Recommended fix:

Optional hardening: add a route-level guard or in-page guard for
`/settings/developer`, `/settings/developer/database`, and
`/settings/developer/logs` so the hidden developer entry and direct route access
share the same unlock state. This is defense-in-depth rather than a required
credential-leak fix.

### Cookie parse-error logging is not a current credential leak

Evidence:

- `lib/services/account/http_cookie_parser.dart:8` to
  `lib/services/account/http_cookie_parser.dart:18` parses each Set-Cookie
  header by taking the first semicolon-separated segment and skips entries
  without `=`.
- `lib/services/account/http_cookie_parser.dart:19` to
  `lib/services/account/http_cookie_parser.dart:21` calls the optional
  `onParseError` callback only on exceptions.
- `lib/services/account/bilibili_account_service.dart:588` to
  `lib/services/account/bilibili_account_service.dart:594` would log the raw
  cookie header only if that parser callback is invoked.
- `lib/services/account/netease_account_service.dart:505` to
  `lib/services/account/netease_account_service.dart:511` has the same
  parse-error logging callback for Netease.

Attack or failure scenario considered:

If the Set-Cookie parser threw while handling a sensitive cookie header, the raw
cookie could be logged and then copied from the in-memory log viewer. Current
parser behavior does not throw for malformed missing-separator cookies; it skips
them, so this is not a present leak.

Recommended fix:

Optional hardening: redact cookie values in these parse-error callbacks anyway
so future parser changes cannot accidentally turn this into a credential leak.

## Evidence summary

The reviewed sensitive storage boundaries are:

- Isar database schemas are centrally registered in
  `lib/providers/database_provider.dart:27` to
  `lib/providers/database_provider.dart:39`.
- Runtime Isar files are opened under the app documents directory's `FMP` child
  through `openFmpDatabase()` in `lib/providers/database_provider.dart:271` to
  `lib/providers/database_provider.dart:325`.
- Account cookies/tokens and lyrics AI API key are stored through
  `FlutterSecureStorage`, not Isar.
- Database viewer reads Isar only through `databaseProvider`; it does not import
  account services or secure-storage helpers.
- Backup export is explicit user action and excludes accounts/download tasks,
  secure credentials, raw `Track.audioUrl`, and local download paths.

## Instruction docs accuracy notes

- Accurate: `lib/data/AGENTS.md` says `Account` is a persisted Isar collection
  and `LyricsTitleParseCache` is cleared on startup; verified in
  `lib/data/models/account.dart:11`, `lib/data/models/lyrics_title_parse_cache.dart:5`,
  and `lib/providers/database_provider.dart:207`.
- Accurate: `lib/providers/AGENTS.md` says runtime Isar files live under the
  app documents directory's `FMP/` child and should be opened through
  `openFmpDatabase()`; verified in `lib/providers/database_provider.dart:271`
  to `lib/providers/database_provider.dart:325`.
- Accurate: `lib/ui/AGENTS.md` says database viewer coverage must stay complete
  for Isar collections and fields; verified by the collection list in
  `lib/ui/pages/settings/database_viewer_page.dart:32` to
  `lib/ui/pages/settings/database_viewer_page.dart:43` and the coverage test's
  stated intent in `test/ui/pages/settings/database_viewer_page_coverage_test.dart:109`
  to `test/ui/pages/settings/database_viewer_page_coverage_test.dart:174`.
- Accurate with caveat: `docs/reviews/security/threat-model.md` treats
  developer database viewer exposure as local developer-context risk. Current
  code hides the settings entry behind a seven-tap unlock, but the router does
  not enforce that unlock at route level. This is a hardening gap, not a current
  token exposure.
