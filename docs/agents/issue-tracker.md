# Issue tracker: Local Markdown

Issues and specs for this repo live as markdown files in `.scratch/`.

GitHub issues on `1morr/FMP` are for outside reports only; turning one into work means writing a ticket here. How to write the GitHub issues themselves is in `AGENTS.md`〈Issues〉.

## Conventions

- One milestone per directory: `.scratch/<milestone>/` (`m0`, `m1`, …); an effort that is not a milestone (a docs cleanup, an audit) uses `.scratch/<effort-slug>/` with the same layout
- The spec is `.scratch/<milestone>/spec.md`, with the sections 目標, 範圍, 共同規則, 驗收, 票序 (steps in `docs/agents/milestone.md`). It is written as the first step of the fresh session where the user runs `/to-tickets docs/roadmap.md 拆 <milestone> 的票`, before the tickets are drafted, by refining the milestone's section in `docs/roadmap.md`; that section then shrinks to one line linking here. Milestones not yet opened have no `.scratch/` directory and live only in the roadmap
- Implementation issues are one file per ticket at `.scratch/<milestone>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file; a ticket inserted later takes the previous number plus a letter (`14b`)
- Each ticket names what to read (`讀: plan §x、brief §y`) and lists its acceptance criteria as checkboxes under `## 驗收`
- The last ticket of a milestone is the acceptance ticket `<NN>-<milestone>-acceptance.md`, blocked by every other ticket; it ends with the user trying the milestone (`docs/agents/milestone.md`)
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings); a finished ticket is `Status: done`
- Blocking is a `Blocked by:` line under `Status:`, listing ticket numbers or `None`
- A new ticket starts from `docs/agents/ticket-template.md`
- Comments and conversation history append to the bottom of the file under a `## Comments` heading; a finished ticket ends it with a `Session 紀錄：` line (and one `偏差：` line per deviation), which whoever merges the ticket copies into `docs/progress.md`

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<milestone>/issues/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
