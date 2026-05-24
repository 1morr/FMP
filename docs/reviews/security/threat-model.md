# FMP Repository Threat Model

## Overview

FMP is a Flutter music player for Android and Windows. It stores user library
state locally, talks to third-party music platforms, supports account login for
Bilibili, YouTube, and Netease, downloads media and metadata to local storage,
and exposes desktop integrations such as tray, global hotkeys, SMTC, and a
lyrics popup window.

Primary runtime code lives under `lib/`, with external source adapters in
`lib/data/sources/`, account services in `lib/services/account/`, download and
filesystem logic in `lib/services/download/`, persistent Isar models in
`lib/data/models/`, database startup in `lib/providers/database_provider.dart`,
and Windows integration under `windows/` plus `lib/ui/windows/`.

## Threat Model, Trust Boundaries, And Assumptions

Assets that matter:

- Third-party account credentials and session material, including cookies,
  SAPISIDHASH-derived headers, and `MUSIC_U`.
- Local listening history, playlists, search history, imported playlist data,
  lyrics cache, download tasks, and settings.
- Downloaded media and metadata on user-controlled filesystem paths.
- Update/download artifacts and Windows integration state.

Trust boundaries:

- User-controlled input enters through URLs, playlist imports, searches,
  WebView login sessions, directory selection, filenames derived from remote
  titles, and settings.
- Third-party platforms control API responses, media URLs, redirects,
  thumbnails, avatars, playlist HTML/JSON, and error messages.
- Local storage and selected download directories may be shared with other
  desktop/mobile apps.
- Debug-only tooling such as VM Service, Isar Inspector, and developer database
  viewer is trusted only in local developer contexts and should not expose
  tokens unnecessarily.
- Windows sub-windows and plugins share process or platform-channel state; a
  sub-window must not steal global plugin channels from the main window.

Assumptions:

- FMP is a client-side app, not a multi-tenant server. Remote attackers generally
  need control over third-party content, an imported URL, a redirect target, or
  a local file/directory path chosen by the user.
- Third-party platforms may rate-limit or revoke accounts; the app should avoid
  leaking credentials across domains and avoid logging secrets.
- Local plaintext storage of application state may be acceptable for a desktop
  music player, but credentials and long-lived cookies still require minimized
  exposure in logs, UI, exports, and developer tools.

## Attack Surface, Mitigations, And Attacker Stories

High-value attack surfaces:

- Account login and token extraction services for Bilibili, YouTube, and
  Netease.
- `SourceHttpPolicy` and all custom Dio clients or one-off request headers.
- Redirect and short URL resolution before importing playlists or media.
- Download path construction, filename sanitization, metadata/cover/avatar
  writes, and overwrite behavior.
- Isar persistence of accounts, settings, lyrics cache, history, and download
  tasks.
- WebView cookie extraction and JavaScript/HTML parsing of remote playlist
  pages.
- Windows update/install helpers, global hotkey registration, tray integration,
  sub-window plugin registration, and desktop lyrics window lifecycle.

Existing controls to verify:

- Central source header policy and source-aware download media/image helpers.
- Netease-only media auth merge boundary in `SourceHttpPolicy.mediaHeaders()`.
- Download path helpers and write-permission checks.
- Database opened through a single provider-controlled path.
- Sub-window plugin registration that excludes globally static channel plugins.
- Developer docs requiring sensitive descriptions to be verified in code.

Realistic attacker or failure stories:

- A malicious playlist or redirect tries to make the app send platform cookies
  or auth headers to a non-platform host.
- A remote title, artist, or playlist name tries to escape the chosen download
  directory or overwrite another file through path traversal or reserved names.
- A long-lived cookie or derived auth header is logged, surfaced in UI, exported
  through the database viewer, or persisted where a normal user does not expect.
- A WebView login flow extracts more cookies than intended or fails to scope
  cookies to the target platform.
- A Windows sub-window registers a global plugin and breaks main-window tray or
  hotkey ownership, causing stability or unintended global input handling.

Out of scope or lower realism:

- Server-side authorization bugs are out of scope because FMP has no backend.
- DRM bypass and platform ToS issues are not security findings unless they
  create user credential leakage, local data exposure, or unsafe filesystem
  behavior.
- Local malware reading the user's app data directory is outside the app's
  protection boundary unless FMP unnecessarily expands exposure to broader
  locations or logs.

## Severity Calibration

Critical:

- Remote-controlled input can cause arbitrary code execution, arbitrary file
  overwrite outside the selected storage boundary, or silent exfiltration of
  account credentials to attacker-controlled hosts.

High:

- Long-lived credentials such as `MUSIC_U` or YouTube/Bilibili cookies can be
  leaked to third-party domains, logs, update artifacts, or UI/database tools
  reachable by normal users.
- A redirect or import path can persist malicious filesystem paths that later
  overwrite sensitive user files.

Medium:

- User privacy data such as history, search terms, playlist imports, or lyrics
  cache is exposed in developer UI without clear gating, or credentials are
  stored/propagated more broadly than the documented setting implies.
- Download path sanitization prevents traversal but still allows predictable
  overwrites or confusing same-folder collisions.

Low:

- Documentation or implementation inconsistencies that could mislead future
  security-sensitive changes but do not currently expose data.
- Stability issues in desktop integrations that can disrupt global hotkey or
  tray behavior without crossing a credential or data boundary.

Informational:

- Confirmed-safe controls, expected local-only storage, and documentation
  clarifications with no immediate exploit path.
