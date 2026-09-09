# lib/providers AGENTS.md

Riverpod providers and provider invalidation. Isar startup, registration and
migration are in `lib/data/AGENTS.md`.

Providers live in semantic subdirectories; do not add new `.dart` files directly
under `lib/providers/`. Use `ls` for the current set.

## Provider Rules

- Pages using `isLoading` must guard with `isLoading && data.isEmpty`.
- `FutureProvider` data must be invalidated after mutations, and optimistic
  updates must roll back on failure.
- Mutation side effects needing playlist/detail/cover/download invalidation go
  through `libraryInvalidationCoordinatorProvider`; UI widgets must not guess
  related provider families manually.
- Play history uses `watchLazy()` plus a shared snapshot stream rather than the
  playlist/radio `watchAll()` data notifier pattern. Profile large history
  datasets before changing its watch/query shape.
- Ranking cache UI watches the immutable `RankingCacheState` from
  `rankingCacheServiceProvider`; refresh/timer methods go through `.notifier`,
  not by reading mutable service snapshot lists. The cache is built from
  whatever `SourceManager` registers a `RankingSource` for, so **neither the
  service nor this provider names individual sources** — a fourth ranked source
  must not require editing either.
- Search source selection is owned by the search page chips: "all" queries all
  three, a source chip queries only that source. Do not add a hidden global
  enabled-source filter in Settings. Source/sort changes must preserve existing
  results while the replacement query loads, so slow networks do not blank the
  list.
- Shared stream resolution wiring lives in
  `lib/providers/audio/stream_resolution_provider.dart`. Download providers
  consume it directly and must not import
  `lib/services/audio/audio_provider.dart` just to resolve streams.
- Fire-and-forget imported playlist refresh must use the named remote sync path
  and log background failures with `AppLogger`.
- **Audio providers live here, not next to the controller.**
  `audioControllerProvider` and the providers building its collaborators are in
  `lib/providers/audio/audio_controller_provider.dart`; every provider derived
  from the controller's state belongs in `audio_player_selectors.dart` beside
  it. `AudioController` still *declares* no provider, but since the `Notifier`
  rewrite it does *consume* them from `build()` — that import goes the other
  way and is why the two files import each other. Do not move a provider
  declaration into `audio_provider.dart` to "fix" that.
- **Ask the right state object.** Playback fields (position, buffering, volume,
  stream metadata, output device) come off `audioControllerProvider`; the
  queue's shape (contents, index, shuffle/loop, mix identity) comes off
  `queueStateProvider`. They share no field, so there is exactly one right
  answer per field — see `lib/services/audio/AGENTS.md` for why both used to
  carry the same twelve.

## Riverpod 3

FMP is on `flutter_riverpod` 3.x.
`test/providers/static_rules/riverpod3_static_rule_test.dart` pins the rules
that fail silently.

- **`lib/` is fully on `Notifier`; the legacy barrel is gone.** The legacy
  family still compiles, so a stray `StateNotifier` would not break the build —
  it would just look like current style to the next reader. `KeepAliveLink`,
  `Override`, `ProviderOrFamily`, `ProviderListenable` and `ProviderException`
  live in `package:flutter_riverpod/misc.dart`.
- **`build()` replaces the constructor, and the instance survives a re-run.**
  Riverpod preserves the notifier across `build()` calls, which is where the
  next four come from. All four fail *silently* — nothing logs, nothing throws
  except the first.
  1. Collaborator fields are `late`, never `late final`; a second assignment to
     a `late final` is a `LateInitializationError`.
  2. Constructor side effects move into `build()` and must be safe to repeat.
     Anything that subscribes, times or watches pairs with an `ref.onDispose`
     **registered in the same `build()`** — `onDispose` runs before a rebuild
     too, so the pair is per-build.
  3. `if (!mounted)` becomes `if (!ref.mounted)`. `AudioController` and
     `RankingCacheService` keep their own `_isDisposed` flags instead.
  4. **A teardown that releases *ownership* must not hang off a watched
     dependency.** `AudioController._teardown` disposes the audio backend and
     hands back system media control; because `onDispose` also fires on rebuild,
     its collaborators are `ref.read`, not `ref.watch`. Use `watch` only when
     re-running the whole build is the correct response to that dependency
     changing (`RadioController` does: it waits for the database).
- **Life-cycle callbacks may not touch any other provider.** Inside
  `ref.onDispose` and selectors, both `state =` and `ref.invalidate` throw;
  `StateNotifier` allowed it. Capture what you need during `build()`, or push
  the work out of the callback stack.
- **`Notifier.new` takes no arguments**, so anything a test used to inject
  through the constructor needs a provider to override instead. Where the
  existing provider was too coarse or too expensive, a narrow one was added
  beside it. `test/support/audio_controller_harness.dart` translates the old
  `AudioController` constructor arguments into overrides.
- **Automatic retry is off, globally.** `ProviderScope` passes
  `retry: (retryCount, error) => null`. Retry belongs where it is visible and
  testable: `SourceHttpPolicy`/Dio for network calls, and `AudioController`'s
  measured load budget for playback. Do not re-enable it per provider without
  reconciling it against those two.
- **A provider that performs a side effect must be anchored above
  `MaterialApp`** — by a `ref.watch` in `FMPApp.build` (`lib/app.dart`) or by a
  `ref.listen`. Never anchor one by a `ref.watch` on a page: Riverpod 3 pauses
  the `ref.watch` subscriptions of consumers under a disabled `TickerMode` (an
  `Overlay` entry covered by an opaque route), so a page-anchored side effect
  stops when the user opens the full-screen player. `ref.listen` subscriptions
  are never paused.
- **`Ref` is a sealed class.** Tests cannot fake it. Take a real one out of a
  real container — `Provider<Ref>((ref) => ref)` read from a `ProviderContainer`
  — and keep the container alive longer than the `Ref`, which throws
  `UnmountedRefException` once its container is disposed. Replace dependencies
  with `overrides`, never by overriding `read`.
- **Errors thrown by a provider arrive wrapped in `ProviderException`**; the
  original is in `.exception`. Assertions and `catch` blocks matching on a
  concrete exception type must unwrap it first.
