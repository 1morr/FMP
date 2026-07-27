# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

FMP is a **single-context** repo: one `CONTEXT.md` and one `docs/adr/` at the root.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the ubiquitous language for source auth and
  media handoff decisions.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these don't exist yet, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## Relationship to `AGENTS.md`

These are different documents with different jobs — don't merge or duplicate them:

- **`CONTEXT.md`** defines *vocabulary* — what a term means and which synonyms to avoid.
- **`docs/adr/`** records *why* a decision was made, including rejected alternatives.
- **`AGENTS.md`** (root + scoped) states *binding rules* for changing code.

If a rule belongs in `AGENTS.md`, put it there and reference it — see the
per-subtree map in the root `AGENTS.md` § Instruction Scope.

## File structure

```
/
├── CONTEXT.md
├── AGENTS.md              ← binding agent rules (+ scoped files under lib/)
├── docs/adr/
│   └── NNNN-<slug>.md
└── lib/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids — e.g. write **Media Request Credentials**, not "playback headers", when you mean the credentials allowed on the actual audio byte request.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_

## Language

ADRs are written in **Traditional Chinese** (台港用語), matching the rest of
`docs/`. `CONTEXT.md` keeps its English term names so they match the identifiers
they describe, with explanations in whichever language the entry already uses.
