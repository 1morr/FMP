# Data layer (`lib/core/`, `lib/data/`)

Applies to source adapters (`lib/data/sources/`), Isar models, repositories and
the database (`lib/data/models/`, `lib/data/repositories/`, `lib/data/database/`),
and the shared foundation in `lib/core/` (errors, logger, constants, utils).

Neither directory imports `lib/services/` or `lib/providers/` (one recorded
exception, `lib/core/extensions/track_extensions.dart`, in
`test/support/layer_boundary_static_rule_test.dart`) — see AGENTS.md § Boundaries. Vocabulary for auth and media handoff is in `CONTEXT.md`.

## Guidelines

| File | Read when |
|------|-----------|
| [sources.md](./sources.md) | Adding or changing a source adapter, a source capability, source HTTP headers, source errors, URL parsing |
| [persistence.md](./persistence.md) | Adding a model field or collection, writing a repository method, migrating the schema, building track identity keys |

Cross-layer error and logging rules: [../shared/errors-and-logging.md](../shared/errors-and-logging.md).

## Pre-Development Checklist

- [ ] Changing a source adapter → read `sources.md` and ADR 0001 (string source ids).
- [ ] Touching `Track` identity, `cid` or lyrics matching → read ADR 0005 and the identity section of `persistence.md`.
- [ ] Adding or changing a persisted field → read the `kFmpSchemaVersion` dartdoc in `lib/data/database/database_migration.dart` **before** editing the model. Changing persisted schema semantics needs the user's approval first (AGENTS.md § Conventions).
- [ ] Anything that reaches Isar → it goes in `lib/data/repositories/` (ADR 0002).

## Quality Check

- Run the AGENTS.md § Verification rows that match the change: *Source adapters / HTTP policy*, *Isar models / migrations*.
- Codegen is gitignored: after a model change run `dart run build_runner build` before tests, or a missing getter looks like a source bug.
- New outbound host, `Timer.periodic`, header literal or cross-feature import → the static-rule test for it turns red; add the entry with a reason rather than working around the detector.
- No `isar.` outside repositories, no concrete adapter outside `SourceManager`, no credentials on media requests (see `sources.md`).
