# AGENTS.md — legacy app

These are the rules for the frozen old app that lives at the repo root. It
only takes hotfixes until the cut-over PR (ADR 0008). Paths below are
relative to the repo root.

## Verification

| Change area | Minimum |
|------------|---------|
| Audio playback/controller/queue | `flutter test test/services/audio` (+ `test/data/sources` when stream resolution changes) |
| Source adapters / HTTP policy | `flutter test test/data/sources test/services/account test/services/radio` |
| Download pipeline | `flutter test test/services/download test/providers/download` |
| Isar models / migrations | `dart run build_runner build` + `flutter test test/providers/database_migration_test.dart` |
| UI widgets/pages | targeted tests under `test/ui` + `flutter analyze` + on-device |
| i18n JSON | `dart run slang` + `flutter analyze` |

- Generated `*.g.dart` files (Isar and slang) are gitignored. After a pull, a
  branch switch or in a fresh worktree, run `dart run build_runner build` and
  `dart run slang` first: stale codegen fails as a missing getter that looks
  like a source bug. An Orca worktree runs them in the `orca.yaml` setup.
- A full run is `flutter test --exclude-tags live`, as in CI; `live` tests hit
  the real source APIs.
- `flutter analyze` and the `dart format lib test tool` CI gate cover `tool/`
  too. `tool/demo/` holds hand-run scripts against the real APIs: analysed and
  formatted, never executed by CI.

**On-device verification is mandatory for user-visible changes** — UI pages or
widgets, playback controls, how source results render, or a string that can
affect layout. Run the `verify-legacy-on-device` skill on the Android emulator (add
Windows only for Windows-specific work) and report the element, log line or
screenshot you observed. When the emulator cannot come up or the change cannot
be reached, report that blocker by name; tests alone do not count.

## Conventions

- Comments are Traditional Chinese. The tree is mixed — everything written
  before the 2026-09 rounds is Simplified. Convert the lines you are already
  editing and leave the rest: a whole-tree conversion buries every real change.
- Ask first before changing persisted schema semantics, the auth boundary,
  public architecture or cross-platform behaviour in a way not already
  documented.
- For questions about the running app — live field values, HTTP traffic, what
  Isar actually holds — use the VM Service recipes in `docs/development.md`
  § 執行期除錯.

## Boundaries

No test checks these; hold them yourself:

- **Audio** — UI playback controls call `AudioController`
  (`lib/services/audio/audio_provider.dart`), never `FmpAudioService`. Radio is
  the one intentional exception.
- **Database** — Isar is opened only by `openFmpDatabase()`; migrations follow
  the `kFmpSchemaVersion` dartdoc in `lib/data/database/database_migration.dart`.
- **Search** — the visible source chips on the search page are the only source
  selector; no setting filters search behind the user's back (`db41b987`).
- **Providers** — `audio_provider.dart` declares no providers.
  `audioControllerProvider` and the backend, queue and stream providers live in
  `lib/providers/audio/`; collaborators such as `nowPlayingPublisherProvider`,
  `playbackSideEffectsProvider` and `queueStateProvider` declare theirs beside
  their class in `lib/services/audio/`. `neteaseSourceProvider` is the
  **lyrics-layer** `NeteaseSource` (`lib/services/lyrics/`); the same-named data
  source adapter is reached only through `SourceManager`'s narrow capabilities.

Gated by static-rule tests. The tests hold the exception lists: add an entry
with a reason, delete it when it goes away.

- **Layers** — `lib/core/` and `lib/data/` import nothing from `lib/services/`
  or `lib/providers/`, and a new import edge between two features (a
  subdirectory name under either) is recorded —
  `test/support/layer_boundary_static_rule_test.dart`.
- **Isar access** — `isar.` appears only in `lib/data/repositories/` (ADR 0002)
  — `test/data/static_rules/isar_boundary_static_rule_test.dart`.
- **Images** — in `lib/ui/`, only the semantic widgets in
  `lib/ui/widgets/images/` load images (the `ImageLoadingService` loaders,
  `Image.network` / `Image.file`, `CachedNetworkImage` /
  `CachedNetworkImageProvider`, `NetworkImage` / `FileImage`) or name an
  `ImageTargetSizes` tier; pages pass them a variant or a display size (#107) —
  `test/ui/static_rules/ui_consistency_static_rule_test.dart`.
- **Sliders** — build `ScopedSlider`; a raw Material `Slider` freezes the
  Windows accessibility tree (`docs/troubleshooting.md`) —
  `test/ui/static_rules/slider_overlay_static_rule_test.dart`.
- **Test waits** — no direct `pumpEventQueue` outside
  `test/support/pump_until.dart`: use its `pumpUntil` / `drainEventQueue`
  (how: `.trellis/spec/legacy/testing/test-conventions.md`; #43, #55) —
  `test/support/wait_convention_static_rule_test.dart`.
- **Static rules** — a test that reads `lib/` source is named
  `*_static_rule_test.dart` and lives in `test/support/` or
  `test/<layer>/static_rules/` —
  `test/support/static_rule_placement_static_rule_test.dart`.
