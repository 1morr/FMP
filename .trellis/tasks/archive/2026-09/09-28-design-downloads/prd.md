# 設計：下載與權限（階段二第 11 項）

## 目標

為 `app/` 定下下載佇列與續傳、下載位置與檔案組織、檔案格式與內嵌標籤、下載與音樂庫的關聯、權限的統一入口。產出 ADR 0020。技術設計見 `design.md`，執行步驟見 `implement.md`。

依據：parent `prd.md` 階段二第 11 項；`docs/audit/questions.md` N1–N11、B13；`phase2-plan.md` §4 對 N2–N11 的方向（使用者按建議確認）；
ADR 0009（平台能力）、0012（媒體請求不帶憑證）、0014／0018（下載由宿主處理，經 `resolveStream`）、0017（下載事件驅動，不歸排程器）、0019（刷新移除曲目不刪下載）。
舊 ADR 0004（Android 不用 MediaStore、`MANAGE_EXTERNAL_STORAGE`＋裸路徑）描述舊專案。

## 現況（`research/current-state.md`，已以程式碼核對，另見 `docs/audit/downloads.md`）

- 每任務一個 isolate、原生 `HttpClient`（不走 dio）；事件驅動加 5 秒輪詢；並行預設 3（1–5）；進度 5% 門檻、只在記憶體。
- 續傳只送 `Range`，沒有 `If-Range`／ETag；回 200 才從頭（N4）。沒有自動重試；每次啟動清掉已完成與**失敗**的任務（N7）。
- 下載與播放共用音質設定（N5）；副檔名一律 `.m4a`（N6）；只有 sidecar（`metadata.json`、`cover.jpg`、`avatar.jpg`），沒有內嵌標籤（B13）。
- 檔案結構 `{根目錄}/{歌單名}/{來源id}_{標題}/P01.m4a`：**依歌單分資料夾，同一首歌在兩張歌單會下載兩份**；歌單改名不改資料夾（N3）。
- 啟動掃描以「資料夾名＝歌單名」重建關聯、掃不到就清路徑（N1 的資料遺失路徑）；播放時找不到檔案就永久清掉路徑（N9）。
- Android：`MANAGE_EXTERNAL_STORAGE`＋裸路徑；Android 上改下載路徑的 UI 被隱藏（N2）；權限走自有 MethodChannel（刻意避開 `permission_handler`：Windows 上會被顯示成使用位置權限）；
  沒有宣告 `POST_NOTIFICATIONS`（N10）。下載只在 App 行程內跑（N8）。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`）

- `background_downloader` 9.6.3（2026-09-25，活躍，160 分）：Android 用 WorkManager／UIDT 在背景繼續下載、iOS／macOS 用背景 URLSession；
  **桌面是純 Dart isolate，App 關掉就停、不產生通知**。支援自訂標頭、並行上限、重試與退避、暫停續傳（桌面以 ETag 驗證）。
  **下載到 SAF URI 時不能暫停續傳**。`flutter_downloader` 不支援桌面。
- Android 11+ 要以裸路徑寫入使用者看得到的資料夾，只有 `MANAGE_EXTERNAL_STORAGE`（Play 受限權限，FMP 不上架故可用）；SAF 免權限但要走 content URI。
  App 私有目錄卸載即刪。`POST_NOTIFICATIONS` 不豁免下載通知（只豁免媒體播放通知）。
- `permission_handler` 沒有 macOS／Linux 實作，Windows 為 no-op。
- 內嵌標籤：m4a、flac 有純 Dart 可寫的套件（`audio_metadata_reader` 等）；**WebM／Opus 幾乎沒有純 Dart 寫入方案**，只有小眾的 `flutter_taglib`，或走已退役的 FFmpegKit 分支（GPL、體積大）。
- 續傳唯一安全的做法是 `If-Range`／強 ETag；B 站、YouTube 的網址是時效簽名，過期必須重新解析。六個參考產品都沒有用 `If-Range`。
- 三家成熟產品（Finamp、Namida、NewPipe）以「資料庫記錄＋啟動對帳」管理下載與音樂庫的關聯。Windows 路徑預設有 260 字元上限。

## 已確定的方向

- 改用成熟套件（權限、背景下載）；Android 下載路徑可改並可重新授權；續傳要驗證；下載專用音質；副檔名照實際格式；
  失敗任務保留到使用者清除；權限統一入口；sidecar 保留並另外寫內嵌標籤；N1 在重寫時處理。

## 已決定

1. **檔案組織（2026-09-28 選 A′）**：每首歌只存一份，依音源分資料夾：`{根目錄}/{音源}/{標題} [{影片 id}].{副檔名}`；多分 P：`{根目錄}/{音源}/{影片標題} [{影片 id}]/P01 {分P標題}.{副檔名}`。「已下載」頁的歌單分類記在資料庫、不看資料夾。「依歌手分資料夾」已否決：B 站、YouTube 的歌手欄位其實是上傳者。舊下載保留原位，依 sidecar 認回。

2. **下載格式（2026-09-28 選 A）**：下載只接受可寫內嵌標籤的格式（m4a／flac／mp3），YouTube 下載取 AAC；播放不受影響。
3. 技術選擇（`design.md`）：`background_downloader`（Android 背景下載、桌面只在 App 執行中）；先下載到私有暫存、寫標籤後再搬到最終位置；
   續傳以 ETag 驗證、網址過期就重解析從頭下載；失敗任務保留；下載紀錄存絕對路徑、啟動對帳只標記不刪除；
   根目錄可改並選擇是否搬檔；權限經平台層統一入口；下載音質與播放分開。

## 驗收條件

- [ ] ADR 0020 記錄：下載引擎與佇列、續傳與重試、下載位置與權限、檔案組織與命名、格式與標籤、與音樂庫的關聯與對帳、刪除、平台差異。
- [ ] N1–N11、B13 各自對到決定。
- [ ] `phase2-plan.md` §3 第 11 項標 ✅ 與 ADR 編號。

## 不在範圍

- 下載頁版面（第 5 項）；邊聽邊存與已下載內容的容量管理（待辦）。
