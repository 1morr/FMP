# 審查表 S / W / I 列的處理結果

對照 `spec-audit.md`：每一列是審查表裡一個 S / W / I 列（line 是審查時的原檔行號）。
action：**fixed**（S 已修正）、**reworded**（W 改寫成描述現況）、**kept (1 example)**
（審查表標為只有 1 例、建議保留）、**deleted**（I 已刪除）。G / P 列不在範圍內。

合計：fixed 4（S 4）、reworded 68（W 64 + G+W 3 + I+W 1）、kept (1 example) 3、
deleted 15（I 14 + P+I 1），與審查表的 S 4 / W 71 / I 15 對得上。兼類列：`cross-layer` 12-14
（I + W，依審查表計入 W）的 I 半句刪、W 半句改寫；`code-reuse` 3-9（P + I）的 I 半句刪、P 半句留。

| spec file:line | class | action | new wording |
|---|---|---|---|
| data/persistence.md:15 | W | reworded | "Model-to-model conversions are methods on the model: `PlayHistory.fromTrack`, `PlayHistory.toTrack()`, `LiveRoom.toTrack()`. Code that builds a `Track` from outside data … assembles it in place (`BackupService`, `download_scanner.dart`)." |
| data/persistence.md:53 | W(1例) | kept (1 example) | — |
| data/persistence.md:66-70 | S | fixed | "Eight repositories have a provider in `repository_providers.dart` …; `downloadRepositoryProvider` / `radioRepositoryProvider` live with their feature. `QueueRepository`, `PlaylistMutationRepository`, `BackupRepository`, `DataIntegrityRepository` have no provider: providers, services and `developer_options_page.dart` construct them inline. Repositories that do have a provider are also constructed inline in places (`TrackRepository` / `SettingsRepository` in `audio_controller_provider.dart`, `stream_resolution_provider.dart`, `source_auth_context_provider.dart`, `download_providers.dart`, `BilibiliFavoritesService`, `developer_options_page.dart` and `main.dart`; `AccountRepository` inside the account services)."（check 階段補上後三處） |
| data/persistence.md:80-82 | W | reworded | "Common method names: … Other names exist (`BackupRepository.allTracks`, `DownloadRepository.saveTask`, `PlayHistoryRepository.addHistory`, `clear…`)." |
| data/persistence.md:87-88 | W | reworded | "A public one that is also called on its own has a wrapper (`addTracks => …addTracksInTxn`); ones called only from inside another txn (a repository or the migration) have none (`mergeDuplicateTrackMembershipsInTxn`, `remapPlaylistTrackReferencesInTxn`, `relinkLyricsMatchToCidKeyInTxn`)." |
| data/persistence.md:91 | W | reworded | "`updatedAt` is set by whoever builds or edits the model before `put` — repositories, and services too (`StreamResolutionService`, `ImportService`, `BackupService`)." |
| data/sources.md:54-56 | W | reworded | "In `BilibiliSource`, `NeteaseSource`, `remote_playlist_id_parser.dart` and the download pipeline, URLs from users or redirects go through `SourceUrlPolicy` … `YouTubeSource` does not use it yet …; new URL handling follows the `SourceUrlPolicy` path instead." |
| data/sources.md:56-57 | W | reworded | 併入上一條："`YouTubeSource` … still recognises its URLs by substring (`url.contains('youtube.com')`)"（刪掉 "Never detect a platform by substring"） |
| data/sources.md:98-99 | W | reworded | "When the source reports a URL expiry, return it in `AudioStreamResult.expiry` rather than a hard-coded TTL (`b1fa0fc5`). `YouTubeSource` gets none and uses the fixed `AppConstants.youtubeAudioUrlExpiryHours`." |
| data/sources.md:129-130 | W | reworded | "Error assertions come in two styles: by kind, which is what callers read — … — and by `numericCode` or `message` (`bilibili_live_client_test.dart`, `netease_source_test.dart`)." |
| services/audio.md:10 | W | reworded | "The rest sit in `lib/services/audio/`, mostly next to their class: `nowPlayingPublisherProvider`, `fmpAudioHandlerProvider` and `windowsSmtcHandlerProvider` in `now_playing_publisher.dart`; `playbackSideEffectsProvider` and `lyricsAutoMatchCoordinatorProvider` in `playback_side_effects.dart`; `queueStateProvider`; `audioRuntimePlatformProvider`." |
| services/audio.md:71-72 | I | deleted | — |
| services/audio.md:83 | W | reworded | "Short `PlaybackTimeoutBudget` values, and an injected `timerFactory:` where the class takes one (`PlaybackRecoveryCoordinator`, `BufferStarvationWatchdog`). Other timers are not injectable, so some tests wait in real time (`queue_manager_test.dart` 11 s; `audio_controller_handoff_and_errors_test.dart`, `audio_controller_output_device_failure_test.dart` 1–2 s)." |
| services/download-and-auth.md:66-70 | W | reworded | "It is still used in a number of tests (`account_credentials_redaction_test.dart`, the NetEase / YouTube account service tests, `backup_service_test.dart`, `lyrics_source_settings_page_test.dart`); no file mixes the two, keep it that way." |
| services/index.md:31 | W | reworded | "New async code in a disposable service or notifier checks disposed / superseded / `ref.mounted` after an `await` that is followed by a state write. Existing code is uneven (the audio and download paths check; `ImportService` and many settings notifiers do not), so do not take an unchecked file as the pattern." |
| services/index.md:32 (provider owns dispose) | W | reworded | "the provider of a new service calls its `dispose` (see `service-conventions.md` § Disposal for the existing exceptions)" |
| services/index.md:32 (unawaited + catchError) | W | reworded | "a fire-and-forget future that can fail logs its error (see `service-conventions.md` § Async guards)" |
| services/service-conventions.md:11 | W | reworded | "Most constructors take named `required` params …; some older ones are positional (`BackupService(Isar isar, …)`, `DownloadPathManager(this._settingsRepo)`, `DownloadPathSyncService`)." |
| services/service-conventions.md:21-22 | G + W | reworded | "wrap it in a repository, usually in the initialiser list (`_accounts = AccountRepository(isar)`); `BilibiliFavoritesService` keeps `_isar` and builds a `TrackRepository` per call. They never call `isar.`"（閘門半句不動） |
| services/service-conventions.md:27-29 | W | reworded | "Most `dispose()` methods are idempotent: a disposed flag and an early return (…). `ImportService`, `RadioRefreshService` and `PlaylistImportService` have no flag." |
| services/service-conventions.md:34-35 | W | reworded | "The provider usually owns the call: `ref.onDispose(service.dispose)`. … Exceptions: `audioServiceProvider` and `queueManagerProvider` are disposed by `AudioController.dispose`; `playlistImportServiceProvider` registers nothing (an open gap, not a pattern)." |
| services/service-conventions.md:46-48 | W | reworded | "One-shot outcomes of a plain service are event classes …, and the service does not toast. `Notifier` services such as `AudioController` toast directly through `toastServiceProvider`." |
| services/service-conventions.md:51-54 | W(1例) | kept (1 example) | — |
| services/service-conventions.md:60-61 | W | reworded | "A disposable object with a disposed flag checks it after an `await` before touching state (`if (_isDisposed) return;`, as in `DownloadService`). `RadioRefreshService` drops stale work by generation instead; `ImportService` has no guard." |
| services/service-conventions.md:74-76 | W | reworded | "Fire-and-forget is usually written as `unawaited(...)`, though some calls drop the future bare (`_handleStreamEnd();` in `radio_controller.dart`). Only a few attach `.catchError` with a log (`AudioController.dispose`); most do not. The `unawaited_futures` lint is not on, so none of this is checked." |
| services/service-conventions.md:80-82 | W | reworded | "Work that must be cancellable is usually a `Timer` (`5f3bec68` …). Some delayed callbacks are an uncancellable `Future.delayed` guarded by a generation or request id instead (`RefreshManagerNotifier`, the skip-to-next in `AudioController`)." |
| services/service-conventions.md:82 | W | reworded | "Only `PlaybackRequestSession` and `PlaybackRecoveryCoordinator` take an injectable `delay:`; elsewhere the delay is hard-coded (`ImportService`, `AutoRefreshService`, `DownloadService`)." |
| services/service-conventions.md:85-86 | W | reworded | "A self-rescheduling `Future.delayed` loop hides from that rule; the one that exists is the bounded reconnect loop in `RadioController._handleStreamEnd`." |
| services/service-conventions.md:102 | W | reworded | "Branch on type and `SourceErrorKind`. Known places that still match message text: the not-owned delete check in `netease_playlist_service.dart` and `YouTubeSource._isRetryableTrendingError`." |
| services/service-conventions.md:114 | I | deleted | — |
| services/service-conventions.md:119-121 | W | reworded | "A test-specific variation is usually a file-local `_FakeX` / `_RecordingX` (…); a shared fake carries a switch only occasionally (`FakeAudioService.playUrlSettlesReady`)." |
| services/service-conventions.md:122-123 | W | reworded | "There is no fake clock package. Time is injected where the class allows it (…); most timers are not injectable, and those tests wait in real time (see `../testing/test-conventions.md` § Time)." |
| services/service-conventions.md:126 | W | reworded | "A regression test usually opens with a `///` naming the issue; a few also quote the observed log." |
| shared/code-style.md:8-10 | W | reworded | "mostly one public concept per file, named after it … Some older files are named after their provider rather than the class they hold (`audio_provider.dart` → `AudioController`, `source_provider.dart` → `SourceManager`), and a file may carry the value types of its main class (`backup_repository.dart`)." |
| shared/code-style.md:11-12 | W | reworded | "Test-only hooks on production code are `@visibleForTesting`, usually with a `…ForTesting` or `debug…` name; a few keep a plain name (`NeteasePlaylistService.normalizeTrackIds`)." |
| shared/code-style.md:18 | W | reworded | "Log messages and identifiers are English, as are most exception messages and test names. Exceptions: the playlist import sources throw translated messages on purpose, `ImportService` throws `ImportException` with translated text, and some tests have Chinese names (`download_filenames_test.dart`)." |
| shared/code-style.md:29-31 | S | fixed | "The last three carry their reason as a comment; the two `prefer_const_*` rules have none." |
| shared/code-style.md:32-33 | W | reworded | "In `lib/`, an `// ignore:` … gets a comment on the line above saying why (…, `5259731c`); a few in `test/` are still bare (`youtube_source_test.dart`, `test/manual/real_db_probe.dart`)." |
| shared/code-style.md:43 | W | reworded | "… subject ≤ 72 (a handful of past subjects run longer)." |
| shared/errors-and-logging.md:10-11 | W | reworded | "— the pattern for `state.error` in notifiers and services. Older code still stores `e.toString()` there (`AudioController`, `RankingCacheService`)." |
| shared/errors-and-logging.md:12-14 | W | reworded | "In widgets, an exception reaches the user through `ToastService.failure(…)`, an `ErrorDisplay(message: userMessageFor(e))`, or a template fed `userMessageFor(e)` (`t.library.downloadedPage.deleteFailed(error: userMessageFor(e))`)." |
| shared/errors-and-logging.md:15-19 (state.error) | W | reworded | "The same holds for `state.error` by convention only, with the exceptions above."（template / toast / ErrorDisplay 的閘門半句保留） |
| shared/errors-and-logging.md:21-24 | W | reworded | "Lower layers mostly throw typed exceptions … Exceptions: the playlist import sources throw `Exception` with a translated message, `ImportService` throws `ImportException` with translated text, and `DownloadService` maps a non-JSON isolate failure to a plain `Exception('Download failed: …')`." |
| shared/errors-and-logging.md:42-44 | W | reworded | "(many older controller lines still log titles, and the prefetch-failure line in `StreamResolutionService` inlines `sourceType:sourceId`)" |
| shared/index.md:14 | I | deleted | — |
| shared/index.md:20 | G + W | reworded | "New user-visible text and new `state.error` values are not built from `e.toString()` (existing `state.error` offenders are listed in `errors-and-logging.md`); …" |
| testing/index.md:16 | I | deleted | — |
| testing/index.md:23 | I | deleted | — |
| testing/index.md:24 | W | reworded | "New waits use `pumpUntil` … and `drainEventQueue` …, not a fixed pump count. Only a direct `pumpEventQueue` is gated; fixed runs of `Future.delayed(Duration.zero)` still appear in provider tests (`home_ranking_settings_provider_test.dart`, `import_playlist_provider_cancellation_test.dart`)." |
| testing/static-rules.md:29-32 | W | reworded | "`_knownFeatureEdges` in `layer_boundary_static_rule_test.dart` is a deliberate exception: a snapshot `Set` in which most edges carry no reason (its dartdoc explains why); a newly added edge gets a reason beside it." |
| testing/static-rules.md:40-45 | W | reworded | 刪掉 "in their own group"："**Two-way mutation tests inside the file**: feed a …" |
| testing/static-rules.md:46 | W | reworded | 前言改成 older rules such as `isar_boundary_static_rule_test.dart` "predate points 1, 6 and 8"；第 8 點原句保留 |
| testing/test-conventions.md:5-6 | W | reworded | "`test/` mostly mirrors `lib/` … `test/providers/` is largely flat (only `download/` and `static_rules/` are subdirectories), and two files sit at the root (`test/bilibili_source_test.dart`, `test/app_content_wrapper_test.dart`)." |
| testing/test-conventions.md:17-18 | W | reworded | "… Some older tests have Chinese names (`test/core/constants/download_filenames_test.dart`)." |
| testing/test-conventions.md:33-34 | W | reworded | "Shared fakes cover the default case; a test-specific variation is usually a file-local `_Fake…` (…). A few shared fakes carry a switch (`FakeAudioService.playUrlSettlesReady`)." |
| testing/test-conventions.md:44-47 | W | reworded | "Some production classes take the time source: … Most timers are not injectable, so their tests wait in real time (`QueueManager`'s position saver makes `queue_manager_test.dart` wait 11 s). A new timer in production code comes with its injection point." |
| testing/test-conventions.md:66-67 | W | reworded | "`ProviderContainer(overrides: …)` + `addTearDown(container.dispose)` (a few use `tearDown`, e.g. `search_pagination_stale_test.dart`). About half of the widget test files wrap in `TranslationProvider` + `ProviderScope` with the locale set to `en`; the rest pump without `TranslationProvider`." |
| ui/i18n-and-routing.md:5 | W | reworded | "User-visible strings are slang keys (a known literal: the `'Info+'` / `'Warning+'` filter labels in `log_viewer_page.dart`)." |
| ui/i18n-and-routing.md:9-10 | I | deleted | — |
| ui/i18n-and-routing.md:24-25 | I | deleted | — |
| ui/index.md:29 | S | fixed | "Not gated — check by hand: `ref.mounted` after awaits, `IconButton` tooltips, `AppRadius` / `AnimationDurations` instead of literals. (Using a `BuildContext` after an await without a `mounted` check is caught by `use_build_context_synchronously`, part of `flutter_lints`.)" |
| ui/riverpod.md:26 | W | reworded | "Files: mostly `lib/providers/<feature>/<name>_provider.dart`; some are named for what they hold (`download_providers.dart`, `audio_player_selectors.dart`, `library_invalidation_coordinator.dart`, `file_exists_cache.dart`)." |
| ui/riverpod.md:26-28 | G + W | reworded | "a new import edge between two features must be recorded there. Give the new entry a reason; most older entries in that snapshot have none." |
| ui/riverpod.md:42-49 | W | reworded | 範例改成具名參數：`XService(repository: repo, sourceManager: ref.watch(sourceManagerProvider))` |
| ui/riverpod.md:51-52 | W | reworded | "A provider that owns something disposable registers `ref.onDispose` (…). Known exceptions: `audioServiceProvider` / `queueManagerProvider` (disposed by `AudioController`) and `playlistImportServiceProvider` (registers nothing — a gap, not a pattern)." |
| ui/riverpod.md:57-58 | W | reworded | "Dependencies come from `ref.watch(...)` in `build()`, not from constructor params; the family id is the usual constructor param. `UpdateNotifier` is an exception that takes test overrides (`service`, `isAndroidOverride`) through its constructor." |
| ui/riverpod.md:66-67 | W | reworded | "`test/providers/notifier_rebuild_test.dart` covers the rebuild behaviour of the layout, theme and playlist-import notifiers only; others have no such test." |
| ui/riverpod.md:68-70 | W | reworded | "After an `await` that is followed by `ref` or `state`, check `if (!ref.mounted) return;` … Many keep-alive notifiers skip the check (`ThemeNotifier`, `TrackDetailNotifier`, `desktop_settings_provider.dart`); do not take them as the pattern." |
| ui/riverpod.md:77-79 | W | reworded | "Errors stored in state are user sentences: …, not `e.toString()` (`5e9d2929`). `AudioController` and `RankingCacheService` still store `e.toString()`." |
| ui/riverpod.md:86-89 | W | reworded | "Equality: most state classes define none (`ThemeState`, `AudioSettingsState`, `LayoutSettingsState`, `TrackDetailState`), so every new instance notifies. A few `extends Equatable` (`SearchState`, `PlaylistListState`, `RefreshManagerState`) and must list **every** field in `props` — gated … Selector outputs are `@immutable` with hand-written `==` / `hashCode` (`QueueControlState`)." |
| ui/riverpod.md:112 | W(1例) | kept (1 example) | — |
| ui/widgets.md:25 | W | reworded | "for an exception `ToastService.failure(context, e, stackTrace:, tag:)`, or a plain toast whose template is fed `userMessageFor(e)` (`downloaded_page.dart`)" |
| ui/widgets.md:30 | W | reworded | "`CappedDraggableSheet`, `SheetDragHandle`. Four older sheets still build a raw `DraggableScrollableSheet` (`account_playlists_sheet.dart`, `account_radio_import_sheet.dart`, `add_to_playlist_dialog.dart`, `remote_playlist_dialog_widgets.dart`)" |
| ui/widgets.md:32 ("no raw size") | S | fixed | "Pages pass a variant or a display `size:`; only those widgets call the `ImageLoadingService` loaders (`loadImage` / `loadAvatar` / `imageProviderCandidates` / `precacheImageCandidates`), `Image.network` / `Image.file`, `CachedNetworkImage`, `NetworkImage` / `FileImage`, or pick an `ImageTargetSizes` tier (#107, gated; `ImageLoadingService.clearNetworkCache()` in settings is fine)"；AGENTS.md § Boundaries 的 Images 同步改寫（見下） |
| ui/widgets.md:46 | W | reworded | "Most call sites use `.when(data:, loading:, error:)`; `maybeWhen` (`download_manager_page.dart`), `whenData` (`add_to_playlist_dialog.dart`) and `hasError` checks (`lyrics_display.dart`) also appear." |
| ui/widgets.md:56-59 | W | reworded | 固定色相清單補上 "the platform brand colours (`kBrandBilibili`, … in `account_management_page.dart`), `Colors.amber` in the lyrics window title bar, and `StartupFailureApp`, which renders before any theme exists." |
| ui/widgets.md:60-61 | W | reworded | "A few literals remain (`BorderRadius.circular(8)` in `color_palette_button.dart`, a `Duration` in `queue_page.dart`)." |
| ui/widgets.md:79 | W | reworded | "The desktop lyrics window's title bar does, with `excludeFromSemantics: true` and a `Semantics` label, in its separate engine." |
| ui/widgets.md:80 | W | reworded | "Aim for 48dp touch targets and no overflow at text scale 2.0. The lyrics window title bar uses 28dp buttons, a few controls use `MaterialTapTargetSize.shrinkWrap`, and only a handful of widget tests check text scale." |
| ui/widgets.md:95-97 | W | reworded | "The usual wrapper is `TranslationProvider(…)` with `LocaleSettings.setLocale(AppLocale.en)` in `setUp`; about half of the widget test files use it, the rest pump without `TranslationProvider`. Assert against `t.xxx`, not literal text — `track_detail_panel_test.dart` still asserts zh-CN literals." |
| guides/index.md:15 | I | deleted | — |
| guides/index.md:19 | I | deleted | 該句刪除；Quality Check 改放 cross-layer:58 改寫後的那一條（見下） |
| guides/index.md:23-27 | I | deleted | 整節 "Reviewing AI findings" 刪除 |
| guides/code-reuse-thinking-guide.md:3-9 | P + I | deleted | I 半句（"Search first" + `rg` 範例）刪除；P 半句保留 |
| guides/code-reuse-thinking-guide.md:32-33 | I | deleted | — |
| guides/cross-layer-thinking-guide.md:12-14 | I + W | reworded | I 半句（"name the type … who converts it"）刪除；W 半句改成 "An error usually becomes a user sentence once, at the edge (`userMessageFor` — …); the import path translates earlier (`ImportService`, the playlist import sources)." |
| guides/cross-layer-thinking-guide.md:57 | I | deleted | 整節 "Before you finish" 刪除 |
| guides/cross-layer-thinking-guide.md:58 | W | reworded | 移到 `guides/index.md` Quality Check："A new error path stays typed until the user-facing edge and becomes a sentence there through `userMessageFor` / `failureMessage`. The existing exceptions (the import path translating early, `e.toString()` in some `state.error`) are listed in `../shared/errors-and-logging.md`; do not extend them." |
| guides/cross-layer-thinking-guide.md:59 | I | deleted | — |
| guides/cross-layer-thinking-guide.md:60 | I | deleted | — |

## AGENTS.md § Boundaries — Images

`test/ui/static_rules/ui_consistency_static_rule_test.dart` 實際檢查的是：掃 `lib/ui/`
底下每個 `.dart`（去掉註解後），找出碰到的低階圖片 API —— `ImageLoadingService.loadImage` /
`loadAvatar` / `imageProviderCandidates` / `precacheImageCandidates`、`Image.network`、
`Image.file`、`CachedNetworkImage(`、`CachedNetworkImageProvider(`、`NetworkImage(`、
`FileImage(`，以及任何 `ImageTargetSizes` 參照 —— 整份「檔案 → API 集合」必須**等於**
`_imageApiOwners`（`lib/ui/widgets/images/` 的 5 個元件）。它不看顯示尺寸：
`TrackThumbnail(size: 48)`、`AvatarImage(size: 48)` 都合法。

改後：

> **Images** — in `lib/ui/`, only the semantic widgets in `lib/ui/widgets/images/`
> load images (the `ImageLoadingService` loaders, `Image.network` / `Image.file`,
> `CachedNetworkImage`, `NetworkImage` / `FileImage`) or name an `ImageTargetSizes`
> tier; pages pass them a variant or a display size (#107) —
> `test/ui/static_rules/ui_consistency_static_rule_test.dart`.

（check 階段修正：初稿寫「`ImageLoadingService`」整個類別，但閘門只管 4 個 loader 方法，
`settings_cache.dart` 呼叫 `ImageLoadingService.clearNetworkCache()` 是合法的；`CachedNetworkImage`
是 widget 不是 image provider，改成逐一點名。）

## Main-session fix after check

- `AGENTS.md` Images sentence and `ui/widgets.md` image row: added `CachedNetworkImageProvider`, which `_imageApiPatterns` in `ui_consistency_static_rule_test.dart` gates separately from `CachedNetworkImage`.
