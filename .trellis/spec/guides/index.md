# Thinking guides

Questions to ask before coding. The layer specs say *how* to write code; these
say *what else a change touches*.

| Guide | Read when |
|-------|-----------|
| [cross-layer-thinking-guide.md](./cross-layer-thinking-guide.md) | The change crosses layers: a new source, a new setting, a new string, anything between a source response and a pixel |
| [code-reuse-thinking-guide.md](./code-reuse-thinking-guide.md) | You are about to write a helper, a table, a list of sources, a retry loop, a widget variant |

## Pre-Development Checklist

- [ ] The change touches 3+ of: `lib/data/sources`, `lib/data/models`, `lib/services`, `lib/providers`, `lib/ui`, `lib/i18n` → cross-layer guide.
- [ ] You are writing a list of source ids, a header, a user message, a retry ladder, an image widget, a confirm dialog → code-reuse guide; the owner already exists.
- [ ] You are editing `.trellis/spec/` (e.g. in `trellis-update-spec`) → a must / never / only sentence names the test that gates it, or you grepped and found no counterexample; otherwise describe the majority pattern and its known exceptions. The 2026-09 audit had to reword 71 of 421 sentences for this (`.trellis/tasks/archive/2026-09/09-26-align-specs-with-code/research/spec-audit.md`).

## Quality Check

- A new error path stays typed until the user-facing edge and becomes a sentence there through `userMessageFor` / `failureMessage`. The existing exceptions (the import path translating early, `e.toString()` in some `state.error`) are listed in `../shared/errors-and-logging.md`; do not extend them.
