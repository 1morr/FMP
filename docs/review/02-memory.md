# 02 — 記憶體與資源占用（面向 A）

> 唯讀審查；本檔僅含經 `file:line` 查證的發現。其中標註 `對抗驗證` 者，已由獨立 agent 重讀原始碼覆核。成熟度評分：**4 / 5**。

## 1. 現狀摘要

- **好：** 圖片／歌詞／檔案存在快取與音訊後端皆有明確上限與完整 dispose 鏈（`FileExistsCache` 5000 條、歌詞 LRU 50 檔/5MB、`ImageCache` 行動 100/50MB、Isar `compactOnLaunch`、長列表全面 virtualization、`AudioController` 取消所有訂閱與 Timer）。
- **壞：** 少數長生命 Provider 把整表常駐記憶體；`LyricsTitleParseCache` 與下載 `.part` 暫存缺乏自動淘汰／清理，磁碟與記憶體會隨使用時間單調上升。

## 2. 發現清單

### A1　`downloadTasksProvider` 常駐全部 DownloadTask — ⚠️ 對抗驗證後**撤回（誤報）**
- 嚴重度：~~High~~ → **無（誤報）**　工作量：—
- 證據：`lib/providers/download/download_providers.dart:116-119`（非 autoDispose 的 StreamProvider，watch 全表）、`lib/data/repositories/download_repository.dart:63-91`（含 `clearCompletedAndErrorTasks`）。
- **覆核結論：** 獨立驗證發現「啟動不自動裁剪」的指控與事實相反——`lib/services/download/download_service.dart:194-200` 的 `DownloadService.initialize()`（由 `downloadServiceProvider` 建構時呼叫，見 `download_providers.dart:40-56`）**已在啟動時自動清除 completed+failed 任務**，註解並標記 `A2: 启动时清理`。手動按鈕呼叫的是另一個 `clearCompleted()`，並非此方法。跨 session 無限增長已被阻斷。
- 殘留真實問題：session 內大量下載且不重啟時的累積，以及 StreamProvider 缺 select/分頁的微優化 — 降為 **Low** 等級打磨項。**保留此條以記錄審查紀律：建議中的機制其實已存在。**

### A2　`playlistListProvider` 非 autoDispose，`watchAll()` 整份歌單表常駐
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/providers/library/playlist_provider.dart:85-90,200-205`（`PlaylistListNotifier._setupWatch()` 訂閱 `repo.watchAll().listen((playlists)=> state=...)`，完整 `List<Playlist>` 永久持有）；`lib/data/repositories/playlist_repository.dart:88`（`watchAll()` 無 limit/分頁）。
- 影響：歌單數量大時整份 Playlist 物件圖（含 trackId 清單）常駐容器、不隨頁面離開釋放。
- 建議：首頁預覽改用精簡 provider（只取 id/name/cover/trackCount）；全量列表維持 watch 但標註僅歌單管理頁使用。

### A3　`LyricsTitleParseCache` 無上限／無淘汰，依 `trackUniqueKey` 無限成長（本面向優先）
- 嚴重度：🟡 Medium　工作量：L　[未個別驗證]
- 證據：`lib/data/repositories/lyrics_title_parse_cache_repository.dart:19-45`（`save()` 以 `trackUniqueKey` 寫入，repo 僅提供 `clear()` 全清，無 LRU/數量上限/過期淘汰）；`lib/services/lyrics/lyrics_auto_match_service.dart`（auto-match 對未命中歌曲呼叫 `save()`，隨曲庫擴大持續累積）。
- 影響：每播放一首歌就可能新增一筆；長年使用後 Isar 檔與 `lyricsTitleParseCaches` collection 單調成長，`compactOnLaunch` 無法回收仍被引用的空間。
- 建議：在 `save()` 或啟動加入淘汰（保留最近 N 筆或近 X 天），或在設定頁提供「清理歌詞解析快取」入口與自動上限（仿歌詞 LRU 的 `setMaxCacheFiles` 模式）。

### A4　`playHistorySnapshotProvider` 一次載入最多 1000 筆歷史並隨每次 watch 重建
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/data/repositories/play_history_repository.dart:253-267`（`loadHistorySnapshot()` 內 `queryHistory(... limit: 1000)`）；`lib/providers/library/play_history_provider.dart:9-18,81-102`（`playHistorySnapshotProvider` 為 `StreamProvider.autoDispose`，每次觸發都重載；`filteredPlayHistoryProvider` 再 `List.from` + 多次 `where`/排序，產生多份 1000 筆副本）。
- 影響：歷史頁開啟時記憶體同時存在 snapshot、filtered 副本、grouped map 等多份上千筆物件，filter/排序每次 tick 重建；重度用戶的歷史頁是 CPU+記憶體尖峰。
- 建議：把篩選/排序下推到 `queryHistory`（已有 `sourceTypes/startDate/endDate/searchKeyword` 參數）避免副本；snapshot 改分頁增量。

### A5　`download_service._cleanupActiveTask` 不刪 `.part` 暫存，僅 promote 路徑會刪（本面向優先）
- 嚴重度：🟡 Medium　工作量：M　[未個別驗證]
- 證據：`lib/services/download/download_service.dart:990-1036`（`_cleanupActiveTask` 只移除 isolate/cancelToken 並 kill isolate，未刪 `task.tempFilePath`；只有 promote 成功路徑 `:1231` 才 `tempFile.delete()`）；`:766-780`（啟動時才檢查並刪既有 tempPath，代表任務已離開佇列時舊 `.part` 會殘留）。
- 影響：暫停/取消/崩潰/手動刪 task 時，下載暫存目錄可能殘留部分寫入的音訊檔，長期累積佔用磁碟；無啟動期孤兒掃描。
- 建議：`_cleanupActiveTask` 與 `_finalizeTaskCleanup` 在任務不恢復續傳時刪 `task.tempFilePath`；`downloadServiceProvider.initialize()` 增加一次孤立 `.part` 掃描清理（比對現存 `DownloadTask.tempFilePath`）。

### A6　`AudioStreamManager.dispose()` 為空實作
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/services/audio/audio_stream_manager.dart:47`（`void dispose() {}`）；`lib/services/audio/audio_provider.dart:528-551`（`AudioController.dispose()` 呼叫 `_queueManager.dispose()` 與 `_audioService.dispose()`，未呼叫 `AudioStreamManager.dispose()`）。
- 影響：目前不持有需釋放資源，但空 dispose 留下未來洩漏隱患（若加入 StreamSubscription/Buffer 不會被清理）。
- 建議：若刻意為空加註釋說明；否則補 dispose 鉤子並由 `AudioController.dispose()` 統一呼叫。

### A7　`AppLogger._logBuffer.removeAt(0)` 為 O(n)；廣播 StreamController 永不關閉
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/core/logger.dart:57-62,211-215`（`_logBuffer` 為 `List<LogEntry>`，`_maxBufferSize=500`，超出用 `removeAt(0)` — O(n) 搬移）；`:62,115`（`_logStreamController = StreamController.broadcast()` 為 `static final`，無 `close()`）。
- 影響：高頻 debug 日誌下每筆觸發 500 元素 List shift。
- 建議：改 `Queue<LogEntry>` + `removeFirst()`（O(1)）或環形緩衝；StreamController 為單例可維持，但加註釋說明刻意不關閉。

### A8　`lyricsCacheServiceProvider` 為常駐 Provider，未掛 `onDispose` 釋放
- 嚴重度：🟢 Low　工作量：M
- 證據：`lib/providers/lyrics/lyrics_provider.dart:55-65`（非 autoDispose，建構時 `service.initialize()`）；`lib/services/lyrics/lyrics_cache_service.dart:332-337`（`dispose()` 存在但只在被呼叫時保存 pending access times；provider 端未見 `ref.onDispose` 觸發 `service.dispose()`）。
- 影響：dispose 路徑未接通，App 關閉/熱重載時 pending access times 可能未寫回 `_metadata.json`，造成 LRU 順序飄移。
- 建議：`lyricsCacheServiceProvider` 加 `ref.onDispose(()=> service.dispose())`；其他單例 service provider（lrclib/netease/qqmusic）若持有 Dio/client 亦同。

### A9　release 模式 `AppLogger` 仍逐筆建立 `LogEntry` 並常駐 500 條
- 嚴重度：🟢 Low　工作量：S
- 證據：`lib/core/logger.dart:220-238`（`_log()` 每筆建立 `LogEntry` 並 `debugPrint`；release `_minLevel=info` 仍記錄 info 以上）；`lib/ui/pages/settings/log_viewer_page.dart`（log viewer 消費 `logs` getter，release 也常駐 500 條）。
- 影響：release 中 info 級日誌持續生成物件與字串拼接（含 `redactSensitive` 的多個 RegExp `replaceAll`），累積 GC 壓力。
- 建議：release 將 `_minLevel` 提至 `warning`，in-memory buffer 縮減（如 100），並對 redact 正則做條件包裝。

### A10　`LyricsWindowService` 單例 + 隱藏不銷毀視窗，桌面歌詞子視窗 engine 常駐
- 嚴重度：🟢 Low　工作量：M　[待確認：實際 engine 成本視 `desktop_multi_window`/`WindowController` 而定]
- 證據：`lib/services/lyrics/lyrics_window_service.dart:98-115,106`（`static final instance` 單例；視窗「關閉時隱藏而非銷毀」，僅持有一個 `_windowChangeSub`）。
- 影響：隱藏視窗持續佔用獨立 Flutter engine 與渲染資源（桌面端）。
- 建議：提供「關閉即銷毀」選項，或長時間未顯示時自動銷毀並再次開啟時重建；記錄選擇隱藏的效能理由。

## 3. 具體建議（可驗收）

1. **下載暫存治理（A5 + A1 殘留）：** 啟動期孤立 `.part` 掃描 + `_cleanupActiveTask` 刪 temp。驗收：模擬取消/崩潰後重啟，下載目錄無 `.part` 殘留。
2. **歌詞解析快取上限（A3）：** `save()` 加 LRU/上限（如 500 筆或 30 天）。驗收：播放 2000 首後 `lyricsTitleParseCaches` 不超過上限。
3. **歷史頁查詢下推（A4）：** 篩選/排序改走 `queryHistory` 參數。驗收：歷史頁開啟時記憶體不再出現多份 1000 筆副本（DevTools memory snapshot）。
4. **歌單精簡 provider（A2）：** 首頁改用 summary provider。驗收：首頁不持有完整 trackId 清單。
5. **dispose 接線（A6/A8/A7/A9）：** 補 `onDispose`、改 Queue、release 提 level。

## 4. 本面向優先級 Top 3

1. **A3** — `LyricsTitleParseCache` 無上限淘汰（唯一跨 session 無上限成長點）
2. **A5** — 下載 `.part` 暫存清理 + 啟動期孤兒掃描（磁碟洩漏，使用者可見的磁碟占用）
3. **A4** — 歷史頁 1000 筆重載與多份副本（重度用戶的 CPU/記憶體尖峰）

> 註：原 Top 候選 A1 經對抗驗證撤回（啟動清理已存在），故以 A4 遞補。
