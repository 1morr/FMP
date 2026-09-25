# Riverpod providers and state

## Provider kinds

| Need | Use | Example |
|------|-----|---------|
| Wrap a service / repository, or derive a value | `Provider<T>` | `playlistServiceProvider`, `currentTrackProvider` |
| Mutable state | `NotifierProvider<XNotifier, XState>(XNotifier.new)` | `themeProvider`, `searchProvider` |
| Per-id mutable state | `NotifierProvider.family`, id through the notifier constructor | `playlistDetailProvider` (`PlaylistDetailNotifier(this.playlistId)`) |
| Page-scoped state that resets when the page leaves | `NotifierProvider.autoDispose` | `searchSelectionProvider`, `lyricsSearchProvider` |
| One-shot snapshot (invalidate to refresh) | `FutureProvider` (+ `.family` / `.autoDispose`) | `allPlaylistsProvider`, `trackByIdProvider` |
| Isar `watch*()` or event stream | `StreamProvider` | `downloadTasksProvider` |
| Narrow read of a wide state per key | `Provider.family` | `downloadTaskProgressProvider(taskId)` |

- Not used: `StateNotifier`, `StateProvider`, `ChangeNotifierProvider`,
  `AsyncNotifier`, `StreamNotifier`. The legacy barrel import is gated
  (`test/providers/static_rules/riverpod3_static_rule_test.dart`).
- Loading and error inside a notifier are **fields** on a plain state class
  (`isLoading`, `error`), not `AsyncNotifier`.
- Default is keep-alive; `autoDispose` only for page-scoped state and page-only
  derived data.

## Naming and location

- `xxxProvider`, `XxxNotifier`, `XxxState`.
- Files: `lib/providers/<feature>/<name>_provider.dart`. The feature subdirectory
  is a feature identity for `test/support/layer_boundary_static_rule_test.dart`:
  a new import edge between two features must be recorded there with a reason.
- Deliberate exceptions live next to their owner: most repository providers in
  `lib/data/database/repository_providers.dart`, `sourceManagerProvider` in
  `lib/data/sources/source_provider.dart`, `queueStateProvider` in
  `lib/services/audio/queue_state.dart`, `radioControllerProvider` in
  `lib/services/radio/radio_controller.dart`. `audioControllerProvider` and its
  core collaborators' providers live in `lib/providers/audio/`; a few audio
  providers sit next to their class in `lib/services/audio/` (see
  `../services/audio.md`).
- A provider file may re-export types its pages need
  (`playlist_provider.dart` `export … show PlaylistUpdateResult`).

## Wiring a service

```dart
final xServiceProvider = Provider<XService>((ref) {
  final repo = ref.watch(xRepositoryProvider);
  final service = XService(repo, ref.watch(sourceManagerProvider));
  ref.onDispose(service.dispose);
  return service;
});
```

Every provider that owns something disposable registers `ref.onDispose`
(`491f76f9`: lyrics sources leaked Dio pools). Database access uses
`ref.watch(databaseProvider).requireValue` or `.value` + `StateError`.

## Notifier `build()`

- Dependencies come from `ref.watch(...)` in `build()`, never from constructor
  params (the family id is the only constructor param).
- Sync initial state + fire-and-forget load: `build()` calls `_load()` without
  awaiting and returns an initial state (`LayoutSettingsNotifier` returns
  `LayoutSettingsState.initial()`). Riverpod
  forbids writing `state` synchronously inside `build()`; use
  `Future.microtask(load)` when needed (`PlaylistDetailNotifier.build`).
- Riverpod 3 keeps the notifier instance across rebuilds: a subscription opened
  in `build()` is closed by a `ref.onDispose` registered in the **same** build
  (`PlaylistListNotifier.build`; covered by `test/providers/notifier_rebuild_test.dart`
  — a rewritten notifier gets a "rebuild keeps state and side effects correct" test).
- After every `await` that is followed by `ref` or `state`, check
  `if (!ref.mounted) return;` — or hoist the read above the await
  (`a43fddbe`: 3.x throws `UnmountedRefException`).
- Never set another provider's state or invalidate from `ref.onDispose`; defer
  with `scheduleMicrotask` and guard `ref.mounted` (`downloadServiceProvider`).
- Stale async results are dropped with a request id or generation counter:
  `if (!ref.mounted || requestId != _searchRequestId) return;` (`SearchNotifier`,
  `RefreshManagerNotifier`). Add a stale-result test like
  `test/providers/search_pagination_stale_test.dart`.
- Errors stored in state are already user sentences:
  `state = state.copyWith(error: failureMessage(e, stack, 'createPlaylist failed', tag: 'Playlist'))`.
  Never store `e.toString()` (`5e9d2929`). See `../shared/errors-and-logging.md`.

## State classes

- Hand-written, immutable, `const` constructor, `copyWith`; clearable nullable
  fields get `bool clearX = false` flags. Some `copyWith` reset `error` when
  omitted — read the class before assuming.
- Equality: `extends Equatable` with **every** field in `props` (gated for classes
  under `lib/providers/` — a missing prop silently stops rebuilds because
  Riverpod 3 filters by `==`), or `@immutable`
  with hand-written `==` / `hashCode` for selector outputs (`QueueControlState`).
- Replace collections, never mutate them: `state = {...state, id: value}`.

## watch / read / listen

- `ref.watch` in `build()` and provider bodies; `ref.read(x.notifier).method()` in
  callbacks.
- Wide, hot providers are never watched whole — use `.select(...)` or a narrow
  derived provider (`audio_player_selectors.dart`). The list is `_narrowOnly` in
  `test/ui/static_rules/watch_scope_static_rule_test.dart`; add a new hot provider
  there with a reason.
- Side effects such as toasts: `ref.listen` in `build()`, comparing `prev` and
  `next`. In a `ConsumerStatefulWidget`, `ref.listenManual` in `initState`, stored
  and closed in `dispose`.
- **Background providers must be watched in `FMPApp.build`** (`lib/app.dart`):
  Riverpod 3 pauses watches of consumers hidden behind an opaque route such as the
  full-screen player. The watched set must equal `_anchoredProviders` in
  `riverpod3_static_rule_test.dart`; add the provider to both. Windows-only ones
  sit under `if (Platform.isWindows)`.
- Library mutations do not call `ref.invalidate(allPlaylistsProvider…)` directly —
  they go through `ref.read(libraryInvalidationCoordinatorProvider)`
  (`call_site_ownership_static_rule_test.dart`).
- Automatic retry is disabled app-wide (`ProviderScope(retry: (retryCount, error) => null)`
  in `main.dart`). A widget test that asserts an error branch passes the same `retry:`.

## Tests

- Unit: `ProviderContainer(overrides: [...])` + `addTearDown(container.dispose)`.
- Replace a notifier with a test subclass that overrides `build()`
  (`_FixedLayoutSettings extends LayoutSettingsNotifier`), via `overrideWith`;
  plain values via `overrideWithValue`.
- `AudioController` has a harness: `buildTestAudioController(...)` in
  `test/support/audio_controller_harness.dart`.
