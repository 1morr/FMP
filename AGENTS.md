# AGENTS.md

FMP is a Flutter music player that plays from **Bilibili**, **YouTube** and
**NetEase Cloud Music**. It is being rewritten: the new app grows in `app/`
while the old one stays at the repo root until the cut-over PR (ADR 0008,
ADR 0026). Human-facing docs live in `docs/`; `docs/README.md` is the map.

## Where things live

| Path | What | Rules to read first |
|------|------|---------------------|
| `lib/`, `test/`, `tool/`, `android/`, `windows/`, `assets/`, root `pubspec.yaml` | The old app — frozen, hotfixes only | `lib/AGENTS.md` |
| `app/` | The new app — its own Flutter project and pub workspace root | `app/AGENTS.md` |
| `docs/adr/` | Decisions. 0008 onward is the rewrite; 0001–0007 describe the old app only | — |
| `.github/workflows/` | `ci.yml` splits by changed path — `app/**` and `.github/**` run the `app` jobs (analyze and test, five platform builds, Linux and Windows integration tests), anything outside `app/` runs the old app's jobs — and `CI Result` fails if any of them did; `release.yml` releases the old app | — |
| `.claude/skills/` | `verify-on-device` for `app/`, `verify-legacy-on-device` for old-app hotfixes; `trellis-*` come with Trellis | — |
| `.trellis/` | Tasks and specs: `spec/legacy/` for the old app, `spec/app/` for the new one, `spec/guides/` shared | — |

Claude Code loads a subdirectory's `AGENTS.md` only when it reads a file there,
so open `lib/AGENTS.md` yourself before an old-app change that touches only
`test/` or other paths outside `lib/`.

## Decisions

No code in `app/` without an accepted ADR covering it. A new cross-module
decision gets a new ADR (`docs/adr/template.md`); an ADR that turns out wrong
on a fact gets a one-line correction, not a rewrite of the decision.

## Issues

Issues live on `1morr/FMP` and are handled with `gh`. Titles and bodies are
written in Traditional Chinese (Taiwan/Hong Kong usage); identifiers, log
strings, commit messages, branch and label names stay in English.

## Trellis

- **Packages** — `.trellis/config.yaml` declares `legacy` (the repo root) and
  `app`; a task's `package` picks its spec tree and its `AGENTS.md`, and
  `session.spec_scope: active_task` limits SessionStart to that package
  (`app` when no task is active). A flat `.trellis/spec/<layer>/` directory is
  injected whatever the scope, so every layer lives under a package directory and
  no `index.md` sits directly in `.trellis/spec/<package>/`; only `guides/` is
  shared.
- **Rules vs patterns** — binding rules stay in the package's `AGENTS.md`;
  `.trellis/spec/<package>/<layer>/` holds how each layer's code is written and
  links there instead of restating a rule. A new rule goes in exactly one of
  them.
- **`trellis update`** — keep the local `.claude/agents/trellis-check.md` and
  `trellis-implement.md`: their Verify steps run the task package's
  verification section. Journals stay local because the repo is public
  (`.trellis/workspace/` is gitignored, `session_auto_commit: false`;
  `orca.yaml` shares the main checkout's copy with Orca worktrees); if an
  update re-adds a journal `merge=union` line to `.gitattributes`, drop it.
- **Managed files left as shipped** — Claude Code runs the customised
  `.claude/agents/trellis-check.md`; the `trellis-check` skill and
  `.trellis/agents/check.md` are Trellis-generated and not used for FMP work.
  With `session_auto_commit: false`, archive and journal steps make no commits:
  commit task changes by hand, whatever the Trellis command docs say. The
  managed block's `.agents/` and `.codex/` lines do not apply: both are
  gitignored local state.

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
