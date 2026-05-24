# Security Documentation Alignment Review

Scope: security, account, source headers, download paths, database viewer /
Isar debug tooling, WebView login/import, and Windows plugin-registration
instructions. Historical source-review reports were treated as background only;
all statements below were rechecked against current code.

## Valid findings

### 1. Release docs put Android signing secrets in shell arguments and leave a keystore copy in temp

Risk: Medium

Affected documentation:
- `docs/build-guide.md:74`-`docs/build-guide.md:82` shows `keytool` with
  `-storepass <你的密码>` and `-keypass <你的密码>` on the command line.
- `docs/build-and-release.md:27`-`docs/build-and-release.md:34` repeats the
  same command-line password pattern.
- `docs/build-and-release.md:77` writes a base64 copy of
  `android/release.keystore` to `$env:TEMP\ks.txt`.
- `docs/build-and-release.md:81`-`docs/build-and-release.md:83` sets GitHub
  secrets with `gh secret set ... --body "<你的密码>"`.

Evidence:
- The CI workflow consumes these values as real signing secrets:
  `.github/workflows/build.yml:56`-`.github/workflows/build.yml:60`.
- Android release signing reads `android/key.properties` fields directly:
  `android/app/build.gradle.kts:11`-`android/app/build.gradle.kts:14` and
  `android/app/build.gradle.kts:39`-`android/app/build.gradle.kts:53`.
- Local secret files are ignored, but that only protects git commits:
  `.gitignore:46`-`.gitignore:48`.

Attack or failure scenario:
- A maintainer follows the docs literally with real passwords. The keystore
  password can land in shell history, terminal logs, process listings, or CI
  troubleshooting transcripts. `$env:TEMP\ks.txt` also remains as a reusable
  base64 keystore copy until manually removed. Anyone with that artifact plus
  the exposed password can sign update-compatible APKs.

Recommended fix:
- Replace command-line password examples with interactive prompts or stdin/file
  input. For GitHub secrets, prefer `gh secret set NAME --body-file -` or
  prompt-driven commands instead of `--body "<secret>"`.
- Add a cleanup step after base64 upload, for example removing
  `$env:TEMP\ks.txt`.
- Add an explicit warning that signing passwords, keystores, and encoded
  keystore files must not be pasted into issue comments, agent reports, shell
  history, or logs.

### 2. VM Service / Isar debug guide omits the privacy boundary for debug tokens and exported local data

Risk: Medium

Affected documentation:
- `docs/debugging-with-vm-service.md:32`-`docs/debugging-with-vm-service.md:48`
  instructs agents to extract and reuse the VM Service URL and token.
- `docs/debugging-with-vm-service.md:453`-`docs/debugging-with-vm-service.md:468`
  documents Isar schema/query/export APIs, including `exportJson`, without
  warning that exports are sensitive local user data.
- `docs/debugging-with-vm-service.md:633`-`docs/debugging-with-vm-service.md:640`
  correctly says VM Service and Isar Inspector are debug/profile-only, but does
  not state that their URI token and outputs must be treated as secrets.

Evidence:
- The app registers privacy-relevant local collections in the same Isar
  database exposed by the debug extension: `lib/providers/database_provider.dart:27`-`lib/providers/database_provider.dart:38`.
- Search history stores raw queries: `lib/data/models/search_history.dart:10`-`lib/data/models/search_history.dart:16`.
- Play history stores source IDs, titles, artists, thumbnails, and timestamps:
  `lib/data/models/play_history.dart:13`-`lib/data/models/play_history.dart:39`.
- Settings include custom download directory, hotkey config, and AI endpoint /
  model configuration: `lib/data/models/settings.dart:126`-`lib/data/models/settings.dart:133` and `lib/data/models/settings.dart:224`-`lib/data/models/settings.dart:231`.

Attack or failure scenario:
- An agent copies the VM Service URI, Isar export JSON, or query output into a
  review artifact or shared debug transcript. The token grants powerful local
  debug API access while the process is running, and exported collections can
  disclose listening history, search terms, local paths, and account metadata.

Recommended fix:
- Add a "Sensitive debug data" section to `docs/debugging-with-vm-service.md`.
- State that VM Service URLs/tokens and Isar export/query outputs must not be
  pasted into reports unless redacted.
- Require minimal-scope exports, temporary-file cleanup, and redaction of search
  history, play history, local paths, account metadata, and settings before
  sharing.
- Keep the existing debug/profile-only note, but clarify that local-only does
  not make the token or exported data safe to disclose.

## Checked and safe items

- Source media header boundary is accurate. Documentation says Bilibili and
  YouTube auth stays out of media/CDN headers while Netease media can carry
  auth. Current code implements that in `SourceHttpPolicy.mediaHeaders()`:
  `lib/data/sources/source_http_policy.dart:33`-`lib/data/sources/source_http_policy.dart:64`.
- Header tests lock this boundary: `test/data/sources/source_http_policy_test.dart:7`-`test/data/sources/source_http_policy_test.dart:42` and
  `test/services/download/download_media_headers_test.dart:10`-`test/services/download/download_media_headers_test.dart:49`.
- Download media/image helper guidance is accurate. The helpers delegate to the
  centralized source policy at `lib/services/download/download_media_headers.dart:4`-`lib/services/download/download_media_headers.dart:21`.
- Download path documentation matches current layout and persistence rules:
  `lib/services/AGENTS.md:8`-`lib/services/AGENTS.md:21` and
  `.serena/memories/download_system.md:17`-`.serena/memories/download_system.md:48`.
  Code computes sanitized playlist/title folders and fixed audio filenames in
  `lib/services/download/download_path_utils.dart:23`-`lib/services/download/download_path_utils.dart:100`.
- Account docs are directionally accurate. Bilibili, YouTube, and Netease
  credentials are persisted in `flutter_secure_storage`, while the Isar
  `Account` collection only stores account metadata:
  `lib/data/models/account.dart:7`-`lib/data/models/account.dart:42`,
  `lib/services/account/bilibili_account_service.dart:543`-`lib/services/account/bilibili_account_service.dart:584`,
  `lib/services/account/youtube_account_service.dart:77`-`lib/services/account/youtube_account_service.dart:83`, and
  `lib/services/account/netease_account_service.dart:437`-`lib/services/account/netease_account_service.dart:446`.
- WebView login docs are consistent with implementation: WebView cleanup and
  platform-scoped cookie extraction exist for Bilibili, YouTube, and Netease:
  `lib/ui/pages/settings/bilibili_login_page.dart:104`-`lib/ui/pages/settings/bilibili_login_page.dart:163`,
  `lib/ui/pages/settings/youtube_login_page.dart:34`-`lib/ui/pages/settings/youtube_login_page.dart:155`, and
  `lib/ui/pages/settings/netease_login_page.dart:106`-`lib/ui/pages/settings/netease_login_page.dart:158`.
- Windows sub-window guidance matches current runner behavior. The main window
  registers all generated plugins, while sub-windows use selective
  `RegisterPluginsForSubWindow()` registration and exclude tray/hotkey plugins:
  `windows/runner/flutter_window.cpp:15`-`windows/runner/flutter_window.cpp:40` and
  `windows/runner/flutter_window.cpp:62`-`windows/runner/flutter_window.cpp:71`.

## Instruction docs accuracy notes

- `lib/data/sources/AGENTS.md:192`-`lib/data/sources/AGENTS.md:196` accurately
  describes the Netease-only media-auth merge boundary. Keep this as a hard
  security boundary for future source/download changes.
- `lib/services/AGENTS.md:18`-`lib/services/AGENTS.md:21` accurately warns
  against relying on `DownloadService` Dio defaults for source-specific media
  headers.
- `lib/ui/AGENTS.md:103`-`lib/ui/AGENTS.md:108` accurately keeps the developer
  database viewer in schema-sync scope. It does not currently require masking
  because `Account` credentials are not in Isar, but future persisted secrets
  would need a viewer redaction rule in the same instruction file.
- `.serena/memories/download_system.md:32` says the centralized avatar path
  helpers are legacy and should be avoided in new code. That is accurate because
  `DownloadPathUtils.getAvatarPath()` and `ensureAvatarDirExists()` remain in
  code at `lib/services/download/download_path_utils.dart:152`-`lib/services/download/download_path_utils.dart:175`, while current metadata saves avatars in
  the video folder.
- The Windows plugin note is conservative. Current checked code excludes both
  tray and hotkey plugins from sub-windows. If dependency internals change, the
  instruction should keep the "check for global/static channel ownership before
  registering new sub-window plugins" rule rather than depending only on the
  historical rationale.

## Verification

- Read required instruction and documentation files:
  `AGENTS.md`, scoped `AGENTS.md` files, `README.md`, `docs/README.md`,
  `docs/development.md`, `docs/build-guide.md`,
  `docs/build-and-release.md`, `docs/debugging-with-vm-service.md`,
  `.serena/memories/*.md`, `docs/reviews/security/instruction-document-corpus.md`,
  and `docs/reviews/security/threat-model.md`.
- Verified claims against current implementation and tests with targeted `rg`
  and line-numbered reads of `SourceHttpPolicy`, account services, WebView
  login pages, download helpers/path utilities, Isar database/provider/viewer
  code, Windows plugin registration, and relevant tests.
- No product code was modified.
