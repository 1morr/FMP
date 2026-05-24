# FMP Security Review Instruction And Documentation Corpus

Scope: repository-wide security and privacy review for FMP, created before
domain-specific review work. This corpus separates normative agent/project
instructions from descriptive documentation that must be verified against code.

## Discovered Instruction Sources

Normative repo-local instruction files:

- `AGENTS.md`
- `CLAUDE.md` importing `AGENTS.md`
- `lib/services/AGENTS.md`
- `lib/services/audio/AGENTS.md`
- `lib/data/AGENTS.md`
- `lib/data/sources/AGENTS.md`
- `lib/providers/AGENTS.md`
- `lib/ui/AGENTS.md`

Agent instruction directories:

- `docs/agents/` was not present.
- `docs/superpowers/` exists with empty `plans/` and `specs/` directories.

Current supplemental `.serena/memories/` files:

- `.serena/memories/code_style.md`
- `.serena/memories/download_system.md`
- `.serena/memories/refactoring_lessons.md`
- `.serena/memories/ui_coding_patterns.md`
- `.serena/memories/update_system.md`

Root and documentation-map referenced current docs:

- `README.md`
- `docs/README.md`
- `docs/development.md`
- `docs/build-guide.md`
- `docs/build-and-release.md`
- `docs/debugging-with-vm-service.md`

Archived or background docs:

- `docs/history/refactoring-log.md` is explicitly historical and not a current
  implementation rule unless reflected in an `AGENTS.md` file or current memory.
- `docs/reviews/sources/*` are prior review artifacts. They may seed questions
  but are not treated as normative or verified security evidence.

## Normative Requirements To Apply Directly

These requirements constrain the review because they define intended security or
privacy boundaries:

- Preserve unrelated user changes and avoid destructive git operations.
- Source API/media headers should be centralized in `SourceHttpPolicy`; source
  adapters and account services should use policy helpers for stable API
  headers.
- Playback/download media headers are intentionally narrower than stream
  resolution auth headers; `SourceHttpPolicy.mediaHeaders()` currently merges
  auth headers only for Netease media requests.
- Bilibili and YouTube auth cookies/authorization should stay in source API or
  stream URL resolution unless a future design explicitly changes that boundary.
- Downloads must use `buildDownloadMediaHeaders()` and
  `buildDownloadImageHeaders()` rather than relying on default Dio headers.
- Download path deduplication is by `savePath`, not `trackId`; files should
  exist before a downloaded path is persisted.
- Android custom download directories require the app-owned storage permission
  path through `StoragePermissionService`.
- Runtime Isar files should live under the app documents directory's `FMP/`
  child and be opened through `openFmpDatabase()`.
- Isar collection or persisted field changes must keep the developer database
  viewer complete.
- UI should not use direct `Image.network()` or `Image.file()` for app image
  rendering.
- `desktop_multi_window` sub-windows should use
  `RegisterPluginsForSubWindow()` and exclude globally static plugins such as
  `tray_manager` and `hotkey_manager`.

## Descriptive Claims Requiring Code Verification

These claims describe current behavior and must be verified in code before being
used as evidence:

- Bilibili login supports QR code and WebView cookie extraction, with cookie
  auto-refresh behavior.
- YouTube login uses WebView cookie extraction and SAPISIDHASH.
- Netease login supports QR code and WebView cookie extraction, and `MUSIC_U`
  is the long-lived token.
- `useBilibiliAuthForPlay`, `useYoutubeAuthForPlay`, and
  `useNeteaseAuthForPlay` defaults and actual call-site propagation.
- Specific headers for Bilibili, YouTube, Netease, live APIs, media/CDN
  requests, download requests, and image requests.
- Short URL redirect handling for `163cn.tv` and external playlist import.
- Spotify embed parsing through `__NEXT_DATA__`.
- Download directory layout, metadata, cover, and avatar write locations.
- Windows update/install, tray, hotkey, and lyrics popup lifecycle behavior.
- Debugging and database viewer exposure described in docs.

## Review Handling Rules

- Only valid findings with a realistic attack, leak, or failure path should
  appear in `summary.md`.
- If a risk is blocked by current code, record it as checked and safe in the
  domain report and, when important, in the summary false-positive section.
- Documentation inaccuracies should be reported separately from security
  findings unless they create a concrete unsafe implementation path.
- Prior source-review findings must be revalidated against current code before
  being carried into this security review.
