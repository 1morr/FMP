# AGENTS.md

FMP is a Flutter music player for Android and Windows that plays from
**Bilibili**, **YouTube** and **NetEase Cloud Music**. Human-facing docs live in
`docs/`; `docs/README.md` is the map.

## Agent skills

- **Issue tracker** — GitHub Issues on `1morr/FMP` via `gh`. See
  `docs/agents/issue-tracker.md`.
- **Triage labels** — the five canonical roles. See
  `docs/agents/triage-labels.md`.
- **Domain docs** — single-context: `CONTEXT.md` + `docs/adr/`. See
  `docs/agents/domain.md`.

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
  like a source bug.
- A full run is `flutter test --exclude-tags live`, as in CI; `live` tests hit
  the real source APIs.
- `flutter analyze` and the `dart format lib test tool` CI gate cover `tool/`
  too. `tool/demo/` holds hand-run scripts against the real APIs: analysed and
  formatted, never executed by CI.

**On-device verification is mandatory for user-visible changes** — UI pages or
widgets, playback controls, how source results render, or a string that can
affect layout. Run the `verify-on-device` skill on the Android emulator (add
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
- **Images** — UI images go through the semantic widgets in
  `lib/ui/widgets/images/` with a semantic variant, never a raw size (#107) —
  `test/ui/static_rules/ui_consistency_static_rule_test.dart`.
- **Sliders** — build `ScopedSlider`; a raw Material `Slider` freezes the
  Windows accessibility tree (`docs/troubleshooting.md`) —
  `test/ui/static_rules/slider_overlay_static_rule_test.dart`.
- **Test waits** — `pumpUntil` for a condition false on entry,
  `drainEventQueue` to assert something did *not* happen
  (`test/support/pump_until.dart`); a fixed pump count is flaky in both
  directions (#43, #55) — `test/support/wait_convention_static_rule_test.dart`.
- **Static rules** — a test that reads `lib/` source is named
  `*_static_rule_test.dart` and lives in `test/support/` or
  `test/<layer>/static_rules/` —
  `test/support/static_rule_placement_static_rule_test.dart`.

## Trellis

- **Rules vs patterns** — binding rules stay in this file;
  `.trellis/spec/<layer>/` holds how each layer's code is written and links
  here instead of restating a rule. A new rule goes in exactly one of them.
- **`trellis update`** — keep the local `.claude/agents/trellis-check.md` and
  `trellis-implement.md`: their Verify steps run § Verification above. Journals
  stay local because the repo is public (`.trellis/workspace/` is gitignored,
  `session_auto_commit: false`); if an update re-adds a journal `merge=union`
  line to `.gitattributes`, drop it.

<!-- TRELLIS:START -->
# Trellis Instructions

These instructions are for AI assistants working in this project.

This project is managed by Trellis. The working knowledge you need lives under `.trellis/`:

- `.trellis/workflow.md` — development phases, when to create tasks, skill routing
- `.trellis/spec/` — package- and layer-scoped coding guidelines (read before writing code in a given layer)
- `.trellis/workspace/` — per-developer journals and session traces
- `.trellis/tasks/` — active and archived tasks (PRDs, research, jsonl context)

If a Trellis command is available on your platform (e.g. `/trellis:finish-work`, `/trellis:continue`), prefer it over manual steps. Not every platform exposes every command.

If you're using Codex or another agent-capable tool, additional project-scoped helpers may live in:
- `.agents/skills/` — reusable Trellis skills
- `.codex/agents/` — optional custom subagents

Managed by Trellis. Edits outside this block are preserved; edits inside may be overwritten by a future `trellis update`.

<!-- TRELLIS:END -->
