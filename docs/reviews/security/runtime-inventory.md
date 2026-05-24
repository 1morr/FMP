# FMP Security Runtime Inventory

This inventory scopes the repository-wide security review to product/runtime
surfaces reachable by users, remote platform responses, local files, or desktop
integration events. Tests, archived docs, generated code, and prior review
reports are not treated as runtime attack surface.

## Entrypoints And Trust Boundaries

- Flutter app startup and provider wiring: `lib/main.dart`, `lib/app.dart`.
- Router-visible user flows: search, library/downloaded views, settings,
  developer tools, account login pages, download manager, radio/player routes in
  `lib/ui/router.dart`.
- Third-party platform APIs and media URLs: `lib/data/sources/**`.
- Account login and session handling: `lib/services/account/**` and
  `lib/ui/pages/settings/*login_page.dart`.
- WebView cookie extraction: Bilibili, YouTube, and Netease login pages using
  `CookieManager`.
- External playlist import: `lib/data/sources/playlist_import/**` and
  `lib/services/import/playlist_import_service.dart`.
- Downloads and filesystem writes/deletes: `lib/services/download/**`,
  `lib/providers/download/**`, and local track path helpers.
- Persistent local data: Isar models in `lib/data/models/**`, repositories in
  `lib/data/repositories/**`, and database initialization in
  `lib/providers/database_provider.dart`.
- Developer data inspection: `lib/ui/pages/settings/database_viewer_page.dart`
  and log viewer routes.
- Desktop/Windows integration: `windows/runner/**`, generated plugin
  registration, `lib/ui/windows/lyrics_window.dart`, hotkey/tray providers, SMTC
  and update service.
- Android permissions and installer integration:
  `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/**`,
  and `lib/services/storage_permission_service.dart`.

## Security-Sensitive Dependencies

Runtime dependencies relevant to this review include `dio`, `isar`,
`flutter_inappwebview`, `youtube_explode_dart`, `just_audio`, `media_kit`,
`audio_service`, `smtc_windows`, `tray_manager`, `hotkey_manager`,
`desktop_multi_window`, `path_provider`, `file_picker`, `open_filex`,
`archive`, `crypto`, `encrypt`, and `pointycastle`.

## High-Impact Coverage Ledger

| Row | Boundary | Family | Status | Evidence / Notes |
|-----|----------|--------|--------|------------------|
| H1 | Account services and login pages | credential leakage / logging / UI exposure | delegated | Account / Credential Agent |
| H2 | SourceHttpPolicy and Dio clients | cross-domain credential/header leakage | delegated | Network / Headers Agent |
| H3 | Redirect and short URL import | credential leak / SSRF-like local fetch / untrusted parsing | delegated | Network and WebView / External Input Agents |
| H4 | Download path construction and deletion | path traversal / arbitrary write/delete / overwrite | delegated | Download / Filesystem Agent |
| H5 | Metadata, cover, avatar writes | untrusted data persistence / filename or JSON injection | delegated | Download / Filesystem Agent |
| H6 | Isar persistence and database viewer | local credential or history exposure | delegated | Database / Local Data Agent |
| H7 | WebView cookie extraction | overbroad cookie capture / stale login state | delegated | WebView / External Input Agent |
| H8 | Windows sub-window plugin registration | global channel ownership / desktop stability | delegated | Desktop / Windows Agent |
| H9 | Global hotkey/tray/lyrics popup lifecycle | unintended global input handling / stale popup state | delegated | Desktop / Windows Agent |
| H10 | Documentation alignment | unsafe or stale security guidance | pending | Security Documentation Alignment Agent to be spawned after agent-slot frees |

## Explicit Scope Limits

- This review does not treat third-party platform policy/ToS bypass as a
  security finding unless it creates user data, credential, filesystem, or local
  privacy risk.
- Local plaintext app data is evaluated relative to a desktop/mobile local-app
  threat model. It becomes reportable when the app exposes secrets through UI,
  logs, exports, cross-domain requests, or unexpectedly broad filesystem scope.
- Update-channel security is reviewed only for concrete reachable risk in the
  checked-out code, not as generic package-version advice.
