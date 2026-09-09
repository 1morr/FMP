# AGENTS.md

Repository-wide rules for AI coding agents working in FMP — a cross-platform
music player (Android + Windows) that plays from **Bilibili**, **YouTube** and
**NetEase Cloud Music**.

Write down only what the code cannot tell you: the unwritten convention, the
reason behind a choice, the trap no config confesses. A file listing, a symbol
name or a count goes stale and nothing notices.

## Instruction Scope

Read this file, then the nearest `AGENTS.md` in the directory you are editing.
Six subtrees have one: `lib/data`, `lib/data/sources`, `lib/providers`,
`lib/services`, `lib/services/audio`, `lib/ui`. Each is paired with a
`CLAUDE.md` holding a single `@AGENTS.md` line, because Claude Code loads nested
`CLAUDE.md`, not `AGENTS.md`, while Codex and opencode read the `AGENTS.md`.
Adding a scoped file means adding both.

State each rule in exactly one file and cross-reference it. Update the scoped
file in the same change as the code. Human-facing docs live in `docs/`;
`docs/README.md` is the map.

## Agent Skills

- **Issue tracker** — GitHub Issues on `1morr/FMP` via `gh`. See
  `docs/agents/issue-tracker.md`.
- **Triage labels** — the five canonical roles. See
  `docs/agents/triage-labels.md`.
- **Domain docs** — single-context: `CONTEXT.md` + `docs/adr/`. See
  `docs/agents/domain.md`.
- **On-device verification** — `.claude/skills/verify-on-device/SKILL.md`.
  Required, not optional; see below.
- **Runtime debugging** — `docs/debugging-with-vm-service.md`. Reach for it when
  the question is about the running app rather than the source. Enable `dart:io`
  profiling *before* the traffic you want to see, or it records nothing.

## Verification

| Change Area | Minimum |
|------------|---------|
| Audio playback/controller/queue | `flutter test test/services/audio` (+ `test/data/sources` when stream resolution changes) |
| Source adapters / HTTP policy | `flutter test test/data/sources test/services/account test/services/radio` |
| Download pipeline | `flutter test test/services/download test/providers/download` |
| Isar models / migrations | `dart run build_runner build` + `flutter test test/providers/database_migration_test.dart test/ui/pages/settings/database_viewer_page_coverage_test.dart` |
| UI widgets/pages | targeted tests under `test/ui` + `flutter analyze` + on-device |
| i18n JSON | `dart run slang` + `flutter analyze` |
| `AGENTS.md` and other docs | `flutter test test/support/agents_docs_static_rule_test.dart` |

`flutter analyze` covers `lib` **and** `test`; `dart format lib test` is a CI
gate. CI runs every job on documentation-only commits, because the rules in
these files are enforced by tests.

**On-device verification is mandatory for user-visible changes** — UI pages or
widgets, playback controls, how source results render, or a string that can
affect layout. Tests and `flutter analyze` are not sufficient on their own.

- **The Android emulator is the required platform**; its semantics tree lets you
  assert on real elements. Verify on Windows too only for Windows-specific work.
- Report what you drove and what you observed — the element, log line or
  screenshot. "Should work" is not a verification.
- If the emulator cannot be brought up or the change cannot be reached, say so
  and name the blocker. Never silently downgrade to tests.

## Hard Boundaries

Always:
- Prefer `rg` / `rg --files` for searching.
- Preserve unrelated user changes in the working tree.
- Preserve comments that explain non-obvious intent, historical rationale, edge
  cases, upstream behaviour or bug workarounds. When updating one, keep the
  original reason unless it is demonstrably stale, and replace it with equivalent
  current rationale rather than deleting it.
- Use repository patterns and local helper APIs before inventing abstractions.
- Write comments in Traditional Chinese. The tree is mixed — everything written
  before the 2026-09 rounds is Simplified and many files hold both. Convert the
  lines you are already editing and leave the rest alone: a whole-tree conversion
  buries every real change in it, and the cost of the mix is readability, not
  correctness. Identifiers, string constants, log messages, commit messages and
  branch names stay English.
- Keep generated Isar/slang outputs in sync when changing schemas or i18n JSON.
- Include the focused verification you actually ran in the final report.

Ask first:
- Before changing public architecture, persisted schema semantics, the auth
  boundary, or cross-platform behaviour in a way not already documented.
- Before destructive git operations or broad rewrites unrelated to the request.

Never:
- Do not bypass `AudioController` from UI playback controls.
- Do not open or migrate the Isar database through ad-hoc paths.
- Do not add hidden global enabled-source filters for search.
- Do not use direct `Image.network()` / `Image.file()` in UI — see
  `lib/ui/AGENTS.md` § Image Components.
- Do not call `pumpEventQueue` in tests. A pump count buys event loop turns, not
  progress, so it fails under load in one direction and on an idle machine in
  the other (issues #43, #55). Use `pumpUntil` for a condition that is false on
  entry, `drainEventQueue` when asserting something did *not* happen.
- Do not import `lib/services/` or `lib/providers/` from `lib/core/` or
  `lib/data/`. Those two are the base every feature sits on, and an upward
  import makes a feature impossible to move or delete while the compiler stays
  silent.
- Do not add an import edge between two features without recording it. A feature
  is a subdirectory name under `lib/services/` or `lib/providers/` — those hold
  two halves of the same features.
- Do not cite `docs/review/execution-log.md` from code, tests or `AGENTS.md`. It
  is history; a cited snapshot becomes an unmaintained live document.
- Do not try to "fix" the benign `Failed to update ui::AXTree` Windows log spam —
  it is a known Flutter engine bug (`flutter/flutter#182444`), not an FMP defect.
  See `docs/troubleshooting.md`.

The last five are enforced by tests under `test/support/` and
`test/ui/static_rules/`, which carry the exception lists. Add a line with a
reason when you add a legitimate exception; delete it when it goes away.

## Architecture

**Audio** — UI playback controls call `AudioController`
(`lib/services/audio/audio_provider.dart`), never `FmpAudioService` directly.
Android uses `JustAudioService`, desktop `MediaKitAudioService`. Radio is the one
intentional exception.

**State** — Riverpod. Two provider facts that are not obvious from the file
layout:

- `audioControllerProvider` and the providers building the controller's
  collaborators live in `lib/providers/audio/`, not beside the controller class,
  which declares no provider of its own.
- `neteaseSourceProvider` is the **lyrics-layer** `NeteaseSource`
  (`lib/services/lyrics/`). The same-named data source adapter
  (`lib/data/sources/`) is registered inside `SourceManager` and must be reached
  through narrow capabilities — never through a concrete source provider.

**Data** — Isar collections in `lib/data/models/`, repositories in
`lib/data/repositories/` (the only place `isar.` may appear, plus two named
exemptions), source adapters in `lib/data/sources/`.
