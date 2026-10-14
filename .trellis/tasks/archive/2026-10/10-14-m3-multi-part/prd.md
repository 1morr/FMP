# B 站分 P（M3b PR 20）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §20、design §4.6、§11.1）。依據 ADR 0028（`multiPart`）、ADR 0005（曲目鍵含 cid）。舊版參考：`lib/ui/pages/search/search_page.dart` 的 `_PageTile`、`lib/data/models/track.dart` 的分 P 欄位。

**拆分**（主對話決定）：
- **20（這個 PR）**：宿主、`fmp-test`、介面、schema。
- **20-plugins**：`fmp-plugins` 的 B 站 `partCount` 與 `multiPart`，另開 PR，fixture 由主對話以匿名真實連線錄。

**主對話的資料決定**（design 沒寫分 P 的顯示資料存哪裡）：
- 比照舊版 `Track` 的 `pageNum` 與 `parentTitle`，`tracks` 加兩個可空欄位：`part_index`（從 1 起）與 `parent_title`。
- 分 P 曲目的 `title` 是分 P 標題；顯示時組成「影片標題 · P2 分 P 標題」。
- 舊版的 `pageCount` 不存，顯示用不到；搜尋結果的 `partCount` 只在記憶體。
- M5 匯入時，舊的 `pageNum` 對應 `part_index`，`parentTitle` 對應 `parent_title`。
- 這是新的資料格式：父 design §3.1 補一行更正，`app/AGENTS.md` § 資料層也補一條。

## 要做的

1. **宿主**（design §4.6）
   - `TrackSummary` 加選填 `partCount`（正整數）。形狀驗證、d.ts、`type_definitions_test.dart` 都要同步。
   - `SourcePlugin.multiPart({sourceId})` 回傳 `{parts: [{cid, title, durationMs?, index}]}`，其中 `index` 從 1 起。
     - 沒宣告 `multiPart` 時拋 `Unsupported`。
     - 這個能力的匯出名稱就是 `multiPart`。
   - `checks.json` 的 `multiPart` 案例要接到解析、契約執行器、健康檢查與插件開發工具，比照 `live`、`mix`。
2. **曲目資料**
   - `TrackInfo`（或對應的領域型別）帶 `partIndex`、`parentTitle`。
   - 從 `multiPart` 的分 P 建出的曲目：
     - `sourceId` 是影片的；
     - `cid`、`title`（分 P 標題）、`durationMs` 用分 P 的；
     - `partIndex` 是分 P 的 `index`；
     - `parentTitle` 是影片標題；
     - 上傳者與封面沿用影片的。
   - **schema v14**：`tracks` 加 `part_index` int?、`parent_title` text?。走 `.trellis/spec/app/data/index.md` § 改 schema 的完整流程，升級時既有的列兩欄都是空的。
   - 寫入曲目的地方：佇列、歷史、曲目 upsert。這兩欄要和其他欄位一樣寫進去、讀出來。
3. **`fmp-test`**
   - 一首有三個分 P 的曲目。在搜尋結果裡帶 `partCount: 3`，例如關鍵字 `parts`，或任何搜尋的第三首，選一種並寫進 README。
   - `multiPart` 回三個分 P，各自有不同的 `cid`，串流用 `tone.wav`。
   - `resolveStream` 對不同 `cid` 都能解析。
   - `checks.json` 加 `multiPart` 案例，README 寫清楚。
4. **介面**（design §11.1，比照舊版 `_PageTile`）
   - **搜尋結果列**：插件宣告 `multiPart` 且 `partCount > 1` 時，列尾多一個展開鈕。
     - 展開時呼叫 `multiPart`，列出分 P：「P2 分 P 標題」與時長。
     - 每個分 P 是一首曲目：點一下臨時播放；選單照曲目列。
     - 展開中、失敗（可重試）、收起的狀態，比照現有的寫法。
   - **點影片本身**：照舊臨時播放。`TrackSummary` 不帶 `cid`，插件的 `resolveStream` 會取第一 P。
   - **影片的選單**：分 P 數大於 1 時，「加入佇列」「下一首播放」套用到全部分 P。
     - 還沒展開過的，先呼叫 `multiPart` 取得分 P。
     - 取得失敗時照統一提示顯示錯誤，不加入。
     - Mix 中這兩項本來就停用（PR 19）。
   - **顯示**：佇列、歷史、播放頁、播放列、右側面板都顯示「影片標題 · P2 分 P 標題」，也就是有 `partIndex` 時才組合。
     - 佇列與歷史連續的同一影片分 P，以既有的 `TrackKey.formatGroup` 分組（design §11.1）。
     - 分組的呈現比照現有元件，用最小的改動；現有元件沒有地方可以分組時，停下回報。
   - i18n 三個語言都要補。
5. **文件**
   - `app/AGENTS.md`：§ 插件的 `multiPart`、§ 資料層的兩欄、§ 介面。
   - 父 design §3.1 加更正（兩欄）。
   - 父 implement.md §20 打勾。

## 驗收（測試）

- **design §11.1 的 widget 閘門**：
  - 展開鈕只在宣告 `multiPart` 且 `partCount > 1` 時出現；
  - 展開時呼叫 `multiPart`；
  - 影片選單套用到全部分 P，沒展開過也是；
  - 取得失敗時不加入，並顯示提示。
- **顯示**：佇列、歷史、播放頁顯示「影片標題 · P2 分 P 標題」；連續的分 P 分組。
- **宿主**：
  - `partCount` 與 `multiPart` 的形狀；
  - 沒宣告時拋 `Unsupported`；
  - 宣告了卻少了匯出時拒絕載入；
  - d.ts 與 Dart 端對照；
  - `checks.json` 的 `multiPart` 案例。
- **migration**：v13 到 v14 的三種測試。兩欄要能寫入與讀回，佇列恢復後分 P 曲目仍顯示組合後的標題。
- **guideline 測試**：搜尋結果的展開狀態、佇列的分 P 分組，寬 400 與 1000、淺色與深色。
- 每個新閘門都做雙向變異驗證並回報。
- 驗證清單：
  - `dart format --output=none --set-exit-if-changed lib test tool integration_test packages`
  - `build_runner` 後沒有實質變動
  - `dart run slang`
  - `dart analyze --fatal-infos`、`flutter analyze`
  - `flutter test`

## 實機（主對話做）

- **重播**（`fmp-test`，Android）：
  1. 展開分 P；
  2. 點 P2 播放；
  3. 用影片選單把全部分 P 加入佇列，佇列顯示組合標題並分組；
  4. 重啟後仍是組合標題。
- **真實**（B 站匿名，20-plugins 合併後）：一支多 P 影片展開，播 P2。
- Windows：沒動平台層與播放後端，就依 2026-10-13 的規則不驗。

## 不做

- B 站插件的 `partCount`、`multiPart`（20-plugins）；`trackDetail`（PR 21）。
- 歌單裡的分 P 群組（M4）。
