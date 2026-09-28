# 現狀盤點：舊專案（lib/）週期性與背景工作

> 查證日期：2026-09-27。分支 `docs/audit`。
> 查證方式：讀 `docs/audit/`（engineering.md、features.md、playback.md、data.md、downloads.md、platforms.md、questions.md）、逐一 Read `lib/` 原始碼核對、Grep 全庫（`Timer(`、`periodic`、`Future.delayed`、`Isolate.spawn`/`compute(`）。
> 入口清單：`test/support/periodic_timer_static_rule_test.dart:34-104` 的 `_timers` 登記表（9 個檔案、12 個 `Timer.periodic`），已逐一核對原始碼。
> 行號皆為本次實際 Read 到的內容；推測另標。

---

## 總覽表

| # | 工作 | 檔案 | 間隔 | 可設定 | 背景暫停 | 離線感知 | 使用者可關 |
|---|---|---|---|---|---|---|---|
| 1 | 網路連通性 DNS 偵測 | connectivity_service.dart | 15 秒（寫死） | 否 | 否 | （本身就是） | 否 |
| 2 | 首頁排行快取刷新 | ranking_cache_service.dart | 預設 60 分 | 是（30/60/120/240 分） | 否 | 部分（聽恢復事件） | 不能關，只能調間隔 |
| 3 | 匯入歌單自動刷新 | auto_refresh_service.dart | 30 分檢查（寫死） | 每歌單各自間隔 | 否 | 否 | timer 不能關；每歌單可不設間隔 |
| 4 | 電台直播狀態輪詢 | radio_refresh_service.dart | 預設 5 分 | 是（關/1/3/5/10 分） | **是**（#95） | 否（錯誤顯示成未開播） | **能**（間隔設「關閉」） |
| 5 | 電台收聽：每秒更新已播放時長 | radio_controller.dart | 1 秒（寫死） | 否 | 否 | 不適用（本機） | 停止收聽即停 |
| 6 | 電台收聽：刷新直播間資訊 | radio_controller.dart | 1 分（寫死） | 否 | 否 | 否 | 停止收聽即停 |
| 7 | 播放位置檢查（補切下一首） | audio_provider.dart | 1 秒（寫死） | 否 | 否（刻意，背景才需要它） | 不適用（本機） | 不適用 |
| 8 | 播放位置定期存檔 | queue_manager.dart | 10 秒（寫死） | 否 | 否 | 不適用（本機） | 不適用 |
| 9 | 下載進度彙整 flush | download_service.dart | 1 秒（寫死） | 否 | 否 | 不適用（本機） | 不適用 |
| 10 | 下載排程 | download_service.dart | 5 秒（寫死）＋事件觸發 | 並行數可設（1–5，預設 3） | 否 | 否 | 不適用 |
| 11 | 評論區自動翻頁 | comment_pager.dart | 10 秒（寫死） | 否 | 否 | 不適用（本機） | 不適用（只在面板開著時） |

---

## 1. 網路連通性偵測

- **檔案**：`lib/services/network/connectivity_service.dart`
- **做什麼**：每 15 秒對 `dns.google`、`one.one.one.one`、`dns.alidns.com` 做 DNS 解析（`InternetAddress.lookup`，任一成功即算有網路，單次逾時 5 秒）；狀態翻轉時更新 `ConnectivityState`，斷→通時 broadcast `onNetworkRecovered`（`:52-56,73-97,102-116`）。
- **誰啟動**：`ConnectivityNotifier.build()` → `_initialize()`（`:43-47,64-80`）。第一個讀它的是 `RankingCacheService.build()`（`ranking_cache_service.dart:149`）與 `AudioController._wireProviderCallbacks()`（`audio_provider.dart:271-273`），實際上 App 啟動後排行快取經 `refreshSettingsProvider`（`app.dart:119`）就會帶起它（推測：啟動早期即開始輪詢）。
- **間隔**：`AppConstants.connectivityPollingInterval` = 15 秒、`dnsTimeout` = 5 秒，皆寫死（`lib/core/constants/app_constants.dart:154,157`）。
- **背景／最小化**：無 AppLifecycleState 處理，背景照跑。
- **離線行為**：它本身就是離線判斷者。
- **失敗退避**：無；每輪固定間隔，三個目標逐一試完才算斷線。
- **取消**：provider dispose → `_teardown()` 取消 timer 並關 controller（`:120-123`）。實務上常駐。
- **使用者能否關閉**：不能（static rule 登記表自承「2026-09 決定不改行為」；questions.md B10 尚未決定）。
- **下游消費者**：排行榜網路恢復重抓（`ranking_cache_service.dart:218-230`）；播放網路恢復（`audio_provider.dart:2155-2163` → `_onNetworkRecovered()`）。

## 2. 首頁排行快取刷新

- **檔案**：`lib/services/cache/ranking_cache_service.dart`
- **做什麼**：對 `SourceManager` 註冊的每個 `RankingSource` 並行抓排行榜存進記憶體 state（不落盤）；啟動時立即抓一次，之後定時整批重抓；網路恢復時也整批重抓（`:178-257`）。
- **誰啟動**：`rankingCacheServiceProvider`（`NotifierProvider`）在 `build()` 裡 `Future.microtask(initialize)` 並接網路監聽（`:146-151`）。由 `refreshSettingsProvider._loadSettings()` 在啟動時 `updateRefreshInterval` 觸發建構（`refresh_settings_provider.dart:62-64`；該 provider 錨在 `FMPApp.build`，`app.dart:119`）。
- **間隔**：`Settings.rankingRefreshIntervalMinutes`，預設 60 分；設定頁選項 30/60/120/240 分（`lib/ui/pages/settings/widgets/settings_cache.dart:245`；預設 `refresh_settings_provider.dart:14`；持久化 `lib/data/models/settings.dart:434`）。改設定即重啟 timer（`:202-215`）。**不能設成關閉**；首頁排行設定頁停用某音源只影響顯示，背景仍抓全部音源（`home_ranking_settings_provider.dart:193-195`；questions.md B12）。
- **背景／最小化**：無生命週期處理，背景照跑照抓。
- **離線行為**：不看 connectivity 狀態就發請求；失敗走退避。網路恢復事件觸發額外一整輪（`:222-227`）。
- **失敗退避**：單一榜單失敗保留舊快取，按 `[5s, 30s, 2m, 10m]` 階梯退避（`Timer` 一次性重試），用完交還給定時刷新與網路恢復；每次整輪刷新重置階梯（`:124-129,297-311,236`）。
- **取消**：provider dispose → `_teardown()` 取消 refresh timer、全部退避 timer、網路訂閱（`:325-335`）。
- **使用者能否關閉**：不能關，只能調間隔。

## 3. 匯入歌單自動刷新

- **檔案**：`lib/services/library/auto_refresh_service.dart`
- **做什麼**：每 30 分鐘掃一次全部歌單，挑出 `needsRefresh` 的（匯入歌單且設了 `refreshIntervalHours`、且 `lastRefreshed + 間隔 < now`），按最久未刷新排序，**一次只刷一張**，每刷完一張等 5 秒再刷下一張（`:57-123`）。刷新本體走 `refreshManagerProvider.refreshPlaylist`（`:100-102`）。
- **誰啟動**：`autoRefreshServiceProvider` 建構即 `service.start()`（`:143-158`），由 `FMPApp.build` watch（`app.dart:122`）。`start()` 立刻檢查一次再開 timer（`:32-45`）。
- **間隔**：檢查節拍寫死 `AppConstants.autoRefreshCheckInterval` = 30 分（`:41-44`；`app_constants.dart:151`）。**不一致**：類別註解（`:13`）寫「每小时检查一次」。每張歌單的刷新間隔是 Isar `Playlist.refreshIntervalHours`（小時；`lib/data/models/playlist.dart:30,76-83`），歌單編輯對話框選項 1/6/12/24/48/72/168 小時或不啟用，新建預設 24 小時（`create_playlist_dialog.dart:57-61,293-320`；「不啟用」存 -1，`:455-457`）。
- **背景／最小化**：無生命週期處理，背景照跑（`features.md` §13.2 亦註明「app 開著就跑（不看前景背景）」）。
- **離線行為**：不看 connectivity；刷新失敗只記 log 繼續下一張（`:108-110`）。
- **失敗退避**：無；單張失敗略過，等下一個 30 分鐘節拍。以 `_checkGeneration` 代際防止舊迴圈寫狀態（`:125-127`）。
- **取消**：`stop()` 取消 timer；provider dispose → `dispose()`（`:48-54,136-139,153-155`）。
- **使用者能否關閉**：timer 本身不能關；但預設不刷新——歌單沒設 `refreshIntervalHours` 就永不入列（`playlist.dart:77`）。`checkNow()` 手動入口是死代碼（`:130`；`features.md` §14）。

## 4. 電台直播狀態輪詢

- **檔案**：`lib/services/radio/radio_refresh_service.dart`
- **做什麼**：輪詢資料庫裡每個電台的 Bilibili 直播間資訊（開播狀態、封面、標題、主播名），更新記憶體快取並按需寫回資料庫，經 `stateChanges` 廣播（`:157-236`）。類別註解自承這是「App 裡唯一開著就永遠在打 Bilibili 的流量」（`:21-26`）。
- **誰啟動**：`main.dart` 第一幀後建立全域單例 `RadioRefreshService.instance`（間隔取預讀設定；`main.dart:247-258`），但**不輪詢**；要等到 `RadioController._initialize()` 呼叫 `setRepository()` 才 `_startRefreshTimer()` 並立即刷一輪（`:92-99`；`radio_controller.dart:304-306`）。觸發點是首頁電台區塊建構 RadioController。
- **間隔**：`Settings.radioRefreshIntervalMinutes`，預設 5 分；設定頁選項 關閉(0)/1/3/5/10 分（`settings_cache.dart:311`；`defaultRefreshInterval` `:34`；`offMinutes = 0` `:38`；`intervalFromMinutes` 把 0 轉成 null = 關閉、非法值回預設 `:42-46`）。改設定即 `updateRefreshInterval` 重啟 timer（`:111-119`；`refresh_settings_provider.dart:83-97`）。
- **背景／最小化**：**有**。`main.dart:256-258,347-365` 的 `_RadioRefreshLifecycleObserver` 把 `paused/hidden/detached` → `pause()`、`resumed` → `resume()`；`inactive` 不算背景（桌面視窗失焦）。timer 不取消，`tick()` 直接不做事；回前景時距上次乾淨刷新超過一個間隔才補一輪（`:123-155`）。手動 `refreshAll` 不受暫停限制。
- **離線行為**：不看 connectivity。非風控例外一律 `_markOffline` 把該台標成未開播（`:252-257`；questions.md D10 記「網路錯誤顯示成未開播」）。
- **失敗退避**：被風控（`SourceApiException.isRateLimited`）的那輪立刻停，下一輪推遲 `interval × 2^n`（n 上限 10）、上限 30 分（`maxBackoff` `:32`；`_enterBackoff` `:239-250`）；乾淨跑完一輪歸零（`:231-233`）。網路錯誤不退避，照常下一拍。
- **取消**：間隔設「關閉」→ timer 不建；`dispose()` 取消 timer 關 controller（`:298-302`）。
- **使用者能否關閉**：**能**，設定 > 電台刷新間隔 > 關閉；關閉時連啟動那一輪都不刷，只剩電台頁手動下拉（`:16-17,97-98`）。死代碼：`refreshStation`/`addStationStatus`/`removeStation`（`:260,276,282`；`features.md` §14）。

## 5. 電台收聽：每秒更新已播放時長

- **檔案**：`lib/services/radio/radio_controller.dart:972-975`
- **做什麼**：收聽電台期間每秒以 `DateTime.now() - _playStartTime` 更新 `state.playDuration`（`:993-998`）。純本機計時，無網路。
- **誰啟動**：`play()` 成功開流後 `_startTimers()`（`:505,968-982`）。
- **間隔**：1 秒，寫死。
- **背景／最小化**：無生命週期處理；直播音訊本身在背景繼續播，timer 照跑。
- **離線行為**：不適用（本機）。
- **失敗退避**：不適用。
- **取消**：`stop()`、直播結束 `_pauseAndWatchForResume()`、換台都 `_stopTimers()`（`:531-532,944-946,985-990,1045`）。
- **使用者能否關閉**：不適用（只在收聽時跑）。

## 6. 電台收聽：每分鐘刷新直播間資訊

- **檔案**：`lib/services/radio/radio_controller.dart:978-981`
- **做什麼**：收聽期間每 1 分鐘呼叫 `refreshStationInfo()`（`:800`）重新拉直播間資訊（高能用戶數等）。打 Bilibili 直播 API。
- **誰啟動**：同 #5，`play()` 成功後 `_startTimers()`。
- **間隔**：1 分鐘，寫死。
- **背景／最小化**：無生命週期處理，背景照打。
- **離線行為**：不看 connectivity；失敗走 `refreshStationInfo` 自己的例外處理（未展開核對）。
- **失敗退避**：無。
- **取消**：同 #5，`_stopTimers()`。
- **使用者能否關閉**：停止收聽即停，無獨立開關。

## 7. 播放位置檢查（補切下一首）

- **檔案**：`lib/services/audio/audio_provider.dart:1304-1316`
- **做什麼**：每秒把播放上下文交給 `PlaybackEventRouter.routePositionCheck`：後端漏掉 completed 事件時（Android 背景播放），位置連續停在結尾（距時長 ≤ 500ms）就合成一次「播完」補切下一首；推進權已 arm 給後端時連續 3 秒不動則收回推進權（`playback_event_router.dart:472-498`；`playback.md` §3.6）。
- **誰啟動**：`AudioController.initialize()`（`:380`），**無條件常駐**——timer 不是只在播放時才跑，是每秒都跑、內部在 `!backendIsPlaying` 時 no-op（`playback_event_router.dart:477`）。登記表上「只在播放時跑」指的是效果，不是 timer 本身。
- **間隔**：`AppConstants.positionCheckInterval` = 1 秒、閾值 `positionCheckThreshold` = 500ms，寫死（`app_constants.dart:69-72`）。
- **背景／最小化**：無生命週期處理；它的存在目的就是補背景播放（`:1302` 註解）。
- **離線行為**：不適用（本機）。
- **失敗退避**：不適用。
- **取消**：`_teardown()` → `_stopPositionCheckTimer()`（`:460,1313-1316`）。
- **使用者能否關閉**：不能，也無必要（本機）。

## 8. 播放位置定期存檔

- **檔案**：`lib/services/audio/queue_manager.dart:819-824`
- **做什麼**：每 10 秒把當前播放位置寫進佇列持久化（`PlayQueue.lastPositionMs`）。
- **誰啟動**：`QueueManager.initialize()`（由 AudioController 初始化帶起）還原佇列後 `_startPositionSaver()`（`:218`）。
- **間隔**：`AppConstants.positionSaveInterval` = 10 秒，寫死（`app_constants.dart:54`）。seek 後另有一次立即存檔（`audio_provider.dart:576-582`，事件觸發非 timer）。
- **背景／最小化**：無生命週期處理，背景照寫。
- **離線行為**：不適用（本機 Isar）。
- **失敗退避**：無（`_savePosition` 內部未展開核對）。
- **取消**：`QueueManager.dispose()`（`:239-245`）。
- **使用者能否關閉**：不能。「記住播放位置」是另一個設定，只影響還原，不影響這個 timer。

## 9. 下載進度彙整 flush

- **檔案**：`lib/services/download/download_service.dart:348-358`
- **做什麼**：每 1 秒把下載 isolate 回報累積在記憶體的進度一次 flush 到 `progressStream`（只進記憶體 state，**不寫 DB**，刻意避免 Isar watch 觸發重建；`:316-358`）。註解說明也為了避免 Windows PostMessage 佇列溢出（`:350-353`）。
- **誰啟動**：`DownloadService.initialize()`（`:226`），由 `downloadServiceProvider` 建構時呼叫（`download_providers.dart:42,59`）。**該 provider 不在 `FMPApp.build` 的啟動清單**；首次被 watch 是下載管理頁（`download_manager_page.dart:20`）或歌單詳情頁的下載動作（`playlist_detail_page.dart:966,1039,1527`）。也就是兩個下載 timer 不是 App 啟動即跑，是第一次碰下載功能才跑（推測：之後常駐不關）。
- **間隔**：1 秒，寫死（`:354-355`）。
- **背景／最小化**：無生命週期處理。
- **離線行為**：不適用（本機彙整）。
- **失敗退避**：不適用。
- **取消**：`dispose()`（`:284-285`）。
- **使用者能否關閉**：不適用。

## 10. 下載排程

- **檔案**：`lib/services/download/download_service.dart:397-406`
- **做什麼**：排程下一個待下載任務：讀 `Settings.maxConcurrentDownloads`、算空槽、把 pending 任務轉 downloading 並 `_startDownload`（每個任務一個 `Isolate.spawn`，`:818`）（`:420-456`）。事件驅動（`_triggerSchedule` broadcast）為主，5 秒 `Timer.periodic` 是備援——啟動初期事件可能丟失，靠定時器補（`downloads.md` §2 記 `_triggerSchedule` 早於訂閱建立時事件會丟）。
- **誰啟動**：`initialize()` → `_startScheduler()`（`:223`），時機同 #9。
- **間隔**：5 秒，寫死（`:403`）。並行數 `Settings.maxConcurrentDownloads` 可設 1–5、預設 3（`downloads.md` §2；`settings.dart:281`）。
- **背景／最小化**：無生命週期處理；下載只在 App 行程內 isolate 跑，無前景服務／WorkManager（questions.md N8）。
- **離線行為**：不看 connectivity；下載失敗由任務自身狀態處理，不自動重試（`downloads.md` §2）。
- **失敗退避**：排程器本身無退避；串流解析層另有一次重試（1 秒）與限流重試（3 秒）。
- **取消**：`dispose()`（`:280-283`）。
- **使用者能否關閉**：不適用；無新任務時每 5 秒空轉一次（讀設定＋查 pending，皆本機）。

## 11. 評論區自動翻頁

- **檔案**：`lib/ui/widgets/panels/comment_pager.dart:96-105`
- **做什麼**：每 10 秒若評論區在螢幕可視範圍內（`_isVisible()` 算 RenderBox 與螢幕交集，`:74-94`）就自動翻到下一則（到底繞回）。
- **誰啟動**：widget `initState` → `_startAutoScroll()`，僅 `autoScroll: true` 時；目前只有桌面 Detail Panel 傳 true（`track_detail_panel.dart:919-922`）；全螢播放頁的 `CommentPager`（`player_page.dart:1081`）不傳，預設 false 不跑。
- **間隔**：10 秒，寫死（`:98`）。
- **背景／最小化**：無生命週期處理；但面板關掉 widget 就 dispose。
- **離線行為**：不適用（資料已抓）。
- **失敗退避**：不適用。
- **取消**：`dispose()` 取消（`:68-71`）；切歌或 `autoScroll` 變動時重啟（`:53-65,107-111`）。
- **使用者能否關閉**：無設定開關；關面板即停。

---

## 登記表之外的發現

以下都不在 `_timers` 登記表（不是 `Timer.periodic`/`Stream.periodic`），但屬於背景／週期性質的工作。

### 啟動時一次性背景工作（非週期）

| 工作 | 時機 | 證據 |
|---|---|---|
| 孤兒 Track 清理（不在任何歌單、不在佇列的 Track 刪除） | 佇列初始化後 10 秒一次性 `Timer`（刻意用 Timer 而非 Future.delayed，避免撞上已關閉的 Isar） | `queue_manager.dart:220-229,830-843`；`track_repository.dart:635-669` |
| 清已完成／失敗下載任務、`downloading` 全部轉 `paused`、刪孤兒 `.downloading` 暫存檔 | `DownloadService.initialize()`（首次碰下載功能時） | `download_service.dart:206-220,238-273` |
| Windows 清理上次更新殘留（Temp 裡 `fmp-*.exe/.zip`、`fmp_updater.*`、`fmp_update/`） | 每次啟動（僅 Windows） | `main.dart:231`；`update_service.dart:259-292` |
| 清空 `LyricsTitleParseCache` 表（只活一個 session 的快取） | 每次啟動開 DB 時 | `lib/data/database/database_migration.dart:66`（data.md §1） |
| 下載目錄掃描同步（`DownloadPathSyncService.syncLocalFiles`） | 啟動時 `startupDownloadSyncProvider`（`app.dart:131`） | `lib/providers/download/startup_download_sync_provider.dart:9-17` |
| B 站 Cookie 刷新＋三平台帳號狀態檢查 | 啟動時一次（`accountStatusCheckProvider`，`app.dart:125`） | `account_provider.dart:131-174` |

### 快取清理（全部事件觸發，無定期清理）

- **網路圖片磁碟快取**：每載入 30 張或估計大小超過上限 90% 時觸發修剪（防抖 `DebounceDurations.long` = 500ms），LRU + 7 天 stale + `Settings.maxCacheSizeMB` 上限（桌面預設 32 MB）；`compute()` 掃目錄。`lib/core/services/network_image_cache_service.dart:202-252,50-86`。設定頁可手動清除。
- **歌詞內容快取**：LRU，檔數 `Settings.maxLyricsCacheFiles`（預設 50，設定選項 10/30/50/100/200，`settings_cache.dart:171`）+ 總量 5 MB 寫死；存取時間寫 `_metadata.json` 用 2 秒防抖 `Timer`。`lib/services/lyrics/lyrics_cache_service.dart:18-39,315`。
- **記憶體串流解析快取**：32 筆 LRU，依 URL 有效期失效（data.md §4；`stream_resolution_service.dart:102-112`）。
- **圖片記憶體快取**：啟動時設 `PaintingBinding` 上限（`main.dart:156-164`）。

### log 輪替

- 有輪替但非定時：`LogFileSink` 單檔 2 MB × 3 檔，寫入時超過上限才輪替（`fmp.log` → `fmp.1.log` …），位置 `Documents/FMP/logs/`。`lib/core/log_file_sink.dart:15-28,82-105`。無啟動時清理、無依日期刪除。

### 更新檢查

- **只有手動**：設定 > 關於 > 檢查更新（`settings_about.dart:70` → `update_provider.dart:80` → `update_service.dart:389`）。啟動時不檢查、無定時檢查（grep `checkForUpdate` 全庫只有這一條 UI 呼叫鏈）。與 questions.md B7–B9 備註一致（使用者明確要求不要啟動／定時檢查）。

### 播放歷史寫入

- 即時寫、非節流：開流成功且 `countsAsNewPlay` 時 `PlayHistorySideEffect.onTrackStarted` → `PlayHistoryRecorder.record`，fire-and-forget microtask 直接寫 Isar，並依 `Settings.playHistoryLimit`（預設 10,000）截斷。`playback_side_effects.dart:166-185`；`play_history_recorder.dart:34-53`。單曲循環每圈記一筆（playback.md §3.9；questions.md D6 使用者確認這是要的行為）。

### 帳號／憑證刷新

- **B 站 Cookie**：只有啟動時一次。`accountCookieRefreshProvider` 先 `needsRefresh()`（打 B 站 API 問伺服器要不要換）再 `refreshCredentials()`；伺服器要求時舊 refresh_token 作廢。`account_provider.dart:131-152`；`bilibili_account_service.dart:331-357`。**無定期刷新**。
- **三平台帳號狀態**（session 有效性 + VIP）：同樣啟動時一次（`accountStatusCheckProvider` → `verifyAllAccountStatuses`，`account_provider.dart:158-174,216-229`）。請求期由攔截器偵測失效寫 Isar，UI 經 `accountSessionExpiryWatcherProvider` 提示（`account_provider.dart:190-199`）。無定期檢查。
- **YouTube／網易**：查不到任何定期憑證刷新。

### Windows 托盤與桌面歌詞

- `lib/services/platform/windows_desktop_service.dart`（托盤、全域熱鍵、關閉縮托盤、安裝程式偵測）**沒有任何 Timer／輪詢**，全事件驅動（tray_manager/hotkey_manager 回呼、provider watch）。
- 桌面歌詞子視窗（`lib/services/lyrics/lyrics_window_service.dart`、`lib/ui/windows/lyrics_window.dart`）主行程側無週期工作，狀態推送走 desktop_multi_window method channel（事件驅動）；子視窗內只有一次性防抖／延遲 Timer（滾動恢復 3 秒 `lyrics_window.dart:813`、樣式 flush `lyrics_window_style.dart:41`）。

### `Future.delayed` 自我排程迴圈（退避形狀，非持續迴圈）

static rule 登記表註解（`periodic_timer_static_rule_test.dart:13-14`）說「目前沒有」`Future.delayed` 自排下一輪的迴圈；核對後確認全庫的 `Future.delayed` 都是**有限次退避重試或 debounce**，沒有無限自我排程：

| 位置 | 形狀 |
|---|---|
| 電台斷流重連 `_handleStreamEnd` | 最多 3 次，1s/3s/10s（`RadioReconnectConfig`，`app_constants.dart:250-262`；`radio_controller.dart:894-941`） |
| 播放失敗復原 `PlaybackRecoveryCoordinator` | 最多 5 次，1s/2s/4s/8s/16s（`NetworkRetryConfig`，`app_constants.dart:226-246`；`playback_recovery_coordinator.dart:170`） |
| 排行榜失敗退避 | 4 階 5s/30s/2m/10m（一次性 `Timer`，見 §2） |
| Mix 補歌 | 最多 10 次、間隔 1 秒（`mix_session_coordinator.dart:293-299`；`app_constants.dart:99-105`） |
| 串流解析重試 | 一般 1 次（1 秒）、限流 1 次（3 秒）（`stream_resolution_service.dart:216,236`） |
| 匯入比對搜尋節流 | 多源 1 秒／單源 800ms（`app_constants.dart:83-88`） |
| 帳號 QR 登入輪詢等待 | `bilibili_account_service.dart:167`（2 秒）、`netease_account_service.dart:146`（3 秒）——登入流程內有限等待，非常駐 |
| media_kit 時長輪詢 | `playUrl/setUrl/playFile/setFile` 四份相同的「等後端回時長」迴圈，50ms 一拍、有逾時上限（`media_kit_audio_service.dart:782-949`；`app_constants.dart:60`） |

### 其他 isolate

- `download_service.dart:818` `Isolate.spawn`：每個下載任務一個長駐 isolate，靠 receivePort 回報進度、cancel port 取消。
- 一次性 `compute()`／`Isolate.run()`：圖片快取目錄掃描與刪檔（`network_image_cache_service.dart:50,55,86`）、下載路徑維護（`download_path_maintenance_service.dart:91,124`）、下載目錄掃描（`download_providers.dart:205,215`、`download_scanner.dart`）、Windows 免安裝版更新解壓（`update_service.dart:656`）。全部一次性，完成即回收。

### 背景暫停覆盤

全庫只有 `RadioRefreshService` 接 `AppLifecycleState`（`main.dart:347-365`，#95）。其餘網路輪詢——DNS 偵測、排行刷新、歌單自動刷新、電台收聽中的資訊刷新——**背景照跑**（Android 上行程被系統限制時自然停，但程式碼層無主動暫停）。

### 離線感知覆盤

唯一對外發請求前會考慮連線狀態的機制是「網路恢復事件」：排行榜（`ranking_cache_service.dart:222-227`）與播放（`audio_provider.dart:2155-2163`）**監聽恢復**；但沒有任何工作在發請求**前**檢查 `connectivityProvider` 狀態——離線時照發，靠各自失敗路徑收拾（電台還會因此把狀態誤標成未開播，D10）。

---

## audit 文件提出的未決問題（與背景工作相關）

出自 `docs/audit/questions.md` 與各 audit 文件，尚未勾選定案：

1. **B10**：每 15 秒解析 `dns.google`、`one.one.one.one`、`dns.alidns.com` 偵測連線——常駐，去留未定（`connectivity_service.dart:52-56,102-116`）。
2. **B12**：首頁排行「停用某音源」只影響顯示，背景仍每小時抓所有音源——有「修改：停用即不抓」選項未定（`ranking_cache_service.dart:233-245`；`home_ranking_settings_provider.dart:193-195`）。
3. **B4**：啟動時自動換 B 站 Cookie（伺服器要求時舊 refresh_token 作廢）——每次啟動檢查，去留未定（`account_provider.dart:131-152`）。
4. **D10**：電台輪詢開播狀態；網路錯誤顯示成「未開播」——未定（`bilibili_live_client.dart:205-208`；`radio_refresh_service.dart:252-257`）。
5. **N8**：下載只在 App 行程內 isolate 跑，無前景服務或系統排程——背景時隨系統回收中斷、重啟變 paused，是否改未定（`downloads.md` §2、§6）。
6. **文件不一致**：`auto_refresh_service.dart:13` 類別註解「每小时检查一次」vs 實際 30 分鐘（`app_constants.dart:151`；`features.md` §13.2 已記）。
7. **E17**：應用內更新只有手動檢查一個入口；使用者在 B7–B9 備註已明確「不要啟動或定時檢查」，重寫應沿用此決定。
8. **E18**：托盤、全域快捷鍵、開機自啟、關閉縮托盤、單一實例（皆 Windows-only、事件驅動）功能去留未定；使用者備註確認單一實例要保留。
9. **M9**：登入失效提示每次 App 執行每平台只跳一次，重新登入後再失效不再提示（`session_expiry_notifier.dart:15,22-23`）——與啟動帳號檢查的觸發頻率相關，未定。
10. **重寫時的機制問題**（非 questions.md 條目，本次盤點觀察）：現行 11 個週期工作中，只有電台輪詢有背景暫停、只有排行刷新有離線恢復通道、失敗退避策略五套各不相同（排行 4 階、電台 2^n 上限 30 分、播放 5 階、電台重連 3 階、歌單刷新無退避）；新專案若要統一背景任務排程，這三個維度是主要分歧點。
