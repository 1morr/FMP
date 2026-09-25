# Code style, comments, commits

## Imports and files

- `lib/` imports only `package:fmp/…` (`always_use_package_imports`; the layer
  rule's regex depends on it). Barrel files re-export with package paths. Tests
  import `test/support/` relatively.
- Files are `snake_case.dart`, one public concept per file, named after it:
  `<Source>Source` → `<source>_source.dart`, `<Entity>Repository` →
  `<entity>_repository.dart`, `XProvider` → `x_provider.dart`.
- Test-only hooks on production code: `@visibleForTesting` + a `…ForTesting` or
  `debug…` name.

## Comments and dartdoc

- New and edited comments are Traditional Chinese (AGENTS.md § Conventions).
  The tree still holds Simplified lines; convert only lines you are editing.
  Log messages, exception messages, test names and identifiers are English.
- The reason for a piece of code lives in its `///` dartdoc or in the test that
  gates it, not in a markdown file. Dartdoc explains **why**: the issue number,
  the commit hash in backticks, the measured number with its date. `[Identifier]`
  references must resolve (`comment_references` lint).
- Load-bearing sentences are `**bold**`. Audio collaborators keep a "what it
  deliberately does not own" paragraph.
- No `TODO` / `FIXME` in `lib/` — open an issue instead.

## Lints and `// ignore:`

`analysis_options.yaml` = `flutter_lints` plus `prefer_const_constructors`,
`prefer_const_declarations`, `always_use_package_imports`,
`deprecated_member_use_from_same_package`, `comment_references`, each with its
reason as a comment. An `// ignore:` or `// ignore_for_file:` gets a comment on the
line above saying why (`lib/data/database/database_migration.dart`).

## Removing code

Code with no callers is deleted, not kept for later (`aa0bdd28`, `19f721c7`).
Internal refactors delete the old path; no compatibility shim. Persisted formats
are the exception — see `../data/persistence.md` § Migrations.

## Commits, branches, PRs

- Conventional Commits, English, imperative, lowercase, no period, subject ≤ 72.
  Scopes follow the area (`audio`, `ui`, `download`, `data`, `sources`,
  `providers`, `settings`, …).
- **Commit types are user-facing.** There is no CHANGELOG: release notes are
  generated from `feat` / `fix` / `perf` / `chore(deps` / `build(deps` subjects
  (`docs/build-and-release.md`). Write those subjects as outcomes the user would
  recognise; use `refactor` / `test` / `docs` / `chore` for everything else.
- The body explains why and non-obvious trade-offs.
- Branches: `<type>/<kebab-description>` (`fix/paused-transport-retry`). One PR per
  branch into `main`, merged with a merge commit. A version bump is its own PR.
