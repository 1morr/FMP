# 舊專案（現行 FMP）下載與權限現況

- **查證日期**：2026-09-28
- **查證方式**：唯讀原始碼審查。讀 `lib/`（Dart）、`android/app/src/main/`（Kotlin + Manifest），
  逐條核對 `docs/audit/downloads.md` 的敘述是否與現行程式碼一致。**未執行 app、未打真實 API、
  未跑 `flutter test`、未做實機驗證。**
- **範圍**：舊專案（repo 根目錄 `lib/`）；不含 `app/` 新專案。
- **標記約定**：`檔案:行號` 為現行 `docs/audit` 分支上的行號；推論一律標「**推測**」；
  程式碼查不到答案的寫「**查不到**」；`docs/audit/downloads.md` 的敘述若與程式碼不一致會註明。
- **既有資料**：`docs/audit/downloads.md`（396 行）與 `docs/audit/questions.md` 已對同一主題做過
  審計。本檔的價值在於**獨立核對**（行號可能與那份不同）與補上那份沒寫到的點。

---

## 0. 一頁摘要（端到端鏈路）

1. 使用者從歌單詳情頁按「下載」→ `playlist_detail_page.dart:967`（整張歌單，`addPlaylistDownload`）
   或 `:1043`（選取曲目，`addTracksDownload`）。
2. `DownloadService` 建 `DownloadTask` 寫入 Isar，狀態 `pending`，再觸發排程器。
3. 排程器每 5 秒輪詢一次，最多同時 `maxConcurrentDownloads` 個；每個任務開一個 **isolate**。
4. isolate 內用原生 `HttpClient` 抓位元組（**不走 Dio**），寫入 `{savePath}.downloading` 暫存檔。
5. 下載完成後 promote 成正式檔名，寫 sidecar（`metadata.json` / `cover.jpg` / `avatar.jpg`），
   DB 交易一次寫入 track 的下載路徑 + 任務 `completed`。
6. 播放時由 `Track.playlistInfo` 的下載路徑判斷是否為本機檔。
7. 使用者在「下載管理」頁暫停／續傳／重試／取消，或在下載頁刪除已下載分類／曲目。

---

## 1. 佇列與並行

| 事實 | 證據 |
|---|---|
| 下載由 `DownloadService` 統一管理，任務持久化在 Isar `DownloadTask` | `lib/services/download/download_service.dart:201`（`initialize`）、`lib/data/models/download_task.dart:25-107` |
| 狀態機 5 態：`pending / downloading / paused / completed / failed` | `lib/data/models/download_task.dart:6-21` |
| 併發上限來自設定 `maxConcurrentDownloads`，**預設 3**，可調 1–5 | `lib/data/models/settings.dart:281`（`= 3`）、`lib/providers/download/download_settings_provider.dart:81-88`（`setMaxConcurrentDownloads`，值域 1–5）、`download_service.dart:426` |
| 排程器是**事件驅動 + 5 秒 fallback 輪詢** | `download_service.dart:403`（`Timer.periodic(Duration(seconds: 5))`）；事件驅動觸發點見 `:398`、`:404`（任務狀態變更後呼叫 `_scheduleDownloads`） |
| 排程邏輯：取 `downloading` 數量，補足到上限，從 `pending` 依 `priority` 升冪取 | `download_service.dart:420-456`；狀態查詢 `lib/data/repositories/download_repository.dart:99-105`（`getTasksByStatus` 按 priority 排序） |
| 新任務的 priority 由 `getNextPriority()` 遞增產生 | `download_service.dart:576-585`；`download_repository.dart:338-344` |
| 同一 track 已存在下載任務時會被跳過（去重） | `download_service.dart:507-519`（比對已下載／已存在）、`:553-586`（`getTasksBySavePaths` 去重後才建） |
| 佇列上限的防護集合：`_discardedTaskIds` / `_tasksInSetupWindow` / `_setupAbortedTasks` / `_externallyCleaned` | `download_service.dart:83-92` |

**觀察**：任務的排序鍵是 `priority`（單調遞增整數），沒有使用者可見的「置頂／順序調整」介面 ——
下載管理頁只有 pause/resume/retry/cancel 與 pauseAll/resumeAll/clearCompleted/clearQueue
（`download_manager_page.dart:32-83, 401-420`）。**推測**：實務上等於 FIFO。

---

## 2. Isolate 模型

| 事實 | 證據 |
|---|---|
| **每個下載任務開一個 `Isolate`**（非 pool，非背景 isolate 常駐） | `download_service.dart:818`（`Isolate.spawn`） |
| isolate 與主 isolate 以 `SendPort`/`ReceivePort` 通訊，訊息型別 `ready / progress / completed / error`（另有 `cancelled` 字串） | `download_service.dart:922`（`_drainIsolateMessages`）、`download_service.dart:1794-1795`（isolate 內送 `ready` + cancel port） |
| isolate 內用原生 `HttpClient()`，**不是 Dio** | `download_service.dart:1819`（`client = HttpClient()`）；`:1820`（`connectionTimeout`） |
| Dio 在下載服務中**只用來抓封面／頭像圖**，不是抓音訊 | `download_service.dart:192-198`（`BaseOptions`，`receiveTimeout` 30 分鐘）；`:1601-1622`（`_dio.download` 抓圖） |
| 手動重導向迴圈，最多 5 次，每次都檢查 scheme 與 private host（SSRF 防護） | `download_service.dart:1831-1890`；起點允許本機、只擋公網跳內網，見 `:1808-1814` |
| 用 `File.open(mode: append/write)` 而非 `openWrite()`，以避免 Android scoped storage 拒寫時產生未處理 async error 殺掉 isolate | `download_service.dart:1913-1915` 與上方註解 `:1905-1911` |
| 每個 chunk 套 30 秒接收逾時（`response.timeout`），避免 CDN 半開連線永久卡住 | `download_service.dart:1928-1930`；註解說明無自動化測試、只能真的等 `:1923-1927` |
| 取消是合作式：主 isolate 送 cancel，isolate 檢查 `isCancelled` 後自行收尾 | `download_service.dart:1787-1791`（cancel port 監聽）、`:1866-1872`（迴圈中檢查） |

**風險點（推測）**：每個任務一個 isolate，同時 3 個下載即 3 個 isolate；isolate 內沒有
獨立的重試，失敗即整個任務失敗（見 §5）。開 isolate 的成本在行動裝置上不算免費，
但現行併發上限 ≤ 5，**推測**影響可接受。

---

## 3. 進度回報

| 事實 | 證據 |
|---|---|
| isolate 內**每累積 5%** 才送一次進度（`downloadProgressUpdateThreshold`），完成時補送 100% | `download_service.dart:1941-1955` |
| 主 isolate 把進度寫入記憶體 map `_pendingProgressUpdates`，**不寫 DB** | `download_service.dart:133`、`:367-387`（`_recordProgressUpdate`） |
| 記憶體 map 上限 256 筆，超過時丟棄最舊的 | `download_service.dart:377-387`（`_pendingProgressUpdateLimit`） |
| 每秒 flush 一次到 `progressStream`（`Timer.periodic` 1000ms） | `download_service.dart:354-357` |
| `totalBytes` 另存 `_knownTotalBytes`（暫停時算續傳進度用） | `download_service.dart:143`、`:371` |
| 進度事件型別 `DownloadProgressEvent`，由 provider 轉成 UI 狀態 | `download_service.dart:99`（`progressStream`）；`lib/providers/download/download_providers.dart`（`downloadProgressStateProvider`，in-memory map） |
| 完成時（isolate 收尾）才把 `progress/totalBytes` 落 DB | `download_service.dart:1219-1253`（`_saveResumeProgress`）、`:1237`（取 `_knownTotalBytes`） |

**設計取捨**：進度有意不寫 DB，避免每秒的寫入風暴。代價是 app 被殺掉後，
進度只剩最後一次落 DB 的值（`_saveResumeProgress` 的觸發點），
**推測** UI 上可能出現進度回退。

---

## 4. 續傳（resume）

| 事實 | 證據 |
|---|---|
| `canResume` = `tempFilePath != null && downloadedBytes > 0` | `lib/data/models/download_task.dart:98` |
| 暫存檔路徑 = `{savePath}.downloading` | `download_service.dart:1092`（`tempPath = '$savePath.downloading'`） |
| 只有在 `canResume && tempFilePath == tempPath && 暫存檔存在` 時才真的續傳，否則重抓 | `download_service.dart:1112-1122` |
| 續傳請求只加 `Range: bytes=N-`，**沒有 `If-Range`、沒有 ETag、沒有 `Content-Range` 驗證** | `lib/services/media/media_handoff.dart:54-62`（`prepareDownloadHop` 只加 `mediaHeaders` + 條件式 `Range`） |
| 若伺服器回 **HTTP 200**（不是 206），自動改成從 0 重寫 | `download_service.dart:1904-1906`（`shouldRestartFromZero`）、`:1918-1919`（`totalBytes` 重算） |
| 續傳時開檔模式 `append`，重寫時 `write` | `download_service.dart:1913-1915` |

**核心風險**：伺服器回 206 但**檔案內容其實已變**（同 URL 不同位元組）時，現行邏輯
無法察覺 —— 因為沒有 `If-Range`／ETag 比對，只有「200 就重來」這一道粗糙防線。
這正是 owner 在 `phase2-plan.md` 要求「resume 必須驗證 If-Range/ETag」的由來。
**推測**：Bilibili / YouTube CDN 對同一 URL 的位元組通常穩定，但 signed URL 換發後
URL 會變，理論上由「URL 變了就查不到舊暫存檔」擋掉一部分；真正會出事的是
URL 不變而內容變的少數情形（例如直播回放轉檔完成）。

---

## 5. 失敗與重試

| 事實 | 證據 |
|---|---|
| 錯誤分成型別：`timeout / network / http / filesystem / unknown`（isolate 內以 JSON 字串回傳，主 isolate 解回例外） | `download_service.dart:1348-1373`（`_isolateFailure`）、isolate 端錯誤分支 `:1965+` |
| 使用者可見訊息是**已翻譯字串**（`_failureMessageFor`），存進任務 `errorMessage` | `download_service.dart:1380-1385`、`:1388-1407`（`_handleDownloadFailure`） |
| HTTP >= 400 直接當失敗，訊息 `HTTP {code}` | `download_service.dart:1892-1901` |
| `retryTask` 會**先刪掉舊檔與暫存檔**再重排 | `download_service.dart:679-692`、`:1299-1344`（重試前刪檔）、`:1263-1293`（`_deleteTaskFiles`） |
| 失敗任務**保留在佇列**，不會自動消失（符合 owner 要求「失敗任務保留到使用者清除」） | 任務僅在 `clearCompletedAndErrorTasks`／`clearQueue` 時移除：`download_repository.dart:66-96`、`:306-315`；`initialize()` 會清 `completed + failed`：`download_service.dart:207-208` |
| HLS（m3u8）串流被明確拒絕，不會嘗試下載 | `download_service.dart:1065-1070` |
| 沒有自動重試／退避（no auto-retry / backoff） | 全檔未見重試迴圈；`retryCount` 只出現在**串流解析**層（`stream_resolution_service.dart:167`），不是位元組下載層 |

**注意**：`initialize()` 在每次啟動時清掉 `completed + failed` 任務（`download_service.dart:207-208`），
同時 `resetDownloadingToPaused()` 把 `downloading` 與 `pending` 都重設成 `paused`
（`download_repository.dart:258-273`）。**推測**：這是「重開 app 後失敗清單消失」的原因；
若新專案要求失敗任務跨重啟保留，這行為要改。

---

## 6. 下載路徑：選擇、儲存、變更

| 事實 | 證據 |
|---|---|
| 自訂下載目錄存 `Settings.customDownloadDir` | `lib/data/models/settings.dart:250` |
| 是否已設定：`hasConfiguredPath()` | `lib/services/download/download_path_manager.dart:25-29` |
| 選目錄流程：Android 先要權限 → `FilePicker.getDirectoryPath()` → 用 `.fmp_test` 檔寫入後刪除**驗證可寫** | `download_path_manager.dart:34-56`；`:44`（getDirectoryPath）、`:48-53`（verifyWrite）、`:59-68`（.fmp_test） |
| 生效目錄：`getEffectiveBaseDir` | `download_path_manager.dart:87-88` |
| **Android 上「變更下載路徑」的 UI 被隱藏**（`if (!Platform.isAndroid)`） | `lib/ui/pages/settings/widgets/settings_storage.dart:60` |
| 預設目錄（各平台） | `download_path_utils.dart:187-216`（`getDefaultBaseDir`） |
| Windows 預設 = 應用文件目錄下的 `FMP`（即 `Documents\FMP`） | `download_path_utils.dart:214`；`lib/data/database/database_provider.dart:51`、`lib/services/logging/log_file_sink.dart:25`（同一目錄慣例） |
| 變更 base path 時**不搬檔、不掃描**，只是清空所有下載路徑 + 刪除 completed/failed 任務 + 存新路徑 | `lib/services/download/download_path_maintenance_service.dart:59-80`（`changeBasePathAndResetDownloads`） |
| 路徑逃逸防護：`isPathInsideBase` | `download_path_utils.dart:117-122`；在 `computeDownloadPath` 內強制 `:51-56` |

**Android 儲存策略**（見 §11）：MANAGE_EXTERNAL_STORAGE + 裸路徑，不用 MediaStore / SAF，
理由記在 ADR 0004。**推測**：因為不用 SAF，所以自訂目錄才需要「先要權限再 getDirectoryPath」，
而且預設目錄（app-specific external）本身免權限。

---

## 7. 檔名與資料夾結構

| 事實 | 證據 |
|---|---|
| 結構：`{baseDir}/{歌單名}/{sourceId}_{parentTitle}/P{NN}.m4a` 或 `.../audio.m4a` | `download_path_utils.dart:23-57`（`computeDownloadPath`）、檔頭註解 `:12`、`:18` |
| 子目錄：有歌單名用歌單名，沒有則用 `未分类` | `download_path_utils.dart:29-32` |
| 影片資料夾名：`{sanitizePathComponent(sourceId)}_{sanitizeFileName(parentTitle)}` | `download_path_utils.dart:34-36` |
| 多 P 影片：`P{pageNum 兩位補零}.m4a`；單 P：`audio.m4a` | `download_path_utils.dart:40-46` |
| **副檔名永遠硬編 `.m4a`**，與實際容器無關 | `download_path_utils.dart:42,44`；`download_path_maintenance_service.dart:596-600` 的註解明白承認：來源設定的 opus/aac「只決定串流容器」，檔名仍是 `.m4a` |
| 非法字元清理：9 個 Windows 非法字元換全形、trim、去尾點、Windows 保留名（CON/PRN/...）、200 字截斷 | `download_path_utils.dart:81-115`（`sanitizeFileName`）、`:124-156`（保留名） |
| sidecar 檔名常數 | `lib/core/constants/download_filenames.dart:14-33`（`cover.jpg` / `avatar.jpg` / `metadata.json`；`metadataCandidatesForAudio`：`P{N}` → `metadata_P{N}.json` 再退 `metadata.json`） |

**與 owner 要求對照**：owner 要求「副檔名要符合實際格式」。現況**不符** —— 一律 `.m4a`。

---

## 8. 附帶檔案（sidecar）

| 檔案 | 何時寫 | 證據 |
|---|---|---|
| `metadata.json` / `metadata_P{N}.json` | 下載完成後寫入曲目中介資料（標題、藝人、時長、sourceId、pageNum 等） | `download_service.dart:1499-1599`（`_saveMetadata`）；欄位 `:1509-1522`；檔名決策 `:1556-1559` |
| `cover.jpg` | 有封面 URL 時以 Dio 抓，尺寸 tier high | `download_service.dart:1567-1581`；抓圖 `:1601-1622`（`ImageTargetSizes.high`） |
| `avatar.jpg` | 僅在 `downloadImageOption` 選 coverAndAvatar 時，尺寸 tier low | `download_service.dart:1583-1598`（`ImageTargetSizes.low`） |
| **沒有歌詞 sidecar** | 下載流程不寫任何歌詞檔 | 全檔未見寫歌詞；歌詞是獨立的 lyrics cache 服務，不在下載目錄 |
| **沒有內嵌 tag（無 ID3／ffmpeg）** | `pubspec.yaml` 無任何 tag／metadata／ffmpeg 套件 | `pubspec.yaml`（依賴清單未見 audiotags / metadata_god / ffmpeg_kit 等） |

**與 owner 要求對照**：owner 要求 B13「保留 sidecar metadata/封面 + 加內嵌音訊 tag」。
現況是**只有 sidecar、沒有內嵌 tag**。內嵌 tag 需要新依賴（見 `packages-and-platform.md`）。

---

## 9. 下載目錄掃描同步（N1：資料遺失路徑）

| 事實 | 證據 |
|---|---|
| 啟動時觸發一次掃描同步 | `lib/app.dart:131`（`ref.watch(startupDownloadSyncProvider)`）；`lib/providers/download/startup_download_sync_provider.dart:9-40`（`syncLocalFiles`，catch + log） |
| `syncLocalFiles` 是 **REPLACE 模式**：掃描結果取代 DB 中的下載狀態 | `lib/services/download/download_path_sync_service.dart:26-232` |
| 重建 `playlistInfo` 時**只保留 `playlistName == 資料夾名` 的項目**，其餘丟棄 | `download_path_sync_service.dart:158-197`（`:158-199`） |
| 掃到但對不上任何曲目的資料夾，會以 `playlistId = 0` 加入 | `download_path_sync_service.dart:158-197` 後段 |
| 第三步：**把本機掃不到的曲目之下載路徑清空** | `download_path_sync_service.dart:214-224` |
| 配對邏輯：`cid → pageNum → true` | `download_path_sync_service.dart:234-272`（`_matchScannedDownload` / `_matchesScannedPage`） |
| 掃描只認 `.m4a`，且只在固定層數內遞迴 | `lib/providers/download/download_scanner.dart:223-233`（`_countAudioFilesInternal` 遞迴 `.m4a`）、`:305-313`（`scanFolderForTrackDto` 兩層） |
| 無 metadata 時的 fallback：用資料夾前綴當 sourceId，且 **sourceId 硬編 `SourceIds.bilibili`** | `download_scanner.dart:385-391` |
| 掃出的 `DownloadedTrackDto.toTrack()` 會把 `playlistId` 設 0，但保留 `sourceTypeName` | `download_scanner.dart:86-105` |
| `cleanupInvalidPaths` 是**死碼**（無呼叫者） | `download_path_sync_service.dart:313-318` |

**N1 資料遺失成因（推測鏈）**：REPLACE 模式 + 「掃不到就清路徑」+「只認特定資料夾名」
三者疊加。若使用者在 app 外改名／搬動資料夾，或來源改了 `parentTitle`，
下次啟動掃描就會把該曲目的下載路徑清成 null。`docs/audit/downloads.md` 已確認呼叫鏈，
但**未在實機重現**。owner 已在 `questions.md` 把此項標為
「`[x]` 先不修，重寫時處理」。

**與 owner 要求對照**：owner 要求 N1 的資料遺失路徑在重寫時處理。現況是**資料遺失路徑存在**。

---

## 10. 播放時的本機檔判斷（N9）

| 事實 | 證據 |
|---|---|
| 下載路徑掛在 `Track.playlistInfo`（`List<PlaylistDownloadInfo>`），每筆含 `playlistId/playlistName/downloadPath` | `lib/data/models/track.dart:11-33`、`:85`（`playlistInfo`） |
| 是否為本機檔：`isDownloadedForPlaylist(playlistId)` / `belongsToPlaylist` | `track.dart:156-158`、`:173-188` |
| 取路徑：`getDownloadPathForPlaylist` / byName | `track.dart:111-146`（`setDownloadPath` 同段） |
| 清除：`clearAllDownloadPaths`；`hasAnyDownload` / `allDownloadPaths` | `track.dart:193-205`、`:229-236` |
| 串流解析只有在 `purpose != download` 時才檢查本機檔 | `lib/services/audio/stream_resolution_service.dart:128` |
| **無效的本機路徑會被永久清除**（不是降級成遠端重抓就好） | `stream_resolution_service.dart:126-145`（invalid → 清 path） |
| 檔案存在性有正／負快取（各上限 5000），避免每次播放都打檔案系統 | `lib/providers/download/file_exists_cache.dart` |

**與 owner 要求對照**：owner 要求 N9（播放時如何判定本機檔）要在重寫時明確定義。
現況判定依據是 DB 中的路徑字串 + 檔案存在性快取，**不是**每次實際開檔驗證，
所以「檔案被外部刪掉」與「檔案存在」之間有一段快取窗口 —— **推測**會出現
「UI 說已下載、實際播放失敗」的短暫不一致。

---

## 11. 權限

### Android：自建 MethodChannel（刻意的，不用 `permission_handler`）

| 事實 | 證據 |
|---|---|
| MethodChannel 名稱 `com.personal.fmp/platform` | `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt:20-35`；Dart 端 `lib/services/platform/storage_permission_service.dart:25-28` |
| **刻意避開 `permission_handler`**：官方原因寫在 dartdoc —— Windows 上會讓 FMP 被顯示成使用「位置」權限 | `storage_permission_service.dart:22-24` |
| SDK < R（Android 11）時 `isManageExternalStorageGranted()` 直接回 true | `MainActivity.kt:62-65` |
| 要 MANAGE_EXTERNAL_STORAGE：先試 `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`，失敗再退到全域設定頁 | `MainActivity.kt:75-103` |
| 舊版權限清單：SDK < M 或 >= R 時回空 | `MainActivity.kt:125-136`（`legacyStoragePermissions`） |
| 開系統設定頁 `openAppSettings` | `MainActivity.kt:138-148` |
| Dart 端 `_manageExternalStorageStatus` **只回 granted / denied 兩態**，所以 `permanentlyDenied` 分支在 Android 上永遠走不到 | `storage_permission_service.dart:145-151` |
| `hasStoragePermission()` **在正式路徑沒有呼叫者**（只被測試用到） | `storage_permission_service.dart:69-77` |
| 說明對話框 + 「去設定」對話框 | `storage_permission_service.dart:180-241`、`:244-269` |
| `openInstallPermissionSettings` / `canRequestPackageInstalls`（APK 安裝權限） | `MainActivity.kt` 同檔另有實作 |

### AndroidManifest

| 權限 | 狀態 | 證據 |
|---|---|---|
| `MANAGE_EXTERNAL_STORAGE` | 有，帶 `tools:ignore="ScopedStorage"` | `android/app/src/main/AndroidManifest.xml:22-23` |
| `READ_EXTERNAL_STORAGE` | 有，`maxSdkVersion=32` | `AndroidManifest.xml:17-18` |
| `WRITE_EXTERNAL_STORAGE` | 有，`maxSdkVersion=29` | `AndroidManifest.xml:19-20` |
| `WAKE_LOCK` / `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PLAYBACK` / `INTERNET` / `ACCESS_NETWORK_STATE` | 有 | `AndroidManifest.xml:5-23` |
| `REQUEST_INSTALL_PACKAGES` | 有 | 同上 |
| **`POST_NOTIFICATIONS`** | **沒有宣告** | 主 manifest 與合併 manifest 皆未見；**推測** Android 13+ 上背景下載的完成通知不會顯示 |
| **`READ_MEDIA_AUDIO` / `READ_MEDIA_*`** | **主 manifest 沒有**；只在 `open_filex` 合併進來 | 主 manifest 未見，來源是 `open_filex` 的 transitive manifest |

**與 owner 要求對照**：owner 要「統一的權限入口」。現況是單一 service（`StoragePermissionService`）
但只涵蓋儲存權限，通知權限根本沒申請。ADR 0004 已「知情接受」MANAGE_EXTERNAL_STORAGE + 裸路徑；
owner 在新專案要求「Android 下載路徑可變更且可重新授權」—— 現況 Android 上該 UI 被隱藏（§6）。

---

## 12. 刪除

| 行為 | 入口 | 證據 |
|---|---|---|
| 刪除單一已下載曲目 | 下載分類頁 | `lib/ui/pages/library/downloaded_category_page.dart:723-724`（`deleteDownloadedTracks([track])`） |
| 批次刪除分類內曲目 | 下載分類頁 | `downloaded_category_page.dart:552-553` |
| 刪除整個已下載分類 | 下載頁 | `lib/ui/pages/library/downloaded_page.dart:467-469`（`deleteDownloadedCategory`） |
| 刪除前**先掃描**再刪，避免刪錯 | — | `download_path_maintenance_service.dart:82-116`、`:118-137` |
| base dir 解析失敗時的停用保護（`_resolveEffectiveBaseDir`） | — | `download_path_maintenance_service.dart:139-156` |
| 刪完清 DB 路徑 `_clearDeletedPaths` | — | `download_path_maintenance_service.dart:167+` |
| **孤兒 track 清理**：定義為「不在佇列 AND 沒有任何 `playlistId > 0` 的 playlistInfo」 | — | `lib/data/repositories/track_repository.dart:625`（註解）、`:635`（`deleteOrphanTracks`）、`:652-656`（判定） |
| 佇列管理器每 10 秒跑一次孤兒清理 | — | `lib/services/audio/queue_manager.dart:226-228`（`Timer(Duration(seconds: 10))` → `_cleanupOrphanTracks`）、`:830`（實作） |

**風險（推測）**：孤兒判定**不看 `Playlist.trackIds`**，只看 `playlistInfo`。
所以「已從歌單移除、但仍有 `playlistId>0` 的下載紀錄」的 track 不會被清；
反之若某 track 從未進過任何歌單而下載路徑被清空，就可能被判孤兒刪掉。
owner 已在 ADR 0019 決定「refresh 移除的曲目不刪下載」，此判定邏輯在重寫時要重新設計。

---

## 13. 下載音質（owner 明確要改的一項）

| 事實 | 證據 |
|---|---|
| **下載與播放共用同一個全域音質設定** `Settings.audioQualityLevelIndex`（高／中／低） | `lib/data/models/settings.dart:309`、`:513-534`（getter/setter）、`lib/services/audio/stream_resolution_service.dart:405`（`AudioStreamConfig.fromSettings`） |
| 下載的串流解析走 `StreamResolutionPurpose.download`，但**音質仍讀全域設定** | `download_service.dart:1047`（purpose: download）、`stream_resolution_service.dart:405` |
| 下載**刻意不重用**快取的解析結果（避免 5 分鐘 URL 失效） | `stream_resolution_service.dart:150-155` 與上方註解 |

**與 owner 要求對照**：owner 要求「下載專用音質」。現況**沒有**下載專用音質 —— 下載與播放同一個設定。

---

## 14. N1–N11／B13 與現況對照

> 完整題目定義見 `docs/audit/questions.md`。下表只把「現況一句話」補上。

| 項 | 現況一句話 | 本檔節 |
|---|---|---|
| N1 下載目錄掃描造成資料遺失 | REPLACE + 掃不到即清路徑；呼叫鏈確認、未實機重現 | §9 |
| N2 佇列與併發 | 5 秒輪詢 + 事件驅動；上限預設 3（1–5） | §1 |
| N3 進度回報 | 5% 門檻、記憶體、每秒 flush；不寫 DB | §3 |
| N4 續傳 | 只有 `Range`，無 `If-Range`／ETag；200 即重來 | §4 |
| N5 失敗與重試 | 5 類錯誤；手動重試；**無自動重試** | §5 |
| N6 內嵌 tag | **無**（無 tag／ffmpeg 依賴），只有 sidecar | §8 |
| N7 儲存位置（Android SAF vs 裸路徑） | MANAGE_EXTERNAL_STORAGE + 裸路徑（ADR 0004） | §6、§11 |
| N8 路徑變更 | 變更即清空所有下載路徑，不搬檔 | §6 |
| N9 播放時本機檔判定 | DB 路徑 + 存在性快取，非每次開檔 | §10 |
| N10 刪除 | 4 個入口，皆先掃描再刪 | §12 |
| N11 權限 | 自建 MethodChannel；只做儲存權限；通知權限缺 | §11 |
| B13 sidecar | metadata.json / cover.jpg / avatar.jpg；無歌詞 | §8 |

---

## 15. 查不到 / 未驗證

- **`POST_NOTIFICATIONS` 在 Android 13+ 的實際行為**：程式碼未宣告，也未申請；
  是否因 `audio_service` 的前景服務而豁免顯示，**查不到**（需實機）。
- **N1 資料遺失是否真的會在使用者操作下發生**：呼叫鏈已確認，**未在實機重現**（`downloads.md` 亦同）。
- **Bilibili / YouTube CDN 對 `Range` 的實際回應**（是否穩定回 206、是否回 ETag）：
  未打真實 API，**查不到**（新專案要用 `packages-and-platform.md` 的公開行為描述 + 實測補）。
- **`_dio` 抓封面失敗時的行為**（是否讓整個下載任務失敗）：程式碼有各自 catch，
  但**推測**不影響音訊檔完成（`_saveMetadata` 在 promote 之後），未逐行確認到 exception 邊界。
- **Windows 可攜版（portable）下載目錄**：現行一律用 `Documents\FMP`（§6），
  可攜版是否應改存自身資料夾是 **A4 開放問題**（`questions.md`），程式碼層面**尚未實作**。

---

## 16. 給新專案設計的三個硬約束（由現況推得）

1. **副檔名要跟實際容器一致**：現行硬編 `.m4a`（§7），新專案要改。
2. **下載要有自己的音質設定**：現行與播放共用（§13），新專案要拆。
3. **續傳要有 `If-Range`／ETag 驗證**：現行只憑 200/206 粗判（§4），新專案要補。
