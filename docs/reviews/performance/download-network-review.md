# Download / Network Performance Review

審查日期：2026-05-25

## 語料與判讀方式

規範性來源：
- `AGENTS.md`
- `lib/services/AGENTS.md`
- `lib/data/sources/AGENTS.md`
- `docs/README.md` 指向的 `docs/development.md`、`docs/build-guide.md`、`docs/build-and-release.md`、`docs/debugging-with-vm-service.md`

描述性補充來源：
- `.serena/memories/download_system.md`
- `.serena/memories/update_system.md`
- `.serena/memories/refactoring_lessons.md`

描述性內容只作線索，以下結論以程式碼與測試驗證為準。未修改程式碼，也未修改既有 `docs/reviews/performance/instruction-corpus.md`。

## Finding 1

Status: Confirmed issue

Evidence:
- `lib/services/update/update_service.dart:449` 使用 `File(zipPath).readAsBytesSync()` 一次讀入整個 Windows portable ZIP。
- `lib/services/update/update_service.dart:450` 以 `ZipDecoder().decodeBytes(bytes)` 解碼整包資料。
- `lib/services/update/update_service.dart:451-456` 逐 entry 以同步 `writeAsBytesSync(file.content as List<int>)` 寫出內容。

Trigger scenario:
- Windows 便攜版更新下載大型 `*-windows.zip`，或 ZIP 內含大型 DLL/資源檔。

User impact:
- 更新流程會把完整 ZIP 和解碼後 entry content 留在記憶體中，可能造成 RSS 峰值接近或超過更新包大小數倍。
- 同步解壓與同步寫檔在主 isolate 執行，可能造成 UI 卡頓；低記憶體裝置可能 OOM。

Suggested measurement or fix:
- 用 `docs/debugging-with-vm-service.md` 的 RSS / heap 快照，在下載前、解壓中、解壓後量測 Windows portable update。
- 將解壓移到 isolate，並優先改成串流或 chunked 解壓/寫檔；若目前 `archive` API 難以真正串流，至少避免在 UI isolate 做同步解壓與同步寫檔。

Instruction docs accuracy notes:
- `docs/build-and-release.md` 與 `.serena/memories/update_system.md` 描述「下載 ZIP、解壓、替換」正確，但沒有揭露目前解壓會整包讀入記憶體。這是描述完整度問題，不是規範衝突。

## Finding 2

Status: Confirmed issue

Evidence:
- `lib/services/download/download_service.dart:805-812` isolate progress 只寫入 `_recordProgressUpdate()` 的記憶體 pending map。
- `lib/services/download/download_service.dart:1048-1056` 暫停/失敗時 `_saveResumeProgress()` 寫入 DB 的 `progress` 與 `totalBytes` 仍取自舊 `task.progress` / `task.totalBytes`。
- `lib/ui/pages/settings/download_manager_page.dart:328-340` UI 沒有記憶體進度時會 fallback 到 DB 的 `task.progress`、`task.downloadedBytes`、`task.totalBytes`。
- `test/services/download/download_service_phase1_test.dart:69-89` 與 `:93-123` 覆蓋 buffered progress 會被清掉，但未驗證 pause/failure 後 DB 進度百分比與 total bytes 正確保存。

Trigger scenario:
- 大檔下載到 40% 後使用者按暫停，或網路中斷導致失敗；之後重新打開下載管理頁或重啟 App。

User impact:
- 續傳本身會因 temp file length 而可用，但下載管理 UI 可能顯示 `0.0%` 或缺少總大小，只顯示舊百分比。
- 使用者會誤判下載進度遺失；重啟後尤其明顯。

Suggested measurement or fix:
- 在 service 內保留每 task 最新 `(progress, downloadedBytes, totalBytes)`，`_saveResumeProgress()` 優先使用它；或以 temp file length 和最後已知 total 重算。
- 補 regression test：模擬 progress event 後 pause/failure，確認 DB 的 `progress`、`downloadedBytes`、`totalBytes` 都更新。

Instruction docs accuracy notes:
- `lib/services/AGENTS.md` 與 `.serena/memories/download_system.md` 說 progress 先留在記憶體、完成/暫停/失敗再落 DB。方向正確，但目前程式只可靠保存 downloaded bytes，百分比與 total bytes 的描述不完全符合實作。

## Finding 3

Status: Suspected issue

Evidence:
- `lib/services/download/download_service.dart:1533-1535` isolate 下載只設定 `HttpClient.connectionTimeout`。
- `lib/services/download/download_service.dart:1562` 等待 `request.close()`，`lib/services/download/download_service.dart:1607-1632` 以 `await for (final chunk in response)` 持續讀取，未看到 receive/idle timeout。
- `lib/services/download/download_service.dart:1586-1591` HTTP `>= 400` 直接回報錯誤。
- `lib/services/download/download_service.dart:930-937` `_startDownload()` 捕捉錯誤後直接標記 failed；`lib/services/download/download_service.dart:575-588` 只有手動 retry。

Trigger scenario:
- CDN 連線建立後長時間不再傳資料、5xx transient failure、SocketException，或行動網路短暫切換。

User impact:
- stalled response 可能長時間占用一個 concurrent download slot。
- transient failure 會立即變 failed，需要使用者手動 retry；大量佇列下載時體感可靠性差。

Suggested measurement or fix:
- 用本地測試 server 建立「送出 headers 後停止送 chunk」案例，確認 active download slot 是否會卡住。
- 加入 per-read idle timeout 與有限次 backoff retry；retry 時保留 `.downloading` temp file 並用 Range 續傳。5xx、SocketException、TimeoutException 可重試，4xx/rate-limit/auth 類錯誤應保留語義。

Instruction docs accuracy notes:
- `lib/data/sources/AGENTS.md` 對 source API 有 retry/fallback 語義，但 download media path 沒有明確規範是否要自動 retry。建議文檔補清楚「媒體下載 transient retry」的目標行為。

## Finding 4

Status: Suspected issue

Evidence:
- `lib/services/download/download_service.dart:1287-1290` cover download 直接使用 `track.thumbnailUrl!`。
- `lib/services/download/download_service.dart:1303-1306` avatar download 直接使用 `videoDetail.ownerFace`。
- `lib/core/utils/thumbnail_url_utils.dart:1-4` 說明 URL 最佳化可降低網路傳輸、磁碟快取與記憶體使用。
- `lib/core/services/image_loading_service.dart:119-122` UI 圖片載入會透過 `ThumbnailUrlUtils.getOptimizedUrlCandidates()`，但 download metadata image path 未使用同樣策略。

Trigger scenario:
- 下載大量 Bilibili / YouTube tracks，原始封面是高解析圖或 `maxresdefault`，且設定為下載 cover/avatar。

User impact:
- 每首歌的 metadata image 可能下載比本地顯示需求更大的圖片，增加下載時間、磁碟占用與圖片解碼成本。

Suggested measurement or fix:
- 統計 100 首混合來源下載時，直接 URL 與 optimized URL 的 cover/avatar 平均 bytes、P95 bytes、失敗率。
- 若本地 metadata 不要求保存原圖，下載時使用 `ThumbnailUrlUtils` 的候選 URL，cover 可用 480 或 640 級距，avatar 可用 200 左右；失敗再 fallback 原 URL。

Instruction docs accuracy notes:
- `lib/services/AGENTS.md` 只規範 downloaded metadata images 必須使用 `buildDownloadImageHeaders()`，這點目前符合。
- `Image Thumbnail Optimization` 章節描述平台最佳化，但沒有明確說 metadata download 也要套用；若要修此問題，應補充該章或 Download System 章節。

## Finding 5

Status: Suspected issue

Evidence:
- `lib/providers/update_provider.dart:124-131` update progress callback 在 operation 已過期時只忽略 state update。
- `lib/providers/update_provider.dart:189-193` `reset()` 只遞增 `_operationId` 並重設 state。
- `lib/services/update/update_service.dart:364-368`、`:404-408`、`:434-438` 三種 update download 都沒有 `CancelToken`。
- `test/providers/update_provider_test.dart:33-56` 驗證 reset 後 late progress/completion 不覆寫 state，但沒有驗證底層 Dio 下載被取消。

Trigger scenario:
- 使用者開始下載更新後關閉對話框、reset 狀態，或 provider lifecycle 變化導致舊 operation 失效。

User impact:
- UI 不再顯示進度，但底層下載可能繼續耗用網路、磁碟和電量；再次開始更新時可能與舊下載競爭同一路徑。

Suggested measurement or fix:
- 增加可注入 `CancelToken`，`reset()` / dispose 時取消 in-flight download。
- 測試用 fake Dio 或 mock service 驗證 reset 會取消底層請求，而不只是忽略 late callback。

Instruction docs accuracy notes:
- `.serena/memories/update_system.md` 和 `docs/build-and-release.md` 未描述更新下載取消語義；目前文檔不算錯，但缺少 lifecycle/resource policy。

## Finding 6

Status: Needs profiling

Evidence:
- `lib/services/download/download_service.dart:1618-1630` isolate 每 5% 或完成時發 progress message。
- `lib/services/download/download_service.dart:269-279` 主 isolate 每 1000ms flush 一次 pending progress。
- `lib/services/download/download_service.dart:132-140` 與 `:282-301` pending progress map 有 256 task 硬上限。
- `lib/providers/download/download_providers.dart:169-174` UI 可用 task-scoped provider 只 watch 單一 task progress。

Trigger scenario:
- 最大 5 個 concurrent downloads 同時下載非常小或非常快的檔案，或 server 使用大量小 chunk。

User impact:
- 從靜態審查看，progress 更新已被 5% 門檻、1 秒 flush 和 task-scoped provider 控制，過頻風險偏低；但仍需要 runtime timeline 才能確認下載管理頁沒有 rebuild/jank。

Suggested measurement or fix:
- 在 profile mode 下同時下載 5 個檔案，開啟下載管理頁，收集 VM Timeline、Widget build profiling、RSS。
- 若仍有 jank，再調整 flush 間隔或只對 visible task tile 觸發 progress view update。

Instruction docs accuracy notes:
- `lib/services/AGENTS.md` 與 `.serena/memories/download_system.md` 關於「progress 保存在記憶體、避免 Isar watch churn / Windows PostMessage overflow」與實作一致。

## 已核對且未列為 finding

- 大型音訊下載未整檔載入記憶體：`lib/services/download/download_service.dart:1607-1616` 逐 chunk 寫入 sink，final promotion 也用 `openRead().pipe()`，見 `lib/services/download/download_service.dart:1202-1204`。
- 並發下載限制有設定與修復路徑：`lib/data/models/settings.dart:149-150` 預設 3，`lib/ui/pages/settings/settings_page.dart:1228-1234` UI 只允許 1-5，`lib/providers/database_provider.dart:85-89` 修復異常值，`lib/services/download/download_service.dart:337-349` scheduler 依 `maxConcurrentDownloads` 啟動任務。
- 下載 media/image headers 的安全邊界大致正確：`lib/services/download/download_media_headers.dart:4-24` 轉交 `SourceHttpPolicy`，`lib/data/sources/source_http_policy.dart:57-67` 只對 allowlisted HTTPS Netease media URL 附加 credential，image path 則 `includeCredentials: false`。
