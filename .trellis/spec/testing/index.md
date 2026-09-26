# Testing (`test/`, `tool/`)

Applies to every test and to static-rule tests. Which tests to run for which
change is AGENTS.md § Verification; the full CI run is
`flutter test --exclude-tags live`.

## Guidelines

| File | Read when |
|------|-----------|
| [test-conventions.md](./test-conventions.md) | Writing any test: layout, fakes, Isar, HTTP, Riverpod, waiting, tags |
| [static-rules.md](./static-rules.md) | Adding or changing a `*_static_rule_test.dart`, or a rule that fires on your change |

## Pre-Development Checklist

- [ ] Before writing a fake, look in `test/support/` and `test/support/fakes/`.
- [ ] A test that needs the network is tagged `live`; a probe or benchmark is **not** named `*_test.dart`.
- [ ] Prefer a behavioural test over a static rule; write a static rule only for a boundary behaviour tests cannot see.

## Quality Check

- New waits use `pumpUntil` for a condition that is false on entry and `drainEventQueue` to assert absence, not a fixed pump count. Only a direct `pumpEventQueue` is gated; fixed runs of `Future.delayed(Duration.zero)` still appear in provider tests (`test/providers/home_ranking_settings_provider_test.dart`, `test/providers/import_playlist_provider_cancellation_test.dart`).
- A new static rule has both mutation tests (see `static-rules.md`).
- `dart format lib test tool` is clean; `flutter analyze` covers `test/` and `tool/`.
