# lib/providers AGENTS.md

Guidance for Riverpod providers, provider invalidation, and database startup.

## Directory Layout

Providers live in semantic subdirectories; do not add new `.dart` files directly
under `lib/providers/`.

- `account/` — login/account state and source account services.
- `audio/` — playback selectors and audio/playback settings.
- `database/` — Isar startup and repository providers.
- `download/` — download state, path, scanner, and file-existence cache.
- `library/` — playlists, play history, remote sync, imports, and track detail.
- `lyrics/` — lyrics search/cache state and lyrics window style.
- `search/` — search, ranking/popular content, and refresh orchestration.
- `settings/` — persisted user settings not owned by a narrower subsystem.
- `system/` — backup, update, and desktop-window integration.
- `ui/` — UI-only state such as selection mode.

## Provider Patterns

| Source | Pattern | Example |
|--------|---------|---------|
| DB collection, multi-writer | Isar `watchAll()` + `StateNotifier` | Playlists, radio |
| DB join query | `StateNotifier` + optimistic update | Playlist detail |
| File system scan | `FutureProvider` + `invalidate` | Downloaded page |
| API + cache state | `StateNotifierProvider` + immutable state | Home/explore rankings (`RankingCacheState`) |
| Settings | `StateNotifier` + direct state update | Settings page |

Rules:

- Pages using `isLoading` must guard with `isLoading && data.isEmpty`.
- `FutureProvider` data must be invalidated after mutations, and optimistic
  updates must roll back on failure.
- Mutation side effects needing playlist/detail/cover/download invalidation go
  through `libraryInvalidationCoordinatorProvider`; UI widgets must not guess
  related provider families manually.
- Play history uses `watchLazy()` plus a shared snapshot stream rather than the
  playlist/radio `watchAll()` data notifier pattern. Profile large history
  datasets before changing its watch/query shape.
- Ranking cache UI must watch the immutable `RankingCacheState` from
  `rankingCacheServiceProvider`; refresh/timer methods go through
  `.notifier`, not by reading mutable service snapshot lists. The cache stores
  lists by source id, so home/explore providers derive their lists from
  `tracksFor(sourceType)` / `isLoaded(sourceType)` / `errorFor(sourceType)`.
  `refreshSource(String sourceType)` is the only refresh entry point; the cache is
  built from whatever `SourceManager` registers a `RankingSource` for, so
  neither the service nor this provider names individual sources.
- Fire-and-forget imported playlist refresh must use the named remote sync path
  and log background failures with `AppLogger`.
- Search source selection is owned by the search page chips: "all" queries
  Bilibili + YouTube + Netease, and a source chip queries only that source. Do
  not add a hidden global enabled-source filter in Settings.
- Search source/sort changes must preserve existing results while the
  replacement query loads, so slow networks do not blank the result list.
- Shared stream resolution wiring lives in
  `lib/providers/audio/stream_resolution_provider.dart`. Audio and download
  providers consume that provider directly; download providers must not import
  `lib/services/audio/audio_provider.dart` just to resolve streams.
- **Audio providers live here, not next to the controller.**
  `audioControllerProvider` and the four providers that build its
  collaborators are in `lib/providers/audio/audio_controller_provider.dart`;
  every provider derived from the controller's state belongs in
  `audio_player_selectors.dart` beside it. `AudioController` itself declares
  no provider, so importing the controller class and subscribing to its
  state are two separate imports — keep them separate.
- **Ask the right state object.** Playback fields (position, buffering,
  volume, stream metadata, output device) come off `audioControllerProvider`;
  the queue's shape (contents, index, shuffle/loop, mix identity) comes off
  `queueStateProvider`. They share no field, so there is exactly one right
  answer per field — see `lib/services/audio/AGENTS.md` for why both used to
  carry the same twelve.

## Riverpod 3

FMP is on `flutter_riverpod` 3.x. Four rules follow from its behaviour changes.

- **Legacy providers come from a second import.** `StateNotifier`,
  `StateNotifierProvider`, `StateProvider`, `StateController` and
  `ChangeNotifierProvider` live in `package:flutter_riverpod/legacy.dart`; add it
  alongside the main barrel. `KeepAliveLink`, `Override`, `ProviderOrFamily`,
  `ProviderListenable` and `ProviderException` live in
  `package:flutter_riverpod/misc.dart`. Rewriting the remaining
  `StateNotifierProvider`s into `Notifier` is a separate, later change — do not
  start it opportunistically.
- **Automatic retry is off, globally.** `ProviderScope` in `lib/main.dart` passes
  `retry: (retryCount, error) => null`. Retry belongs where it is visible and
  testable: `SourceHttpPolicy`/Dio for network calls, and `AudioController`'s
  measured load budget for playback. Do not re-enable it per provider without
  reconciling it against those two.
- **A provider that performs a side effect must be anchored above
  `MaterialApp`** — by a `ref.watch` in `FMPApp.build` (`lib/app.dart`) or by a
  `ref.listen`. Never anchor one by a `ref.watch` on a page. Riverpod 3 pauses
  the `ref.watch` subscriptions of consumers whose subtree sits under a
  disabled `TickerMode` (an `Overlay` entry covered by an opaque route), so a
  page-anchored side effect stops when the user opens the full-screen player.
  `ref.listen` subscriptions are never paused.
- **`Ref` is a sealed class.** Tests cannot fake it. Use
  `test/support/riverpod_test_ref.dart` (`createTestRef`), which hands back a
  real `Ref` from a `ProviderContainer`, and replace dependencies with
  `overrides` rather than by overriding `read`.
- **Errors thrown by a provider arrive wrapped in `ProviderException`**; the
  original is in `.exception`. Assertions and `catch` blocks that match on a
  concrete exception type must unwrap it first.

## Database Startup And Migration

This file owns the open/registration wiring; `lib/data/AGENTS.md` owns the
"does this field need repair?" decision rules.

- Runtime Isar files live under the app documents directory's `FMP/` child
  folder. Open the DB through `openFmpDatabase()`
  (`lib/providers/database/database_provider.dart`) **only** — never open
  `fmp_database` directly from `getApplicationDocumentsDirectory()` elsewhere.
- Collection registration is catalog-owned in
  `lib/providers/database/database_catalog.dart`. `database_provider.dart` owns
  opening and path handling; `database_migration.dart` owns migration.
- `database_migration.dart` separates two things that used to be one:
  - **Versioned steps** (`fmpMigrationSteps`, gated on `Settings.schemaVersion`)
    run once each, in order, and stamp the version. Add a step and bump
    `kFmpSchemaVersion` together.
  - **Invariants** (`repairSettingsInvariants`, `hasUnwrittenQueueSignature`)
    run on every launch regardless of version. They also defend against a bad
    backup import and a downgrade round-trip, so never version-gate them.
- Steps so far: v0 to v1 rewrites every `PlayHistory` row so the `trackKey`
  index exists; v1 to v2 folds the six per-source `Settings` columns into
  `sourceSettings`. The v1 to v2 step **copies without clearing** — the old
  columns stay populated so installing an older build back over the database
  keeps per-source settings. They are `@Deprecated` and
  `deprecated_member_use_from_same_package` makes "only the migration reads
  them" a compiler rule rather than a convention.
- Read the stored version through `effectiveSchemaVersion()`, never the raw
  field: Isar returns `Isar.minLong` for an int column an old row does not have.
- `runDatabaseMigrationForTesting()` is the test hook.
- Home ranking settings fields must stay in sync with migration/default repair.

When model schemas or persisted defaults change:

1. Read `lib/data/AGENTS.md` § Migration And Default Repair.
2. Update the model and migration/default repair together when needed.
3. Run `dart run build_runner build`.
4. Run `flutter test test/providers/database_migration_test.dart`.
5. If collection/schema visibility changes, update `database_catalog.dart` and
   run `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`.
