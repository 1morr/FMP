# Debug 頁的播放狀態與資料庫（M3b PR 14a）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §14、design §12.2、§12.3）。依據 ADR 0025 §決定 2、5、8，ADR 0018，ADR 0011。

**拆分**（主對話決定）：implement.md 的 PR 14 拆成兩個。這個 14a 只做唯讀的部分：播放狀態區塊、資料庫的瀏覽與檢查。備份、從備份還原、重設資料、重啟留給 14b。資料庫檢查發現問題時「從備份還原」「重設資料」的按鈕在 14b 加。

## 要做的

1. **`PlaybackDiagnostics`**（`lib/playback/playback_diagnostics.dart`）
   - 由 `PlaybackSession` 提供的唯讀快照：
     - 選中候選的容器、編碼、位元率、來源類型（網路／asset）；
     - 後端名稱（例如 `just_audio`、`media_kit`）；
     - 輸出裝置（後端拿得到才有；拿不到就是空，不為此改後端的行為）；
     - `Retrying` 時的重試次數與下次重試時間（`Retrying.delay` 加開始時間）。
   - 加上控制器既有的狀態（sealed `PlaybackState`，`Failed` 附 `AppError` 類型）、曲目的插件 id 與曲目鍵，以及 `QueueState`：總數、目前索引、前後各 5 首、隨機與循環。
   - **不改** sealed `PlaybackState` 的形狀；`QueueState` 照舊分開（ADR 0018 §決定 2）。播放控制仍只經 `PlaybackController`，這個區塊不放控制按鈕。
   - 位置每秒刷新：UI 讀既有的進度 stream，不開計時器。
   - `toJson()`：「複製快照」輸出 JSON。串流網址（若放進快照）與所有字串經 `Redactor`。
2. **Debug 頁「播放狀態」區塊**（`DebugSection` 照 ADR 0025 §決定 2 的順序：概覽、Log 與錯誤歷史、網路、**播放狀態**、……、**資料庫**）。沒有在播時顯示空狀態。「複製快照」按鈕。
3. **資料庫的唯讀查詢**（`lib/data/`，只有它能 import drift）
   - 例如 `DatabaseInspector`：`tables()` 回 `allTables` 的名稱與筆數；`rows(table, page)` 以 `select(table)` 分頁，每頁 50 列，回欄位名與值（值轉成字串或 null）。
   - `check()`：`PRAGMA integrity_check`、`PRAGMA foreign_key_check`（列出違規的表、rowid、parent）、孤兒曲目數（M2 `deleteOrphans` 同一個條件的計數版，**與它共用條件**，不要複製一份 SQL）。「檔案遺失的下載數」在 M6，不做。
   - 只讀，不寫任何東西。
4. **Debug 頁「資料庫」區塊**
   - 表清單與筆數 → 點進表看分頁的列（上一頁／下一頁）。
   - 每個值經 `Redactor.redact`；`plugin_storage` 的 `value` 欄整欄顯示 `***`。
   - 「檢查」按鈕：顯示三項結果；乾淨時說沒有問題。
5. i18n 三個語言（slang）；`app/AGENTS.md`（播放狀態、資料庫各一條，寫出閘門）、`.trellis/spec/app/{ui,data,playback}/index.md` 視需要。

## 驗收（測試）

- `PlaybackDiagnostics`：欄位取對（含 `Retrying` 的下次重試時間、佇列前後各 5 首在頭尾的邊界）；**遮蔽**：串流網址帶假媒體 CDN 簽名（例如 `upsig=FAKE_…`）、假 token 時，`toJson()` 的輸出不含原值（ADR 0025 §如何確認）。
- 資料檢查：關掉外鍵寫一筆違規列再開，`check()` 的報告列出它；乾淨的資料庫報告無問題；孤兒曲目數和 `deleteOrphans` 會刪的筆數相同。
- 瀏覽：`plugin_storage` 有假 cookie 時顯示 `***`；其他表的值裡的假 token 經遮蔽；分頁 50 列。
- widget：兩個區塊的空狀態、複製快照的內容、檢查結果的顯示。
- guideline：兩個區塊寬 1000、窄 400，淺色深色（含表的列頁與檢查結果）。
- 每個新閘門雙向變異驗證並回報。
- 驗證清單：`dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`；動到 lint 時 `packages/fmp_lints` 的 `dart test` 與 `dart run tool/lint_sentinel.dart`。

## 實機（主對話做）

- 若動到 `lib/playback/backends/`：Android 模擬器與 Windows 都驗；否則只驗 Android。
- 重播：`fmp-test` 播一首，看播放狀態（後端、容器、位置每秒更新、佇列），複製快照；`flaky` 看重試中的下次重試時間；資料庫瀏覽 `plugin_storage` 的值是 `***`、檢查乾淨。

## 不做

- 備份、還原、重設資料、重啟（14b）。
- 在 App 內編輯資料庫（ADR 0025 否決）。
- 啟動時自動檢查。
