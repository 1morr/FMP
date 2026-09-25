# Research: testing conventions and repo-wide cross-cutting conventions

- **Query**: Test layout, mocking, static-rule pattern, wait conventions, lints, CI gates, logging, error handling, comment language, git conventions, codegen — for Trellis spec bootstrap
- **Scope**: internal
- **Date**: 2026-09-25

Already documented elsewhere (link, do not repeat): `AGENTS.md` (verification table, boundaries, static-rule list),
`docs/building.md#常用指令`, `docs/build-and-release.md` §CI 流程 / §Release Notes, `docs/development.md` §執行期除錯,
`test/manual/README.md`.

---

## 1. Test layout

| Rule | Evidence | Anti-pattern avoided |
|---|---|---|
| `test/` mirrors `lib/` layers: `test/{core,data,providers,services,ui}/<feature>/` | `test/services/audio/` (35 files) ↔ `lib/services/audio/`; `test/data/repositories/`, `test/ui/layouts/` | — |
| One class may have several test files split by behaviour, named `<class>_<aspect>_test.dart` | `audio_controller_handoff_and_errors_test.dart`, `audio_controller_mix_boundary_test.dart`, `media_kit_audio_service_{buffer,state}_test.dart`, `download_service_progress_and_disposal_test.dart` | multi-thousand-line single test files |
| Shared helpers live in `test/support/`, shared fakes in `test/support/fakes/`; imported **relatively** (`'../../support/pump_until.dart'`) since `test/` is not under `package:fmp` | import counts: `isar_test_harness` 59, `pump_until` 33, `fake_audio_service` 18, `now_playing` 14, `fake_source_auth_context` 14, `dart_source` 12, `audio_controller_harness` 11 | copy-pasting harnesses |
| Only files named `*_test.dart` are picked up; anything that must not run in `flutter test` is deliberately **not** named `_test.dart` | `test/manual/*.dart`, `test/performance/*_benchmark.dart`, `tool/demo/*_demo.dart` (headers explain why) | infinite-running probes / wall-clock budgets / live calls in CI |

**One-offs (do not mirror):** `test/bilibili_source_test.dart` and `test/app_content_wrapper_test.dart` sit at `test/` root (legacy placement; most source tests are under `test/data/sources/`).

### Special directories

- `test/live/sources_live_test.dart` — real-network smoke test of the 3 audio sources; file-level `@Tags(['live'])` + `library;`. Run by hand.
- `test/manual/` — human-watched probes (`pathological_stream_servers.dart`, `real_db_probe.dart`), see its README. `real_db_probe` runs via `FMP_PROBE_DB_DIR=… flutter test test/manual/real_db_probe.dart` on a **copy** of the DB.
- `test/performance/` — `startup_benchmark.dart`, `list_scrolling_benchmark.dart`: absolute ms budgets → "property of the machine, not the code", opt-in only (`flutter test test/performance/startup_benchmark.dart`). Use `// ignore: avoid_print` for printing.
- `test/workflows/` — tests over repo meta files: `pubspec_version_test.dart` (committed version not behind newest tag; needs `fetch-depth: 0`, skips via `markTestSkipped` on shallow clone; regression of `8d04147e`), `release_workflow_test.dart` (parses `release.yml` via `package:yaml`, `needs` graph), `release_assets_verification_test.dart` (tests `tool/release/verify_release_assets.dart`), `dependabot_group_static_rule_test.dart`.
- `tool/demo/` — hand-run scripts against real APIs; analysed + formatted by CI, never executed; header comment `// Manual probe, not a test… Run it by hand: dart run tool/demo/…` + `// ignore_for_file: avoid_print`.

### Tags

- Only tag: **`live`**, declared in `dart_test.yaml` (`tags: live:` with a comment). CI: `--exclude-tags live`.
- Two declaration forms in use: file-level `@Tags(['live'])` (`test/live/sources_live_test.dart:12`) and per-test `}, tags: 'live');` (`test/bilibili_source_test.dart:902`).
- Guarded by `test/support/live_source_tag_static_rule_test.dart`: a test that builds a real source with its **default constructor** (no injected Dio/client) for any of `_guardedClasses` (BilibiliSource, YouTubeSource, NeteaseSource, QQ Music, lrclib, Spotify…) must be tagged `live`, unless listed in `_exceptions` (`Map<path, reason>`). Origin: #56 (`setUp` built a real `BilibiliSource()`).

## 2. Mocking approach

- **No mocking library.** `pubspec.yaml` dev_deps have no mocktail/mockito (only `flutter_test`, `build_runner`, `isar_community_generator`, `flutter_lints`, `slang`, `http`, `yaml`, icon/installer tools). All doubles are **hand-written fakes**.
- Styles (counted in `test/`): `class _FakeX implements Y` (~46), `class _FakeX extends RealY` overriding members (~49), `extends Fake implements Y` from flutter_test (5), and `noSuchMethod` fall-through for unimplemented members (10 files). Unimplemented members intentionally throw `NoSuchMethodError` ("easier to debug than a fake value").
- Fakes record calls as public lists for assertions: `FakeAudioService.playUrlCalls`, `setNextMediaCalls`, `seekCalls` (`test/support/fakes/fake_audio_service.dart`).
- Convention stated in `FakeSourceAuthContext` dartdoc: the shared fake covers only the default ("not logged in") case; tests needing call recording / per-source headers write a **file-local `_Fake…`** instead of adding switches to the shared one. Hence 5 local `_FakeSourceAuthContext`, 9 local `_FakeSourceManager`, 7 local `_FakeHttpClientAdapter`.

### Shared fakes / helpers to reuse

| File | Symbol | Purpose |
|---|---|---|
| `test/support/fakes/fake_audio_service.dart` | `FakeAudioService implements FmpAudioService` | broadcast stream controllers + recorded calls; uses `CountWaiters` |
| `test/support/fakes/count_waiters.dart` | `CountWaiters.waitFor(n)` / `notify()` | wait until a call count reaches N (monotonic, never misses a moment) |
| `test/support/fakes/fake_isar.dart` | `FakeIsar extends Fake implements Isar` | constructor placeholder; any DB call throws |
| `test/support/fakes/fake_settings_repository.dart` | `FakeSettingsRepository(settings)` | in-memory `get`/`update` on one `Settings` instance |
| `test/support/fakes/fake_source_auth_context.dart` | `FakeSourceAuthContext` | logged-out auth: `authForPlay` → null, media headers from `SourceHttpPolicy.mediaHeaders` |
| `test/support/fakes/fake_secure_key_value_store.dart` | `MemorySecureKeyValueStore`, `UnavailableSecureKeyValueStore` | credential store; failing variant throws `SecureStorageUnavailable` |
| `test/support/fakes/secure_storage_channel.dart` | `mockSecureStorageChannel({values, failing})` | mocks the `flutter_secure_storage` MethodChannel; auto `addTearDown`. Explicitly avoids `FlutterSecureStorage.setMockInitialValues` (global, not restored) |
| `test/support/audio_controller_harness.dart` | `buildTestAudioController(...)`, `buildTestAudioControllerIn(...)` | turns collaborators into provider overrides for `AudioController` (a `Notifier`) |
| `test/support/audio_settings_notifier.dart` | `audioSettingsNotifierFor(repo)` | ProviderContainer + override + `addTearDown(container.dispose)` |
| `test/support/now_playing.dart` | `testNowPlayingPublisher()` | real `FmpAudioHandler` + un-initialised `WindowsSmtcHandler` (safe on Windows dev boxes) |
| `test/support/isar_test_harness.dart` | `initializeIsarForTests()`, `resolveIsarLibraryPath()` | loads native Isar core from pub cache via `.dart_tool/package_config.json` |
| `test/support/pump_until.dart` | `pumpUntil`, `drainEventQueue` | wait helpers (§4) |
| `test/support/dart_source.dart` | `stripDartComments` | static-rule preprocessing (§3) |

### Time / clocks

- **No `fake_async` / `package:clock`.** Time is injected per class instead:
  - timer factory: `PlaybackRecoveryTimerFactory` typedef (`lib/services/audio/playback_recovery_coordinator.dart:23`), used by `BufferStarvationWatchdog(timerFactory:)`; test fake `_FakeTimer implements PlaybackRecoveryTimer` with `fire()` (`test/services/audio/buffer_starvation_watchdog_test.dart:100`).
  - `DateTime Function()? now` (`lib/services/radio/radio_refresh_service.dart:75`) — one-off.
  - Timeout budgets passed as values: `PlaybackTimeoutBudget` param in `buildTestAudioController`.
- Where a timer lives in an isolate that no fake clock can drive, the rule is a comment at the constant instead of a slow test (commit `175e5d2a`, download receive timeout).

### HTTP stubbing

- Sources take an injected Dio (`YouTubeSource(dio: dio)`, `NeteaseSource(dio: …)`); tests set `dio.httpClientAdapter = _FakeHttpClientAdapter((options, body) => ResponseBody…)`. The adapter is re-declared locally per file (9 files: `test/data/sources/youtube_source_test.dart:1699`, `test/bilibili_source_test.dart`, `test/services/lyrics/qqmusic_source_test.dart`, `test/services/account/*`…). No shared adapter in `test/support`.
- Real loopback servers for streaming/download bytes: `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` (`test/services/download/download_service_progress_and_disposal_test.dart:430`, `test/bilibili_source_test.dart`).
- One Dio `Interceptor`-based stub: `test/data/sources/netease_source_test.dart` (one-off).
- Platform channels: `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(...)` + reset in teardown (5 files).

### Isar in tests

- Real Isar, not mocked, for repositories/migrations. Pattern (60 files use `initializeIsarForTests`):
  ```dart
  setUpAll(initializeIsarForTests);
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('account_repository_test_');
    isar = await Isar.open([AccountSchema], directory: tempDir.path, name: 'account_repository_test');
  });
  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });
  ```
  (`test/data/repositories/account_repository_test.dart:16-31`). Some files use a `_createHarness()` + `addTearDown(harness.dispose)` variant (`data_integrity_repository_test.dart`).
- Native lib: `isar_community_flutter_libs` `windows/libisar.dll` / `linux/libisar.so` / `macos/libisar.dylib`; requires `flutter pub get` first. `initializeIsarCore` is idempotent so per-file `setUpAll` is safe.
- Tests that don't need a DB pass `FakeIsar()` to repository constructors.

### Riverpod / widget test setup

- `ProviderContainer(overrides: [...])` + `addTearDown(container.dispose)` (38 occurrences); widget tests wrap in `ProviderScope(overrides: …)` (29 files); `overrideWith`/`overrideWithValue` ~189 uses.
- i18n in widget tests: `setUp(() => LocaleSettings.setLocale(AppLocale.en))` (or `setLocaleSync`) + `TranslationProvider(child: …)` (35 files, e.g. `test/ui/layouts/collapsed_nav_rail_test.dart:15,26`).
- Cleanup via `addTearDown(...)` is pervasive (~380 calls).

## 3. Static-rule test pattern

Placement/naming enforced by `test/support/static_rule_placement_static_rule_test.dart`: any `*_test.dart` that does `File(`/`Directory(` on a `lib/…` path must live in `test/support/` (cross-layer) or `test/<layer>/static_rules/` (single-layer) **and** end in `_static_rule_test.dart`. No exception list "and none intended". `lib/i18n/**.json` reads are exempt (product data).

### Anatomy (repeated across files)

1. **Top dartdoc = the rationale** (why the rule exists, often issue/commit refs), then `library;`.
2. **`stripDartComments(source)`** from `test/support/dart_source.dart` before matching — used by 21 of 25 rule files. It walks string literals (`r''`, `'''`, escapes) so `'https://…'` is not treated as a comment.
3. **Exception/owner lists as `const Map<String, String>` path/name → reason**: `_lowerLayerExceptions` (layer_boundary), `_exceptions` (live_source_tag), `_hosts` (outbound_hosts), `_anchoredProviders` (riverpod3), `_deliberatelyExcludedSettingsFields` (settings_backup_coverage), `_narrowOnly` (watch_scope); or a typed table `_table = <String, _Ownership>{…why, pattern, owners, scope}` (call_site_ownership). Pure-path allowlists (`_allowedFiles` in isar_boundary / wait_convention) carry reasons in the dartdoc above.
4. **Stale-exception check**: "every allowlist entry still exists / every named exception is still real / no exclusion names a field that no longer exists" (7 files) — an exception that no longer applies turns red.
5. **Scan sanity**: `expect(scanned, greaterThan(N))` so a wrong path can't make offenders silently empty (16 files, e.g. `greaterThan(200)` in wait_convention, `greaterThan(60)` in layer_boundary).
6. **Set comparison, not substring presence**: scanned set must *equal* the named list — one more or one fewer is red (commit `12c487ab` "compare sets instead of source substrings"; call_site_ownership, outbound_hosts, periodic_timer, watch_scope, source_branch_points uses equality budgets per file; audio_provider_size is a two-sided ratchet with `_slack`).
7. **Two-way mutation tests inside the file** (a separate `group('the … detector(s)')`): one test feeds a synthesised violation string and asserts it is caught (`'a synthesised violation is caught'`, `'guard detects a spaced call and a tear-off'`), one feeds a harmless variant — comment, reformatting, line break, look-alike name — and asserts it is not (`'a violation written in a comment does not count'`, `'renames, line breaks, getters and comments are read correctly'`). Detectors are top-level public functions (`fixedPumpOffenders`, `readsLibSource`, `upwardImportOffenders`, `filesMatching`, `silentErrorBranches`) so they can be fed strings. Commit `8e9a6837` closed bypasses found this way.
8. Failure `reason:` says what to do instead (e.g. "Use pumpUntil for a condition, or drainEventQueue…").
9. Paths normalised with `.replaceAll('\\', '/')` for Windows.

Behavioural tests are preferred when possible: `20a96dc9` ("check UI rules by pumping widgets instead of reading source"), `175e5d2a` (audio/download rules → behaviour tests on existing fakes).

### Every `*_static_rule_test.dart` (25)

| File | Rule |
|---|---|
| `test/support/layer_boundary_static_rule_test.dart` | `lib/core`, `lib/data` import nothing from `services/`/`providers/` (1 named exception: `track_extensions.dart`); cross-feature edges are a snapshot `_knownFeatureEdges` — new edge needs an entry + reason comment |
| `test/support/static_rule_placement_static_rule_test.dart` | tests reading `lib/` source must be named/placed as static rules |
| `test/support/wait_convention_static_rule_test.dart` | only `pump_until.dart` (+ its own test + this file) may call `pumpEventQueue` |
| `test/support/live_source_tag_static_rule_test.dart` | real-network tests (default-constructed sources) tagged `live` |
| `test/support/source_http_policy_static_rule_test.dart` | every client talking to a source API goes through `SourceHttpPolicy` (derived from paths, whole `lib/`) |
| `test/support/source_branch_points_static_rule_test.dart` | per-source-id branching outside `lib/data/sources/` has an exact per-file budget (can only shrink) |
| `test/support/outbound_hosts_static_rule_test.dart` | every hard-coded host in `lib/` is listed in `_hosts` with a purpose; DNS targets in `_dnsLookups` |
| `test/support/periodic_timer_static_rule_test.dart` | every `Timer.periodic`/`Stream.periodic` in `lib/` is named in `_timers` |
| `test/support/call_site_ownership_static_rule_test.dart` | ownership table: bilibili live API, `sourceManagerProvider` in UI, source calls in UI, `CustomTitleBar(`, playlist-provider invalidation |
| `test/support/audio_provider_size_static_rule_test.dart` | `audio_provider.dart` code-line ratchet (blank/comment lines excluded, ESLint `max-lines` style), red on growth or on shrink past slack |
| `test/support/android_manifest_static_rule_test.dart` | `android:allowBackup="false"` |
| `test/core/static_rules/core_source_static_rule_test.dart` | `main.dart` registers third-party licences before the scoped `runApp(ProviderScope(` |
| `test/data/static_rules/isar_boundary_static_rule_test.dart` | `isar.` member access only in `lib/data/repositories/` + `database_catalog.dart`, `database_migration.dart` (ADR 0002) |
| `test/data/static_rules/source_ownership_static_rule_test.dart` | concrete source adapters reached only via `SourceManager`; recorded direct imports; lyrics-layer `NeteaseSource` allowed |
| `test/providers/static_rules/riverpod3_static_rule_test.dart` | side-effect providers anchored in `FMPApp.build` (`_anchoredProviders`); no riverpod legacy barrel import; Equatable states list all fields in `props` |
| `test/services/static_rules/audio_backend_shared_rules_static_rule_test.dart` | the three shared backend rule tables exist once and all backends delegate to them (#41) |
| `test/services/static_rules/audio_seam_static_rule_test.dart` | `PlayerState`/`QueueState` share no field; `PlaybackRequestStreamAccess` session-only; only auth context + provider name the wide type |
| `test/services/static_rules/playback_event_routing_static_rule_test.dart` | pattern matching on `PlaybackEndReason` only in `playback_event_router.dart` |
| `test/services/static_rules/lyrics_window_strings_static_rule_test.dart` | every translation key the lyrics sub-window reads is pushed to it |
| `test/services/static_rules/settings_backup_coverage_static_rule_test.dart` | every persisted `Settings` field (read from generated schema) is exported+imported by backup or listed as excluded with reason |
| `test/ui/static_rules/ui_consistency_static_rule_test.dart` | only semantic image widgets reach low-level image APIs (#107); `ListTile.leading` not a raw `Row` |
| `test/ui/static_rules/slider_overlay_static_rule_test.dart` | no raw Material `Slider`/`RangeSlider`; use `ScopedSlider` |
| `test/ui/static_rules/watch_scope_static_rule_test.dart` | wide, hot providers not `ref.watch`ed whole (use `.select`/narrow providers) |
| `test/ui/static_rules/error_presentation_static_rule_test.dart` | async error branch never renders nothing (use `ErrorDisplay(compact: true)`); no raw exception in i18n templates (whole `lib/`); no raw exception to user-facing widgets |
| `test/workflows/dependabot_group_static_rule_test.dart` | every 0.x direct dep excluded from the minor/patch group; `flutter_secure_storage` major-ignore present |

Note: `AGENTS.md` lists only 6 of these under "Gated by static-rule tests".

## 4. Wait conventions

- `pumpUntil(condition, reason:, timeout: 5s)` — condition must be **false on entry**; first 50 rounds of `pumpEventQueue()` (no wall-clock), then 10 ms sleeps; `reason` required, it is the timeout message. `drainEventQueue(reason:, times: 20)` — only for asserting something did **not** happen; preferred alternative is to `pumpUntil` a later milestone first. Rationale: issues #43 (positive asserts too early under load) and #55 (absence asserts pass too early). Source: `test/support/pump_until.dart`.
- Usage: `pumpUntil` 226 calls / 35 files; `drainEventQueue` 78 calls / 21 files. Typical:
  ```dart
  await pumpUntil(() => lyricsService.enabledSourceCalls.length == 1,
      reason: 'the auto-match call should record its enabled source list');
  await drainEventQueue(reason: 'the superseded seek must not reach the backend');
  expect(audioService.seekCalls, isEmpty);
  ```
  (`test/services/audio/audio_controller_handoff_and_errors_test.dart:232,597`).
- Call-count waits: `CountWaiters.waitFor(n)` on fakes (7 `waitFor(` uses).
- Guard only covers `pumpEventQueue`; widget tests' `tester.pump()` / `pumpAndSettle` (85 uses) are not gated.
- History: `2e03babe`, `800f4ec8` (convert to conditions), `d9244526` (add guard).

## 5. Lints

`analysis_options.yaml`: `include: package:flutter_lints/flutter.yaml`; excludes `**/*.g.dart`, `build/**`, platform dirs. Extra rules, each with a Traditional-Chinese rationale comment:
- `prefer_const_constructors`, `prefer_const_declarations`
- `always_use_package_imports` — `lib/` uses `package:fmp/…` only (layer_boundary regex relies on it)
- `deprecated_member_use_from_same_package` — `@Deprecated` Settings fields readable only by migration
- `comment_references` — dartdoc `[Identifier]` must resolve ("rules' rationale lives in dartdoc")
- `prefer_single_quotes` is **not** enabled (layer_boundary regex accepts both quotes because of it).
No custom lint package.

`// ignore:` in practice (lib has 3): each preceded by a comment explaining why —
`lib/data/database/database_migration.dart:1-4` (`ignore_for_file: deprecated_member_use_from_same_package`, "sole legal reader"),
`lib/services/radio/radio_refresh_service.dart:66` (`prefer_final_fields`), `lib/data/sources/youtube_source.dart:298` (`deprecated_member_use`, no reason — one-off).
In `test/`: `// ignore: avoid_print` (23, benchmarks/probes), `deprecated_member_use_from_same_package` (manual `real_db_probe.dart`), `overridden_fields` with preceding reason (`test/data/sources/youtube_source_test.dart:1733`).

## 6. Formatting / CI gates

`.github/workflows/ci.yml` job `validate` (ubuntu, Flutter `3.47.1`, `fetch-depth: 0`), in this order:
1. `flutter pub get`
2. `dart format --output=none --set-exit-if-changed lib test tool` — runs **before** codegen (generated slang code not guaranteed format-clean; `*.g.dart` absent on fresh checkout)
3. `dart run build_runner build`
4. `dart run slang`
5. `flutter analyze`
6. `flutter test --coverage --exclude-tags live` (lcov uploaded as artifact)
Then `build-android` (arm64 APK) and `build-windows` smoke builds, `needs: validate`. No path filter (prose commits must run validate). Concurrency groups PRs by ref and main pushes by SHA (comment: 20 main commits lost CI results). Actions pinned by commit SHA with `# vX` comment. SDK constraint `>=3.9.0` → tall-style formatter.
Release (`release.yml`) re-runs analyze + test before building.

## 7. Logging

- Single logger: `AppLogger` in `lib/core/logger.dart` (static). API: `debug(msg, [tag])`, `info`, `warning`, `error(msg, [error, stackTrace, tag])`. Levels `LogLevel {debug, info, warning, error}`; min level debug in `kDebugMode`, else info. 500-entry in-memory `Queue` buffer, broadcast `logStream` (in-app log viewer), optional `LogFileSink` (`lib/core/log_file_sink.dart`, rotation) attached in `main.dart` after binding init with backfill.
- `mixin Logging` gives `logDebug/logInfo/logWarning/logError` with `logTag => runtimeType.toString()` — used by 61 lib files; direct `AppLogger.x(…, 'Tag')` in 26 files with PascalCase string tags (`'Startup'`, `'Backup'`, `'Lyrics'`, `'AccountRefresh'`, `'PlatformError'`).
- No `print(` in lib; `debugPrint` only inside the logger.
- **Redaction** is built in: every message and `error.toString()` passes `AppLogger.redactSensitive` — Authorization, `SAPISIDHASH`, `Bearer`, `Cookie:` headers and key=value/JSON forms of `_sensitiveKeys` (MUSIC_U, SESSDATA, bili_jct, csrf, eparams, SAPISID family, refresh/access_token, apiKey, passwords, token…). File sink writes the same redacted entry. Tests: `test/core/logger/redaction_test.dart`, `log_file_sink_test.dart`. No separate URL-redaction helper found.

## 8. Error handling (cross-cutting)

- `lib/core/errors/user_message.dart`: `userMessageFor(Object)` → translated sentence, never raw exception text; recognises `SourceApiException`, `DioException` (via `SourceApiException.classifyDioError`), `SocketException/HttpException/TlsException`, `TimeoutException`, `FormatException`, `PathAccessException`; everything else → `t.error.unknownError` (no guessing "network", issue #41). `failureMessage(error, stack, what, {tag})` logs + returns the message for `state.error`. `sourceErrorReason(SourceApiException)` exhaustive switch on `SourceErrorKind`.
- Source adapters share `SourceApiException` (`lib/data/sources/source_exception.dart`).
- UI surfaces: `ToastService` (`lib/core/services/toast_service.dart`) — static `show/success/error/warning(context, …)`, **`ToastService.failure(...)` = the only entry to show an exception** (logs original, shows `userMessageFor`); instance `showInfo/showError…` stream for background services via `toastServiceProvider`; `buildSnackBar` is the only SnackBar builder. Inline errors: `ErrorDisplay` (`lib/ui/widgets/feedback/error_display.dart`, `compact: true` + retry).
- Usage: `userMessageFor` 24 lib files, `failureMessage` 10, `ToastService.failure` 6. Gated by `error_presentation_static_rule_test.dart`.
- Global handlers in `lib/main.dart:102-125`: `FlutterError.onError` → `AppLogger.error(…,'FlutterError')`; `PlatformDispatcher.instance.onError` → log `'PlatformError'` + `_showStartupFailure`; `runZonedGuarded` body; pre-`runApp` failures render `StartupFailureApp` in the same zone (issue #37).
- **No crash reporting service** (no sentry/crashlytics in lib or pubspec); logs stay local.

## 9. Comment language

- Rule (AGENTS.md): Traditional Chinese; convert only lines you edit. Heuristic scan of `//`/`///` lines with CJK:
  - `lib/`: ~1740 lines Simplified vs ~2918 Traditional; files: 48 Simplified-only, 141 Traditional-only, 106 mixed.
  - `test/`: 52 vs 1400; 174 Traditional-only files — tests are almost fully Traditional.
  - `tool/`: mixed. Some files are English-only (`test/live/sources_live_test.dart`, `test/performance/*`, `tool/demo/*` headers, CI YAML comments mostly English, `.github/dependabot.yml` English).
- Dartdoc style: `///` explains **why**, cites issues (`issue #41` ×7, `#107` ×5, `#40`, `#106`, `#37`…; 47 refs in lib) and commit hashes in backticks (`` `0dfc33a9` ``); `[Identifier]` references (lint-checked); `**bold**` for the load-bearing sentence; em-dash asides. No TODO/FIXME in lib (0).
- Test names and `reason:` strings are English sentences in behavioural voice (`'the superseded seek must not reach the backend'`).

## 10. Git conventions

- Conventional Commits, English, imperative, lowercase, no period. Last 400 non-merge subjects: fix 99, docs 97, refactor 75, test 55, chore 41, feat 21, ci 6, perf 4, style 1, revert 1; all conform. Max subject length 87 (a few exceed 72).
- Common scopes: audio 65, ui 33, review 24, deps 20, download 16, data 16, sources 15, providers 9, release 8, agents 8, settings 7, skill 5, support 5, core/backup/account/library 5.
- Subjects describe behaviour/outcome ("fix(audio): keep counting retries after a retry reopens the stream"); bodies explain why (see `ecf432bb`, `12c487ab`).
- Branches: `<type>/<kebab-description>` matching commit type (`fix/paused-transport-retry`, `docs/slim-agent-instructions`, `test/stale-source-error-race`, `chore/bump-version-1-11-0`, `refactor/source-driven-ui`); dependabot `dependabot/pub/...`.
- PR flow: one PR per branch into `main`, merged with **merge commits** ("Merge pull request #162 from 1morr/docs/slim-agent-instructions"). Older history has "Merge branch 'main' of …" noise.
- Version bump is its own PR (`chore: bump the app version to 1.11.0`); tag pushed on main triggers release.
- **No CHANGELOG file.** Release notes are generated in `release.yml:488-491` from commit prefixes: `^feat` → Features, `^fix` → Fixes, `^perf` → Performance, `^(chore|build)\(deps` → Dependencies; other types only via compare link. Body also feeds the in-app update dialog. So the commit type is user-facing.
- Dependabot: weekly, actions grouped; pub minor/patch grouped except every 0.x direct dep; `flutter_secure_storage` majors ignored.

## 11. Codegen

- Isar: `dart run build_runner build` (`isar_community_generator`), no `build.yaml`.
- i18n: `dart run slang` standalone CLI (config `slang.yaml`: base `zh-CN`, namespaces, `lazy: false`, output `lib/i18n/strings.g.dart`). `slang_build_runner` was removed in `ecf432bb` (version conflict with isar generator); `lazy: false` needed because `LocaleSettings.*Sync` APIs and `main.dart` read `t.notification.channelName` early.
- `*.g.dart` gitignored (`.gitignore:29`); CI regenerates each job. Pitfall (AGENTS.md): stale codegen after pull/branch switch/fresh worktree shows as a "missing getter" that looks like a source bug.
- `settings_backup_coverage_static_rule_test.dart` reads the **generated** Settings schema, so it needs codegen before running.
- Format check runs before codegen and does not cover generated files; analyzer excludes `**/*.g.dart`.

## Caveats / Not Found

- No shared `FakeHttpClientAdapter` in `test/support` — each file declares its own (documented as observed, not a rule).
- No `fake_async` / clock package; time control is ad-hoc injection.
- No crash reporting; no CHANGELOG; no PR template found in `.github/`.
- `.github/dependabot.yml` comment references `lib/services/AGENTS.md`, which does not exist in the tree.
- Simplified/Traditional counts are a character-set heuristic (~30 distinguishing characters), approximate.
