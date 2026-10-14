# 插件開發工具：執行步驟

依序做；每一步結束時 `app/` 可編譯、`flutter test` 全綠（第 1–3 步是純搬移，行為不變）。介面與理由在 `design.md`，驗收在 `prd.md`。

## 模型

- **實作：sonnet（`trellis-implement`）**。版面、互動、資料標記、搬移範圍都已在 design 定案，實作者不做計畫外的決定。建議兩次派工：A＝第 1–3 步（純搬移，以既有契約測試為準）；B＝第 4–9 步。
- 派工 prompt 附 `design.md`、`prd.md`、本檔全文，並寫明：**遇到計畫沒涵蓋的設計決定就停下回報**，不自行拍板（例如：某個既有測試的斷言非改不可、搬移後發現還有別的檔案要一起搬、Riverpod 的行為與 design 假設不同）。
- **審查：opus（`trellis-check`）**，要它試著攻破：錄製寫出的檔有沒有漏遮（憑證、帳號名稱、IP）、隔離環境是否真的碰不到 App 的 storage 與憑證、殘留列的清理會不會刪到已安裝的列與它的 storage、`restrictedImports` 的變異案例。

## 1. `json_shape.dart` 移到 `lib/core/`

- `git mv app/lib/plugins/json_shape.dart app/lib/core/json_shape.dart`，改六個 `lib/plugins/` 的 import 與 `test/plugins/contract/fixture.dart`、`type_definitions_test.dart`。
- 驗證：第一列的驗證清單。

## 2. fixture 的三個檔案移到 `lib/core/network/fixture/`，加 `CaseTransport`

- `git mv` `test/plugins/contract/{fixture,fixture_adapters,ip_scrub}.dart` 到 `app/lib/core/network/fixture/`，改成 `package:fmp/...` 的 import；註解裡的路徑跟著改。
- `fixture_adapters.dart` 加 design §4.1 的 `CaseTransport`、`ReplayTransport`、`NetworkTransport`、`CaseTransports`（包現有的兩個 adapter，不改它們的行為）。
- `test/plugins/contract/` 的 `contract_runner.dart`、`credential_scan.dart`、`fixture_scan_test.dart`、`ip_scrub_test.dart`、`record_test.dart`、`contract_runner_test.dart`、`type_definitions_test.dart` 改 import。契約執行器暫時仍直接用 `ReplayAdapter`／`RecordingAdapter`（第 3 步才換）。
- `packages/fmp_lints/lib/src/rules/layer_imports.dart` 的 `restrictedImports` 加：
  ```dart
  // M3 design §12.5：fixture 的錄製、重播與格式只給插件開發工具（契約執行器在 test/，不受限）。
  'lib/core/network/fixture': ['lib/plugins/dev', 'lib/core/network/fixture'],
  ```
- `layer_imports_test.dart` 加 prd「lint」的兩組案例；`tool/lint_sentinel.dart` 加 import 一行與 `_expectedMessages` 一則。
- 驗證：第一列加 `packages/fmp_lints/` 的 `dart test`、`dart run tool/lint_sentinel.dart`；`flutter test test/plugins/` 全綠。

## 3. 插件目錄讀取與隔離執行環境移到 `lib/plugins/dev/`

- `lib/data/database/open_app_database.dart` 加 `openInMemoryDatabase()`（design §4.7）。
- 新檔 `lib/plugins/dev/plugin_folder.dart`（design §4.2）：從 `contract_runner.dart` 搬 `pluginDirectories`、`_scripts`、`PluginDirectory` 的格式檢查部分（改名 `PluginFolder`，加 `inspectFixture`）、`_writeFixtures`（改名 `writeFixtures`）。
- 新檔 `lib/plugins/dev/case_runner.dart`（design §4.3）：從 `contract_runner.dart` 搬 `_Environment`、`_execute`／`_executeLoaded`（不含 `mediaHeaderProblems`、`inspectLog` 這兩個憑證掃描）、`describeError`、`redactorFor` 若只有測試用就留在 test；`recordCase` 是現在 `recordContract` 迴圈裡一個案例的內容。空的 `SecureStorage` 是本檔私有的 class。
- `test/plugins/contract/contract_runner.dart` 改成薄的一層：
  - `PluginDirectory.read` = `PluginFolder.read(directory, inspectFixture: …)`，`inspectFixture` 做網域檢查與 `scanFixture`（問題的字串與順序不變）。
  - `runCheck`：`Redactor()`、`_facade(redactor)`（或呼叫端給的 `log`）、`CaseTransports().replay(...)`、`runIsolatedCase(reportTag: 'contract')`，再接 `mediaHeaderProblems`、`inspectLog`、`transport.problems`、`transport.unused`，加上 `'$name: '` 前綴，順序同現在。
  - `recordContract`：每個案例新的 `Redactor` 與 `Log`、`CaseTransports(network: network).record(redactor, now: now)`、`recordCase(credentials: null)`；憑證掃描的問題在 `recordCase` 之後補上。
  - `checkPluginDirectory` 用 `loadIsolated`。`describeError(error, [log])` 保留給測試用的簽章，內部呼叫 lib 的版本（tag `contract`）。
- 驗證：prd「搬移不改行為」的測試清單不改斷言全綠。若有斷言非改不可，停下回報。

## 4. `installed_plugins.from_dev_folder`（schema v10）

- `tables.dart`：`late final fromDevFolder = boolean().withDefault(const Constant(false))();`（欄位名 `from_dev_folder`）；`schemaVersion` 10；`stepByStep` 的 `from9To10` 只 `addColumn`。照 `.trellis/spec/app/data/index.md` § 改 schema：`build_runner`、`drift_dev make-migrations`、快照、三種 migration 測試。
- `plugin_repository.dart`：design §4.7 的三個改動；`InstalledPlugin.fromDevFolder`。
- 測試：prd 的 migration 與 `plugin_repository_test.dart` 條目。

## 5. 平台層與設定

- `files.dart` 加 `Future<String?> pickDirectory();`（註解：使用者取消回 `null`）；`file_picker_dialogs.dart` 以 `FilePicker.getDirectoryPath()` 實作。測試裡實作 `FileDialogs` 的假物件跟著加。
- `PlatformCapabilities.pluginDevTools`：建構子、`none`、`withoutMediaControls`、`platform.dart` 的 Windows（真）與 Android（假）；`platform_test.dart` 斷言兩個平台的值。
- `DeveloperNotifier.setPluginDevFolder(String? path)`；`developer_settings_test.dart` 加寫入與清空。
- 驗證：加 `flutter build windows --flavor dev`。

## 6. 載入開發資料夾

- `lib/plugins/dev/dev_folder.dart`（design §4.4）、`plugin_development.dart`（design §3.3、§4.5）。注意：
  - `ref.listen(pluginDevFolderProvider, …, fireImmediately: true)` 只在 `AsyncData` 時套用；`AsyncError` 記 log、當 `null`。
  - 所有動作排進同一條序列；套用前 `await ref.read(pluginRegistryProvider.future)`。
  - 記住「目前套用的資料夾路徑」，同一個路徑的重複通知不重套（`rescan` 除外）。
  - 載入失敗的原因經 `describeError(error, log, tag: 'plugins')`，`DevPlugin.problem` 存已遮蔽的字串。
- `plugin_registry.dart`：`build` 略過 `fromDevFolder` 的列；`restoreInstalled`（design §4.7）。
- `fmp_app.dart`：`ref.listenManual(pluginDevelopmentProvider, (_, _) {}, fireImmediately: true);`（同 `devPluginInstallProvider`）。
- `health_check.dart`：開發中的插件讀 `<目錄>/checks.json`；Debug 健康檢查區塊的案例數同樣。
- 測試：prd 的 `plugin_development_test.dart`、`health_check_test.dart` 條目。用到 registry 的既有測試若因新的依賴紅了（`platformCapabilitiesProvider` 沒 override 會拋錯），只在共用的測試 harness 補 override，不改斷言；`pluginDevelopmentProvider` 只有 `FmpApp` 與 dev 的測試會讀，理應不影響既有測試。

## 7. 跑案例

- `lib/plugins/dev/dev_case_runs.dart`（design §3.2、§4.6）。`run` 的流程：
  1. 已在跑就回；記下代際與模式；從 `pluginDevelopmentProvider` 找目錄。
  2. `Isolate.run(() => PluginFolder.read(dir))`；沒有 `file` 或沒有這個能力的案例 → 失敗結果（問題是讀取的問題）。
  3. `requiresLogin` 且不是重播：`credentialStoreProvider` 的 `activeCredentials(id)`，`null` → 略過（`DevSkip.requiresLogin`），不連網。
  4. 重播：`transports.replay(...)` + `runIsolatedCase(wait: noWait)`，問題＝`run.problems` + `transport.problems` + 未用到的 fixture。真實：`transports.real()`，等待照真的時間。錄製：`recordCase(..., shouldWrite: () => 代際沒變)`；`handEdited` 的略過對到 `DevSkip.handEdited`。
  5. 回傳值照 design §3.2 轉成縮排 JSON；所有字串經 App 的 `Redactor`。
  6. 代際變了就丟掉；否則寫進 `results` 並寫一筆 log（design §4.6）。
- `Log`、`Redactor`、`NetworkRecordIds` 用 App 的 provider（`logProvider`、`redactorProvider`、`networkRecordIdsProvider`）。
- 測試：prd 的 `dev_case_runs_test.dart` 條目。

## 8. 介面

- `lib/ui/debug/debug_plugin_dev.dart`：design §3.6 的版面。卡片標題沿用 `lib/ui/plugins/plugin_widgets.dart` 的 `PluginHeading`、`PluginTag`；回傳值的樣式沿用 Log 區塊的單筆詳細。
- `debug_page.dart`：`DebugSection.pluginDev`（`Icons.extension_outlined`），清單與內容只在 `pluginDevTools` 時有；`_logTag` 狀態，「查看 log」→ `_selected = log`、`_logTag = id`；從清單點 Log 時 `_logTag = null`。`DebugLog` 加 `initialTag`（以 `ValueKey(tag)` 讓篩選重設）。
- `plugins_page.dart`：design §3.5。讀 `pluginDevelopmentProvider`。
- 字串：`debug.pluginDev`、`debug.pd*`、`plugins.tagDev`、`plugins.devManaged`，三個語言；`dart run slang`。
- 測試：prd 的 widget 與 guideline 條目（`guidelines_test.dart` 的 `the Debug overview at …` 旁邊）。

## 9. 文件

- design §6 的五行更正（ADR 0015、ADR 0025、父 design 三處）。
- `app/AGENTS.md`：
  - § 平台層：`pluginDevTools`、`pickDirectory`（閘門 `platform_test.dart`）。
  - § 資料層：`from_dev_folder` 的意義與「`install` 一律寫假」（閘門 `plugin_repository_test.dart`）。
  - § 插件：開發工具一段（模式只作用於跑案例、隔離環境、殘留列在下一次啟動刪、載入失敗不退回、只有開發資料夾才有的插件卸載時保留帳號與憑證、registry 重建會丟開發版〔沒有閘門〕、讀列的元件看到的是已安裝版的 manifest〔沒有閘門〕）；「插件目錄」與「重播」「fixture 寫檔前經 Redactor」各條的檔案位置改成 `lib/`。
  - § 介面：Debug 的插件開發區塊與「查看 log」。
  - § Lint：表格的 `restrictedImports` 加 `core/network/fixture/`。
- `.trellis/spec/app/plugins/index.md`：契約執行器與開發工具的位置、App 內錄製怎麼用。
- 父 implement.md §16：勾掉 16b 的項目、加「PR 16b 留下的」（審查與實機發現的後續）。
