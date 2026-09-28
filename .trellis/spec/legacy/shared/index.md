# Shared conventions (every layer)

Applies to all Dart code in `lib/`, `test/` and `tool/`, and to commits.

## Guidelines

| File | Read when |
|------|-----------|
| [errors-and-logging.md](./errors-and-logging.md) | Throwing, catching or showing an error; writing a log line |
| [code-style.md](./code-style.md) | Every change: imports, comments and dartdoc, lints and `// ignore:`, naming, commits and PRs |

## Pre-Development Checklist

- [ ] The change touches an error path or adds logging → read `errors-and-logging.md`.

## Quality Check

- `dart format --output=none --set-exit-if-changed lib test tool` and `flutter analyze` are clean (CI order: format → `build_runner` → `slang` → analyze → test).
- New user-visible text and new `state.error` values are not built from `e.toString()` (existing `state.error` offenders are listed in `errors-and-logging.md`); no secret, cookie or signed URL in a new log line.
- Comments on edited lines are Traditional Chinese; untouched Simplified lines are left alone.
