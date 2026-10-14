# 插件開發工具（M3b PR 16b）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（design §12.5、§2.2、§4.8；implement.md §16）。依據 ADR 0015 §決定 5–7、ADR 0025 §決定 1、2、7、ADR 0009、ADR 0030 §決定 11。設計與理由：本目錄 `design.md`；步驟：`implement.md`。

PR 16 拆成三個（主對話決定）：16a 健康檢查（先合併）、**16b 插件開發工具（這個）**、16c 以 App 內登入重錄 `requiresLogin` 的案例（要擁有者登入）。

## 目標

Windows 上的開發者在 App 裡選一個插件資料夾（例如 `fmp-plugins` 的 clone），資料夾裡的插件以「開發中」取代已安裝版；改了檔案按「重新載入」；每個插件以「重播｜錄製｜真實」跑 `checks.json` 的案例、看已遮蔽的結果與 log；錄製寫出的 fixture 與命令列錄製一模一樣、能在 `fmp-plugins` 的 CI 重播。

## 要做的

1. **搬移**（design §2）
   - `lib/plugins/json_shape.dart` → `lib/core/json_shape.dart`，所有 import 跟著改。
   - `test/plugins/contract/` 的 `fixture.dart`、`fixture_adapters.dart`、`ip_scrub.dart` → `lib/core/network/fixture/`；`fixture_adapters.dart` 加 `CaseTransport`／`CaseTransports`。
   - `fmp_layer_imports` 的 `restrictedImports` 加 `lib/core/network/fixture` → `[lib/plugins/dev, lib/core/network/fixture]`；lint 測試、哨兵、`app/AGENTS.md` § Lint 的表。
   - 契約執行器的插件目錄讀取、隔離執行環境、錄製寫檔 → `lib/plugins/dev/plugin_folder.dart`、`case_runner.dart`；`lib/data/` 加 `openInMemoryDatabase()`；`test/plugins/contract/` 改為引用它們，只留憑證掃描（`credential_scan.dart`）、網域檢查等測試專用的部分。
2. **資料**：`installed_plugins.from_dev_folder`（bool，預設假），schema v10，照 `.trellis/spec/app/data/index.md` § 改 schema 的完整流程；`PluginRepository` 的 `fromDevFolder`、`putDevFolderRow`、`removeDevFolderRows`，`install` 寫入假。
3. **平台層**：`FileDialogs.pickDirectory()`（`file_picker` 的 `getDirectoryPath`）；`PlatformCapabilities.pluginDevTools`（Windows 真、Android 假）。
4. **設定**：`DeveloperNotifier.setPluginDevFolder(String?)`。
5. **載入**（design §3.3、§3.4）：`pluginDevFolderProvider`、`PluginDevelopment`（套用資料夾、對齊列、重新載入、重新掃描、載入失敗不退回已安裝版）；`PluginRegistry` 略過標記列、加 `restoreInstalled`；`FmpApp` 啟動時讓它活著；健康檢查對開發中的插件讀資料夾的 `checks.json`。
6. **跑案例**（design §3.1、§3.2）：`DevCaseRuns`（每插件的模式、單跑與全跑、一次一個、錄製經 `recordCase` 寫進資料夾、`requiresLogin` 的處理、代際丟棄、每案例一筆 log）。
7. **介面**（design §3.5、§3.6）：Debug 頁「插件開發」區塊；Log 區塊可帶 tag 篩選開啟（「查看 log」）；插件頁的「開發中」標記、停用的動作、「全部更新」與可安裝分頁略過開發中的 id；三個語言的字串。
8. **文件**：design §6 的更正各一行；`app/AGENTS.md` 的 § 平台層、§ 資料層、§ 插件（開發工具一段、契約執行器的位置）、§ 介面（Debug 區塊）、§ Lint；`.trellis/spec/app/plugins/index.md`（契約執行器與開發工具的位置）、`.trellis/spec/app/platform/index.md` 視需要；父 implement.md §16 勾選與「PR 16b 留下的」。

## 驗收（測試）

每個新閘門都要在測試檔內雙向變異驗證（造一個違規證明會紅、改一次無關的東西證明不紅），並在回報說明。

- **搬移不改行為**：`contract_runner_test.dart`、`contract_test.dart`、`record_test.dart`、`fixture_scan_test.dart`、`ip_scrub_test.dart`、`checks_test.dart`、`type_definitions_test.dart` 不改斷言就全綠（只改 import；若 `contract_runner_test` 依賴問題的順序，用 `PluginFolder.read` 的 `inspectFixture` 保持原順序，不改斷言）。
- **lint**：`layer_imports_test.dart` 加兩組：
  - 會報：從 `lib/plugins/plugin_registry.dart`、`lib/plugins/devtools/x.dart`（名稱相近的目錄）、`lib/ui/debug/debug_page.dart`、`lib/core/network/source_http_client.dart` import `lib/core/network/fixture/fixture.dart`；別名、相對路徑、export 一樣報。
  - 不報：`lib/plugins/dev/case_runner.dart`、`lib/core/network/fixture/fixture_adapters.dart`、`test/plugins/contract/contract_runner.dart` import 它；`lib/core/network/fixture_helpers.dart`、`lib/core/network/fixtures/x.dart`（名稱相近的檔案與目錄）、註解與字串裡提到的。
  - 哨兵加一行 `import 'package:fmp/core/network/fixture/fixture.dart';` 與 `_expectedMessages` 的 `lib/core/network/fixture is only imported from`。
- **migration**（v9 → v10）：空資料升級；資料完整性（升級前的 B 站列升級後 `from_dev_folder` 為假，`enabled`、`manifest_json`、`script`、`checks_json` 不變，它的 `plugin_storage` 還在）；快照。
- **`plugin_repository_test.dart`**：`putDevFolderRow` 在沒有列時插入標記列、有標記列時更新內容、有已安裝的列時一個欄位都不動且回傳假；`removeDevFolderRows` 只刪標記列且 storage 跟著刪、`keep` 裡的留下；`install` 把標記列轉成未標記（storage 保留）。
- **`plugin_development_test.dart`**（以 `fmp-test` 的複本當資料夾，不連網）：
  - 沒有已安裝的列：補標記列、registry 裡是開發版、`fmp.storage.set` 寫得進去；卸載（`setPluginDevFolder(null)`）後列與 storage 都不在、registry 沒有它。
  - 有同 id 的已安裝列（版本不同）：registry 裡是開發版；列的 version／manifest／script／enabled 不變；卸載後 registry 裡是已安裝版（版本等於列上的），列與 storage 都還在。
  - 殘留：資料庫有標記列、生效資料夾是 `null` → 套用後那一列與 storage 被刪，registry 從來沒載入它（registry 的 `build` 略過標記列）。
  - 關閉開發者模式（`setDeveloperMode(false)`）→ 卸載並恢復已安裝版（ADR 0025 §如何確認「關閉時開發資料夾卸載」）。
  - 平台沒有 `pluginDevTools`：`plugin_dev_folder` 有值也不載入。
  - 重新載入：改資料夾裡的 `.js`（版本加一）→ `reload` 後 registry 是新版本、舊的 runtime 已關閉。
  - 載入失敗（壞掉的 `.js`）：registry 沒有它（沒有退回已安裝版）、狀態是 `failed` 且原因已遮蔽、有一筆 tag `plugins` 的錯誤 log。
  - 兩個目錄同 id：第一個載入、第二個記在 `problems`。
  - 重新掃描：資料夾新增一個插件目錄後 `rescan` 載入它。
- **`dev_case_runs_test.dart`**（以 `caseTransportsProvider` override 成假上游）：
  - 預設模式是重播；`http_test_plugin` 的複本重播全部通過。
  - 隔離：App 資料庫的 `fmp-test` storage 有 `titlePrefix = Warm`，跑 `search` 的結果標題以 `Test tone` 開頭，App 的 storage 不變。
  - 錄製：寫出的 fixture 沒有假憑證（`FAKE_`），重播通過；與 `recordContract` 對同一個假上游、同一個時鐘寫出的目錄逐位元組相同；手改過的 fixture 略過且原檔不動；結果不符時不寫。
  - `requiresLogin`：真實與錄製模式下沒登入 → 略過、假上游沒收到請求；已登入 → `loginVerify` 收到 `CredentialStore` 的憑證；重播模式用 `checks.json` 的假憑證。
  - 一次一個：跑的期間再呼叫 `run` 不會開第二個。
  - 代際：跑的期間換資料夾 → 結果被丟掉、錄製沒有寫檔。
  - 每個案例一筆 tag 為插件 id 的 `Plugin case` log，欄位正確；`LoginAccount` 的回傳值顯示不含帳號名稱。
- **`health_check_test.dart`**：開發中的插件以資料夾的 `checks.json` 跑。
- **widget**：
  - 未宣告 `pluginDevTools` 時清單與內容都沒有「插件開發」（ADR 0025 §如何確認）；宣告時在健康檢查與資料庫之間。
  - 區塊：未選資料夾、資料夾問題、三種卡片標記（開發中、取代已安裝 x、載入失敗與原因）、選錄製時的警告、結果列展開（錯誤、問題、已寫入、回傳值）、跑的時候按鈕停用。
  - 「查看 log」切到 Log 區塊且 tag 篩選是該插件 id。
  - 插件頁：開發中的卡片有標記、顯示開發版版本、開關／更新／移除停用；「全部更新」不含開發中的 id；可安裝分頁裡開發中的 id 沒有安裝鈕。
- **guideline**：插件開發區塊（含展開的通過與失敗結果）寬 400、1000，淺色深色；插件頁含開發中的卡片。
- **驗證清單**：`dart format --output=none --set-exit-if-changed .`、`dart run build_runner build --delete-conflicting-outputs` 後無實質變動、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、`packages/fmp_lints/` 的 `dart test`、`dart run tool/lint_sentinel.dart`；`flutter build windows --flavor dev`（動到平台層）。

## 實機（主對話做，`verify-on-device`）

動到平台層的 Windows 實作（`pluginDevTools`、`getDirectoryPath`）：Windows 必驗、Android 驗沒有入口。

- **準備**：把同層的 `fmp-plugins` clone 複製到 scratchpad（`Copy-Item -Recurse`，含 `.git`），只動複本。
- **Windows（dev flavor，重播＋最少的真實連線）**：
  1. Debug → 插件開發 → 選擇資料夾（複本）→ 三張卡片都是「開發中」，已安裝的標「取代已安裝 x」；插件頁的那幾張卡片有「開發中」、動作停用。
  2. B 站：重播模式「全部執行」→ 全部通過（`login` 用假憑證）。
  3. 在複本的 `bilibili.js` 的 `search` 加一行 `fmp.log.info`，「重新載入」→ 提示顯示新版本 → 搜尋頁搜一次（真實，一次）→「查看 log」看到新的那一行。
  4. 錄製模式只跑 `search`（真實，一個案例）→ 結果「已寫入 n 個 fixture」→ 在複本 `git diff --stat` 只有 `fixtures/search/` 變了 → 打開寫出的檔：cookie、`access_key` 等名單上的值是 `***`，沒有帳號名稱。
  5. 「卸載」→ 插件頁回到已安裝版、版本正確；只有開發資料夾才有的插件不見了。
  6. 再選一次資料夾 → 概覽關掉開發者模式 → 再打開開發者模式進 Debug：資料夾已清空、已安裝版在用。
- **Android（重播）**：Debug 頁沒有「插件開發」；健康檢查照常（`fmp-test` 顯示「沒有檢查案例」）；插件頁沒有「開發中」標記。
- 回報寫明平台與模式；截圖不含帳號名稱與頭像。

## 不做

- 16c：以 App 內登入重錄 `requiresLogin` 的案例（機制在這個 PR，實際錄製要擁有者登入）。
- Android 的插件開發（要 SAF 讀目錄，另立 ADR；ADR 0025「之後要注意」）。
- 檔案監看、自動重新載入（ADR 0025 已否決）。
- 模式作用於 App 裡的插件（App 內一律真實連線，design §3.1）；模式跨重啟保留。
- 卸載只有開發資料夾才有的插件時清它的帳號與憑證（保留，design §3.4）。
- 診斷包標示開發中的插件與它的版本。
- registry 重建時保留開發版（registry 目前不會重建，design §3.3）。
- 在 `PluginInstaller` 層擋開發中 id 的安裝、更新、移除（只在插件頁擋）。

## 主對話的決定（2026-10-14）

- **接受**「三種模式只作用於跑案例、每個案例在隔離環境執行；App 內載入的開發中插件一律真實連線」，偏離父 design §12.5「切換模式時重建該插件的 client」的字面。理由：在帶著 storage 快取的插件上錄的 fixture 在 CI 的空 storage 重播時會對不上；錄放是一段測試的設定（Polly.js／VCR 的慣例）。ADR 0025 §決定 7 加一行補充。
- schema v10 的 `installed_plugins.from_dev_folder` 是附加欄位、預設假，不影響既有資料，照做。
- 已知限制（記到父任務的後續）：隔離環境只把已存憑證當 `loginVerify` 的輸入；M4 出現「需要登入、但不是 login 能力」的案例時，要讓隔離環境帶上該音源的憑證。
