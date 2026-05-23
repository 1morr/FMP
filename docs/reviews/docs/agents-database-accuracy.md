# AGENTS Database Accuracy Review

Reviewed: 2026-05-21

Scope: `AGENTS.md` Data Layer, persisted collections table, Database Migration, database storage path, database viewer maintenance, and current migrated/default-repaired fields, compared against `lib/data/models/`, `lib/providers/database_provider.dart`, and `lib/ui/pages/settings/database_viewer_page.dart`.

Method: Used `rg` first for heading, schema, model, migration, path, and viewer searches, then read the relevant files with line numbers.

## Summary

The scoped database documentation is mostly current. The top-level persisted collection list, database storage path, migration/default-repair function location, and database viewer collection coverage match the code. I found no direct outdated or contradicted `AGENTS.md` claim in the scoped paragraphs.

Important missing details: startup migration clears `LyricsTitleParseCache`; migration also bootstraps missing singleton/default records; `Track` persists an embedded `PlaylistDownloadInfo` list; `Playlist` has persisted Mix metadata not called out in its table row. Two items need human decision: whether `models.dart` should export `Account`, and whether the stale-looking `LyricsMatch` model comment should be aligned with AGENTS/runtime behavior.

## Confirmed Accurate Claims

- [accurate] The persisted top-level collection table matches schema registration and database viewer collection coverage.
  Related AGENTS paragraph: Data Layer / Persisted Isar collections, `AGENTS.md:136-150`.
  Code evidence: `lib/providers/database_provider.dart:27-39` registers `Track`, `Playlist`, `PlayQueue`, `Settings`, `SearchHistory`, `DownloadTask`, `PlayHistory`, `RadioStation`, `LyricsMatch`, `LyricsTitleParseCache`, and `Account`; `lib/ui/pages/settings/database_viewer_page.dart:32-44` lists those collections and `lib/ui/pages/settings/database_viewer_page.dart:121-134` routes each collection to a view.

- [accurate] The database storage path paragraph matches production code.
  Related AGENTS paragraph: Database storage path, `AGENTS.md:164`.
  Code evidence: `lib/providers/database_provider.dart:22-24` defines `fmp_database` and file names; `lib/core/constants/app_constants.dart:8` defines the app directory name as `FMP`; `lib/providers/database_provider.dart:223-252` resolves and creates the documents-directory `FMP` child folder; `lib/providers/database_provider.dart:288-304` opens Isar through `openFmpDatabase()` using that directory.

- [accurate] The migration decision rule is reflected by current defaults and repair logic.
  Related AGENTS paragraph: Database Migration / migration decision, `AGENTS.md:158-163`.
  Code evidence: `lib/data/models/track.dart:87-92` has `isAvailable = true` and `isVip = false`, matching the documented no-repair example for a false bool default; `lib/data/models/settings.dart:230-237` gives Netease auth a business default of `true`; `lib/providers/database_provider.dart:173-179` repairs old upgraded settings when `neteaseStreamPriority` is empty.

- [accurate] The current migrated/default-repaired field list is represented in migration code.
  Related AGENTS paragraph: Current migrated/default-repaired fields, `AGENTS.md:174-183`.
  Code evidence: `lib/providers/database_provider.dart:85-179` repairs download, cache, audio quality, lyrics, stream priority, refresh interval, legacy playback/lyrics, and Netease defaults; `lib/providers/database_provider.dart:61-74` detects legacy queue volume state and `lib/providers/database_provider.dart:191-200` repairs `PlayQueue.lastVolume`; model defaults are in `lib/data/models/settings.dart:89-245` and `lib/data/models/play_queue.dart:41-42`.

- [accurate] The non-persisted DTO examples are not registered Isar collections.
  Related AGENTS paragraph: Data Layer / non-persisted DTOs, `AGENTS.md:152`.
  Code evidence: `lib/data/models/live_room.dart:21` defines `LiveRoom`, `lib/data/models/video_detail.dart:51` defines `VideoDetail`, and `lib/data/models/hotkey_config.dart:205` defines `HotkeyConfig`; none are present in `fmpDatabaseSchemas` at `lib/providers/database_provider.dart:27-39`.

## Outdated Or Contradicted Claims

None found in the scoped AGENTS.md paragraphs. The notes below are omissions or unclear ownership boundaries rather than direct contradictions.

## Missing Important Behaviors

- [missing] The Database Migration section does not mention that startup migration clears `LyricsTitleParseCache`.
  Related AGENTS paragraph: Current migrated/default-repaired fields, `AGENTS.md:174-183`.
  Code evidence: `lib/providers/database_provider.dart:186` unconditionally clears `isar.lyricsTitleParseCaches`; the collection is registered at `lib/providers/database_provider.dart:36-37` and modeled at `lib/data/models/lyrics_title_parse_cache.dart:5-19`.
  Suggested doc action: Add this startup-clearing behavior to the Database Migration section or cross-reference the Lyrics System paragraph that mentions cache clearing.

- [missing] The Database Migration section under-describes bootstrap/default initialization.
  Related AGENTS paragraphs: Migration function and current repaired/default fields, `AGENTS.md:162` and `AGENTS.md:174-183`.
  Code evidence: `lib/providers/database_provider.dart:43-49` creates platform-sensitive bootstrap settings, including `maxCacheSizeMB = 16` on mobile; `lib/providers/database_provider.dart:76-80` creates missing settings; `lib/providers/database_provider.dart:191-194` creates a missing `PlayQueue`.
  Suggested doc action: Clarify that `_migrateDatabase()` currently performs both migration repairs and startup default/bootstrap initialization.

- [missing] The Data Layer table does not call out `Track`'s persisted embedded playlist/download object.
  Related AGENTS paragraphs: Persisted Isar collections and non-persisted DTOs, `AGENTS.md:136-152`.
  Code evidence: `lib/data/models/track.dart:22-24` defines `@embedded PlaylistDownloadInfo`; `lib/data/models/track.dart:98-99` persists `List<PlaylistDownloadInfo> playlistInfo`; the database viewer exposes it at `lib/ui/pages/settings/database_viewer_page.dart:195-219`.
  Suggested doc action: Mention `PlaylistDownloadInfo` as an embedded persisted value under `Track`, especially because AGENTS says embedded object changes require database viewer maintenance.

- [missing] The `Playlist` row omits persisted Mix playlist metadata.
  Related AGENTS paragraph: Persisted Isar collections table, `AGENTS.md:140-142`.
  Code evidence: `lib/data/models/playlist.dart:49-56` persists `isMix`, `mixPlaylistId`, and `mixSeedVideoId`; the database viewer shows these fields at `lib/ui/pages/settings/database_viewer_page.dart:323-330`.
  Suggested doc action: Extend the `Playlist` row if Mix playlist persistence should be discoverable from the Data Layer table, not only from audio/queue sections.

## Architecture Rules Not Currently Followed

None found in this scoped review. The production storage path rule appears followed by `lib/providers/database_provider.dart:250-304`, and the database viewer currently covers all registered collections via `lib/ui/pages/settings/database_viewer_page.dart:32-44` and `lib/ui/pages/settings/database_viewer_page.dart:121-134`.

## Unclear Items Needing Human Decision

- [unclear] `lib/data/models/models.dart` may not be a complete model barrel because it omits `Account`.
  Related AGENTS paragraph: Data Layer / Models and persisted `Account` row, `AGENTS.md:132` and `AGENTS.md:144`.
  Code evidence: `lib/data/models/models.dart:4-13` exports the persisted model files except `account.dart`; `lib/data/models/account.dart:11-13` is an `@collection`; `lib/providers/database_provider.dart:38` registers `AccountSchema`.
  Decision needed: If `models.dart` is intended as the canonical export barrel, code diverges. If direct model imports are preferred for `Account`, no AGENTS.md change is needed.

- [unclear] The AGENTS `LyricsMatch` description appears more current than the model comment.
  Related AGENTS paragraph: Persisted `LyricsMatch` row, `AGENTS.md:149`.
  Code evidence: `lib/data/models/lyrics_match.dart:5-21` says the record stores Track-to-lrclib matches and labels Netease/QQ Music as future, while runtime loading branches on `qqmusic`, `netease`, and lrclib at `lib/providers/lyrics_provider.dart:139-147`, and match saves persist `result.source` at `lib/providers/lyrics_provider.dart:425-431`.
  Decision needed: Treat this as a code-comment cleanup unless humans intend `LyricsMatch` to remain lrclib-only at the model contract level.
