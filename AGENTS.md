# AGENTS.md

Repository-wide guidance for AI coding agents working in FMP. Keep this file
short enough to stay in the default agent context; put subsystem details in the
nearest scoped `AGENTS.md`.

## Instruction Scope

Read this root file first, then the nearest `AGENTS.md` in the directory you are
editing. More specific files extend or override this file for their subtree.

| Area | Scoped Instructions |
|------|---------------------|
| Downloads, lyrics, account, backup, radio, update, Windows sub-windows | `lib/services/AGENTS.md` |
| Audio controller/backends/queue | `lib/services/audio/AGENTS.md` |
| Models, repositories, migration decisions | `lib/data/AGENTS.md` |
| Source adapters, stream resolution, HTTP/auth policy | `lib/data/sources/AGENTS.md` |
| Riverpod providers, database startup | `lib/providers/AGENTS.md` |
| UI pages/widgets/layouts | `lib/ui/AGENTS.md` |

`CLAUDE.md` is an import stub for Claude Code. Keep guidance here, not there.

## Project Overview

FMP (Flutter Music Player) is a cross-platform music player supporting
**Bilibili**, **YouTube**, and **NetEase Cloud Music (Netease / 网易云音乐)**
audio sources. Target platforms are Android and Windows.

## Agent Skills

- **Issue tracker** — GitHub Issues on `1morr/FMP`, via the `gh` CLI. See
  `docs/agents/issue-tracker.md`.
- **Triage labels** — the five canonical roles, each label string equal to its
  name. See `docs/agents/triage-labels.md`.
- **Domain docs** — single-context: root `CONTEXT.md` + `docs/adr/`. See
  `docs/agents/domain.md`.
- **On-device verification** — `.claude/skills/verify-on-device/SKILL.md`. How
  to boot the emulator detached, own `flutter run` in an Orca terminal, drive
  the UI with `orca emulator ax` / `tap`, read Dart logs, and hot reload.
  Required for user-visible changes (see Targeted verification below), not
  optional. Two hard constraints: the Windows build exposes no semantics tree
  (screenshot and window-local coordinates only), and non-ASCII input on Android
  is unavailable — cover CJK input with `integration_test` and
  `WidgetTester.enterText` instead.
- **Runtime debugging** — `docs/debugging-with-vm-service.md`. Reach for it when
  a question needs the running app rather than the source: memory pressure and
  GC (§3.2–3.3), frame timing (§3.4), widget/render trees (§4.3 — dump to a file
  first, the render tree measured 3.85 MB), Isar contents (§5), and `dart:io`
  HTTP/socket profiling (§3.5–3.6 — enable it *before* the traffic you want to
  see, or it records nothing). `getHttpProfileRequest` gives per-request timing
  plus full headers and bodies, which beats adding a Dio interceptor.

## Documentation Maintenance

Update the relevant instruction file in the same change as the code:

| Change Type | Section to Update |
|------------|-------------------|
| Audio architecture, queue, playback errors | `lib/services/audio/AGENTS.md` |
| Source adapters, stream/auth/header policy | `lib/data/sources/AGENTS.md` |
| New model fields, schemas, migrations | `lib/data/AGENTS.md` + `lib/providers/AGENTS.md`, and `lib/ui/AGENTS.md` if the database viewer changes |
| Download, lyrics, account, import, backup, radio, update | `lib/services/AGENTS.md` |
| UI patterns, layouts, widgets | `lib/ui/AGENTS.md` |
| Emulator/desktop verification steps, device limitations | `.claude/skills/verify-on-device/SKILL.md` |
| Repo-wide commands or architecture map | this file |

Scoped `AGENTS.md` files are authoritative. Do not maintain a parallel memory
directory (e.g. the removed `.serena/memories/`) — separate notes drift from the
code. State each rule in exactly one file and cross-reference it from the others
instead of restating it.

Human-facing documentation lives in `docs/`; `docs/README.md` is the map.

## Common Commands

```bash
flutter run                          # Run the app
flutter build apk                    # Android APK
flutter build windows                # Windows executable
dart run build_runner build  # Isar code generation
dart run slang                       # Regenerate i18n after lib/i18n/**/*.json changes
flutter analyze                      # Static analysis
flutter test                         # Run tests
```

**Targeted verification:**

| Change Area | Minimum Verification |
|------------|----------------------|
| Audio playback/controller/queue | `flutter test test/services/audio` (+ `test/data/sources` when stream resolution changes) |
| Source adapters / HTTP policy | `flutter test test/data/sources test/services/account test/services/radio` |
| Download pipeline | `flutter test test/services/download test/providers/download` |
| Isar models / migrations | `dart run build_runner build` + `flutter test test/providers/database_migration_test.dart test/ui/pages/settings/database_viewer_page_coverage_test.dart` |
| UI widgets/pages | Targeted tests under `test/ui` + `flutter analyze` + the on-device check below |
| i18n JSON changes | `dart run slang` + `flutter analyze` |
| Documentation-only changes | `git diff --check` |

**On-device verification is mandatory for user-visible changes.** When a change
alters UI pages or widgets, playback controls, how source results render, or a
user-facing string in a way that can affect layout, tests and `flutter analyze`
are not sufficient on their own — run the app and confirm the change on screen
before reporting it. Follow `.claude/skills/verify-on-device/SKILL.md`.

- **Android emulator is the required platform.** Its semantics tree lets you
  assert on real elements and text; the Windows build yields screenshots only.
  Verify on Windows as well only when the change is Windows-specific.
- Report what you drove and what you observed — the element, log line, or
  screenshot path. "Should work" is not a verification.
- If the emulator cannot be brought up or the change cannot be reached in the
  UI, say so explicitly and name the blocker. Never silently downgrade to tests.

## Hard Boundaries

Always:
- Prefer `rg` / `rg --files` for searching.
- Preserve unrelated user changes in the working tree.
- Preserve comments that explain non-obvious intent, historical rationale, edge
  cases, upstream behavior, or bug workarounds. When updating one, keep the
  original reason unless it is demonstrably stale, and replace it with equivalent
  current rationale instead of deleting it.
- Use repository patterns and local helper APIs before inventing abstractions.
- Keep generated Isar/slang outputs in sync when changing schemas or i18n JSON.
- Include focused verification in the final report.

Ask first:
- Before changing public architecture, persisted schema semantics, the auth
  boundary, or cross-platform behavior in a way not already documented.
- Before destructive git operations or broad rewrites unrelated to the request.

Never:
- Do not bypass `AudioController` from UI playback controls.
- Do not open or migrate the Isar database through ad-hoc paths.
- Do not add hidden global enabled-source filters for search.
- Do not use direct `Image.network()` / `Image.file()` in UI.
- Do not try to "fix" the benign `Failed to update ui::AXTree` Windows log spam —
  it is a known Flutter engine bug (`flutter/flutter#182444`), not an FMP defect.
  See `docs/troubleshooting.md`.

## Architecture Map

**Audio** — UI playback controls call `AudioController`
(`lib/services/audio/audio_provider.dart`), never `FmpAudioService` directly.
Android uses `JustAudioService`; desktop uses `MediaKitAudioService`. Radio is
the one intentional exception.

**State** — Riverpod is the app state layer. Key providers:

- `audioControllerProvider` — main audio state (`PlayerState`)
- `playlistListProvider` / `playlistDetailProvider` — playlist management
  (`lib/providers/library/playlist_provider.dart`)
- `libraryInvalidationCoordinatorProvider` — playlist/detail/cover/download
  invalidation coordinator
- `searchProvider` — search state; chips select All/Bilibili/YouTube/Netease
- `neteaseAccountProvider` / `neteaseAccountServiceProvider` — Netease account
- `lyricsSearchProvider` — multi-source lyrics search
- `audioSettingsProvider` — audio quality settings
- `neteaseSourceProvider` — the **lyrics-layer** `NeteaseSource` singleton
  (`lib/services/lyrics/netease_source.dart`). A same-named data source adapter
  exists at `lib/data/sources/netease_source.dart`; it is registered inside
  `SourceManager` and must be reached through narrow capabilities, never through
  a concrete source provider. See `lib/data/sources/AGENTS.md`.

**Data** — Isar collections in `lib/data/models/`, repositories in
`lib/data/repositories/`, source adapters in `lib/data/sources/`.

## Key Paths

```text
lib/core/                  Logger, ToastService, image loading/cache services,
                           UI constants, breakpoints, shared utils (thumbnail
                           URLs, Netease crypto, platform checks)
lib/services/audio/        AudioController, playback backends, queue, stream handoff
lib/services/download/     Download scheduling, paths, source-aware media headers
lib/services/media/        MediaHandoff — the byte-request header/redirect seam
lib/services/lyrics/       Lyrics search, cache, AI matching, desktop popup
lib/services/account/      Bilibili/YouTube/Netease login, SourceAuthContext
lib/services/radio/        Radio/live playback ownership and Bilibili live streams
lib/services/backup/       Portable JSON backup export/import
lib/services/cache/        Ranking and search result caches
lib/services/import/       Playlist import pipeline
lib/services/library/      Playlist CRUD and remote playlist sync
lib/services/network/      Shared Dio setup and connectivity
lib/services/platform/     Storage permissions, autostart, platform shims
lib/services/refresh/      Stale-data refresh coordination
lib/services/search/       Search orchestration across sources
lib/services/update/       In-app update check and installer handoff
lib/data/models/           Isar collections and DTOs
lib/data/repositories/     Isar data access — the only place `isar.` may
                           appear, apart from lib/providers/database/
lib/data/sources/          Bilibili/YouTube/Netease adapters, SourceHttpPolicy
lib/providers/             Riverpod providers and database initialization
lib/ui/                    Pages, widgets, layouts, windows
lib/i18n/                  slang translation JSON
```
