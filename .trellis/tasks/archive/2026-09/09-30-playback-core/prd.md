# 播放核心最小集（M1 PR 10）

父任務：`../09-28-m1-skeleton-tracer`（implement「10.」；design 3.16 與「媒體 client」一列）。前一批：9a–9c 與遮蔽修正（#183–#186）。

依據：
- ADR 0018：決定 1–3、6 的 M1 部分，以及「如何確認」；
- ADR 0013：錯誤類別；
- ADR 0012：交給播放後端的 headers 經 `mediaRequestHeaders`；
- ADR 0009：平台層宣告後端與可播格式；
- ADR 0015：`fmp_layer_imports`，`just_audio`、`media_kit` 只在後端實作目錄。

## 做什麼

1. **`AudioBackend` 介面與兩個實作**：
   - `JustAudioBackend` 給 Android，`MediaKitBackend` 給 Windows；
   - 平台層以能力宣告選用哪一個，並宣告**可播格式**。Linux、macOS、iOS 照 ADR 0009 §決定 4 宣告「沒有播放能力」（原寫「只宣告」，與 ADR 衝突；以後用哪個後端寫在 `AudioBackendKind` 的 dartdoc）。
   - 不能收斂的差異寫進介面的 dartdoc。
   - 可收斂的規則寫成共用純函數，並有契約測試：
     - 結束原因分類；
     - 前瞻計畫。
   - 後端只持有「目前＋一個前瞻」。
   - 套件版本取 pub.dev 最新 stable，先查官方文件：
     - `just_audio` 怎麼做 gapless 與前瞻（`ConcatenatingAudioSource` 或新版的替代做法）、headers；
     - `media_kit` 的 playlist 或 prefetch、headers，以及 Windows 需要的 libs 套件。
2. **`PlaybackController`**：UI 唯一的播放入口，M1 只有這些操作：
   - 播放某一首（清單加起點）；
   - 播放、暫停；
   - 上一首、下一首；
   - seek。

   狀態：
   - 一份 sealed 播放狀態：`Idle`、`Loading`、`Playing`、`Paused`、`Buffering`、`Retrying`、`Failed(AppError)`；
   - 位置、時長、緩衝走獨立的 stream；
   - 協作者只回報、不寫狀態。
3. **`QueueModel`**：只在記憶體，只有 `queue` 模式，依序播放，不持久化（design 3.16）。
   - 介面照 ADR 0018，只做 M1 需要的部分，不寫空殼；
   - `QueueState` 與播放狀態沒有共同欄位。
4. **`StreamResolver`**：直接呼叫插件的 `resolveStream`（M1 沒有下載與網址快取）。
   - 輸入：`TrackKey`、平台可播格式、用途 `playback`。
   - 候選依優先序；開流失敗換候選一次。
   - 前瞻交接前檢查 `expiresAt`，過期就重新解析。
   - 交給後端的 headers 一律先經 `mediaRequestHeaders`。
5. **錯誤恢復的 M1 部分**（`RecoveryPolicy`，純函數）：
   - `Unavailable`、`NotFound`、需登入、`Unsupported`：跳過；
   - `NetworkError`、`RateLimited`：重試 1、3、9 秒共 3 次，再跳過；
   - 連續跳過達佇列長度就停止。

   M1 沒有 `Online` 偵測與提示 UI：失敗以狀態表達，提示在 PR 12 接 `Toaster`。
6. **Android 換歌時不釋放音訊焦點**（ADR 0018 §決定 3、§7 實測）。
7. **dev 的驗證入口**：
   - 用測試插件 `fmp-test` 的本機音檔，連續播兩首並記下交接；可選 B 站插件（見下）。
   - 形式可以是 `integration_test`、只在 dev 的入口，或只在 dev 顯示的身分頁按鈕，二擇一並寫明。
   - 不進正式路徑；PR 12 的 UI 上線後刪掉或保留，寫明。

## 驗收

- [ ] `app/` 驗證清單全過：format、build_runner 沒有實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、哨兵。
- [ ] 單元測試：
  - `QueueModel`：依序、上一首或下一首的邊界；
  - `RecoveryPolicy`：每一類錯誤；
  - 前瞻只解析一次；
  - 過期重新解析；
  - 換候選一次。
- [ ] 後端契約測試：同一份純規則斷言，跑兩個實作與假後端。真後端跑不了 `flutter test` 的部分，寫明改在 `integration_test` 或實機。
- [ ] 實機（主對話執行，§7）：
  - Windows 與 Android 模擬器用測試插件連續播兩首，第二首由前瞻接上；記錄交接的間隔。
  - Android 換歌時音訊焦點沒有被釋放（`dumpsys audio` 的焦點堆疊）。
  - 可選：用 B 站插件真實播放一首，確認 Referer 的 headers 有生效，屬 ADR 0027 允許的最少操作。
- [ ] `fmp_layer_imports` 擋得住後端套件出現在實作目錄以外，並有雙向變異驗證。
