# Persistence: Isar models, repositories, migrations

Isar is `isar_community` v3 (ADR 0007). Only repositories touch it (ADR 0002,
gated by `test/data/static_rules/isar_boundary_static_rule_test.dart`).

## Isar models (`lib/data/models/`)

- `@collection class X { Id id = Isar.autoIncrement; … }` plus
  `part 'x.g.dart';`. `Settings` is the singleton exception with `Id id = 0`.
- Models are **mutable classes with field initialisers**: `late String sourceId;`
  for required fields, nullable for optional ones, defaults like
  `bool isAvailable = true`. Build them with cascades
  (`PlayHistory()..sourceId = …`). No `const`, `copyWith` or `==` on collections;
  copies use a hand-written `copy()` (`Track.copy`).
- Conversions are methods on the model: `PlayHistory.fromTrack(track)`, `toTrack()`.
- `@Index()` on lookup and sort fields. Getter indexes
  (`Track.sourcePageKey`, `PlayHistory.trackKey`) are recomputed only on `put`, so
  changing a getter's output needs a rewrite migration.
- **`@embedded` values must be replaced, not mutated in place**: build a new
  object and a new list, or Isar will not see the change (`Settings._putEntry`,
  comments in `track.dart` / `settings.dart`).
- Enums: new `Settings` fields use an `int xxxIndex` column plus `@ignore`
  getter/setter (`themeModeIndex` / `themeMode`); `@Enumerated(EnumType.name)`
  also exists (`DownloadTask.status`). Source ids are never enums — `String` with
  `SourceIds.*` (ADR 0001).
- Default tables are data, not schema: `kDefaultStreamPriorityBySource`,
  `kDefaultUseAuthForPlayBySource`, keyed by `SourceIds`.
- Removing a field: mark it `@Deprecated('read only by the vN to vN+1 migration…')`;
  the `deprecated_member_use_from_same_package` lint keeps every other file off it.
  Delete it outright once nothing reads it (`6de4dfca`).
- Credentials are never persisted in Isar: `Account` keeps non-sensitive fields,
  cookies and tokens go to `SecureKeyValueStore` (`lib/core/secure_key_value_store.dart`).
- Not every file in `models/` is a collection; the registered list is
  `database_catalog.dart` (`docs/development.md` § 資料模型分類).

## Registering a collection

Add a `_collection<T>(…)` entry to `fmpDatabaseCollections` in
`lib/data/database/database_catalog.dart`. The schema list passed to `Isar.open`
is derived from it. The database is opened only by `openFmpDatabase()`.

## Migrations

The procedure lives in the `kFmpSchemaVersion` dartdoc in
`lib/data/database/database_migration.dart` — follow it, do not re-derive it.
Points that bite:

- Old rows read a new non-null field as Isar's type default (`int` → `Isar.minLong`,
  `bool` → false, `String` → `''`). If that differs from the business default,
  add a `NamedMigrationStep` and bump the version.
- Version-independent repairs (`repairSettingsInvariants`, the startup lyrics
  relink) run every launch and take no version number.
- A removed step stays as a no-op so the version list has no gap.
- A new `Settings` field must also be exported and imported by backup, or listed
  in `_deliberatelyExcludedSettingsFields` with a reason
  (`test/services/static_rules/settings_backup_coverage_static_rule_test.dart`).
- Verify with the *Isar models / migrations* row of AGENTS.md § Verification; for
  risky schema work also run `test/manual/real_db_probe.dart` against a **copy**
  of a real database.

## Repositories (`lib/data/repositories/`)

- Concrete class taking `Isar` (usually `XRepository(this._isar)`;
  `PlaylistMutationRepository({required Isar isar})` is the named-param outlier);
  no repository interface layer (ADR 0002). Add `with Logging` if it logs.
- Most providers live in `lib/data/database/repository_providers.dart` in this
  shape. Exceptions: `downloadRepositoryProvider` (`lib/providers/download/`,
  `requireValue`), `radioRepositoryProvider` (`radio_controller.dart`, nullable),
  and `QueueRepository` / `PlaylistMutationRepository`, which providers construct
  inline with no provider of their own:

  ```dart
  final xRepositoryProvider = Provider<XRepository>((ref) {
    final db = ref.watch(databaseProvider).value;
    if (db == null) throw StateError('Database not initialized');
    return XRepository(db);
  });
  ```

- Method names: reads `getById` / `getAll` / `getBySourceId` / `getOrCreate`,
  writes `save` / `saveAll` / `delete` / `upsert` / `update(mutate)`, streams
  `watch` / `watchAll` / `watchById`. Return Isar models directly, no mapping layer.
- Every write is inside `_isar.writeTxn(...)`. Read-modify-write happens in the
  **same** txn (`SettingsRepository.update(void Function(Settings) mutate)` —
  separate get/save lost updates between notifiers).
- A method named `…InTxn` assumes the caller is already inside `writeTxn` and
  takes no txn handle; a nested `writeTxn` throws (`4bfab27d`). Pair it with a
  wrapper: `addTracks => _isar.writeTxn(() => addTracksInTxn(...))`.
- Cross-collection atomic writes belong in a repository, not a service
  (`BackupRepository.writeImport`: all or nothing, `8a43d914`).
- Repositories set `updatedAt` before `put`, and take policy numbers from callers
  (`addHistory(keepAtMost:)`) instead of reading settings.
- Watch streams use `watch(fireImmediately: true)` for lists and
  `watchLazy()` for change pings.

## Identity keys

Build track keys only with `TrackKey.format(sourceType, sourceId, cid:)` /
`TrackKey.formatGroup`; never inline `'$type:$id'`. Output is pinned by
`test/data/models/track_key_test.dart` (ADR 0005). When a `cid` is backfilled,
the lyrics match is relinked in the same txn (`TrackRepository.backfillCid`).

## Tests

Repositories are tested against a real Isar in a temp directory, never a fake:

```dart
setUpAll(initializeIsarForTests);                  // test/support/isar_test_harness.dart
setUp(() async {
  tempDir = await Directory.systemTemp.createTemp('x_repository_test_');
  isar = await Isar.open([XSchema], directory: tempDir.path, name: 'x_repository_test');
});
tearDown(() async {
  await isar.close(deleteFromDisk: true);
  if (await tempDir.exists()) await tempDir.delete(recursive: true);
});
```

Open only the schemas the test needs. Code that needs a repository but not a
database passes `FakeIsar()` or uses `FakeSettingsRepository`
(`test/support/fakes/`). Migration tests call `runDatabaseMigrationForTesting`.
