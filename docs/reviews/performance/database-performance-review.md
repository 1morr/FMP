# Isar / Database Performance Review

審查日期：2026-05-25

範圍：Isar `watchAll` / `watchLazy`、query、repository、migration、play history、download task、playlist detail、大歌單與大量下載 task 的成本。

本報告只審查與記錄，不修改程式碼。未執行 runtime profiling；分類中的 `needs profiling` 表示目前有明確成本路徑，但仍需要實機或 profile mode 數據決定是否值得改。

## 語料分層

### 規範性要求

- `AGENTS.md`、`lib/data/AGENTS.md`、`lib/providers/AGENTS.md`、`lib/ui/AGENTS.md` 是本次 database/provider/UI 邊界的規範來源。
- DB collection 多寫入者建議使用 Isar watch + Riverpod state；DB join / 特殊查詢使用 `StateNotifier` + optimistic update；file system scan 使用 `FutureProvider` + invalidate。
- Isar 必須透過 `openFmpDatabase()` 開啟，runtime DB 在 documents/FMP 子目錄。
- schema/default 變更要同步 migration/default repair 與 database viewer coverage。本次不做 schema 變更。
- playlist/detail/cover/download 聯動刷新應走 `libraryInvalidationCoordinatorProvider`。
- 下載進度優先在記憶體 provider，完成/暫停/失敗時才落 DB，避免 Isar watch 高頻重建。

### 描述性內容，已用程式碼驗證

- `docs/development.md` 描述 Isar collections 與 DB 開啟路徑；程式碼在 `lib/providers/database_provider.dart:27` 註冊 schemas，`lib/providers/database_provider.dart:309` 透過 `openFmpDatabase()` 開啟。
- `.serena/memories/download_system.md` 說下載任務按 `savePath` 去重；程式碼在 `lib/services/download/download_service.dart:448` 批量查 `savePath`，`lib/data/repositories/download_repository.dart:47` 用 `anyOf(savePaths)` 查既有 task。
- `.serena/memories/refactoring_lessons.md` 說下載進度在記憶體中；程式碼在 `lib/services/download/download_service.dart:241` 說明 progress 不寫 DB，`lib/providers/download/download_providers.dart:141` 建立記憶體 progress state。
- `lib/providers/AGENTS.md` 說 history 屬於 watch-driven collection；實作不是 `watchAll + StateNotifier`，而是 `watchLazy()` 驅動 `StreamProvider` snapshot，見 `lib/data/repositories/play_history_repository.dart:135`、`lib/providers/play_history_provider.dart:8`。

## Findings

### DB-PERF-01 - Play history snapshot 與統計仍有多條全表掃描路徑

Classification：Confirmed issue

Evidence：
- `lib/data/repositories/play_history_repository.dart:29` `getPlayCount()` 先 `where().findAll()` 再在 Dart 過濾 `trackKey`。
- `lib/data/repositories/play_history_repository.dart:36` `getMostPlayed()` 載入全部 history 再分組統計。
- `lib/data/repositories/play_history_repository.dart:197` `deleteAllForTrack()` 載入全部 history 再找同 track。
- `lib/data/repositories/play_history_repository.dart:220` `getHistoryStats()` 載入全部 history 再算 today/week/total。
- `lib/data/repositories/play_history_repository.dart:302` `queryHistory()` 在有 filters/search/playCount sort 時 fallback 到全部 records。
- `lib/providers/play_history_provider.dart:13` 首次載入 snapshot，`lib/providers/play_history_provider.dart:15` 每次 `watchLazy()` 事件後重新載入 snapshot。
- `test/data/repositories/play_history_repository_phase4_test.dart:162` 測試確認 history 不再被舊 snapshot cap 限制，資料會持續累積。

Trigger scenario：長期使用後累積數千到數萬筆播放歷史；使用者打開 History page、切換搜尋/音源/日期/播放次數排序、刪除某首歌所有歷史，或首頁/統計 provider 因 history watch 事件重新查詢。

User impact：UI isolate 會載入與排序大量 Dart object，可能造成 History page 進入、搜尋、排序、統計卡頓；播放中新增 history 也會觸發 watched snapshot 重新查詢。

Suggested measurement or fix：
- 先在 profile mode 以 1k / 10k / 50k history 量測：History page 首次載入、搜尋、playCount sort、`getHistoryStats()`、`deleteAllForTrack()` 的 wall time、heap allocation、GC。
- 將 `trackKey` 持久化並加 index，避免每次用 getter 在 Dart 層全掃。
- 對 stats 改成多個 bounded/indexed query，例如 today/week date range 與 total count 分開；避免 `findAll()`。
- 對 History page 改為 paged query 或 server-side filter/sort，只有播放次數排序需要額外 aggregation 時再做受限範圍。
- `watchLazy()` 後可 debounce/coalesce，避免連續播放或批量刪除造成重複 snapshot reload。

Instruction docs accuracy notes：`lib/providers/AGENTS.md:9` 將 history 放在 `watchAll() + StateNotifier` 類別，但目前實作是 `watchLazy()` + `StreamProvider` snapshot。這不是功能錯誤，但文檔描述與實作不一致，之後更新 provider 指引時應修正。

### DB-PERF-02 - Download manager 全量 watch task，且每個 tile 另開 track 查詢

Classification：Suspected issue

Evidence：
- `lib/data/repositories/download_repository.dart:316` `watchAllTasks()` 回傳所有 `DownloadTask`，依 priority 排序並 `fireImmediately`。
- `lib/providers/download/download_providers.dart:116` `downloadTasksProvider` 直接暴露上述全量 stream。
- `lib/ui/pages/settings/download_manager_page.dart:17` Download manager watch 全量 tasks。
- `lib/ui/pages/settings/download_manager_page.dart:195` 到 `lib/ui/pages/settings/download_manager_page.dart:199` 每次 build 都把同一份 task list 分成 downloading/pending/paused/failed/completed 多個 list。
- `lib/ui/pages/settings/download_manager_page.dart:326` 每個 `_DownloadTaskTile` 再 watch `trackByIdProvider(task.trackId)`。
- `lib/providers/download/download_providers.dart:223` `trackByIdProvider` 對每個 trackId 呼叫 `trackRepo.getById()`。

Trigger scenario：下載大型歌單後累積大量 pending/paused/completed tasks；打開 Download manager 或滾動列表；批量 pause/resume/clear 造成 task stream 重新發出整份 list。

User impact：全量 task list 會在每次 DB task 變更後重建；可見 rows 會各自查 Track，滾動大量 rows 時容易形成 N+1 型查詢。因 `ListView.builder` 只建 visible rows，實際影響需要 profiling，但大量 task 時風險明確。

Suggested measurement or fix：
- 以 500 / 2,000 / 10,000 download tasks 量測 Download manager 首次 render、滾動 1,000 rows、pause all/resume all 後 rebuild 次數與 DB query 次數。
- 考慮建立 `DownloadTaskWithTrack` 批量 provider：stream task ids 後用 `getAll(trackIds)` 批量 hydrate visible 或 current page。
- 或在 `DownloadTask` denormalize 顯示必要欄位（title/artist/source）以免 manager 為每個 row 查 Track。
- 對 manager 做分頁或只 watch active/pending，completed/failed 改 lazy load。

Instruction docs accuracy notes：下載進度使用 task-scoped memory provider 符合 `.serena/memories/download_system.md` 與 `lib/providers/AGENTS.md` 的方向；風險在 task metadata 全量 watch 與 row-level Track lookup，現有文檔未明確規範。

### DB-PERF-03 - DownloadRepository 的 bulk status update 在單一 transaction 內逐筆 put

Classification：Confirmed issue

Evidence：
- `lib/data/repositories/download_repository.dart:246` `resetDownloadingToPaused()` 查出 matching tasks 後，`lib/data/repositories/download_repository.dart:253` 到 `lib/data/repositories/download_repository.dart:255` 逐筆 `put()`。
- `lib/data/repositories/download_repository.dart:262` `pauseAllTasks()` 同樣在 `lib/data/repositories/download_repository.dart:269` 到 `lib/data/repositories/download_repository.dart:271` 逐筆 `put()`。
- `lib/data/repositories/download_repository.dart:278` `resumeAllTasks()` 同樣在 `lib/data/repositories/download_repository.dart:283` 到 `lib/data/repositories/download_repository.dart:285` 逐筆 `put()`。
- 同一 repository 已有較好的批量模式：`lib/data/repositories/download_repository.dart:214` 到 `lib/data/repositories/download_repository.dart:225` 先 `getAll(ids)` 後 `putAll()`。

Trigger scenario：app 啟動時大量 task 留在 downloading/pending；使用者在 Download manager 對幾百或幾千個 task 執行 pause all/resume all。

User impact：雖然包在單一 transaction，逐筆 `put()` 仍增加 Isar write work 與 transaction duration；Download manager watch 會在 commit 後收到整份 task list，長 transaction 也會延後 UI 狀態更新。

Suggested measurement or fix：
- 用 100 / 1,000 / 5,000 tasks benchmark `resetDownloadingToPaused()`、`pauseAllTasks()`、`resumeAllTasks()`。
- 將 loop 改成修改 objects 後一次 `putAll(tasks)`；若數量極大，可用 chunked `putAll`，但保留單一語義結果。
- 如果 pause/resume all 主要針對 active/pending，可在 query 層 limit 或分 status 分批，避免無界掃描。

Instruction docs accuracy notes：文檔要求下載進度不要高頻寫 DB，這裡不是 progress hot path；是 bulk state transition。現有指引沒有明確要求 bulk writes 用 `putAll()`，可補一條 repository performance pattern。

### DB-PERF-04 - 刪除下載分類/檔案後，DB path cleanup 會載入所有已下載 Track 並逐筆保存

Classification：Suspected issue

Evidence：
- `lib/services/download/download_path_maintenance_service.dart:114` 刪除單一 category 或 selected downloads 後，呼叫 `getAllTracksWithDownloads()` 載入所有有下載路徑的 Track。
- `lib/data/repositories/track_repository.dart:199` `getAllTracksWithDownloads()` 是 `playlistInfoElement(downloadPathIsNotEmpty()).findAll()`。
- `lib/services/download/download_path_maintenance_service.dart:116` 到 `lib/services/download/download_path_maintenance_service.dart:118` 在 Dart 端建立所有 persisted tracks 的 sourceKey map。
- `lib/services/download/download_path_maintenance_service.dart:160` 到 `lib/services/download/download_path_maintenance_service.dart:162` 每個 changed track 呼叫 `_trackRepository.save()`，也就是逐筆 transaction。

Trigger scenario：使用者在已下載頁刪除一個分類或少量檔案，但整個 library 已有數千首下載。

User impact：局部刪除會付出全 library downloaded-track 掃描成本；多筆 changed tracks 又變成逐筆 transaction，可能讓刪除完成後 UI 等待明顯變長。

Suggested measurement or fix：
- 以 100 / 1,000 / 10,000 downloaded tracks，刪除 1 個 category 與 10 首 selected tracks，量測 `_clearDeletedPaths()` 的 DB query time、file IO time、write count。
- 沿用 `DownloadPathSyncService.syncLocalFiles()` 的批量 identity 策略：從 scannedTracks 建 identities，先 `getBySourceIdentities()`，必要時再 fallback by sourceId。
- 將 changed persisted tracks 收集後 `saveAll()`，避免逐筆 write transaction。

Instruction docs accuracy notes：`.serena/memories/download_system.md` 描述同步本地文件以 sourceId/sourceType/cid 匹配；目前 full sync 已批量化，局部 delete cleanup 尚未套用同樣模式。文檔本身不是錯，但容易讓讀者誤以為所有下載同步/清理路徑都已批量匹配。

### DB-PERF-05 - 大歌單全量操作會一次載入全部 Track 並一次建立/查重全部 DownloadTask

Classification：Needs profiling

Evidence：
- `lib/providers/playlist_provider.dart:273` playlist detail 初始 page size 是 100，`lib/providers/playlist_provider.dart:323` load more 也是分頁，日常瀏覽已避免一次載入全部。
- 但 `lib/providers/playlist_provider.dart:350` `getAllTracks()` 在需要全量操作時會呼叫完整 `getPlaylistWithTracks()`。
- `lib/services/library/playlist_service.dart:79` 到 `lib/services/library/playlist_service.dart:84` 會用 `playlist.trackIds` 一次 `getByIds()` 全部 tracks。
- `lib/ui/pages/library/playlist_detail_page.dart:987` 到 `lib/ui/pages/library/playlist_detail_page.dart:990` 「全部加入佇列」會走 full list。
- `lib/services/download/download_service.dart:515` 到 `lib/services/download/download_service.dart:519` 下載整個歌單也會一次載入全部 tracks。
- `lib/services/download/download_service.dart:448` 到 `lib/services/download/download_service.dart:491` 對全部待下載 tracks 一次計算 paths、批量查既有 tasks、一次 `saveTasks()`。

Trigger scenario：YouTube / Bilibili / Netease 匯入超大歌單，例如 2,000 到 10,000 首；使用者點「下載歌單」、「全部加入佇列」、「隨機加入佇列」。

User impact：單次操作可能產生大量 Track object、path string、DownloadTask object 與一個大 `putAll()` transaction；UI 可能在確認後卡住，且 DB 檔案快速膨脹。這是 user-requested bulk operation，不一定要避免，但需要量測可接受上限。

Suggested measurement or fix：
- 建立 synthetic playlist 量測 1k / 5k / 10k：`getByIds()` latency、`addPlaylistDownload()` wall time、heap peak、`saveTasks()` transaction time、Download manager 首次 render。
- 若超過可接受時間，改成 chunked enqueue：每批 200-500 tracks 計算/查重/寫入，期間回報 progress，最後再 trigger schedule。
- 對「全部加入佇列」也可 chunk 加入 queue，或提示大操作進度，避免一次佔用 UI isolate。

Instruction docs accuracy notes：現有 provider guidance 正確區分 playlist detail 是 DB join query + StateNotifier；實作也有分頁。文檔未描述 full-list command 的資料量上限，建議補上大歌單 bulk operation 的量測/分批準則。

### DB-PERF-06 - Playlist remote refresh / delete 使用大 transaction，正確性強但需量測 write lock 成本

Classification：Needs profiling

Evidence：
- `lib/services/library/playlist_mutation_service.dart:426` `replaceTracksFromRemoteRefresh()` 以單一 `writeTxn()` 包住 identity 查詢、`putAll()`、removed-track pruning、cover update 與 playlist save。
- `lib/services/library/playlist_mutation_service.dart:444` 已批量 `_findTracksByIdentity()`，`test/services/library/playlist_mutation_batch_structure_test.dart:6` 也用測試防止回到逐筆 identity lookup。
- pruning 時仍會查所有 reverse-linked tracks：`lib/services/library/playlist_mutation_service.dart:554` 到 `lib/services/library/playlist_mutation_service.dart:557`。
- `deletePlaylist()` 也在一個 transaction 中刪 playlist、查 stale reverse tracks、getAll cleanup candidates、deleteAll/putAll，見 `lib/services/library/playlist_mutation_service.dart:199` 到 `lib/services/library/playlist_mutation_service.dart:256`。

Trigger scenario：匯入歌單 refresh 回傳數千 tracks，且遠端移除大量 tracks；刪除大型本地/匯入歌單。

User impact：單一 transaction 有助關係一致性，但 transaction duration 可能很長，期間其他 DB writes 會等待；若 UI 等待同步完成，使用者會感到 refresh/delete 卡住。

Suggested measurement or fix：
- 以 1k / 5k / 10k refreshed tracks 測量 transaction duration、Isar write lock wait、UI frame jank。
- 保持關係一致性的前提下，評估 prepare phase 移出 write transaction：先在 read path 建立 identity/result plan，再用較短 write transaction commit。
- 若 pruning reverse-linked tracks 是主要成本，可考慮維護 playlistId -> track ids 的查詢輔助結構；這會牽涉 schema，需另開設計與 migration。

Instruction docs accuracy notes：`lib/providers/AGENTS.md` 要求 DB join query 用 StateNotifier + optimistic update，這與 playlist detail/provider 實作一致。service 層的單 transaction 是正確性取向；文檔沒有明確說明大 refresh/delete 的 transaction 粒度上限。

### DB-PERF-07 - Migration/default repair 目前成本可控，但 startup write transaction 有潛在膨脹點

Classification：Needs profiling

Evidence：
- `lib/providers/database_provider.dart:226` `initializeDatabaseDefaults()` 以 `writeTxn()` 包住 default repair。
- `lib/providers/database_provider.dart:207` 每次 migration/default repair 清空 `LyricsTitleParseCache`。
- `lib/providers/database_provider.dart:213` 載入全部 `PlayQueue` 再檢查 legacy volume signature。
- `lib/providers/database_provider.dart:320` Isar `maxSizeMiB` 設為 64。

Trigger scenario：cache collection 意外累積大量 rows、多個 legacy PlayQueue rows、或未來 migration 把更多 collection repair 加入 startup transaction；長期使用後 DB 接近 64 MiB。

User impact：目前 registered repair 多集中在 single Settings row 與 queue，應該可控；但 startup migration 是 app 啟動路徑，若未來加入大 collection 掃描，會直接影響啟動時間。64 MiB DB 上限也可能在長 history、download tasks、lyrics matches 增長後變成容量壓力。

Suggested measurement or fix：
- 在 profile mode 量測 cold open + `_migrateDatabase()`，使用含大量 PlayHistory / DownloadTask / LyricsMatch 的 seeded DB。
- 對未來 migration 建立規則：大 collection repair 必須 chunk 或只用 indexed bounded query，避免 startup 全表掃描。
- 觀察實際 Isar file size；若 history/download retention 不設上限，評估 `maxSizeMiB` 是否需要調整或建立 retention policy。

Instruction docs accuracy notes：`lib/data/AGENTS.md` 將 `LyricsTitleParseCache` 定義為啟動清除的 ephemeral cache，與 `lib/providers/database_provider.dart:207` 一致。文檔未提 DB size / startup migration budget，可在 performance guidance 補充。

## 正向觀察

- Track identity 批量查詢已存在：`lib/data/repositories/track_repository.dart:94`，playlist mutation 與 download sync 都有使用。
- Playlist detail 日常瀏覽已有分頁：`lib/providers/playlist_provider.dart:273`、`lib/providers/playlist_provider.dart:323`。
- Download progress 不走 Isar hot path：`lib/services/download/download_service.dart:241`、`lib/providers/download/download_providers.dart:141`。
- Download completion 同 transaction 更新 task 與 track path：`lib/data/repositories/download_repository.dart:180`，符合「完成且文件存在後才寫 Track downloadPath」的規範。

## 建議量測清單

1. Play history 10k / 50k rows：History page load、search、playCount sort、stats、delete all for track。
2. Download tasks 1k / 10k rows：Download manager first render、scroll、pause all、resume all、clear queue。
3. Playlist 5k / 10k tracks：detail lazy scroll、play all、shuffle all、download playlist enqueue。
4. Downloaded library 10k tracks：delete category、delete selected downloaded tracks、sync local files。
5. Startup seeded DB：DB open + migration/default repair + DownloadService initialize。
