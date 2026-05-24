# Performance Review Summary

審查日期：2026-05-25

本總結整合 7 個子報告與共同語料基線：

- `audio-runtime-review.md`
- `riverpod-rebuild-review.md`
- `database-performance-review.md`
- `download-network-review.md`
- `image-cache-review.md`
- `ui-scalability-review.md`
- `performance-docs-alignment-review.md`
- `instruction-corpus.md`

本輪只產出文檔，未修改產品程式碼。所有描述性文檔 claim 都以程式碼位置重新核對；`docs/history/refactoring-log.md` 只視為歸檔背景。

## Performance Risks Ranked By User Impact

| Rank | Classification | Risk | Concrete trigger | Primary impact | Evidence |
|------|----------------|------|------------------|----------------|----------|
| 1 | Confirmed issue | Windows portable update 解壓整包讀入記憶體並同步寫檔 | 下載大型 `*-windows.zip` 後更新便攜版 | RSS 峰值暴增、UI 卡頓、低記憶體 OOM | `lib/services/update/update_service.dart:449` 到 `:456` |
| 2 | Confirmed issue | 播放歷史多條路徑全表掃描與 Dart 端聚合 | 長期使用後打開 History、搜尋、排序、統計或刪除 track history | History 頁卡頓、heap allocation/GC 增加 | `lib/data/repositories/play_history_repository.dart:29`, `:36`, `:197`, `:220`, `:302` |
| 3 | Confirmed issue | 搜尋切 source / sort 清空結果造成全頁 loading 閃爍 | 多音源搜尋後切 chip 或排序，且網路慢 | 使用者失去閱讀位置，列表重建與 UX flicker | `lib/providers/search_provider.dart:516` 到 `:540`; `lib/ui/pages/search/search_page.dart:436` |
| 4 | Confirmed / suspected | 搜尋與歌單多選 watch 範圍過大 | 長結果或 500+ 首歌單中連續選取 | 整頁、SliverAppBar、可見 rows 跟著每次選取 rebuild | `lib/ui/pages/search/search_page.dart:76`, `:491`, `:559`; `lib/ui/pages/library/playlist_detail_page.dart:164`, `:650` |
| 5 | Confirmed / suspected | 本地與 target-only 圖片缺少 decode memory 上限 | 已下載頁、歌單詳情、播放詳情載入大量本地/高解析封面 | external image memory、image cache 驅逐、滾動 jank | `lib/core/services/image_loading_service.dart:65` 到 `:68`, `:413` 到 `:427` |
| 6 | Suspected issue | Download manager 全量 watch tasks，row 再查 Track | 大量 pending/completed/failed tasks，滾動下載管理頁 | 全量 list rebuild + visible rows N+1 查詢 | `lib/data/repositories/download_repository.dart:316`; `lib/ui/pages/settings/download_manager_page.dart:17`, `:326` |
| 7 | Confirmed issue | 下載 pause/failure 沒可靠保存最新 progress ratio / total bytes | 大檔下載到中途後暫停或網路失敗 | 續傳 bytes 存在但 UI 顯示 0% 或舊進度 | `lib/services/download/download_service.dart:805` 到 `:812`, `:1048` 到 `:1056` |
| 8 | Suspected / needs profiling | `AudioController` raw position tick 與歌詞彈窗 IPC 過頻 | 長時間播放並開 Windows 歌詞彈窗 / radio UI | CPU、platform channel、rebuild callback 壓力 | `lib/services/audio/audio_provider.dart:2725`; `lib/ui/widgets/track_detail_panel.dart:144` 到 `:169`; `lib/services/lyrics/lyrics_window_service.dart:323` |
| 9 | Suspected issue | media download 缺 receive/idle timeout 與 transient retry | CDN 已連線但停止送 chunk，或 5xx / SocketException | 下載 slot 長時間被佔用，使用者需手動 retry | `lib/services/download/download_service.dart:1533`, `:1562`, `:1607` |
| 10 | Needs profiling | 大歌單 full-list 操作一次載入/寫入大量資料 | 2k-10k 首歌單點下載整個歌單、全部加入佇列 | UI isolate 與 Isar transaction 峰值壓力 | `lib/providers/playlist_provider.dart:350`; `lib/services/download/download_service.dart:515`, `:448` |

## Memory Leak Or Resource Leak Candidates

- Suspected：`AudioController.dispose()` 同步呼叫 async `_audioService.dispose()`，沒有 await / catch backend cleanup errors。關閉 app、hot restart 或 provider dispose 時，native player cleanup failure 可能成為 unhandled async error。Evidence: `lib/services/audio/audio_provider.dart:521` 到 `:543`; `lib/services/audio/media_kit_audio_service.dart:443` 到 `:467`; `lib/services/audio/just_audio_service.dart:284` 到 `:306`。
- Needs profiling：desktop `MediaKitAudioService` aggressive buffer profile 正確記錄且有測試，但 YouTube Mix、VPN/CDN 抖動與快速切歌需要 30-60 分鐘 RSS / external memory profile。Evidence: `lib/services/audio/media_kit_audio_service.dart:19` 到 `:26`, `:248` 到 `:285`。
- Suspected：`MediaKitAudioService` backend handoff 缺 request-scoped cancellation token；快速切歌時舊 handoff 可能晚到 backend。Evidence: `lib/services/audio/media_kit_audio_service.dart:630` 到 `:640`, `:698` 到 `:731`; controller supersession 在 `lib/services/audio/audio_provider.dart:1981` 到 `:2104`。
- Confirmed：本地 `FileImage` 沒 decode-size hint，長列表本地封面可能把完整圖片解入 external memory。Evidence: `lib/core/services/image_loading_service.dart:65` 到 `:68`, `:318` 到 `:323`。
- Suspected：update download reset 只忽略 late callback，沒有 `CancelToken` 取消底層 Dio 下載。Evidence: `lib/providers/update_provider.dart:124` 到 `:131`, `:189` 到 `:193`; `lib/services/update/update_service.dart:364`, `:404`, `:434`。

## Expensive Rebuild Hotspots

- Confirmed：`SearchPage` 頂層 watch 整個 `searchProvider` / `searchSelectionProvider`，多選時全頁 rebuild。Evidence: `lib/ui/pages/search/search_page.dart:76` 到 `:83`。
- Confirmed：`PlaylistDetailPage` 頂層 watch `playlistDetailSelectionProvider`，每次選取牽動頁面與 SliverAppBar。Evidence: `lib/ui/pages/library/playlist_detail_page.dart:164`, `:650` 到 `:672`。
- Confirmed：Explore 同時 watch inactive source tracks 與完整 `rankingCacheServiceProvider`。Evidence: `lib/ui/pages/explore/explore_page.dart:59` 到 `:69`, `:128` 到 `:160`。
- Confirmed：Radio UI watch 完整 `audioControllerProvider`，只為音量/裝置卻被 position/progress 牽動。Evidence: `lib/ui/widgets/radio/radio_mini_player.dart:34` 到 `:38`; `lib/ui/pages/radio/radio_player_page.dart:29` 到 `:32`。
- Needs profiling：列表 item 大量 watch `currentTrackProvider`，切歌時 visible/cache rows 會一起 rebuild。Evidence: search, playlist, downloaded, explore, home rows at `lib/ui/pages/search/search_page.dart:996`, `lib/ui/pages/library/playlist_detail_page.dart:1468`, `lib/ui/pages/library/downloaded_category_page.dart:716`, `lib/ui/pages/explore/explore_page.dart:244`。
- Confirmed / needs profiling：`SearchState.mixedOnlineTracks` getter 在 build 熱路徑多次建立 list / sort。Evidence: `lib/providers/search_provider.dart:96` 到 `:142`; `lib/ui/pages/search/search_page.dart:546` 到 `:589`。
- Suspected：`PlaylistDetailPage` 頂層 watch 全域 `fileExistsCacheEpochProvider`，下載/cache epoch 變更可能讓整頁 rebuild；row 級 per-path watch 已存在。Evidence: `lib/ui/pages/library/playlist_detail_page.dart:164` 到 `:167`, `:1103` 到 `:1109`。
- Needs profiling：Queue drag hover 用整頁 `setState`，500+ queue 拖拽可能卡。Evidence: `lib/ui/pages/queue/queue_page.dart:184`, `:406`, `:610`, `:630`。

## Database Query Hotspots

- Confirmed：Play history stats/search/sort/delete all for track 有多條 `findAll()` 全表掃描路徑。Measure first with 1k / 10k / 50k rows. Evidence: `lib/data/repositories/play_history_repository.dart:29`, `:36`, `:197`, `:220`, `:302`。
- Suspected：Download manager `watchAllTasks()` 全量 stream + row-level `trackByIdProvider`。Measure with 500 / 2k / 10k tasks. Evidence: `lib/data/repositories/download_repository.dart:316`; `lib/providers/download/download_providers.dart:116`, `:223`; `lib/ui/pages/settings/download_manager_page.dart:326`。
- Confirmed：bulk task status updates 在 transaction 內逐筆 `put()`，可改 `putAll()`。Evidence: `lib/data/repositories/download_repository.dart:246` 到 `:285`; existing better pattern at `:214` 到 `:225`。
- Suspected：刪除下載分類/檔案後 cleanup 載入所有 downloaded tracks，再逐筆 save changed tracks。Evidence: `lib/services/download/download_path_maintenance_service.dart:114` 到 `:162`; `lib/data/repositories/track_repository.dart:199`。
- Needs profiling：playlist remote refresh/delete 使用大 transaction；正確性強但需量測 write lock 成本。Evidence: `lib/services/library/playlist_mutation_service.dart:426`, `:554`, `:199` 到 `:256`。
- Needs profiling：startup migration/default repair 目前可控，但未來大 collection repair 會影響 cold start；DB `maxSizeMiB` 是 64。Evidence: `lib/providers/database_provider.dart:207`, `:213`, `:226`, `:320`。

## Network / Download Resource Risks

- Confirmed：Windows portable update 解壓在 UI isolate 同步整包讀取與寫檔。建議 isolate + chunked/streaming extraction。
- Confirmed：pause/failure DB progress 不完整，與文檔對「paused/failed 時落 DB」的說法不完全一致。
- Suspected：media download isolate 只設 connection timeout，缺 receive/idle timeout 和有限 transient retry。Stalled response 可能卡住並發 slot。
- Suspected：download metadata cover/avatar 直接用原 URL，未套用 thumbnail optimization；大量下載可能多抓高解析圖。Evidence: `lib/services/download/download_service.dart:1287`, `:1303`; `lib/core/utils/thumbnail_url_utils.dart:1`。
- Suspected：update download reset/dispose 沒取消底層 Dio request。
- Needs profiling：active download progress path 已有 5% threshold、1s flush、task-scoped provider，靜態看過頻風險低；仍需在 5 concurrent downloads + download manager open 時量測。

## Quick Optimizations

這些項目 evidence 足夠，修正範圍小，通常可先做 targeted tests：

- 將 update ZIP 解壓移出 UI isolate，避免 `readAsBytesSync()` / `writeAsBytesSync()`。
- `DownloadService._saveResumeProgress()` 使用最新 pending progress 或 temp file length + total bytes。
- Download bulk status update 改成修改 objects 後 `putAll()`。
- Radio UI 改用 `audioControllerProvider.select(...)` 或既有音量/裝置 selector，避免完整 `PlayerState` watch。
- Explore tab content 使用 source-specific selectors，不 watch 完整 ranking state 與 inactive source tracks。
- Search / PlaylistDetail selection 改 per-row selected boolean selector，頂層只 watch `isSelectionMode` / selected count。
- `SearchPage` 同一次 build 先快取 `state.mixedOnlineTracks`；後續再把 mixed/sorted 結果 memoize 或搬到 notifier state。
- `_PageTile` 與 PlaylistDetail multi-P group wrapper 加穩定 keys；Download manager rows/headers/task tiles 加 keys。
- `ImageLoadingService` 將 `targetDisplaySize` 也作為 `memCacheWidth` / `memCacheHeight` fallback；本地圖片也提供 decode-size hint。
- Radio cover preload 使用相同 cache manager / candidate URL / headers，或提供統一 preload helper。

## Changes That Require Profiling Before Implementation

- Desktop media_kit buffer profile：不要只因 buffer 值大就調低；先 A/B 比較 stall 次數、RSS、external memory、first-play latency。
- `currentTrackProvider` row 級 selector：先量測切歌 dirty widgets。如果 visible rows 可接受，無需增加 provider 複雜度。
- Queue drag architecture：先量測 100 / 500 / 1000 items 拖拽 frame time，再決定是否下放 hover state 或引入 reorderable list strategy。
- Playlist large bulk operations：先量測 1k / 5k / 10k tracks 的 full enqueue / download playlist transaction，再決定 chunk size。
- Playlist remote refresh/delete transaction splitting：需先量測 transaction duration；改動涉及一致性邊界。
- FileExistsCache epoch removal：現有測試保護該 pattern；先重現 stale cache 場景，再用 narrower listener/per-path watch 取代。
- Downloaded `FutureProvider` refresh flicker：Riverpod 預期保留舊資料，但應用 widget/runtime test 固化後再改 UI。
- Lyrics search/provider granularity：先用 ProviderObserver/widget test 確認非歌詞設定會不會重建並重置搜尋。

## Suggested Measurement Methods

| Major issue | Measurement |
|-------------|-------------|
| Windows update ZIP memory | Profile Windows portable update；在下載前、解壓中、解壓後取 VM `_currentRSS`、`_maxRSS`、heap/externalUsage。 |
| Play history full scans | Seed 1k / 10k / 50k rows；量測 History page load、search、playCount sort、stats、delete all for track wall time / allocations / GC。 |
| Search rebuild/flicker | `flutter run --profile` + `profileWidgetBuilds`；錄製 search -> switch chip -> switch sort；對比 spinner 時長與 dirty widgets。 |
| Selection rebuild hotspots | 500+ search/playlist rows，連選 20 tracks；開 `trackRebuildDirtyWidgets` 與 timeline P90/P99。 |
| Image decode memory | 已下載頁 100+ 本地封面快速滾動；記錄 `externalUsage`、image cache bytes、`invertOversizedImages` 與 frame jank。 |
| Download manager | Seed 500 / 2k / 10k tasks；量測 first render、scroll 1k rows、pause all/resume all DB time 與 query count。 |
| Download stalled slot | 本地 HTTP server 送 headers 後停止 chunks；確認 active slot 是否卡住與 timeout 行為。 |
| Audio position/lyrics IPC | Windows profile，開/關歌詞彈窗播放 5-10 分鐘；記錄 platform channel call count、UI thread frame time、Dart CPU。 |
| MediaKit buffer | Windows YouTube Mix 30-60 分鐘；記錄 RSS/externalUsage 每次切歌前後，並 A/B buffer profile。 |
| Queue drag | 100 / 500 / 1000 queue items；拖拽跨 row，量測 dirty widgets、frame P90/P99、heap。 |

## Performance-Related Documentation Inaccuracies

- Android `JustAudioService` load control buffer policy 缺少核心指令文檔；desktop media_kit buffer 文檔準確。Evidence: `lib/services/audio/just_audio_service.dart:138` 到 `:147`。
- 下載 progress 文檔說 paused/failed 時落 DB，但實作未可靠保存最新 progress ratio / total bytes。
- `.serena/memories/download_system.md` 與 `instruction-corpus.md` 說 `FileExistsCache` 只快取存在路徑；實作也有 5000 條 missing negative cache。Evidence: `lib/providers/download/file_exists_cache.dart:21` 到 `:43`, `:165` 到 `:173`。
- `lib/providers/AGENTS.md` 把 history 列為 `watchAll() + StateNotifier` 範例；實作是 `watchLazy()` + `StreamProvider` snapshot。Evidence: `lib/providers/play_history_provider.dart:8` 到 `:17`; `lib/data/repositories/play_history_repository.dart:135`。
- 圖片規範覆蓋 visible widget，但未覆蓋 preload；目前 radio cover preload 繞過統一 cache policy。
- Bilibili live cover 規範只明確提 preloading；radio cover display paths 未傳 live headers，文檔邊界不清。
- `.serena/memories/download_system.md` 寫 Windows 下載在 isolate；實作全平台 `Isolate.spawn()`，核心 `lib/services/AGENTS.md` 較準確。
- Lyrics provider selector 粒度只明確保護 `audioControllerProvider`，未覆蓋 `lyricsSearchProvider` watch 整個 `AudioSettingsState`。

## Verification Scope

本輪文檔審查沒有執行 Flutter runtime tests。各子報告已以靜態程式碼 evidence 標註風險；後續實作前應根據上表補 profile 或 targeted widget/repository tests。
