# 錯誤詳細頁與 GitHub 回報（M3b PR 13）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §13、design §13）。依據 ADR 0023 §決定 4、ADR 0013、ADR 0025。

## 目標

錯誤提示能打開一個詳細頁：開發者看到錯誤類型、音源、請求摘要、stack trace 並複製；一般使用者遇到 `Unsupported`、`UnexpectedError` 能把遮過的報告貼到 GitHub issue。

## 要做的

1. **`ErrorReport`**（`lib/core/errors/error_report.dart`，純 Dart，不 import 平台層）
   - 由一筆錯誤歷史的 `LogRecord`（`report()` 寫的那筆，已遮蔽）組裝：錯誤類型（`fields.type`）、原因（`record.error`）、音源 id（`fields.pluginId`）與版本（呼叫端給，可為空）、使用者動作（`record.message`，即 `report()` 的 operation，英文）、請求摘要（以 `fields.networkRecordId` 在傳入的記憶體歷史找 tag `network`、`id` 相同的那筆：方法、`host`+`path`+`query`、狀態碼、耗時；找不到就沒有）、stack trace、App 版本與 flavor、平台與系統版本、時間（`record.time` 的 ISO 8601 UTC）。
   - `String toMarkdown()`：標題、欄位清單、stack trace 放 code block。內容只來自已遮蔽的紀錄，組裝時再整份經一次 `Redactor.redact`（多一層保險，因為版本字串等也進來）。
   - **與 design §13 的差異（主對話決定）**：不另存報告的 id。`Log.write` 改回傳寫入的 `LogRecord?`（低於層級被丟掉時 `null`），`report()` 跟著回傳；提示與 Debug 頁都由那筆紀錄組報告。前幾次執行的紀錄（log 檔讀回）一樣能組，只是沒有請求摘要（`networkRecordId` 只在同一次執行唯一），App 版本是開頁時的版本。
2. **`Toaster` 的動作**（ADR 0023：每則最多一個動作）
   - 呼叫端給了 `action` 就用它（目前沒有任何 `toaster.error` 呼叫帶動作）。
   - 沒給時：開發者模式開著 → 「詳細」；否則錯誤是 `Unsupported` 或 `UnexpectedError` → 「回報」；其餘沒有動作。兩者開同一個詳細頁。
   - `report()` 回傳 `null`（層級被濾掉）時不附動作。
   - Toaster 需要讀開發者模式（`developerProvider` 的有效值）與開頁面的方法。App 目前沒有根 navigator key：在 `lib/app/` 加一個給 `MaterialApp.navigatorKey` 的 key（provider），提示的動作經它 push 詳細頁。若這個做法和既有結構衝突，停下回報。
3. **詳細頁**（`lib/ui/errors/error_detail_page.dart`，全螢幕路由）
   - 文字可選取（`SelectionArea`），內容就是 `ErrorReport` 的欄位（版面照 `.trellis/spec/app/ui` 與 `AppLayout` token）。
   - 「複製」：Markdown 進剪貼簿，提示「已複製」。
   - 「在 GitHub 回報」：先複製，再開 `endpoints.dart` 的 `newIssueUrl`（`https://github.com/1morr/FMP/issues/new?template=bug_report.yml`）。**報告內容不進網址**。
   - 第一次按「在 GitHub 回報」先跳對話框：repo 是公開的，送出前請檢查內容；勾選「不再提醒」並繼續時寫入 `developer_settings.report_reminder_dismissed`（`DeveloperSettingsRepository` 加 setter）。取消就不開也不寫。
   - 平台沒有 `urlOpener` 能力時：只複製，並在頁面顯示網址文字讓使用者自己開。
4. **平台層 `lib/platform/url_opener/`**
   - `UrlOpener.open(Uri) → Future<bool>`、`urlOpenerProvider`；`PlatformCapabilities.urlOpener`（Android、Windows 為真，其餘照現有能力表的慣例）。
   - 用 `url_launcher`：design 寫 6.3.3，先查 pub.dev 目前的 stable，有更新的 stable 就用它並在回報說明。`launchUrl(..., mode: LaunchMode.externalApplication)`。
   - Android 照 url_launcher README 補 manifest 的 `<queries>`（若需要）。
   - `url_launcher` 只准在 `lib/platform/`：加進 lint `fmp_layer_imports` 的 `platformPackages`，`layer_imports_test.dart` 加案例（雙向變異）。
5. **`AppInfo` 加系統版本**（`osVersion`，在平台層讀 `Platform.operatingSystemVersion`），詳細頁與報告用。
6. **`.github/ISSUE_TEMPLATE/bug_report.yml`**（繁中）：問題描述、重現步驟、錯誤報告（`render: markdown`，提示貼上「複製」的內容）、App 版本、平台；標籤 `bug`。必要欄位：問題描述、錯誤報告。
7. **Debug 頁**：Log 區塊裡錯誤歷史的紀錄（有 `fields.type` 的）展開後有「詳細」按鈕，開同一個詳細頁。
8. **i18n** 三個語言（slang），文件：`app/AGENTS.md`（詳細頁與回報、url_opener 各一條，寫出閘門）、`.trellis/spec/app/ui/index.md`、`.trellis/spec/app/platform/index.md` 視需要。

## 驗收（測試）

- `ErrorReport`：欄位從紀錄取對；找得到／找不到網路紀錄；Markdown 格式；**遮蔽**：錯誤原因、stack trace、query 帶假 cookie、假 token、假媒體 CDN 簽名網址，Markdown 不含原值（ADR 0023 §如何確認）。
- `Toaster`：開發者模式每則錯誤附「詳細」；一般使用者只有 `Unsupported`、`UnexpectedError` 附「回報」；呼叫端的動作優先；層級被濾掉時沒有動作。
- 詳細頁 widget：複製的內容是 Markdown；「在 GitHub 回報」開的網址**等於** `endpoints.dart` 的常數、不含報告內容；第一次提醒、「不再提醒」寫入後第二次不跳；取消不開不寫；沒有 `urlOpener` 時只複製並顯示網址。
- Debug 頁：錯誤紀錄的「詳細」開詳細頁。
- `bug_report.yml` 結構測試（`app/test/` 讀 `../.github/ISSUE_TEMPLATE/bug_report.yml`，`yaml` 解析）：必要欄位、`render: markdown`、標籤 `bug`。
- guideline 測試：詳細頁寬 1000、窄 400，淺色深色。
- `integration_test/toast_layering_test.dart` 加詳細頁（全螢幕頁之上提示可見）。
- 每個新閘門做雙向變異驗證（改壞會紅、無關改動不紅），回報結果。
- 驗證清單：`dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`。

## 實機（主對話做）

- 動到原生依賴與 `lib/platform/`：**Android 模擬器與 Windows 都驗**（ADR 0027 §決定 3 修訂）。
- 重播：`fmp-test` 搜 `fail`，開發者模式下「詳細」→ 複製 →「在 GitHub 回報」開瀏覽器到範本頁（不送出）；關掉開發者模式後以會丟 `UnexpectedError` 的情境看「回報」。
- 兩平台各跑一次 `flutter test integration_test/toast_layering_test.dart -d <裝置>`。

## 不做

- 診斷包、匯出 log 檔（PR 15）。
- 把報告內容放進網址（ADR 0023 否決）。
- 回報到 `fmp-plugins`（一律 `1morr/FMP`，由維護者 Transfer）。
