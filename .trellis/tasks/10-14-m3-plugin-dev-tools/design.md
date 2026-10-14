# 插件開發工具設計（M3b PR 16b）

父任務 design §12.5 是需求的權威來源；本檔只寫 §12.5 留給「PR 16 決定」的部分，以及落地時的模組邊界與介面。依據：ADR 0015 §決定 5–7、ADR 0025 §決定 1、2、7、ADR 0009、ADR 0030 §決定 11。前提：PR 16a（健康檢查，`feat/app-health-check`）先合併，`checks.json` 的解析與案例期望已在 `lib/plugins/health/checks.dart`。

## 1. 一句話

開發資料夾的插件載入成「開發中」、本次執行取代同 id 的已安裝版（App 其他地方用到的一律是真實連線的它）；「真實｜錄製｜重播」是**跑案例**的模式，每個案例在與命令列契約執行器**同一份程式碼**的隔離環境（記憶體資料庫、空的 storage 與憑證、新的 runtime 與 client）裡跑。

## 2. 模組與檔案

```
lib/core/
  json_shape.dart                    # 從 lib/plugins/json_shape.dart 移來（不依賴插件的任何東西）
  network/fixture/                   # restrictedImports：只給 lib/plugins/dev/ 與目錄內互相 import
    fixture.dart                     # 從 test/plugins/contract/ 移來（HttpFixture、fixtureShapes…）
    fixture_adapters.dart            # 同上（ReplayAdapter、RecordingAdapter），加 CaseTransport／CaseTransports
    ip_scrub.dart                    # 同上（錄製時換掉公網 IP；fixture_adapters 依賴它）
lib/data/
  database/open_app_database.dart    # 加 openInMemoryDatabase()
  database/tables.dart               # installed_plugins 加 from_dev_folder（schema v10）
  repositories/plugin_repository.dart# fromDevFolder、putDevFolderRow、removeDevFolderRows
lib/platform/
  files/                             # FileDialogs.pickDirectory（file_picker 13.1.0 的 getDirectoryPath）
  platform_capabilities.dart         # pluginDevTools（Windows 真、Android 假）
lib/plugins/
  plugin_registry.dart               # build 略過 from_dev_folder 的列；加 restoreInstalled
  dev/
    plugin_folder.dart               # 插件目錄的讀取（從 contract_runner 移來）、writeFixtures
    case_runner.dart                 # 隔離環境跑一個案例、recordCase（從 contract_runner 移來）
    dev_folder.dart                  # pluginDevFolderProvider、掃描資料夾、DevFolderState
    plugin_development.dart          # 載入／卸載／重新載入／對齊列（PluginDevelopment）
    dev_case_runs.dart               # 每插件的模式與跑案例（DevCaseRuns）
  health/health_check.dart           # 開發中的插件讀資料夾的 checks.json
lib/ui/debug/debug_plugin_dev.dart   # Debug 頁「插件開發」區塊
lib/ui/plugins/plugins_page.dart     # 「開發中」標記與停用的動作
lib/app/fmp_app.dart                 # 啟動時 listenManual(pluginDevelopmentProvider)
```

依賴方向（全部符合現有 lint 表，只多一條 `restrictedImports`）：

- `lib/core/network/fixture/` 用 `dio`（`externalPackageOwners` 以前綴 `lib/core/network` 判斷，子目錄也算）與 `lib/core/json_shape.dart`、`lib/core/redaction/`。
- `lib/plugins/dev/` import `fixture/`，但**不寫出 dio 的型別名稱**：`HttpClientAdapter` 只出現在 `fixture/` 的宣告裡，`dev/` 呼叫 `CaseTransports` 的方法、把 `transport.createAdapter` 這個 tear-off 交給 `SourceHttpClientFactory(createAdapter:)`。`SourceHttpClientFactory` 不動（它本來就只接受外部給的 adapter 工廠）。
- `lib/plugins/plugin_registry.dart` 不認得 `dev/`（不 import），只多「略過標記列」與 `restoreInstalled`。開發資料夾的載入由 `dev/plugin_development.dart` 呼叫 registry 既有的 `register`／`unregister`。
- `lib/ui/` import `lib/plugins/dev/` 的狀態型別，不 import `fixture/`。
- 測試不受 `restrictedImports` 限制；`test/plugins/contract/` 改為 import `lib/core/network/fixture/` 與 `lib/plugins/dev/`。

### 2.1 為什麼是 `lib/core/network/fixture/` 目錄，不是父 design §2.1 寫的兩個平鋪檔案

`fixture_adapters.dart` 還依賴 `ip_scrub.dart`，三個檔案一起搬。放一個目錄，`restrictedImports` 只要一條（同 `lib/platform/cache_directory` 的先例），哨兵也只多一行；平鋪就要三條。仍在 `lib/core/network/` 底下，ADR 0015 的更正文字照樣成立。父 design §2.1、§2.2 各加一行更正。

## 3. 決定

### 3.1 模式只作用於「跑案例」，案例在隔離環境跑（與父 design §12.5 的字面不同，要擁有者確認）

父 design §12.5 寫「`SourceHttpClientFactory` 依模式掛 adapter，切換時重建該插件的 client」，字面上是把 App 裡那個插件的 client 換掉。本設計改成：

- **App 裡的開發中插件一律真實連線**（搜尋頁、播放、帳號頁照常用它）。
- **模式決定案例怎麼跑**，每個案例各自新建：記憶體資料庫（裡面放一列給 storage 外鍵）、空的憑證、新的 QuickJS runtime、以對應 adapter 建的 client；跑完全部關掉。重播 = `ReplayTransport`，錄製 = `NetworkTransport(record: true)`，真實 = `NetworkTransport(record: false)`。
- 這個環境就是契約執行器現在的 `_Environment`／`_execute`，搬到 `lib/plugins/dev/case_runner.dart`，命令列與 App 內共用。

理由：

1. **錄的 fixture 要能在 CI 重播**。重播比對請求的順序，而插件會把狀態存進 storage：B 站存 `anonymousIdentity`、`wbiKeys`（`fmp-plugins/bilibili/bilibili.js:3296`、`:3416`），有值時就不發取得它們的請求。在 App 裡那個插件（storage 是真的、通常已有值）上錄，fixture 會少那幾個請求；`fmp-plugins` 的 CI 以空 storage 重播時第一個請求就對不上。只有空 storage 錄才對得上，而那正是契約執行器的環境。
2. **重播在 App 的一般使用裡沒有意義**：fixture 是「一個案例的依序請求」，搜尋頁打出的任意請求對不上；錄製也不知道要寫進哪個能力的目錄。
3. 「與命令列錄製同一個函式」直接成立：兩邊都呼叫 `recordCase`。

採用的慣例：Polly.js 的 `replay`／`record`／`passthrough` 模式、VCR 的 cassette——模式是「錄放這一段測試」的設定，不是整個 App 的網路開關；每個案例一份獨立的錄音。

### 3.2 案例的其他規則

- **每次跑都讀磁碟上的現況**（`.js`、`checks.json`、`fixtures/`），同命令列 `runContract(directory)`；App 其他地方用的是上次載入的版本，按「重新載入」才換。讀檔在 `Isolate.run`（YouTube 的 fixture 可能很大）。
- **一次只跑一個案例**（整個區塊；「全部執行」依序跑一個插件的每個案例），同健康檢查。
- **預設模式「重播」**（零聯網，與 CI 相同；ADR 0027 實機預設重播）。模式只在記憶體，換資料夾或卸載時清掉。
- **錄製不跳確認框**：照命令列錄製的規則（結果不符合 `checks.json` 不寫、手改過的 fixture 略過），選「錄製」時在卡片上顯示一行警告。插件資料夾是 git repo，誤錄以 `git checkout` 還原（VCR `record: :all` 的做法）。
- **`requiresLogin` 的案例**：重播用 `checks.json` 裡的假憑證（同契約執行器）；真實與錄製用 `CredentialStore.activeCredentials(id)` 當 `loginVerify` 的輸入（同健康檢查），沒登入就「略過：需要登入」、不連網。`loginVerify` 由插件自己以輸入組 Cookie、宿主在呼叫前把這組值加進遮蔽（`fmp-plugin.d.ts`），所以隔離環境用空的憑證存放就夠，16c 的重錄不需要再改程式。
- **遮蔽與 log**：隔離環境用 App 的 `Redactor`（已登記所有已登入帳號的憑證與家目錄，寧可多遮）與 App 的 `Log`（插件 `fmp.log` 的 tag 是插件 id，「查看 log」看得到案例執行時的 log；網路紀錄出現在網路區塊）、App 的 `NetworkRecordIds`；不回報網路狀態（同契約執行器）。命令列照舊每個案例新的 `Redactor` 與 `Log`。多遮只會讓 fixture 多幾個 `***`，重播時 `***` 不比值。
- **回傳值的顯示**：`checkItems(result)`（`fmp-plugin.d.ts` 的欄位名稱）→ `Redactor.redactValue` → 縮排 JSON，上限 32 KiB（超過截斷並標示）。`LoginAccount` 的 `userId`、`displayName`、`avatar` 一律顯示成 `***`／空（有沒有），畫面上不出現帳號名稱（父 implement.md § 真實帳號）。
- **跑的途中換資料夾、卸載、關閉開發者模式**：`DevCaseRuns` 以代際計數（同 design §4.9 的做法）丟掉結果，錄製在寫檔前一刻檢查代際、不寫；插件呼叫本身無法中斷，讓它跑完、關掉環境。
- **跑的途中按「重新載入」**：不影響進行中的案例（它用自己的 runtime，檔案在開始時已讀好），所以重新載入不必擋。

### 3.3 開發中的插件怎麼載入、卸載

`PluginDevelopment`（`lib/plugins/dev/plugin_development.dart`）是唯一的入口，所有動作經一條序列（前一個做完才做下一個）：

- **觸發**：`build` 以 `ref.listen(pluginDevFolderProvider, fireImmediately: true)` 監看「生效的資料夾」（平台宣告 `pluginDevTools` 且開發者模式開著且 `plugin_dev_folder` 有值，否則 `null`）。`FmpApp` 以 `listenManual` 讓它在啟動時就活著（同 `devPluginInstallProvider` 的先例）。選資料夾、卸載、關閉開發者模式（`turnOffDeveloperMode` 已在同一筆寫入清空 `plugin_dev_folder`）都只是改設定，由這裡接手。
- **套用一個資料夾**（含 `null`）：
  1. 對上一次開發中的每個 id：`registry.unregister(id)`。
  2. 掃描新資料夾（`scanDevFolder`）。
  3. 對齊 `installed_plugins`（§3.4）：刪掉不在新資料夾裡的標記列，為新資料夾裡沒有任何列的 id 補標記列、已有標記列的更新內容、已安裝的列不動。
  4. 上一次有、這一次沒有的 id：`registry.restoreInstalled(id)`（有已安裝且啟用的列才載入）。
  5. 新資料夾的每個插件：`scriptPluginLoader.load` → `registry.register`。
- **「重新載入」（單一插件）**：重讀那個目錄 → 載入 → `register`（取代並關掉舊 runtime 與媒體 client）；標記列一併更新內容。manifest 的 id 變了就算失敗（「id 改變了，請重新掃描資料夾」）。
- **「重新掃描資料夾」**：以目前的資料夾再套用一次（新增或刪掉的插件目錄要靠它）。
- **載入失敗（含重新載入失敗）**：`registry.unregister(id)`，**不退回已安裝版**；卡片標「載入失敗」並顯示已遮蔽的原因（`describeError`），另以 `log.report` 寫 tag `plugins`；手動重新載入另跳提示。理由：退回已安裝版會讓人以為自己的新程式在跑。慣例：VS Code 擴充功能啟用失敗時就是沒有啟用、錯誤顯示在通知與輸出；LX Music 自訂源初始化失敗標在那個源上。
- **啟動時的空窗**：registry 先載入已安裝的插件，`PluginDevelopment` 隨後換成開發版，中間有一小段是已安裝版（或沒有）。只影響開發者，不處理。
- **registry 重建會丟掉開發版**：registry 目前沒有會變的依賴（從不重建），所以不處理；`app/AGENTS.md` 寫成已知限制（沒有閘門）。

慣例：VS Code 的 Extension Development Host——`--extensionDevelopmentPath` 的擴充功能在那個視窗取代同 id 的已安裝版，並以 `ExtensionMode.Development` 區分；手動「Reload Window」，不監看檔案。LX Music「切換＝銷毀重建」。

### 3.4 開發工具補的列：存在 `installed_plugins.from_dev_folder`（schema v10）

- **欄位**：`from_dev_folder` bool，not null，預設假。真＝這一列是開發工具為了 `plugin_storage` 的外鍵補的，不是使用者裝的。
- **不用記憶體集合**：App 在載入中途或開著開發資料夾時被結束，記憶體裡的標記就沒了，下次啟動分不出哪一列是補的——它會變成一個永遠刪不掉、腳本是開發版的「已安裝插件」。
- **對齊時機**：`PluginDevelopment` 每次套用資料夾（含啟動時、`null` 資料夾），所以殘留列在**下一次啟動**就被刪掉（storage 經外鍵一起刪）。Android 沒有這個能力，生效資料夾一律 `null`，對齊只會刪（不會有列）。
- **registry 的 `build` 略過標記列**：它們不是已安裝的插件；有資料夾時由 `PluginDevelopment` 載入開發版，沒有時下一步就被刪。
- **`PluginRepository.install` 寫入 `from_dev_folder = false`**：開發中時若有同 id 的插件被正式安裝（例如在另一個流程裡），那一列轉成已安裝的列，卸載時不會被刪（storage 保留）。
- **已安裝的列被沿用時**：manifest、腳本、版本、`enabled` 都不動，storage 共用（父 design §12.5）。開發版的 manifest 若比已安裝版多了 `login` 等能力，讀列的元件（例如 `CredentialStore` 判斷誰宣告 `login`）看到的是已安裝版的 manifest——已知限制，寫進 `app/AGENTS.md`。
- **只有開發資料夾才有的插件，卸載時只刪列與 storage**：它的帳號列與憑證保留（重新載入資料夾後仍是登入狀態）；要清就先在帳號頁登出再卸載。理由：完整的移除流程（`AccountService.removePlugin`）讀 registry，從卸載流程呼叫它要處理相依；開發者用得到、一般使用者碰不到。寫進 `app/AGENTS.md`。

慣例：VS Code 解除安裝擴充功能時先寫進 `extensions/.obsolete`，下次啟動才真正清掉——持久化的標記加啟動時的清理。

### 3.5 「開發中」在其他地方的呈現

- **插件頁**（ADR 0030 §決定 11 已列「開發中」標記）：已安裝分頁的那張卡片加標記「開發中」，名稱與版本顯示**載入的開發版** manifest（載入失敗時顯示列上的）；啟用開關、更新、移除停用，下面一行說明「開發中的插件由 Debug 頁『插件開發』管理，卸載後才能啟用、更新或移除」。「全部更新」略過開發中的 id；可安裝分頁裡開發中的 id 顯示「開發中」、沒有安裝鈕。理由：這些動作會 `register` 已安裝版、蓋掉開發版，或刪掉開發版正在用的列與 storage。
- **健康檢查**：開發中的插件讀資料夾的 `checks.json`（父 design §12.5），用 App 裡那個開發版跑（真實連線，同其他插件）。
- **其他地方不加標記**（搜尋頁音源列、佇列、診斷包）：開發者知道自己載入了什麼；診斷包顯示的版本是列上的版本，不另外處理（「不做」）。

### 3.6 Debug 頁「插件開發」區塊的版面與互動

位置照 ADR 0025 §決定 2 的表：音源健康檢查之後、資料庫之前；`DebugSection` 加 `pluginDev`，只在 `capabilities.pluginDevTools` 時列出（清單與內容都看它）。

**單欄、每個插件一張卡片**，不在 Debug 的 list-detail 裡再做一層 list-detail：Debug 右側在 1000 寬只有約 720，再切兩欄太擠；3 個插件的卡片直接攤開就看得完。與健康檢查區塊、插件頁的卡片一致。

```
說明一行：資料夾裡的每個插件目錄（一個 .js、checks.json、fixtures/）載入成「開發中」……
┌ 資料夾 ──────────────────────────────────────────────┐
│ ~\src\fmp-plugins（未選：還沒選資料夾）                  │
│ [選擇資料夾] [重新掃描] [卸載]       （套用中：進度條）   │
│ 資料夾層級的問題：不存在／沒有插件目錄／x 與 y 的 id 相同  │
└──────────────────────────────────────────────────────┘
┌ Bilibili  bilibili · 1.1.0   [開發中] [取代已安裝 1.0.0] ┐   ← 或 [載入失敗] + 原因
│ 模式 (重播｜錄製｜真實)  [重新載入] [查看 log] [全部執行]   │   ← Wrap，窄時換行
│ （選錄製時）錄製以真實連線執行，結果符合 checks.json 時…   │
│ ───────────────────────────────────────────────────── │
│ ✓ search        通過 · 312 ms · 重播            [▶]    │   ← 點列展開／收起
│     回傳值（縮排 JSON，可選取）  [複製]                   │
│ ✗ resolveStream 失敗 · 88 ms · 重播 · NetworkError [▶]  │
│     期望不符與重播不符的說明（可選取）                     │
│ – login         略過：需要登入，目前沒有登入         [▶]  │
└──────────────────────────────────────────────────────┘
```

- **模式切換在卡片標題下的 `SegmentedButton`**（每插件一個），旁邊是「重新載入」「查看 log」「全部執行」；每個案例列的尾端是「執行」（▶），跑的時候換成小的進度圈。慣例：VS Code 測試檢視（Test Explorer）每個測試與每組各有執行鈕、狀態圖示、展開看輸出；Postman Collection Runner 每個請求一列通過／失敗，展開看回應。
- **結果列**：狀態圖示、能力名稱、「通過／失敗／略過 · 耗時 · 模式 · 錯誤類別」。展開後：錯誤說明、問題清單（期望不符、重播比對不到與沒用到的 fixture、錄製的問題）、錄製的「已寫入 n 個 fixture」或「沒有寫入（結果不符合 checks.json）」、回傳值。全部是 `SelectableText`、已遮蔽。
- **「查看 log」**：切到 Log 區塊並把 tag 篩選設成該插件 id（ADR 0025 §決定 7「log 預設篩成該插件的 tag」）。之後使用者自己從清單點 Log 時不帶篩選。不在卡片裡另做一份 log 檢視（重用 Log 區塊的複製、匯出、含之前的紀錄）。慣例：VS Code 每個擴充功能一個 Output 頻道，「Show Output」直接切到那個頻道。
- **按鈕何時停用**：套用資料夾中（`DevFolderState.busy`）停用選擇／重新掃描／卸載／重新載入；有案例在跑時停用所有「執行」「全部執行」與那個插件的模式切換；載入失敗的插件仍可跑案例（案例讀磁碟、不用 App 裡的 runtime，失敗訊息有助於找原因）。
- **提示**（統一提示）：手動「重新載入」成功「已重新載入 {名稱} {版本}」、失敗「重新載入失敗：{名稱}」（細節在卡片上）。跑案例不跳提示（結果就地顯示）。
- **路徑顯示**經 `Redactor.redact`（家目錄換成 `~`，同概覽的資料目錄）。
- 字串一律 slang（`debug.pd*`、`plugins.tagDev`、`plugins.devManaged`），間距與尺寸用 token，guideline 測試 400 與 1000 寬、淺色深色。

### 3.7 不做檔案監看

ADR 0025 §考慮過的選項已否決（編輯器存到一半會讀到半個檔；MusicFree、LX Music 都沒有）。補充：Obsidian 的熱重載是第三方插件（opt-in），核心是手動停用再啟用；VS Code 預設也是手動 Reload Window。手動「重新載入」與「重新掃描資料夾」就夠。

## 4. 介面

只列跨檔案的簽章；內部照現有程式碼的寫法（`contract_runner.dart` 是搬移的來源）。

### 4.1 `lib/core/network/fixture/fixture_adapters.dart`（加）

```dart
/// 一個案例送出請求的方式（ADR 0015 §決定 5、7）。每個案例建一個、只建一次 client：
/// `SourceHttpClientFactory(createAdapter: transport.createAdapter)`。
sealed class CaseTransport {
  HttpClientAdapter createAdapter();
  /// 比對不到、送到清單外、回應不是 UTF-8 等；空的就是沒有。
  List<String> get problems;
}

final class ReplayTransport extends CaseTransport {   // 包 ReplayAdapter
  List<String> get unused;                             // 沒被請求用到的 fixture 名稱
}

final class NetworkTransport extends CaseTransport {  // record 為真時包 RecordingAdapter
  List<HttpFixture> get recorded;                      // record 為假時永遠是空的
}

/// 建 [CaseTransport]。真實連線的 adapter 來自 [network]，測試換成假上游。
final class CaseTransports {
  const CaseTransports({this.network = IOHttpClientAdapter.new});
  final HttpClientAdapter Function() network;
  ReplayTransport replay(List<NamedFixture> fixtures, Redactor redactor, AllowedHosts allowedHosts);
  NetworkTransport real();
  NetworkTransport record(Redactor redactor, {DateTime Function() now = DateTime.now});
}
```

`ReplayAdapter`、`RecordingAdapter`、`NamedFixture` 照舊公開（內容不改）。

### 4.2 `lib/plugins/dev/plugin_folder.dart`

```dart
/// [root] 本身有 .js 就是一個插件目錄，否則是底下有 .js 的子目錄（依名稱排序）。
List<Directory> pluginDirectories(Directory root);

/// 讀好的插件目錄：只檢查格式（一個 .js、manifest、checks.json、fixtures/<能力>/*.json）。
/// [inspectFixture] 在每個 fixture 讀好時呼叫（契約執行器以它加網域與憑證掃描，問題的順序與現在相同）。
final class PluginFolder {
  factory PluginFolder.read(
    Directory directory, {
    void Function(String name, HttpFixture fixture, List<String> problems)? inspectFixture,
  });
  final Directory directory;
  PluginFile? get file;
  List<PluginCheck> get checks;
  Map<String, List<NamedFixture>> get fixtures;   // 鍵是能力名稱
  List<String> get problems;
  PluginManifest get manifest;
  String get label;
}

/// 寫進 [target]（`fixtures/<能力>/`）：先刪原有的 .json，依序寫 001.json…；沒有 fixture 時
/// 連空目錄一起刪。命令列錄製與 App 內錄製共用（經 recordCase）。
void writeFixtures(Directory target, List<HttpFixture> fixtures);
```

### 4.3 `lib/plugins/dev/case_runner.dart`

```dart
final class CaseRun {
  final bool loaded;
  final Object? result;
  final AppError? error;
  /// 不含能力名稱前綴：'load: …'、'threw X, not an AppError'、
  /// 'tried to reach a host outside allowedHosts (…)'、期望不符、expiresAt 的問題。
  final List<String> problems;
  /// 結果符合案例的期望。
  final bool matched;
}

/// 隔離環境跑 [check]：openInMemoryDatabase() 放一列 installed_plugins、空的憑證存放、
/// 新的 ScriptPluginLoader 與 SourceHttpClientFactory(createAdapter: transport.createAdapter)；
/// 跑完關 runtime 與資料庫。[credentials] 只給 login 案例（換掉 checks.json 的假憑證）。
Future<CaseRun> runIsolatedCase({
  required PluginFile file,
  required PluginCheck check,
  required CaseTransport transport,
  required Log log,
  required Redactor redactor,
  required String reportTag,
  LoginCredentials? credentials,
  NetworkRecordIds? recordIds,
  Future<void> Function(Duration delay) wait = noWait,
});

/// 只載入一次（契約執行器的 checkPluginDirectory）；載入得了回 null。
Future<AppError?> loadIsolated({required PluginFile file, required Log log, required Redactor redactor});

/// [error] 寫成一行「類別名: 已遮蔽的原因」（經 log.report，tag 是 [tag]）。
String describeError(AppError error, Log log, {required String tag});

final class RecordResult {
  final List<String> problems;   // 已帶 '<能力>: ' 前綴，字串同現在的 recordContract
  final String? skipped;         // '<能力>: requires a login'、'<能力>: has hand-edited fixtures'
  final int? written;            // 寫了幾個檔；沒寫是 null
  final CaseRun? run;            // 略過時是 null
}

/// 以 [transport]（record 為真）跑 [check]，寫進 `<folder>/fixtures/<能力>/`。規則同現在的
/// recordContract：requiresLogin 而沒給 [credentials] → 略過；有 meta.edited 的 fixture → 略過；
/// 結果符合期望且錄製沒有問題才寫，否則原檔不動。[shouldWrite] 在寫檔前一刻呼叫，回假就不寫。
Future<RecordResult> recordCase(
  PluginFolder folder,
  PluginCheck check, {
  required NetworkTransport transport,
  required Log log,
  required Redactor redactor,
  required String reportTag,
  LoginCredentials? credentials,
  NetworkRecordIds? recordIds,
  Future<void> Function(Duration delay) wait = realWait,
  bool Function() shouldWrite = alwaysWrite,
});
```

隔離環境的憑證存放：`CredentialStore` 接在記憶體資料庫的 repository 與一個本檔私有的空 `SecureStorage`（讀回 `null`、寫入拋 `StateError`）上；`AccountGuard` 照契約執行器的寫法。

### 4.4 `lib/plugins/dev/dev_folder.dart`

```dart
/// 生效的插件開發資料夾：capabilities.pluginDevTools && developerMode && plugin_dev_folder != null
/// 時是那個目錄，否則 null。
final pluginDevFolderProvider = FutureProvider<Directory?>(...);

enum DevLoad { loaded, failed }

@immutable
final class DevPlugin {
  final String id;                    // manifest 的 id；讀不出 manifest 時是目錄名
  final Directory directory;
  final DevLoad load;
  final String? problem;              // 已遮蔽
  final PluginManifest? manifest;     // 載入成功時是開發版的 manifest
  final String? replacedVersion;      // 取代的已安裝版本；沒有已安裝的列是 null
  final List<PluginCapability> cases; // checks.json 的能力；讀不懂是空的（原因在 problem）
}

@immutable
final class DevFolderState {
  final Directory folder;
  final List<DevPlugin> plugins;      // 依目錄名
  final List<String> problems;        // 資料夾層級（不存在、沒有插件目錄、id 重複），已遮蔽
  final bool busy;                    // 套用或重新載入中
}
```

同 id 的兩個目錄：依目錄名排序，第一個載入，後面的記在 `problems`、不載入。

### 4.5 `lib/plugins/dev/plugin_development.dart`

```dart
final pluginDevelopmentProvider =
    NotifierProvider<PluginDevelopment, DevFolderState?>(PluginDevelopment.new);

final class PluginDevelopment extends Notifier<DevFolderState?> {
  bool isInDevelopment(String pluginId);   // 含載入失敗的
  Future<void> reload(String pluginId);
  Future<void> rescan();
}
```

### 4.6 `lib/plugins/dev/dev_case_runs.dart`

```dart
enum CaseMode { replay, record, real }
enum DevCaseOutcome { passed, failed, skipped }
enum DevSkip { requiresLogin, handEdited }

@immutable
final class DevCaseResult {
  final PluginCapability capability;
  final CaseMode mode;
  final DevCaseOutcome outcome;
  final Duration elapsed;
  final String? errorType;
  final List<String> problems;  // 已遮蔽
  final DevSkip? skip;
  final int? written;           // 錄製寫了幾個檔
  final bool notWritten;        // 錄製而結果不符、沒寫
  final String? value;          // 縮排 JSON，最多 32 KiB
  final bool truncated;
}

@immutable
final class DevCaseRunsState {
  final Map<String, CaseMode> modes;
  final ({String pluginId, PluginCapability capability})? running;
  final Map<String, Map<PluginCapability, DevCaseResult>> results;
  CaseMode modeOf(String pluginId);   // 預設 replay
  bool get busy;
}

/// 測試以假上游 override。
final caseTransportsProvider = Provider<CaseTransports>((ref) => const CaseTransports());

final devCaseRunsProvider = NotifierProvider<DevCaseRuns, DevCaseRunsState>(DevCaseRuns.new);

final class DevCaseRuns extends Notifier<DevCaseRunsState> {
  void setMode(String pluginId, CaseMode mode);              // 那個插件在跑時忽略
  Future<void> run(String pluginId, PluginCapability capability);
  Future<void> runAll(String pluginId);
}
```

每跑完一個案例寫一筆 log：tag 是插件 id、訊息 `Plugin case`、欄位 `capability`、`mode`、`result`、`durationMs`、`errorType?`、`written?`（失敗用 warning，其他 info）。

### 4.7 其他層的小改動

- `PluginRepository`：`InstalledPlugin.fromDevFolder`（預設假，相等與 hash 一併改）；`install` 寫 `fromDevFolder: false`；`Future<bool> putDevFolderRow(InstalledPlugin plugin)`（沒有列就插入標記列、有標記列就更新 version／manifest／script、有已安裝的列不動；回傳這個 id 是不是標記列，一個 transaction）；`Future<List<String>> removeDevFolderRows({Set<String> keep = const {}})`（刪標記列中不在 [keep] 的，回傳刪掉的 id）。
- `PluginRegistry`：`build` 略過 `fromDevFolder` 的列；`Future<void> restoreInstalled(String pluginId)`：有未標記且啟用的列就載入並 `register`（失敗照 `build` 的做法 `log.report`）；未標記但停用就放進停用清單並發出新狀態；沒有列什麼都不做。
- `FileDialogs.pickDirectory()` → `Future<String?>`（使用者取消回 `null`）；`FilePickerDialogs` 以 `FilePicker.getDirectoryPath()` 實作（13.1.0，已查 pub cache 的 `lib/src/file_picker.dart:136`）。
- `PlatformCapabilities.pluginDevTools`（`none` 為假；Windows 真；Android 假，ADR 0025「之後要注意」：Android 要 SAF 讀目錄另立 ADR）。
- `DeveloperNotifier.setPluginDevFolder(String? path)`：`null` 清欄位，否則寫入；只寫這個欄位。
- `openInMemoryDatabase()`：`AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true))`（契約執行器現在的寫法）。
- `HealthCheck`：插件在開發中時，案例來源是 `<目錄>/checks.json` 的內容（沒有檔就當沒有案例）；Debug 健康檢查區塊的案例數同樣讀它。

## 5. 閘門

| 規則 | 閘門 |
|---|---|
| `lib/core/network/fixture/` 只給 `lib/plugins/dev/` | `fmp_layer_imports` 的 `restrictedImports`；`layer_imports_test.dart` 雙向變異；`tool/lint_sentinel.dart` 一行 import 加 `_expectedMessages` 一則 |
| 命令列與 App 內錄製同一個函式、同樣的輸出 | `dev_case_runs_test.dart`：同一個假上游與時鐘，App 內錄製與 `recordContract` 寫出的目錄逐位元組相同；`record_test.dart` 照舊全綠 |
| 案例在隔離環境跑（不碰 App 的 storage） | `dev_case_runs_test.dart`：App 資料庫裡 `fmp-test` 的 storage 有 `titlePrefix`，跑 `search` 的結果標題仍是 `Test tone`、App 的 storage 不變 |
| 開發工具補的列的生命週期 | `plugin_development_test.dart`、`plugin_repository_test.dart`（§6 的條目） |
| 插件開發區塊依 `pluginDevTools` 出現 | `debug_page_test.dart`（ADR 0025 §如何確認的 widget 測試） |
| 開發中的插件在插件頁不能被蓋掉 | `plugins_page_test.dart` |

## 6. 文件更正（只加一行，不改決定）

| 文件 | 內容 |
|---|---|
| ADR 0015 §決定 6 | 更正（M3 PR 16b）：錄製與重播的 adapter 與 fixture 格式的解析移到 `lib/core/network/fixture/`、`checks.json` 的解析與案例期望移到 `lib/plugins/health/`、插件目錄的讀取與每個案例的隔離執行環境與寫檔移到 `lib/plugins/dev/`（App 內開發工具與健康檢查使用），`app/test/plugins/contract/` 改為引用它們、只留憑證掃描等測試專用的檢查，格式不變；上一則更正的「放進 `lib/` 違反分層」只指零聯網的測試準備（矛盾 10）。16a 若已為 `checks.json` 加了一行，改寫那一行，不另加第二行 |
| ADR 0025 §決定 7 | 補充（M3 PR 16b）：真實／錄製／重播是跑案例的模式，每個案例在隔離環境（空的 storage 與憑證、新的 runtime 與 client）以對應的 adapter 執行，與命令列契約執行器同一份程式碼；App 其他地方用到的開發中插件一律真實連線。開發工具補的 `installed_plugins` 列以 `from_dev_folder` 標記，每次套用資料夾（含啟動）時對齊 |
| 父 design §2.1、§2.2 | 更正（M3 PR 16b）：fixture 的三個檔案在 `lib/core/network/fixture/`，`restrictedImports` 一條（目錄） |
| 父 design §3.1 | 更正（M3 PR 16b）：`installed_plugins` 加 `from_dev_folder` bool（預設假），schema v10 |
| 父 design §12.5 | 更正（M3 PR 16b）：模式只作用於跑案例（本檔 §3.1）；來源標記存 `installed_plugins.from_dev_folder`，殘留列在下一次啟動時刪（本檔 §3.4） |
