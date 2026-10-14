# 曲目詳細（M3b PR 21）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §21、design §4.7、§11.2）。依據 ADR 0028（`trackDetail`）。舊版參考：`lib/data/models/video_detail.dart` 與舊版的詳細面板。

M3b 的最後一個 PR。

**拆分**（主對話決定）：
- **21（這個 PR）**：宿主、`fmp-test`、詳細資料區，另外修一個小地方（見第 5 項）。
- **21-plugins**：`fmp-plugins` 三個插件的 `trackDetail`，另開一個 PR；fixture 由主對話以匿名真實連線錄。

## 要做的

1. **宿主**（design §4.7）
   - `SourcePlugin.trackDetail({sourceId, cid?})` 回傳 `TrackDetail`：
     - `description?`
     - `publishedAt?`：UTC epoch 毫秒
     - `uploaderAvatar?`：`Artwork[]`
     - `album?`
     - `stats?`：`[{kind, count}]`
   - 欄位都可以是 `null` 或不給。
   - `stats.kind` 是封閉 union：`view`、`like`、`favorite`、`comment`、`share`、`danmaku`、`coin`。
     - Dart 端用列舉。
     - 不認得的 `kind` 整筆拒收（形狀錯），不能悄悄丟掉。
     - `count` 是非負整數。
   - `uploaderAvatar` 的網域檢查照現有的 `Artwork`。
   - 沒宣告 `trackDetail` 時拋 `Unsupported`；匯出名稱就是 `trackDetail`。
   - 一併補上：d.ts、`type_definitions_test.dart`（`stats.kind` 的 union 要對到 Dart 的列舉）、`checks.json` 的 `trackDetail` 案例（接到四個執行器）。
2. **`fmp-test`**
   - 一首曲目有完整的詳細資料：每個欄位都有，`stats` 七種都有。
   - 另一首的 `trackDetail` 失敗，例如拋 `NetworkError`，用來看重試。
   - 用哪個關鍵字或哪首寫進 README。
   - `checks.json` 加 `trackDetail` 案例。
3. **詳細資料區**（design §11.2）
   - 位置：播放頁的「詳細」分頁，以及右側面板的 `TrackDetails`。
   - 插件宣告 `trackDetail` 時，在現有資料下方多顯示：
     - 簡介：可能很長，比照現有元件決定要不要收合，例如預設幾行加「展開」；
     - 發佈時間：依地區格式顯示；
     - 上傳者頭像；
     - 專輯；
     - 統計：依 `kind` 挑圖示與翻譯，人數用 CLDR 縮寫，和電台人數同一套格式；不顯示插件給的文字。
   - 資料取用：
     - 每首在第一次顯示詳細時呼叫一次；
     - 結果以曲目鍵放進記憶體 LRU，32 筆，不持久化。
   - 載入中與失敗：
     - 載入中顯示佔位；
     - 失敗只在詳細區顯示「無法取得詳細資料」和重試，不跳提示；
     - 沒宣告 `trackDetail` 時只顯示現有資料。
   - 直播時的詳細分頁照 18c，不呼叫 `trackDetail`。
   - 版面比照現有的 `TrackDetails` 與 ADR 0024，用最小的改動；需要新設計的區塊時停下回報。
   - i18n 三個語言都要補，包括七種統計的名稱。
4. **離線**：離線時不發請求，比照現有的離線處理；詳細區顯示離線狀態或沿用快取。
5. **小修正（PR 20 的實機與審查發現）**：分 P 標題等於 `P<index>` 時，`partLabel` 只顯示 `P<index>`，不重複成「P3 P3」。B 站插件在分 P 標題是空的時候就是給 `P<n>`。要補測試。
6. **文件**
   - `app/AGENTS.md`：§ 插件的 `trackDetail`、§ 介面。
   - 父 implement.md §21 打勾。

## 驗收（測試）

- **design §11.2 的 widget 閘門**：
  - 沒宣告時只顯示現有資料；
  - 有宣告時顯示新欄位；
  - 失敗時顯示重試，按了會重新取。
- **LRU**：
  - 同一首第二次顯示不再呼叫；
  - 第 33 筆會擠掉最舊的那一筆。
- **宿主**：
  - 形狀，包括不認得的 `kind`、負的 `count`、頭像網域不對；
  - 沒宣告時拋 `Unsupported`；
  - 宣告了卻少了匯出時拒絕載入；
  - d.ts 的 union 對 Dart 列舉；
  - `checks.json` 的 `trackDetail` 案例。
- **`partLabel`** 不重複。
- **guideline 測試**：詳細區（完整資料、失敗、載入中），寬 400 與 1000，淺色與深色。
- 每個新閘門都做雙向變異驗證並回報。
- **驗證清單**：
  - `dart format --output=none --set-exit-if-changed lib test tool integration_test packages`
  - `dart run slang`
  - `dart analyze --fatal-infos`、`flutter analyze`
  - `flutter test`

## 實機（主對話做）

- **重播**（`fmp-test`，Android）：播放頁的詳細分頁，看完整資料與失敗後重試。
- **右側面板**（Windows，只在桌面寬度出現）：依 2026-10-13 的規則，沒動平台層就不驗 Windows；寬度 1000 的 guideline 與 widget 測試涵蓋面板。這次改在 M3b 驗收時一起看。
- **真實**（三個音源匿名，21-plugins 合併後）：各看一次詳細。

## 不做

- 三個插件的 `trackDetail`（21-plugins）。
- 熱門評論（design §16 第 13 條）。
