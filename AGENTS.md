# AGENTS.md

This file provides repository-wide guidance to AI coding agents working in FMP.
Keep it short enough to stay in the default agent context; put subsystem details
in the nearest scoped `AGENTS.md`.

## Instruction Scope

Read this root file first, then read any more specific `AGENTS.md` in the
directory you are editing. More specific files extend or override this file for
their subtree.

| Area | Scoped Instructions |
|------|---------------------|
| Services, downloads, lyrics, account, radio | `lib/services/AGENTS.md` |
| Audio controller/backends/queue | `lib/services/audio/AGENTS.md` |
| Models, repositories, source overview | `lib/data/AGENTS.md` |
| Source adapters and stream resolution | `lib/data/sources/AGENTS.md` |
| Riverpod providers and database startup/migration | `lib/providers/AGENTS.md` |
| UI pages/widgets/layouts | `lib/ui/AGENTS.md` |

`CLAUDE.md` imports this file for Claude Code. Do not duplicate full guidance
between `CLAUDE.md` and `AGENTS.md`.

## Project Overview

FMP (Flutter Music Player) is a cross-platform music player supporting
**Bilibili**, **YouTube**, and **NetEase Cloud Music (Netease / 网易云音乐)**
audio sources. Target platforms are Android and Windows.

## Documentation Maintenance

After significant code changes, update the relevant instruction file in the same
change:

| Change Type | Section to Update |
|------------|-------------------|
| Audio architecture, queue, playback errors | `lib/services/audio/AGENTS.md` |
| Source adapters, stream/auth/header policy | `lib/data/sources/AGENTS.md` |
| New model fields, schemas, migrations | `lib/data/AGENTS.md`, `lib/providers/AGENTS.md`, `lib/ui/AGENTS.md` if the database viewer changes |
| Download, lyrics, account, import, radio, update services | `lib/services/AGENTS.md` |
| UI patterns, layouts, widgets | `lib/ui/AGENTS.md` |
| Repo-wide commands or architecture map | this file |

Keep `.serena/memories/` for narrow supplemental notes only. Do not duplicate
current core guidance there; when a memory becomes core/current, merge it into
the relevant `AGENTS.md` and delete the duplicate memory.

Human-facing documentation lives in `docs/`. Use `docs/README.md` as the
document map:
- Local build prerequisites and commands -> `docs/build-guide.md`
- CI release/signing/update asset behavior -> `docs/build-and-release.md`
- Runtime debugging/VM Service/Marionette workflows -> `docs/debugging-with-vm-service.md`
- General contributor onboarding -> `docs/development.md`

Historical refactoring notes are archived in `docs/history/refactoring-log.md`;
do not treat them as current guidance unless reflected in an `AGENTS.md` or a
current memory.

## Common Commands

```bash
flutter run                          # Run the app
flutter build apk                    # Android APK
flutter build windows                # Windows executable
flutter pub run build_runner build --delete-conflicting-outputs  # Isar code generation
dart run slang                       # Regenerate i18n files after lib/i18n/**/*.json changes
flutter analyze                      # Static analysis
flutter test                         # Run tests
```

**Targeted verification:**

| Change Area | Minimum Verification |
|------------|----------------------|
| Audio playback/controller/queue | `flutter test test/services/audio` + relevant `test/data/sources/*_source_test.dart` when stream resolution changes |
| Source adapters / HTTP policy | `flutter test test/data/sources test/services/account test/services/radio` |
| Download pipeline | `flutter test test/services/download test/providers/download` |
| Isar models / migrations | `flutter pub run build_runner build --delete-conflicting-outputs` + `flutter test test/providers/database_migration_test.dart test/ui/pages/settings/database_viewer_page_coverage_test.dart` |
| UI widgets/pages | Targeted widget/static-rule tests under `test/ui` + `flutter analyze` |
| i18n JSON changes | `dart run slang` + `flutter analyze` |
| Documentation-only changes | `git diff --check` |

## Hard Boundaries

Always:
- Prefer `rg` / `rg --files` for searching.
- Preserve unrelated user changes in the working tree.
- Preserve meaningful comments that explain non-obvious intent, historical
  rationale, edge cases, upstream behavior, or bug-workaround context. When
  updating such comments, keep the original reason unless it is demonstrably
  stale, and replace it with equivalent current rationale instead of deleting it.
- Use repository patterns and local helper APIs before inventing new abstractions.
- Keep generated Isar/slang outputs in sync when changing schemas or i18n JSON.
- Include focused verification in the final report.

Ask first:
- Before changing public architecture, persisted schema semantics, auth boundary,
  or cross-platform behavior in a way not already documented.
- Before destructive git operations or broad rewrites unrelated to the request.

Never:
- Do not bypass `AudioController` from UI playback controls.
- Do not open or migrate the Isar database through ad-hoc paths.
- Do not add hidden global enabled-source filters for search.
- Do not use direct `Image.network()` / `Image.file()` in UI.
- Do not commit, amend, rebase, or push unless the user explicitly requests it.

## Architecture Map

### Audio

UI playback controls call `AudioController` from `lib/services/audio`, not
`FmpAudioService` directly. Android uses `JustAudioService`; Windows uses
`MediaKitAudioService`. Queue order, shuffle/loop, temporary playback, network
retry, Mix mode, and stream handoff details are in
`lib/services/audio/AGENTS.md`.

### State Management

Riverpod is the app state layer.

Key providers:
- `audioControllerProvider` - main audio state (`PlayerState`)
- `playlistProvider` / `playlistDetailProvider` - playlist management
- `libraryInvalidationCoordinatorProvider` - playlist/detail/cover/download invalidation coordinator
- `searchProvider` - search state; chips select All/Bilibili/YouTube/Netease
- `neteaseSourceProvider` - lyrics-layer `NeteaseSource` singleton (`lib/services/lyrics/netease_source.dart`); distinct from the same-named data source adapter in `lib/data/sources/netease_source.dart`, which must not be consumed at runtime per `lib/data/sources/AGENTS.md`
- `neteaseAccountProvider` / `neteaseAccountServiceProvider` - Netease account
- `lyricsSearchProvider` - multi-source lyrics search
- `audioSettingsProvider` - audio quality settings

Provider patterns and database startup rules are in `lib/providers/AGENTS.md`.

### Data

Persisted Isar models live in `lib/data/models/`, repositories in
`lib/data/repositories/`, and source adapters in `lib/data/sources/`.
Model/migration rules live in `lib/data/AGENTS.md`; source adapter rules live in
`lib/data/sources/AGENTS.md`.

### Services

Service details for downloads, lyrics, accounts, playlist import, radio, update,
Windows sub-windows, and thumbnail URL behavior live in
`lib/services/AGENTS.md`.

### UI

UI rules for image components, track actions, AppBar spacing, ListTile layout,
UI constants, and responsive breakpoints live in `lib/ui/AGENTS.md`.

## Agent Coordination

- For standalone delegated agents, resume follow-up work by the exact
  tool-returned agent identity, not by a human-friendly display label.
- Treat the returned agent ID as the source of truth for completed or idle
  one-off agents.
- Teammate names are for swarm/team workflows only unless the tool explicitly
  maps them to resumable standalone agents.
- After sending follow-up input, read the tool result carefully. Only consider
  delegation active when the result confirms the intended agent actually resumed
  or started executing.

## Key Paths

```text
lib/services/audio/        AudioController, playback backends, queue, stream handoff
lib/services/download/     Download scheduling, paths, source-aware media headers
lib/services/lyrics/       Lyrics search, cache, AI matching, desktop popup
lib/services/account/      Bilibili, YouTube, Netease login/account services
lib/services/radio/        Radio/live playback ownership and Bilibili live streams
lib/data/models/           Isar collections and DTOs
lib/data/repositories/     Isar data access
lib/data/sources/          Bilibili/YouTube/Netease source adapters and HTTP policy
lib/providers/             Riverpod providers and database initialization
lib/ui/                    Pages, widgets, layouts, windows
lib/i18n/                  slang translation JSON
```
