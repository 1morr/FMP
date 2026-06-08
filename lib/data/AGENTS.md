# lib/data AGENTS.md

Data-layer guidance for models, repositories, and source-adjacent value objects.
For concrete source adapter rules, also read `lib/data/sources/AGENTS.md`.

## Models And Repositories

- Isar collections live in `lib/data/models/`.
- `lib/data/models/models.dart` is the barrel export for persisted model types,
  including `Account`.
- CRUD repositories live in `lib/data/repositories/`.
- Audio source parsers live in `lib/data/sources/` and share
  `SourceApiException`.
- Repository bulk status changes should mutate loaded Isar objects and call
  `putAll()` inside one write transaction instead of issuing per-row `put()`
  calls.

## Persisted Isar Collections

| Model | Description |
|-------|-------------|
| `Track` | Song entity (`SourceType`, `isVip`, `originalSongId`/`originalSource`, `bilibiliAid` populated on demand) |
| `Playlist` | Playlist (`ownerName`, `ownerUserId`, `useAuthForRefresh`) |
| `PlayQueue` | Play queue, Mix state, position persistence, volume persistence |
| `Settings` | Quality, auth, lyrics, AI modes, popup style, refresh intervals, per-source stream priority |
| `Account` | Platform account login/VIP state |
| `RadioStation` | Radio/live station |
| `PlayHistory` | Play history record |
| `SearchHistory` | Search history |
| `DownloadTask` | Download task |
| `LyricsMatch` | Track-to-lyrics match (`lrclib`/Netease/QQ Music) |
| `LyricsTitleParseCache` | Registered Isar collection for AI-parsed title cache; cleared on startup and treated as an ephemeral runtime cache |

Non-persisted DTO/value objects in `lib/data/models/` include `LiveRoom`,
`VideoDetail`, and `HotkeyConfig`. Do not add database migration logic for those
unless they become registered Isar schemas.

## Database Migration

When modifying Isar models, decide whether migration/default repair is needed.

Isar upgrade defaults:
- `int` -> `0`
- `bool` -> `false`
- `String?` -> `null`
- `List` -> `[]`

A migration/default repair is needed only when Isar's type default does not
match the business default. Example: `bool isVip = false` upgrades to `false`
automatically, so no repair logic is required. A field like
`useNeteaseAuthForPlay`, whose business default is `true` while Isar upgrades to
`false`, must be repaired.

Migration/default repair entry point:
- `_migrateDatabase()` in `lib/providers/database/database_provider.dart`
- testing helper: `runDatabaseMigrationForTesting()`
- Persisted collection registration is catalog-owned in
  `lib/providers/database/database_catalog.dart`; migration/default repair
  remains in `lib/providers/database/database_provider.dart`.

Database storage path:
- Runtime Isar files live under the app documents directory's `FMP/` child
  folder.
- Open through `openFmpDatabase()` in `lib/providers/database/database_provider.dart`.
- Do not open `fmp_database` directly from `getApplicationDocumentsDirectory()`
  elsewhere.

`LyricsTitleParseCache` is intentionally registered as an Isar collection so
lyrics matching can share repository/query code, but `_migrateDatabase()` clears
it on startup. Treat it as ephemeral runtime cache data, not durable user data.

When adding a persisted field:
1. Modify the model in `lib/data/models/`.
2. Decide whether Isar default equals business default.
3. If needed, add repair logic in `_migrateDatabase()`.
4. Run `flutter pub run build_runner build --delete-conflicting-outputs`.
5. Test old-version to new-version upgrade behavior.

## Current Default-Repaired Fields

- `maxConcurrentDownloads`, `maxCacheSizeMB`, `audioQualityLevelIndex`,
  `downloadImageOptionIndex`
- `lyricsDisplayModeIndex`, `maxLyricsCacheFiles`, `lyricsSourcePriority`,
  `disabledLyricsSources`
- `lyricsAiTitleParsingModeIndex` (legacy index `1`/fallback repaired to `off`)
  and `lyricsAiTimeoutSeconds` (default 20s)
- Lyrics popup style fields use nullable sentinels; `null` means built-in
  default popup style, so no upgrade repair is needed.
- `audioFormatPriority`, `youtubeStreamPriority`, `bilibiliStreamPriority`,
  `neteaseStreamPriority`
- `rankingRefreshIntervalMinutes`, `homeRankingSourcePriority`,
  `disabledHomeRankingSources`, `radioRefreshIntervalMinutes`
- `useNeteaseAuthForPlay` (business default `true`, Isar default `false`)
- Legacy default-signature repair for `rememberPlaybackPosition`,
  `tempPlayRewindSeconds`, and disabled lrclib auto-match defaults
- Legacy queue default repair for `PlayQueue.lastVolume`

`allowPlainLyricsAutoMatch = false` matches Isar bool default, so no repair is
needed.

## Stable Keys

List/grid items should use stable identity keys. For persisted models,
`ValueKey(item.id)` is usually enough. For tracks that may be unpersisted,
grouped, or multi-page, prefer source/group/page identity such as `sourceId` +
`pageNum` / `groupKey`.
