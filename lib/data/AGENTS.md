# lib/data AGENTS.md

Data-layer guidance for models, repositories, and migration decisions. For
concrete source adapter rules, read `lib/data/sources/AGENTS.md`. For database
startup/open wiring, read `lib/providers/AGENTS.md`.

## Dependency Note — Isar v3 On The Community Fork

`isar_community` / `isar_community_flutter_libs` / `isar_community_generator`
are pinned at `^3.3.2` (`pubspec.yaml`). FMP moved off the upstream
`isar` packages in Phase 2 (see `docs/review/05-roadmap.md`).

Why the fork:

- Upstream `isar/isar` has been dormant since 2025-07; its `isar_generator`
  constrains `analyzer >=4.6.0 <6.0.0`, which froze the whole toolchain at
  analyzer 5.13.0 / build 2.4.1. The fork's generator wants
  `analyzer >=8.0.0 <11.0.0`, which is what unblocked analyzer 10.x.
- The fork also ships 16 KB-aligned Android libraries: every `libisar.so`
  LOAD segment moved from `0x1000` to `0x4000` across all four ABIs, which is
  what Android 15+ requires.

Why it is safe for existing databases:

- Still Isar **v3** on disk. All eleven collections regenerate to semantically
  identical code — the schema id hashes, property ids, and index/link
  definitions are unchanged; only formatting and the embedded generator
  version string differ.
- `CollectionSchema.version` is a build-time `assert(Isar.version == version)`
  guarding stale generated files. It is not an on-disk format check.

What differs and bites if forgotten:

- The Windows dynamic library is named `libisar.dll`, not `isar.dll`. Linux
  and macOS names are unchanged.
- The Windows plugin header moved to
  `<isar_community_flutter_libs/isar_flutter_libs_plugin.h>`; the plugin class
  and registrar name (`IsarFlutterLibsPlugin`) did not change. FMP registers it
  by hand for sub-windows in `windows/runner/flutter_window.cpp`.
- `test/support/isar_test_harness.dart` is the only place in `test/` that knows
  the package name and per-platform library file names. Keep it that way.

Honest limitation: the fork is *maintained*, not actively developed — five
releases total, the last one months old. It solves "nobody is minding the
upstream", not "back under active development". **Do not upgrade to v4**
without a migration tool and a tested migration path. Long-term fallback
candidates if v3 ever becomes unbuildable: `drift`, `sqflite`, or `objectbox`.

## Models And Repositories

**`isar.` / `_isar.` may appear only under `lib/data/repositories/`**, plus two
named exemptions: `lib/providers/database/database_migration.dart` (it runs
after `Isar.open()` and is by definition the layer holding the `Isar` handle)
and `lib/providers/database/database_catalog.dart` (its `query: (isar) => …`
closures *are* the debug viewer). Anything else that needs Isar gets a
repository method.

`test/data/repositories/isar_boundary_static_rule_test.dart` pins this rule and
carries the same allowlist. Measured counts, import lines excluded:
`database_catalog.dart` 11, `database_migration.dart` 8, everything else outside
`lib/data/repositories/` zero. `database_provider.dart` and
`database_viewer_page.dart` import the `Isar` **type** but never touch an
instance, so neither needs an exemption.

A repository is **not** "one per collection". `TrackRepository` reads
`playlists`, `playQueues` and `lyricsMatchs` for its orphan sweep;
`DownloadRepository` reads `tracks`; `PlaylistMutationRepository` and
`DataIntegrityRepository` own write transactions spanning up to five
collections. Cross-collection atomic writes are the data layer's job — a
service that opens its own `writeTxn` has the boundary in the wrong place.

**Do not add an `abstract interface class Repository` layer.** Immich spent
20+ PRs deleting theirs. The existing classes are already the thin abstraction.

- Isar collections live in `lib/data/models/`; `models.dart` is the barrel
  export for persisted model types, including `Account`.
- CRUD repositories live in `lib/data/repositories/`.
- Source parsers live in `lib/data/sources/` and share `SourceApiException`.
- Repository bulk status changes should mutate loaded Isar objects and call
  `putAll()` inside one write transaction instead of issuing per-row `put()`.

## Persisted Isar Collections

| Model | Description |
|-------|-------------|
| `Track` | Song entity (`sourceType` as a `SourceIds` string, `isVip`, `originalSongId`/`originalSource`, `bilibiliAid` populated on demand) |
| `Playlist` | Playlist (`ownerName`, `ownerUserId`, `useAuthForRefresh`) |
| `PlayQueue` | Play queue, Mix state, position persistence, volume persistence |
| `Settings` | Quality, lyrics, AI modes, popup style, refresh intervals, desktop layout, and one embedded `sourceSettings` entry per source (stream priority + play auth) |
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
| `int` (non-nullable) | **`Isar.minLong`** (`-9223372036854775808`), *not* `0` |
| `double` (non-nullable) | `double.nan`, *not* `0.0` |
| `bool` | `false` |
| `String` (non-nullable) | `''` |
| `String?` | `null` |
| `List` | `[]` |

The two numeric rows were measured against a real pre-Phase-3 database when
`Settings.schemaVersion` was added: the existing row read back as
`-9223372036854775808`. Isar's generated reader calls `readLong`/`readDouble`,
which return the type's null sentinel for a property the stored schema does not
have — it does not fall back to the Dart field initialiser. **A new
non-nullable numeric field therefore always needs repair**, even when its
business default looks like zero.

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
4. Run `dart run build_runner build`.
5. Run `flutter test test/providers/database_migration_test.dart` and test
   old-version to new-version upgrade behavior.

Database open path, collection registration, and the catalog rules live in
`lib/providers/AGENTS.md` § Database Startup And Migration. Never open the Isar
database through an ad-hoc path.

## Stable Keys

`lib/data/models/track_key.dart` is the **only** implementation of the track
identity key. Never inline `'${sourceType.name}:$sourceId'` again — call
`TrackKey.format` (with `cid`) or `TrackKey.formatGroup` (without).

That string is part of the persisted format, not an internal detail:

- `Track.sourcePageKey` is an Isar composite-index getter, and Isar only
  recomputes index entries on `put`. Changing the literal output silently
  desynchronises existing rows from new queries.
- `TrackBackup.uniqueKey` and `PlayHistoryBackup.trackKey` are the foreign key
  the backup format uses to reattach play history to tracks.

`test/data/models/track_key_test.dart` pins the literal output and asserts all
nine producers agree. Keep it that way.

The key discriminates parts by **`cid`, not `pageNum`**. Callers that need
pageNum (the in-process stream-resolution cache) append it themselves — see
`stream_resolution_service.dart`.

List/grid items should use stable identity keys. For persisted models,
`ValueKey(item.id)` is usually enough. For tracks that may be unpersisted,
grouped, or multi-page, prefer source/group/page identity such as `sourceId` +
`pageNum` / `groupKey`.
