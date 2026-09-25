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
- [ ] You are changing a value → `rg` for it across `lib/`, `test/` and `docs/` first.

## Quality Check

- The cross-layer guide's "Before you finish" list holds for every arrow touched.

## Reviewing AI findings

Before acting on a review finding, check it against the code:
- "Untrusted input" — trace where the data comes from (bundled JSON, a source API, user text).
- "Missing validation" — the boundary may already validate (`SourceUrlPolicy`, `SourceHttpPolicy`).
- "Behaviour change" — read the dartdoc; FMP records intentional behaviour there with the issue or commit.
- "Bug in the test" — mentally delete the feature under test; if the test still passes, it is tautological.
