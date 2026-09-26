# Cross-layer thinking guide

## The flow

```
source API ─► adapter (lib/data/sources) ─► SourceManager capability
          ─► service (lib/services) ─► repository ─► Isar
          ─► provider (lib/providers) ─► widget (lib/ui) ─► slang string
media bytes: StreamResolutionService ─► MediaHandoff ─► audio backend / download isolate
```

Each arrow is a contract. An error usually becomes a user sentence once, at the
edge (`userMessageFor` — see `../shared/errors-and-logging.md`); the import path
translates earlier (`ImportService`, the playlist import sources).

## Changes that always fan out

### A new persisted setting

1. Field on `Settings` with a default; decide whether Isar's type default for old
   rows is acceptable → migration step or not (`../data/persistence.md`).
2. `dart run build_runner build`.
3. Backup export + import, or an entry in `_deliberatelyExcludedSettingsFields`
   with a reason.
4. Read-modify-write through `SettingsRepository.update(...)`.
5. The provider that exposes it; if it drives background behaviour, anchor it in
   `FMPApp.build`.
6. UI + strings in all three locales.
7. If audio reads it, both backends honour it, or the difference is in the
   `FmpAudioService` dartdoc.

### A new source, or a new capability on a source

Adapter + exception subtype + `SourceHttpPolicy._bySource` row + outbound hosts +
`SourceManager` registration + `live` guard list + per-source default tables in
`settings.dart` + source lists from the providers, never hand-written.
ADR 0001 says what an unknown source id must do at each branch point.

### A new user-visible string

Three locale files, `dart run slang`, and on-device verification if it can
change layout. A string the desktop lyrics window reads must also be pushed to it.

### A new track identity or key

`TrackKey` only; ADR 0005 explains why `cid` is part of it and what must be
relinked in the same transaction.

### Anything about credentials

Name which of the `CONTEXT.md` terms applies: Stream Resolution Auth
(adapter request) and Media Request Credentials (byte request, empty by
construction) are different arrows. Changing either needs the user's approval.
