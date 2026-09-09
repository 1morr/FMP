# lib/data AGENTS.md

Models, repositories, database startup and migration. Source adapter rules live
in `lib/data/sources/AGENTS.md`.

## Isar v3 On The Community Fork

`isar_community` / `isar_community_flutter_libs` / `isar_community_generator`
are pinned at `^3.3.2`. Why the fork:

- Upstream `isar/isar` has been dormant since 2025-07 and its generator
  constrains `analyzer >=4.6.0 <6.0.0`, which froze the whole toolchain at
  analyzer 5.13.0 / build 2.4.1. The fork wants `analyzer >=8.0.0 <11.0.0`.
- It ships 16 KB-aligned Android libraries — every `libisar.so` LOAD segment
  moved from `0x1000` to `0x4000`, which Android 15+ requires.

It is still Isar **v3 on disk**: all collections regenerate to semantically
identical code, and `CollectionSchema.version` is a build-time assert guarding
stale generated files, not an on-disk format check.

What bites if forgotten:

- The Windows dynamic library is `libisar.dll`, not `isar.dll`, and its plugin
  header moved to `<isar_community_flutter_libs/isar_flutter_libs_plugin.h>`.
  FMP registers the plugin by hand for sub-windows in
  `windows/runner/flutter_window.cpp`.
- `test/support/isar_test_harness.dart` is the only place in `test/` that knows
  the package name and per-platform library file names. Keep it that way.

Honest limitation: the fork is *maintained*, not actively developed — five
releases, the last months old. It solves "nobody is minding the upstream", not
"back under active development". **Do not upgrade to v4** without a migration
tool and a tested migration path. Long-term fallbacks if v3 becomes
unbuildable: `drift`, `sqflite`, `objectbox`.

## Models And Repositories

**`isar.` / `_isar.` may appear only under `lib/data/repositories/`**, plus two
named exemptions in `lib/data/database/`: `database_migration.dart` (it runs
after `Isar.open()` and is by definition the layer holding the handle) and
`database_catalog.dart` (its `query: (isar) => …` closures *are* the debug
viewer). Anything else that needs Isar gets a repository method.
`test/data/repositories/isar_boundary_static_rule_test.dart` pins this and
carries the allowlist.

A repository is **not** "one per collection" — several own write transactions
spanning up to five. Cross-collection atomic writes are the data layer's job; a
service that opens its own `writeTxn` has the boundary in the wrong place. **Do
not add an `abstract interface class Repository` layer.** The reasoning, and the
alternatives that were rejected, are in `docs/adr/0002-repository-boundary.md`.

- Isar collections live in `lib/data/models/`; `models.dart` is the barrel for
  persisted model types.
- Source parsers live in `lib/data/sources/` and share `SourceApiException`.
- Bulk status changes mutate loaded objects and call `putAll()` inside one write
  transaction, never per-row `put()`.
- `LyricsTitleParseCache` is registered as a collection so lyrics matching can
  share repository code, but it is cleared on startup — treat it as an ephemeral
  runtime cache, not durable user data.
- Non-persisted DTOs also live in `lib/data/models/`. Do not add migration logic
  for one unless it becomes a registered schema.

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

The two numeric rows were measured against a real pre-`schemaVersion` database:
the existing row read back as `-9223372036854775808`. Isar's generated reader
calls `readLong`/`readDouble`, which return the type's null sentinel for a
property the stored schema does not have — it does not fall back to the Dart
field initialiser. **A new non-nullable numeric field therefore always needs
repair**, even when its business default looks like zero. Read the stored
version through `effectiveSchemaVersion()`, never the raw field, for the same
reason.

**Repair is needed only when Isar's type default does not match the business
default.** `bool isVip = false` upgrades to `false`, so no repair. Netease's
`useAuthForPlay`, whose business default is `true`, must be repaired. Nullable
sentinels (where `null` means "built-in default") need none.

`database_migration.dart` separates two things that used to be one:

- **Versioned steps** (`fmpMigrationSteps`, gated on `Settings.schemaVersion`)
  run once each, in order, and stamp the version. Add a step and bump
  `kFmpSchemaVersion` together.
- **Invariants** (`repairSettingsInvariants`, `hasUnwrittenQueueSignature`) run
  on every launch regardless of version. They also defend against a bad backup
  import and a downgrade round-trip, so never version-gate them.

The v1 to v2 step **copies without clearing**: the six old per-source columns
stay populated so installing an older build back over the database keeps
per-source settings. They are `@Deprecated`, and
`deprecated_member_use_from_same_package` makes "only the migration reads them"
a compiler rule rather than a convention.

`runDatabaseMigration()` is the single entry point and the authoritative list of
repaired fields — read it rather than maintaining a duplicate list here.
`runDatabaseMigrationForTesting()` in `database_provider.dart` is the test hook.

When adding a persisted field:

1. Modify the model in `lib/data/models/`.
2. Decide whether the Isar default equals the business default; if not, add
   repair logic in `runDatabaseMigration()`.
3. `dart run build_runner build`.
4. `flutter test test/providers/database_migration_test.dart`, and test an
   old-version to new-version upgrade.
5. If collection or schema visibility changed, update `database_catalog.dart`
   in the same change — the debug viewer routes entirely off it, so a
   collection or field missing there is invisible in the viewer without any
   compile or test failure.

## Database Startup

- Runtime Isar files live under the app documents directory's `FMP/` child.
  Open through `openFmpDatabase()` **only** — never open `fmp_database`
  directly from `getApplicationDocumentsDirectory()` elsewhere.
- Collection registration is catalog-owned in `database_catalog.dart`;
  `database_provider.dart` owns opening and paths; `database_migration.dart`
  owns migration.

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

`test/data/models/track_key_test.dart` pins the literal output and asserts every
producer agrees. The key discriminates parts by **`cid`, not `pageNum`**;
callers needing pageNum append it themselves.

List/grid items should use stable identity keys — `ValueKey(item.id)` for
persisted models, source/group/page identity for tracks that may be
unpersisted, grouped or multi-page.
