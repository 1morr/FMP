# lib/providers AGENTS.md

Guidance for Riverpod providers, provider invalidation, and database startup.

## Directory Layout

Providers live in semantic subdirectories; do not add new `.dart` files directly
under `lib/providers/`.

Current folders:
- `account/` - login/account state and source account services.
- `audio/` - playback selectors and audio/playback settings.
- `database/` - Isar startup and repository providers.
- `download/` - download state, path, scanner, and file-existence cache.
- `library/` - playlists, play history, remote sync, imports, and track detail.
- `lyrics/` - lyrics search/cache state and lyrics window style.
- `search/` - search, ranking/popular content, and refresh orchestration.
- `settings/` - persisted user settings not owned by a narrower subsystem.
- `system/` - backup, update, and desktop-window integration.
- `ui/` - UI-only state such as selection mode.

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
- Play history currently uses `watchLazy()` plus a shared snapshot stream rather
  than the playlist/radio `watchAll()` data notifier pattern. Profile large
  history datasets before changing its watch/query shape.
- `FutureProvider` data must be invalidated after mutations.
- Mutation side effects that need playlist/detail/cover/download provider
  invalidation should go through `libraryInvalidationCoordinatorProvider`; UI
  widgets should not manually guess related provider families.
- Ranking cache UI must watch immutable `RankingCacheState` from
  `rankingCacheServiceProvider`. Refresh/timer methods are called through
  `rankingCacheServiceProvider.notifier`, not by reading mutable service
  snapshot lists. The ranking cache refreshes Bilibili, YouTube, and Netease
  sources together; home/explore providers should derive their lists from that
  shared three-source cache.
- Fire-and-forget imported playlist refresh must use the named remote sync path
  and log background failures with `AppLogger`.
- Search source selection is owned by search page chips: "all" queries
  Bilibili + YouTube + Netease, and a source chip queries only that source. Do
  not add a hidden global enabled-source filter in Settings.
- Search source/sort changes should preserve existing results while the
  replacement query is loading, so slow networks do not blank the result list.
- Optimistic updates must roll back on failure.
- Shared stream resolution wiring lives in
  `lib/providers/audio/stream_resolution_provider.dart`. Audio and download
  providers should consume that provider directly; download providers must not
  import `lib/services/audio/audio_provider.dart` just to resolve streams.

## Database Startup And Migration

Database provider rules are shared with `lib/data/AGENTS.md`:
- Runtime Isar files live under the app documents directory's `FMP/` child
  folder.
- Open the DB through `openFmpDatabase()` only.
- Migration/default repair entry point is `_migrateDatabase()` in
  `database/database_provider.dart`.
- Testing helper is `runDatabaseMigrationForTesting()`.
- Home ranking settings fields must stay in sync with migration/default repair.

When model schemas or persisted defaults change:
1. Read `lib/data/AGENTS.md`.
2. Update model and migration/default repair together when needed.
3. Run `flutter pub run build_runner build --delete-conflicting-outputs`.
4. Run `flutter test test/providers/database_migration_test.dart`.
5. If collection/schema visibility changes, update
   `lib/ui/pages/settings/database_viewer_page.dart` and run
   `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`.
