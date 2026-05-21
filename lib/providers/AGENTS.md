# lib/providers AGENTS.md

Guidance for Riverpod providers, provider invalidation, and database startup.

## Provider Patterns

| Source | Pattern | Example |
|--------|---------|---------|
| DB collection, multi-writer | Isar `watchAll()` + `StateNotifier` | Playlists, radio, history |
| DB join query | `StateNotifier` + optimistic update | Playlist detail |
| File system scan | `FutureProvider` + `invalidate` | Downloaded page |
| API + cache state | `StateNotifierProvider` + immutable state | Home/explore rankings (`RankingCacheState`) |
| Settings | `StateNotifier` + direct state update | Settings page |

Rules:
- Pages using `isLoading` must guard with `isLoading && data.isEmpty`.
- `FutureProvider` data must be invalidated after mutations.
- Mutation side effects that need playlist/detail/cover/download provider
  invalidation should go through `libraryInvalidationCoordinatorProvider`; UI
  widgets should not manually guess related provider families.
- Ranking cache UI must watch immutable `RankingCacheState` from
  `rankingCacheServiceProvider`. Refresh/timer methods are called through
  `rankingCacheServiceProvider.notifier`, not by reading mutable service
  snapshot lists.
- Fire-and-forget imported playlist refresh must use the named remote sync path
  and log background failures with `AppLogger`.
- Search source selection is owned by search page chips: "all" queries
  Bilibili + YouTube + Netease, and a source chip queries only that source. Do
  not add a hidden global enabled-source filter in Settings.
- Optimistic updates must roll back on failure.

## Database Startup And Migration

Database provider rules are shared with `lib/data/AGENTS.md`:
- Runtime Isar files live under the app documents directory's `FMP/` child
  folder.
- Open the DB through `openFmpDatabase()` only.
- Migration/default repair entry point is `_migrateDatabase()` in
  `database_provider.dart`.
- Testing helper is `runDatabaseMigrationForTesting()`.

When model schemas or persisted defaults change:
1. Read `lib/data/AGENTS.md`.
2. Update model and migration/default repair together when needed.
3. Run `flutter pub run build_runner build --delete-conflicting-outputs`.
4. Run `flutter test test/providers/database_migration_test.dart`.
5. If collection/schema visibility changes, update
   `lib/ui/pages/settings/database_viewer_page.dart` and run
   `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`.
