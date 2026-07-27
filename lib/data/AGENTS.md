# lib/data AGENTS.md

Data-layer guidance for models, repositories, and migration decisions. For
concrete source adapter rules, read `lib/data/sources/AGENTS.md`. For database
startup/open wiring, read `lib/providers/AGENTS.md`.

## Dependency Note — Isar v3 Freeze

`isar` / `isar_flutter_libs` / `isar_generator` are intentionally pinned at
`^3.1.0+1` (`pubspec.yaml`). This is a deliberate freeze, not neglect:

- v3 is upstream's recommended production version. The upstream `isar/isar`
  repository is **not** archived; its README states v4 is not production-ready.
- No v3 → v4 migration tool exists, so upgrading would risk every persisted
  collection in `lib/data/models/`.
- **Do not upgrade to v4** without a migration tool and a tested migration path.

Tracking guidance: monitor v4 stable releases and any official migration tool.
Before tagging a release, confirm target-platform native libs resolve
(Android `arm64-v8a` / `armeabi-v7a` / `x86_64`, Windows `x86_64`, and Windows
`arm64` if supported). Long-term fallback candidates if v3 ever becomes
unbuildable: `drift`, `sqflite`, or `objectbox`.

## Models And Repositories

- Isar collections live in `lib/data/models/`; `models.dart` is the barrel
  export for persisted model types, including `Account`.
- CRUD repositories live in `lib/data/repositories/`.
- Source parsers live in `lib/data/sources/` and share `SourceApiException`.
- Repository bulk status changes should mutate loaded Isar objects and call
  `putAll()` inside one write transaction instead of issuing per-row `put()`.

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
| `LyricsTitleParseCache` | AI-parsed title cache; registered so lyrics matching can share repository/query code, but cleared on startup — treat as ephemeral runtime cache, not durable user data |

Non-persisted DTO/value objects in `lib/data/models/` include `LiveRoom`,
`VideoDetail`, and `HotkeyConfig`. Do not add migration logic for those unless
they become registered Isar schemas.

## Migration And Default Repair

Isar upgrade defaults for a newly added field:

| Type | Upgrades to |
|------|-------------|
| `int` | `0` |
| `bool` | `false` |
| `String?` | `null` |
| `List` | `[]` |

**Repair is needed only when Isar's type default does not match the business
default.** `bool isVip = false` upgrades to `false` automatically, so no repair.
`useNeteaseAuthForPlay`, whose business default is `true` while Isar upgrades to
`false`, must be repaired. Nullable sentinels (e.g. the lyrics popup style
fields, where `null` means "built-in default") also need no repair.

`_migrateDatabase()` in `lib/providers/database/database_provider.dart` is the
single entry point and the authoritative list of repaired fields — read it
rather than maintaining a duplicate list here. `runDatabaseMigrationForTesting()`
is the test hook, covered by `test/providers/database_migration_test.dart`.

When adding a persisted field:

1. Modify the model in `lib/data/models/`.
2. Decide whether the Isar default equals the business default.
3. If not, add repair logic in `_migrateDatabase()`.
4. Run `dart run build_runner build --delete-conflicting-outputs`.
5. Run `flutter test test/providers/database_migration_test.dart` and test
   old-version to new-version upgrade behavior.

Database open path, collection registration, and the catalog rules live in
`lib/providers/AGENTS.md` § Database Startup And Migration. Never open the Isar
database through an ad-hoc path.

## Stable Keys

List/grid items should use stable identity keys. For persisted models,
`ValueKey(item.id)` is usually enough. For tracks that may be unpersisted,
grouped, or multi-page, prefer source/group/page identity such as `sourceId` +
`pageNum` / `groupKey`.
