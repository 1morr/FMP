# 音源健康檢查（M3b PR 16a）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §16、design §12.5）。依據 ADR 0025 §決定 6、ADR 0015 §決定 4。

**拆分**（主對話決定）：implement.md 的 PR 16 拆成三個。
- **16a（這個）**：`checks.json` 的解析與案例期望搬到 `lib/plugins/health/`，加上健康檢查與 Debug 頁的區塊。
- **16b**：插件開發工具（`json_shape.dart` 與 fixture adapter 搬到 `lib/core/`、選資料夾、開發中標記、模式切換、錄製），由 opus 先定版面。
- **16c**：以 App 內登入重錄 `requiresLogin` 的案例，要擁有者登入。

## 要做的

1. **搬 `checks.json` 的解析與期望**
   - `test/plugins/contract/checks.dart` 裡 App 需要的部分搬到 `lib/plugins/health/`：`PluginCheck`、`parseChecks`、`checkShapes`、`CheckExpectation`（`ExpectSuccess`、`ExpectError`）、`checkItems` 與欄位抽取。判斷只有一份。
   - 只有測試用、App 不用的（例如 `expiresAtProblems` 若只有契約執行器用）可以留在 `test/`。要不要搬，以「App 有沒有呼叫」判斷，並在回報說明。
   - `test/plugins/contract/` 的契約執行器、`checks_test.dart`（可移到 `test/plugins/health/`）、`type_definitions_test.dart` 改引用新位置。**M1 的契約測試要全綠**（`contract_runner_test.dart`、`contract_test.dart` 以 `fmp-test` 跑）。
2. **健康檢查**（`lib/plugins/health/`）
   - 對**已安裝且啟用**的插件，以 App 裡已載入的插件（插件清單的 runtime，真實連線、帶已存憑證）跑它的案例。
   - 案例來源：`installed_plugins.checks_json`（從 index 安裝的才有）；沒有的插件（從檔案或網址、開發入口安裝）顯示「沒有檢查案例」。開發資料夾的 `checks.json` 在 16b。
   - 手動觸發「全部」或單一插件；**一次只跑一個插件**（全部時依序跑）。跑的期間可以看到進度；不能同時再開一輪。
   - 每個案例的結果：通過／失敗／略過、耗時、失敗時的 `AppError` 類別（與期望不符的說明）。`requiresLogin` 而該音源沒登入的案例標「略過」；已登入就用已存的憑證跑（design §4.8）。
   - 結果以 tag `health` 經 log 門面寫入（每個案例一筆，帶插件 id、能力、結果、耗時、錯誤類型），**不另外存**。
3. **Debug 頁「音源健康檢查」區塊**（ADR 0025 §決定 2 的順序：播放狀態之後、資料庫之前）
   - 每個插件一列：名稱、版本、案例數或「沒有檢查案例」、「檢查」按鈕；上方「全部檢查」。
   - 跑完顯示每個案例的結果（通過／失敗／略過、耗時、錯誤類別）；失敗的說明文字經 `Redactor`。
4. i18n 三個語言（slang）；`app/AGENTS.md`（健康檢查一條，寫出閘門；契約執行器引用的位置變了要同步）、`.trellis/spec/app/plugins/index.md` 視需要。

## 驗收（測試）

- 搬移後 M1 的契約測試與 `checks_test` 全綠；`type_definitions_test.dart` 比對 `checkShapes` 的位置跟著改。
- 健康檢查（以測試插件與假的 http 回應，不連網）：
  - `requiresLogin` 而未登入 → 略過；已登入 → 用已存憑證跑（請求帶憑證）。
  - 一次一個插件：「全部」依序跑，不會同時有兩個插件在跑；跑的期間再按不會開第二輪。
  - 停用的插件不跑；沒有 `checks_json` 的插件顯示「沒有檢查案例」。
  - 每個案例寫一筆 tag `health` 的 log，欄位正確；不另外存（資料庫沒有新表）。
  - 期望不符時標失敗並帶說明；插件丟 `AppError` 以外的東西也標失敗、不讓整輪中斷。
- widget：區塊的清單、進度、結果、沒有案例的說明。
- guideline：區塊（含結果）寬 1000、窄 400，淺色深色。
- 每個新閘門雙向變異驗證並回報。
- 驗證清單：`dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`；動到 lint 時跑 lint 的測試與 sentinel。

## 實機（主對話做）

- 沒動 `lib/platform/` 與後端：只驗 Android。
- Android：從 index 安裝 B 站（真實，安裝一次），健康檢查跑 B 站一輪（真實，最少操作）；`fmp-test`（開發入口安裝）顯示「沒有檢查案例」。

## 不做

- 插件開發工具、fixture adapter 搬移（16b）。
- 定時自動跑健康檢查（ADR 0025：手動觸發）。
