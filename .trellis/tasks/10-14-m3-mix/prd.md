# Mix（M3b PR 19）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §19、design §3.1、§4.5、§10）。依據 ADR 0028（`mix`）、ADR 0018 §決定 4、7、10，ADR 0031 §決定 8–11。舊版規格：`docs/audit/playback.md` §3.11。

**拆分**（主對話決定）：
- **19（這個 PR）**：宿主的 `mix` 能力、`fmp-test` 的假實作、佇列的 Mix 模式、補歌、持久化、選單入口。
- **19-plugins**：`fmp-plugins` 的 YouTube `mix`，在 `fmp-plugins` repo 另開 PR；fixture 由主對話以匿名真實連線錄。

## 要做的

1. **宿主 `mix` 能力**（design §4.5）
   - `SourcePlugin.mix`：
     - 輸入是 `{seed: {sourceId, cid?}}` 或 `{mixId, cursor}`；
     - 回傳 `{mixId, title, tracks: TrackSummary[], cursor: string | null}`。
     - 沒宣告 `mix` 時拋 `Unsupported`。
   - 一起補齊：DTO 與形狀驗證（`source_dto.dart`）、腳本插件的實作、`fmp-plugin.d.ts`、`type_definitions_test.dart`。
   - `checks.json` 的 `mix` 案例接到解析、契約執行器、健康檢查與插件開發工具，比照 18a 的 `live`。案例的輸入是 `seed`。
   - `mix` 的請求怎麼標 `auth` 由插件決定，宿主不管，和 `live` 一樣。
2. **`fmp-test` 的假實作**
   - manifest 加 `mix`。
   - 以任何 `seed` 開始時：回一個新的 `mixId`，每批 5 首。
   - 以 `{mixId, cursor}` 續取時：第二、三批照常回，第三批的 `cursor` 是 `null`。
   - 曲目用 2 秒的 `tone.wav`，曲目鍵要能分辨批次，例如 `mix-<mixId>-<n>`。
   - 第二批刻意重複第一批的一首，用來驗證去重。
   - `checks.json` 加 `mix` 案例；README 寫上行為。
3. **schema v13**：`player_state` 加 `mode`（空值或 `queue`／`mix`）、`mix_plugin_id`、`mix_id`、`mix_title`、`mix_cursor`（design §3.1）。走 `.trellis/spec/app/data/index.md` § 改 schema 的完整流程，`converters.dart` 寫死字串。
4. **`QueueModel` 的 Mix 模式**（design §10）
   - `QueueMode.mix`（與 `queue`、`temporary`、`live` 並列）。
   - **開始 Mix**：`mix({seed})` 回來的曲目取代整個佇列，進入 `mix` 模式，從第一首播。
   - **禁止的操作**：
     - 隨機、加入佇列、下一首播放、打亂，都回傳「拒絕」，不改佇列。
     - 拖曳排序與移除單首照常，舊版允許。
   - **清空佇列就是退出 Mix**：回到 `queue` 模式，佇列為空。
   - **跳過與臨時播放**：跳過走下一首，與佇列相同；臨時播放照常可用，結束後回到 Mix 佇列。
   - **修剪**：已播超過 100 首時，刪最舊的已播項目。剛好 100 首不刪；目前這首與還沒播的不動。位置位移照 M2 佇列的差量寫入。
   - **插件停用或移除**：Mix 照佇列處理，曲目標「音源未安裝」並跳過，補歌停止。
5. **`lib/playback/mix_session.dart` 的補歌**
   - **何時補**：每首開始時，若之後只剩 1 首以下，就呼叫 `mix({mixId, cursor})`。
     - `cursor` 為空時，改以佇列最後一首當 `seed` 開新的一批，Mix 身分換成回傳的新 `mixId`。
   - **合併**：回來的曲目以曲目鍵去重（已在佇列的丟掉）後附加，並更新 Mix 身分與 `mix_cursor`。
   - **並行**：同時只有一個補歌在跑。
   - **失敗或去重後一首都沒有**：記進錯誤歷史（`log.report`），不提示；在同一首內不重試，到下一首開始時再試。
   - **佇列播到底時**：補歌還在跑就等它完成，再決定往下播或停。
   - **呼叫方式**：補歌是播放核心的事件，**不經排程器**（ADR 0017 只管週期工作）；請求經插件，比照 `resolveStream` 的呼叫方式。
6. **持久化與恢復**（ADR 0018 §決定 10）
   - `queue_store` 寫入 `mode` 與 `mix_*`。
   - 重啟時 `mode = mix` 就恢復 Mix 模式、Mix 身分與 `mix_cursor`，照常補歌；`mix_cursor` 為空時同樣換種子。
   - `temporary`、`live` 照舊不持久化。
   - M2 的恢復測試不改期望，要全綠。
7. **介面**
   - `TrackRowMenu`（搜尋、歷史、佇列的曲目列）：
     - 只在該曲目的插件宣告 `mix` 時多一項「開始 Mix」；
     - 開始失敗時，照統一提示顯示錯誤。
   - Mix 模式中的停用項目：
     - 隨機鈕（播放列、播放頁）停用，附說明（tooltip 或 semantics，例如「Mix 中無法隨機播放」）；
     - 選單的「加入佇列」「下一首播放」停用，附說明；
     - 「打亂」若有入口，也停用。
     - 文字照現有的停用說明寫法。
   - 佇列分頁：Mix 模式時，在標題或適當位置顯示 Mix 標題（`mix_title`），讓使用者知道現在是 Mix。
     - 版面比照現有元件，用最小的改動。
     - 如果現有佇列分頁沒有放得下的位置，就停下回報，不要自己設計新區塊。
   - i18n 三個語言都要補。
8. **文件**
   - `app/AGENTS.md` § 播放，以及 § 插件的 `mix` 契約：只寫查不到的東西與它的閘門。
   - `.trellis/spec/app/playback/index.md` 視需要更新。
   - 父 implement.md §19 打勾。

## 驗收（測試）

- **design §10 的閘門**：
  - `QueueModel` 的修剪：剛好 100 首不刪；101 首刪最舊的已播；目前這首與還沒播的不動。
  - 禁止的操作回傳拒絕。
  - 清空佇列就退出 Mix。
  - `MixSession`：
    - 補歌時機：之後只剩 1 首以下才補；
    - 去重；
    - `cursor` 為空時換種子；
    - 一首都沒補到時，同一首內不重試；
    - 同時只有一個補歌；
    - 播到底時等補歌完成。
  - 持久化與恢復：含 v12→v13 的 migration 三種。
  - 選單只在插件宣告 `mix` 時出現。
- **宿主**：
  - `mix` 的形狀；
  - 沒宣告時拋 `Unsupported`；
  - 宣告了卻少了匯出時拒絕載入；
  - d.ts 與 Dart 端的對照；
  - `checks.json` 的 `mix` 案例。
- **`fmp-test`**：每批 5 首、第三批的 `cursor` 為空、重複的那一首。
- **widget**：
  - 隨機鈕與停用的選單項目在 Mix 中停用，並附說明；
  - 「開始 Mix」只在宣告 `mix` 時出現；
  - 佇列分頁顯示 Mix 標題。
- **guideline 測試**：佇列分頁的 Mix 版、停用的隨機鈕，寬 400 與 1000、淺色與深色。
- **雙向變異**：每個新閘門都要驗，並回報。
- **驗證清單**：
  - `dart format --output=none --set-exit-if-changed lib test tool integration_test packages`
  - `build_runner` 後沒有實質變動
  - `dart run slang`
  - `dart analyze --fatal-infos`、`flutter analyze`
  - `flutter test`
  - 動到 lint 時，加跑 lints 測試與哨兵

## 實機（主對話做）

照父 implement.md §19，Android 模擬器與 Windows 都要：

- **重播**（`fmp-test`）：
  1. 開始 Mix；
  2. 補歌三次，第三批後換種子；
  3. 試禁止的操作；
  4. 重啟後仍是 Mix；
  5. 清空佇列，退出 Mix。
- **真實**（YouTube 匿名，19-plugins 合併後）：開始 Mix，播到倒數第二首，觸發補歌一次。

## 不做

- YouTube `mix`（19-plugins）。
- M4 的 `playlists.kind = mix`、歌單卡的「Mix 播放」（ADR 0031）。
