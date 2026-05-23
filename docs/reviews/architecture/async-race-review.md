# Async / Race Condition Review

## Findings

1. **P1 - 更新流程缺少 operation generation，並且大多數 await 後未檢查 mounted。**

   理由：`UpdateNotifier.checkForUpdate()` 在進入 checking 後直接 await GitHub release 查詢，完成後無 request id / generation / mounted 檢查就寫回 `updateAvailable` 或 `upToDate`。`downloadAndInstall()` 也在讀取既有下載檔、下載進度 callback、下載完成與 catch 分支直接更新 state。這與播放、搜尋、歌詞搜尋中已採用的 superseded 檢查不一致。

   風險：使用者快速重試、關閉更新對話框、provider 被銷毀或同時觸發檢查/下載時，較舊的請求可能覆蓋較新的狀態；下載進度 callback 也可能在狀態已 reset 或另一個下載已開始後繼續推進舊 progress。最壞情況是 UI 顯示錯誤版本的 ready/install/error 狀態，或在 notifier disposed 後嘗試寫 state。

   建議方向：在 `UpdateNotifier` 增加輕量 `_operationId`，`checkForUpdate()`、`downloadAndInstall()`、`_triggerInstall()` 共用 `_isCurrentOperation(id)`；每個 await 後與 progress callback 內都檢查目前 operation。`reset()` 應遞增 operation id 以 supersede 既有 check/download，但不需要改 `UpdateService` 的平台安裝邏輯。

2. **P2 - 遠程刷新/自動刷新在 dispose 時只清 listener/timer，沒有取消正在執行的 refresh 工作。**

   理由：`RefreshManagerNotifier` 以 `_activeImportServices` 保存每個刷新中的 `ImportService`，`cancelRefresh()` 會呼叫 `cancelImport()`，但 `dispose()` 只取消 `_subscriptions`、清空集合與 generations，沒有對 `_activeImportServices` 逐一 `cancelImport()` / `dispose()`。`AutoRefreshService.dispose()` 也只停 timer，沒有 disposed flag 或 generation，使已進入 `_checkAndRefresh()` 的 async 工作可繼續 await 後使用 `_ref.read(refreshManagerProvider.notifier)`。

   風險：provider/container 銷毀、database provider 重建或測試 teardown 時，背景 import 仍可能繼續解析遠端歌單並寫入 Isar。`RefreshManagerNotifier` 的 state 更新會因 `mounted`/generation 失效被擋下，但 DB mutation 屬於 `ImportService.refreshPlaylist()` 內部流程，dispose 本身沒有同步取消該流程。這會造成「UI 已無刷新狀態，但資料庫仍被背景刷新改動」的 state desync。

   建議方向：在 `RefreshManagerNotifier.dispose()` 對 `_activeImportServices.values` 呼叫 `cancelImport()`，再安全地 `dispose()`；若擔心 double-dispose，保留 finally 的 `identical()` 移除邏輯即可。`AutoRefreshService` 可加 `_isDisposed` 或 `_generation`，`stop()/dispose()` 後讓 `_checkAndRefresh()` 在每個 await 後返回，並避免再讀 `_ref`。

3. **P2 - 搜尋匹配歌單匯入的舊 notifier 仍用單一 boolean 取消旗標，並行 import/manual search 可能互相覆蓋。**

   理由：`PlaylistImportNotifier.importAndMatch()` 只把 `_importCancelled` 設回 false，沒有 operation id。若第二次 import 在第一次未完成時開始，第一次完成後看到 `_importCancelled == false`，仍會把自己的 playlist/matchedTracks 寫回 state。`manualSearch()` 也在 await 前複製 `matchedTracks`，await 後直接把舊快照寫回，沒有確認目前仍是同一批匯入結果、同一個 index 或同一個 search source。

   風險：外部歌單搜尋匹配 UI 中，快速貼第二個連結、取消後重啟、或同時手動搜尋多首未匹配歌曲，可能把較舊的匹配結果覆蓋較新的結果。這類 desync 不一定造成資料庫寫入錯誤，但會讓使用者在建立歌單前看到錯誤的 matchedTracks。

   建議方向：不用大重構；沿用 `ImportPlaylistNotifier` 的 `_operationId/_activeOperationId` 模式，將 `importAndMatch()` 與 `manualSearch()` 綁到 operation id。`manualSearch()` 可同時捕捉該列的原始 track identity，回寫前確認 state 中該 index 仍對應同一筆。

4. **P3 - Radio 手動刷新錯誤時可能卡住 `isRefreshingStatus`。**

   理由：`RadioController.refreshAllLiveStatus()` 先把 `isRefreshingStatus` 設 true，接著 await `RadioRefreshService.instance.refreshAll()`，最後才設 false；中間沒有 try/finally。`RadioRefreshService.refreshAll()` 內部雖有 generation/coalescing，但 `_refreshAll()` 的 `repository.getAll()` 或其他非 per-station 錯誤可讓 Future 以 error 完成。

   風險：手動刷新直播狀態若遇到 repository 或全域服務錯誤，UI 可能維持 refreshing 狀態，下一次呼叫又被 `state.isRefreshingStatus` 擋掉。

   建議方向：只需在 `refreshAllLiveStatus()` 用 try/finally 還原 `isRefreshingStatus`，並在 finally 前後加 `mounted` 檢查。不需要調整 `RadioRefreshService` 已有的 refresh coalescing。

## Evidence

- `lib/providers/update_provider.dart:63` 至 `lib/providers/update_provider.dart:81`：`checkForUpdate()` await `_service.checkForUpdate()` 後直接更新 state，catch 也直接寫 state。
- `lib/providers/update_provider.dart:85` 至 `lib/providers/update_provider.dart:138`：`downloadAndInstall()` 讀 state.updateInfo、await `getExistingDownloadPath()`、下載 progress callback 與下載完成後都沒有 operation guard；progress callback 在 `lib/providers/update_provider.dart:110` 至 `lib/providers/update_provider.dart:118` 直接讀寫目前 state。
- `lib/providers/update_provider.dart:141` 至 `lib/providers/update_provider.dart:158`：`_triggerInstall()` 只有 Android install 回來後使用 `mounted`，但該 guard 沒覆蓋 check/download 流程。
- `lib/services/update/update_service.dart:216` 至 `lib/services/update/update_service.dart:321`：release 查詢包含 ABI、GitHub API、PackageInfo 與 asset parsing，多個 await 使 provider 層需要 superseded 防護。
- `lib/services/update/update_service.dart:326` 至 `lib/services/update/update_service.dart:348`：下載安裝服務本身是平台行為分派，適合保持無 UI state；race guard 應留在 provider 層。

- `lib/providers/refresh_provider.dart:103` 至 `lib/providers/refresh_provider.dart:107`：refresh manager 保存 active playlist ids、subscriptions、active import services 與 generation。
- `lib/providers/refresh_provider.dart:153` 至 `lib/providers/refresh_provider.dart:170`：progress stream 有 generation guard，說明 stale UI progress 已被考慮。
- `lib/providers/refresh_provider.dart:173` 至 `lib/providers/refresh_provider.dart:249`：refresh 完成/失敗後 finally 會 cancel subscription、移除 active service 並 dispose import service。
- `lib/providers/refresh_provider.dart:252` 至 `lib/providers/refresh_provider.dart:260`：顯式 cancel path 會 bump generation、呼叫 active import service 的 `cancelImport()` 並移除 state。
- `lib/providers/refresh_provider.dart:313` 至 `lib/providers/refresh_provider.dart:322`：dispose 只 cancel subscriptions、清 sets/maps，沒有 cancel 或 dispose `_activeImportServices`。
- `lib/services/import/import_service.dart:425` 至 `lib/services/import/import_service.dart:545`：`refreshPlaylist()` 會解析遠端歌單並在 `replaceTracksFromRemoteRefresh()`、playlist save 等步驟寫 DB；取消檢查存在但需要外部呼叫 `cancelImport()` 才會生效。
- `lib/services/refresh/auto_refresh_service.dart:37` 至 `lib/services/refresh/auto_refresh_service.dart:48`：自動刷新 timer 可停止，但 `_checkAndRefresh()` 已在執行時不會因此停止。
- `lib/services/refresh/auto_refresh_service.dart:58` 至 `lib/services/refresh/auto_refresh_service.dart:105`：自動刷新 await repository、refresh manager 與 delay，期間沒有 disposed/generation check。
- `lib/services/refresh/auto_refresh_service.dart:114` 至 `lib/services/refresh/auto_refresh_service.dart:116`：dispose 僅呼叫 `stop()`。

- `lib/providers/playlist_import_provider.dart:107` 至 `lib/providers/playlist_import_provider.dart:124`：舊 playlist import notifier 用 `_importCancelled` boolean 控制取消。
- `lib/providers/playlist_import_provider.dart:138` 至 `lib/providers/playlist_import_provider.dart:171`：`importAndMatch()` 開始時把 `_importCancelled` 設 false，await 後只檢查該 boolean，沒有 operation id。
- `lib/providers/playlist_import_provider.dart:203` 至 `lib/providers/playlist_import_provider.dart:230`：`manualSearch()` await 前複製整個 matchedTracks，await 後直接回寫，沒有 stale source/index/operation 檢查。
- `lib/providers/import_playlist_provider.dart:62` 至 `lib/providers/import_playlist_provider.dart:96`：另一個匯入 notifier 已有 `_operationId/_activeOperationId` 與 progress listener guard，可作為局部修正參考。
- `lib/providers/import_playlist_provider.dart:99` 至 `lib/providers/import_playlist_provider.dart:176`：`importFromUrl()` 在 await 前後檢查 active operation，finally 清 service/keepAlive，這是較一致的 pattern。

- `lib/services/radio/radio_controller.dart:848` 至 `lib/services/radio/radio_controller.dart:860`：`refreshAllLiveStatus()` 設定 loading 後 await refreshAll，沒有 finally。
- `lib/services/radio/radio_refresh_service.dart:81` 至 `lib/services/radio/radio_refresh_service.dart:94`：`refreshAll()` coalesces overlapping refresh requests。
- `lib/services/radio/radio_refresh_service.dart:96` 至 `lib/services/radio/radio_refresh_service.dart:145`：`_refreshAll()` 使用 generation 防 stale，但外層沒有吞掉所有錯誤。

- `lib/services/audio/audio_provider.dart:1790` 至 `lib/services/audio/audio_provider.dart:1887`：播放 request 進入 loading 會遞增 `_playRequestId`，退出/重置 loading 都檢查 request。
- `lib/services/audio/audio_provider.dart:1937` 至 `lib/services/audio/audio_provider.dart:2055`：`_executePlayRequest()` 在多個 await 後檢查 superseded，錯誤/重試分支也使用 request guard。
- `lib/services/audio/audio_provider.dart:2175` 至 `lib/services/audio/audio_provider.dart:2445`：network retry 使用 `_retryGeneration`、current track key、timer cancel 與手動 retry generation。
- `lib/services/audio/playback_request_executor.dart:113` 至 `lib/services/audio/playback_request_executor.dart:210`：playback handoff/fallback 在 selection、fallback、handoff 後檢查 request superseded。
- `lib/services/audio/audio_provider.dart:1580` 至 `lib/services/audio/audio_provider.dart:1620`：歌詞 auto-match fire-and-forget 使用 `_lyricsAutoMatchRequestId` 與 disposed guard。

- `lib/providers/search_provider.dart:239` 至 `lib/providers/search_provider.dart:290`：主搜尋使用 `_searchRequestId`，結果與錯誤回寫前檢查 request 與 mounted。
- `lib/providers/search_provider.dart:315` 至 `lib/providers/search_provider.dart:383`：loadMore 使用 query、source、order、liveRoomFilter 與 current page 檢查，避免 pagination stale append。
- `lib/providers/lyrics_provider.dart:119` 至 `lib/providers/lyrics_provider.dart:155`：current lyrics content 使用 `ref.onDispose()` guard，避免舊 provider 把過期歌詞寫入 cache。
- `lib/providers/lyrics_provider.dart:327` 至 `lib/providers/lyrics_provider.dart:420`：manual lyrics search 使用 `_searchRequestId` 與 mounted guard。
- `lib/services/download/download_service.dart:83` 至 `lib/services/download/download_service.dart:93`：下載服務有 setup/discard guard 集合，避免取消中的任務復活。
- `lib/services/download/download_service.dart:665` 至 `lib/services/download/download_service.dart:952`：下載 setup、isolate registration、finalization、completion event 都有 abort/discard 檢查。
- `lib/providers/download/download_providers.dart:78` 至 `lib/providers/download/download_providers.dart:108`：download provider 訂閱 completion/progress/failure stream，onDispose 取消訂閱、清 progress 並 dispose service。

## Risk

- **高優先級**：更新流程狀態競態。這是使用者可直接觸發的 UI flow，且涉及下載與安裝動作；若舊 operation 覆蓋新 operation，錯誤提示、readyToInstall 與 progress 都可能失真。
- **中優先級**：遠程刷新 dispose 後仍可能 mutate DB。平常使用中較少遇到 provider teardown，但測試、app 關閉、資料庫重建或熱重載時可能造成非預期資料變更。
- **中優先級**：搜尋匹配歌單匯入 stale overwrite。影響建立歌單前的 UI 決策，尤其是快速重試或手動搜尋多列時。
- **低到中優先級**：radio 手動刷新 loading stuck。主要是 UI 卡住與後續刷新被擋，不太會造成資料損壞。

## Suggested direction

- 優先用現有 pattern 補洞，不建議大規模重構 async 架構。`AudioController`、`SearchNotifier`、`LyricsSearchNotifier`、`ImportPlaylistNotifier` 已經示範 request id / generation / mounted guard；更新與舊 playlist import notifier 可以局部套用同一模式。
- 不建議重寫 `UpdateService`。服務層目前負責平台下載/安裝與 asset parsing，沒有持有 UI state；race guard 放在 `UpdateNotifier` 能降低改動面。
- 不建議改播放 retry 架構。播放層已將 request supersession、retry generation、duplicate retry suppression、premature completion retry 分散在清楚的 owner 內，且符合 `lib/services/audio/AGENTS.md` 對 AudioController ownership 的規範。
- 不建議改下載 isolate/進度策略。下載層已有 discard/setup/finalization guard、主 isolate 批量 progress flush、completion event debounce；本次只看到 lifecycle 已被系統性處理，沒有發現需要為 race condition 立即調整的點。
- 建議為以上 finding 增加 focused tests：
  - update provider：兩個可控 `checkForUpdate()` completion 反序回來時，舊結果不能覆蓋新狀態；reset 後 progress callback 不應更新 state。
  - refresh manager：provider dispose 後 active import service 必須收到 cancel，且可控 parse 完成後不能寫 DB。
  - playlist import notifier：兩次 `importAndMatch()` 反序完成時只保留最新 operation；manualSearch 反序完成時只更新仍相同的列。
  - radio：`RadioRefreshService.refreshAll()` throw 時 `isRefreshingStatus` 回到 false。

## Instruction docs accuracy notes

- **規範性語料**：
  - `AGENTS.md:84` 至 `AGENTS.md:103` 是硬邊界與工作方式，包括優先用 `rg`、保留 user changes、不要 bypass `AudioController`、不要加入 hidden search filter。
  - `AGENTS.md:120` 至 `AGENTS.md:127` 列出核心 provider，包括 audio、playlist、library invalidation、search、Netease account、lyrics search 與 audio settings。
  - `lib/services/audio/AGENTS.md:28` 至 `lib/services/audio/AGENTS.md:43` 定義 AudioController / PlaybackRequestExecutor / AudioStreamManager ownership；本次代碼驗證顯示這些 ownership 與實作一致。
  - `lib/services/AGENTS.md:6` 至 `lib/services/AGENTS.md:24` 規範 download path 去重、file exists 後才保存、isolate progress 與 media headers；代碼驗證與此一致。
  - `lib/services/AGENTS.md:30` 至 `lib/services/AGENTS.md:69` 規範 lyrics auto-match priority、AI fallback 與 lyrics popup lifecycle；代碼中 auto-match request guard 符合 race 防護期待。
  - `lib/providers/AGENTS.md:15` 至 `lib/providers/AGENTS.md:23` 規範 FutureProvider invalidation、library invalidation coordinator 與 API/cache state pattern；download completion 與 refresh success 路徑大致遵守。
  - `lib/data/sources/AGENTS.md:82` 至 `lib/data/sources/AGENTS.md:136` 規範 SourceApiException、SourceErrorKind、quality fallback 與非 fallbackable error preservation；播放錯誤/retry 分支與 download stream fallback 的方向一致。

- **描述性語料，已用代碼驗證**：
  - `docs/README.md:15` 至 `docs/README.md:20` 說明 `AGENTS.md` 是權威、`docs/development.md` 只做 onboarding、`.serena/memories` 是窄補充；本 review 以 AGENTS 為規範，memory 僅作補充線索。
  - `docs/development.md:34` 至 `docs/development.md:60` 描述 UI -> Provider/Controller -> Service -> Data/Source 分層；審查時按此分層追到 provider state、service work、repository mutation。
  - `.serena/memories/refactoring_lessons.md:11` 至 `.serena/memories/refactoring_lessons.md:18` 對播放 request id、loading context 與 JustAudio 快速退出的記憶仍符合當前 `audio_provider.dart`。
  - `.serena/memories/refactoring_lessons.md:38` 至 `.serena/memories/refactoring_lessons.md:47` 對 download/remote refresh 的補充與當前 download/refresh 代碼多數一致；但本 review 發現 dispose lifecycle 仍有缺口。
  - `.serena/memories/download_system.md:34` 至 `.serena/memories/download_system.md:41` 描述 savePath 去重、完成後才保存下載路徑、Windows isolate progress；已由 `download_service.dart` 與 provider subscriptions 驗證。
  - `.serena/memories/update_system.md:15` 至 `.serena/memories/update_system.md:31` 與 `.serena/memories/update_system.md:33` 至 `.serena/memories/update_system.md:51` 描述 update asset/平台行為；代碼吻合，但 memory 未提 update provider 的 async supersession 要求。

