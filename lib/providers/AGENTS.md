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
  lists by `SourceType`, so home/explore providers derive their lists from
  `tracksFor(sourceType)`. `refreshBilibili()` / `refreshYouTube()` /
  `refreshNetease()` are compatibility wrappers around `refreshSource()`.
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

## Database Startup And Migration

This file owns the open/registration wiring; `lib/data/AGENTS.md` owns the
"does this field need repair?" decision rules.

- Runtime Isar files live under the app documents directory's `FMP/` child
  folder. Open the DB through `openFmpDatabase()`
  (`lib/providers/database/database_provider.dart`) **only** — never open
  `fmp_database` directly from `getApplicationDocumentsDirectory()` elsewhere.
- Collection registration is catalog-owned in
  `lib/providers/database/database_catalog.dart`. `database_provider.dart` owns
  opening, migration/default repair (`_migrateDatabase()`), and path handling.
- `runDatabaseMigrationForTesting()` is the test hook.
- Home ranking settings fields must stay in sync with migration/default repair.

When model schemas or persisted defaults change:

1. Read `lib/data/AGENTS.md` § Migration And Default Repair.
2. Update the model and migration/default repair together when needed.
3. Run `dart run build_runner build --delete-conflicting-outputs`.
4. Run `flutter test test/providers/database_migration_test.dart`.
5. If collection/schema visibility changes, update `database_catalog.dart` and
   run `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`.
