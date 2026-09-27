# 研究：Dart 自訂 lint 現況與 FMP 靜態規則落地方案

> 對應 `.trellis/tasks/09-27-design-testing` 研究第 1 點：Dart 自訂 lint 現況
> （`analysis_server_plugin`／`custom_lint`／第三方工具）、能否表達 ADR
> 0009–0013 要求的四類規則、`flutter analyze` 是否會顯示這些診斷、以及
> lint 規則本身的雙向變異測試怎麼做。
> 查證方式：官方文件與原始碼（WebFetch／context7）、GitHub issue／PR
> 一手來源、pub.dev／dcm.dev 官方頁面（WebSearch＋WebFetch）。查不到的
> 一律寫「查不到」，推論一律標「推測」。查證時間 2026-09-27。

---

## 第 1 點之一：官方 `analysis_server_plugin` 現況

Dart SDK 3.10 起，官方提供新一代 analyzer plugin 系統
`analysis_server_plugin`，取代舊的 legacy plugin 協定：

- 套件：<https://pub.dev/packages/analysis_server_plugin>
- 撰寫規則指南：<https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server_plugin/doc/writing_rules.md>
- 撰寫插件指南：<https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server_plugin/doc/writing_a_plugin.md>
- 使用插件指南：<https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server_plugin/doc/using_plugins.md>
- 測試規則指南：<https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server_plugin/doc/testing_rules.md>
- Dart 官方總覽頁：<https://dart.dev/tools/analyzer-plugins>

結構：一個 analyzer plugin 是一般 Dart 套件，入口在 `lib/main.dart`
匯出頂層 `plugin` 變數；每條規則拆成 `AnalysisRule`（規則本體）＋
`SimpleAstVisitor`（AST 走訪），用 `registerNodeProcessors` 註冊、
`rule.reportAtNode(node)` 回報診斷。啟用方式是在消費專案的
`analysis_options.yaml` 頂層 `plugins:` 區塊列出套件，**規則預設不開，
要逐條在設定檔打開**（來源：`writing_rules.md`／`using_plugins.md`）。

### `custom_lint`（社群方案）現況：已封存、已被 SDK 正式棄用其依賴的舊協定

- **Repo 已封存**：GitHub 顯示 `invertase/dart_custom_lint` 由 owner 於
  2026-03-24 封存，唯讀狀態（來源：GitHub repo 頁面 metadata，透過
  WebSearch 查得該日期；第三方一份 README 寫封存日是 2026-05，以
  GitHub 官方封存通知的 2026-03-24 為準）。
- **停在舊版 analyzer**：`custom_lint` 最新版 0.8.1（發布於
  2025-09-09），鎖定 `analyzer ^8.0.0`；目前 `analyzer` 已到 14.x，
  沒有任何已發布的 `custom_lint_builder` 相容新版 analyzer
  （來源：pub.dev 版本頁 <https://pub.dev/packages/custom_lint/versions>
  ＋ WebSearch 綜合，pub.dev 頁面本身未寫「deprecated」字樣，此為
  用版本號與封存狀態推論出的現況，非套件自我聲明）。
- **在新 SDK 上會壞**：`dartway_lints` 專案回報在 Flutter
  3.47.2／Dart 3.13 pin 下，`custom_lint` 於 IDE analyzer 內丟出
  `Unknown request: analysis.setAnalysisRoots` 而崩潰
  （來源：GitHub issue，經 WebSearch 摘要取得，未逐字覆核 issue 全文，
  故此點標記部分推論）。
- **SDK 官方棄用時間軸**：
  - Dart SDK issue #62164〈Deprecating the legacy analyzer plugin
    system〉，2025-12 開立，官方目標是棄用 `custom_lint` 所依賴的舊
    plugin 協定：<https://github.com/dart-lang/sdk/issues/62164>
  - **Dart 3.13.2**（2026-08-25 發布）的 changelog 正式將舊 plugin
    系統標記為 deprecated（來源：WebSearch 摘要 Dart changelog
    <https://dart.dev/changelog> 條目，未逐字複製全文措辭）。
  - Dart SDK issue #64188〈Remove legacy analyzer plugin system〉
    （2026-09-02 開立）：「舊系統已於 3.13.2 棄用，未來某個穩定版將
    開始移除（先停用執行舊插件）」：
    <https://github.com/dart-lang/sdk/issues/64188>

**結論**：`custom_lint` 不建議在 FMP 新專案 `app/` 採用——它依賴的協定
已被 SDK 正式列入棄用／移除時程表，套件本身已封存且技術上已在目前
Dart 版本上出現崩潰。FMP 應直接以官方 `analysis_server_plugin` 為
基礎（riverpod_lint 已完成遷移，見下）。

### 生態系遷移現況佐證

- `riverpod_lint` 已改用 `analysis_server_plugin` 實作
  （來源：WebSearch 摘要 riverpod GitHub issue 討論串內容，pub.dev
  頁面 <https://pub.dev/packages/riverpod_lint>／changelog
  <https://pub.dev/packages/riverpod_lint/changelog> 可交叉核對版本
  時間，此處僅摘要「已遷移」的事實陳述，未逐條核對每個版本號）。
- `import_lint` 的 pub.dev 頁面（查閱日 2026-09-27 顯示的頁面更新
  日期為 2026-04-18）已要求 Dart 3.10+ 並使用新版 `plugins:` 設定：
  <https://pub.dev/packages/import_lint>；changelog：
  <https://pub.dev/packages/import_lint/changelog>（**查不到**具體是
  從哪個版本號開始遷移——changelog 頁面查得的最新可讀條目是舊格式，
  版本號需要直接開 pub.dev 頁面核對，此處不虛構版本號）。
- 遷移實戰文章（第二手來源，僅供交叉參考、不作為權威）：
  <https://leancode.co/blog/migrating-to-dart-analyzer-plugin-system>、
  <https://verygood.ventures/blog/creating-your-first-dart-analyzer-plugin-with-the-new-plugin-system/>

---

## 第 1 點之二：關鍵風險——`flutter analyze` 是否會顯示 plugin 診斷

這是 FMP 能否採用 `analysis_server_plugin` 的**前提性風險**，因為
`AGENTS.md` 現有 CI 閘門明文是 `flutter analyze`（見
`AGENTS.md`「Verification」表格與「`flutter analyze` and the
`dart format lib test tool` CI gate」一句）。

**現況（2026-09-27 查證）：這是一個仍未修復、已知存在的 bug。**

- `flutter/flutter#193203`〈`flutter analyze` hides analyzer plugin
  diagnostics and reports "No issues found!"〉，2026-09-23 提出，已被
  標記為 `#187999` 的重複單：
  <https://github.com/flutter/flutter/issues/193203>
- 回報環境與 FMP 目前用的版本非常接近：**Flutter 3.47.5（stable，
  commit 6a19cca）、Dart 3.13.4**。回報內容：`flutter analyze`（即使
  在套件根目錄執行）與 `dart analyze <目錄>` 都印出「No issues
  found!」、完全不含 plugin 診斷；只有對**單一檔案**路徑執行
  `dart analyze` 才會顯示 plugin 診斷。核心 lint（非 plugin）不受影響，
  一樣正常顯示——也就是說用 `flutter analyze` 跑 CI 會「安靜地放行」
  所有 plugin 規則的違規，`flutter analyze` 顯示通過不代表真的通過。
- 官方文件的說法（`analysis_server_plugin` 相關頁面）宣稱 plugin
  診斷「在 IDE 與命令列執行 `dart analyze` 或 `flutter analyze` 時都
  可取得」——目前與這個已知 bug 的實測結果矛盾。
- 根因與修復進度：Dart SDK PR #63805〈Defer analysis-complete
  notification until plugins finish〉指出問題在於 analysis server 會
  在 plugin 分析**尚未完成**時就送出 `$/progress kind:end`
  （及對應的 `analyzerStatus` 通知），導致 LSP client（`flutter
  analyze` 的底層機制）誤判分析已結束、在 plugin 診斷真正發布前就
  收工。該 PR 的討論串顯示「Gerrit CL 已核准，等待 reviewer merge」，
  但**查不到明確證據顯示此修復已經合併進 stable**（來源：WebSearch
  摘要該 PR 討論串內容，未直接開 Gerrit 頁面核對合併狀態，標記
  「查不到」而非猜測已修復或未修復）。
- **社群目前的因應方式**：改跑 `dart analyze --fatal-infos`（在套件
  根目錄執行，而非 `flutter analyze` 或對子目錄跑 `dart analyze`），
  或是在 CI 中額外放一個「必定觸發某條 plugin 規則」的哨兵測試檔，
  只靠「No issues found!」不足以證明 plugin 規則真的有跑（第二個
  作法來自另一個遷移專案的 CI 修復方式，WebSearch 摘要，未看到原始
  PR diff）。

### 對 FMP 的具體建議

1. **CI 的 lint 步驟不能只依賴 `flutter analyze`**：至少要加一個
   `dart analyze --fatal-infos`（在 `app/` 目錄下執行）或直接用
   `dart analyze` 對整個套件根目錄執行，兩者都要留著，因為
   `flutter analyze` 仍然要拿來檢查 Flutter 專屬的分析行為
   （例如它認得 `.dart_tool/package_config.json` 裡 Flutter SDK 的
   部分，`dart analyze` 有時反而看不到某些 Flutter 特定診斷——這是
   **推測**，未實測驗證兩者診斷集合的確切差異，落地前必須在
   `app/` 建好骨架後親自跑一次兩個指令比對輸出）。
2. **無論選哪個指令，落地前必須先建一個「哨兵規則違規」測試固定檔**
   （例如一個刻意 `print()` 的假檔案），跑一次 CI 確認它真的被攔下、
   而不是「沒有輸出＝規則沒生效」被誤判為通過。這與下方「雙向變異
   測試」的精神一致，只是層級提高到「整條 CI pipeline 有沒有接上
   plugin 診斷」而非「單一規則邏輯對不對」。
3. 這個 bug 屬於 Dart/Flutter 工具鏈本身的暫時性缺陷，不影響「該不該
   採用 `analysis_server_plugin`」的長期判斷（生態系已經全面遷移、
   `custom_lint` 已停滯），但**會影響 FMP 現在（2026-09）能不能只信任
   `flutter analyze` 這一個指令**——這點必須寫進 CI 設計，不能假設它
   會在可預見時間內修好。

---

## 第 1 點之三：ADR 要求的四類規則，各工具能不能表達

FMP 需要用靜態規則表達的類型（依 ADR 0008–0014 逐條列出）：

| 類型 | 具體規則 | 來源 ADR |
|---|---|---|
| (a) 目錄 A 不得 import 目錄 B | `app/` 不得 import 根目錄舊專案；`lib/core/`／`lib/data/` 不得 import `lib/services/`／`lib/providers/`；`legacy_import` 模組不得被其他模組 import | 0008、既有 `AGENTS.md` Layers、0010 |
| (b) 符號 X 只能在目錄 Y 內使用 | `isar.` 只能出現在 repositories 層；`talker` 只能在 log 門面內直接 import | 既有 `AGENTS.md` Isar access、0011 |
| (c) 禁止空 catch／靜默吞錯 | 不只 `catch (_) {}`，含「catch 到但沒有任何後續動作」 | 0013 |
| (d) 禁止 `print`／`debugPrint`／`developer.log`／直接 `talker` 呼叫 | 只能經單一 log 門面 | 0011 |
| (e，0014 新增) UI／service 不得出現音源 id 字串常數或特定音源型別 | 見下方專節說明，這條**沒有任何工具能直接做到** | 0014 |

### (a) 目錄間 import 限制

**可以做到**，且有兩條路：

- **DCM `avoid-banned-imports`**：官方文件
  <https://dcm.dev/docs/rules/common/avoid-banned-imports/>，設定為
  `entries` 陣列，每筆有 `paths`（regex，適用哪些檔案）、`deny`
  （禁止 import 什麼）、`message`、選填 `severity`，另有 `exclude-paths`
  可排除例外檔案。DCM 官方還有一篇專門的架構治理指南
  〈Enforcing Architecture Boundaries with DCM〉
  <https://dcm.dev/docs/guides/advanced-architecture-rules-guide/>，
  裡面的範例就是「禁止 `lib/` 內非 `core/` 的地方 import
  `flutter_bloc`」「禁止 web 目標檔案 import `dart:io`」這種形狀，與
  FMP「`app/` 不得 import 根目錄舊專案」「`legacy_import` 不得被其他
  模組 import」幾乎是同一種規則的不同參數。**注意**：文件特別提醒
  Windows 裝置上 `paths` 的 regex 要注意路徑分隔符號，這對在 Windows
  上開發的 FMP 有直接影響，落地時要驗證。
- **官方 `analysis_server_plugin` 自寫規則**：FMP 現有
  `test/support/layer_boundary_static_rule_test.dart` 本來就是手刻
  AST／字串掃描邏輯，改寫成一條 `AnalysisRule` 是同等工作量的搬遷，
  差別只在於錯誤是「lint 診斷」而非「測試失敗」，可以在 IDE 即時顯示
  （若前一節的 `flutter analyze` bug 修好的話）。

### (b) 符號限制在目錄內

**可以做到，而且是「順便」做到**：Dart 語言規則是「要呼叫某個
extension 方法或存取某個型別的成員，必須先 import 定義它的
library」，所以只要用 (a) 的機制把 `package:isar_community/isar.dart`
這類 import **在允許目錄以外全面禁止**，呼叫端根本沒有辦法在沒有
import 的情況下寫出 `isar.xxx`——**禁止 import 等於連帶禁止了符號
使用**，不需要額外一條「禁止某符號」的規則。DCM 的
`avoid-banned-imports` 或自寫 import-lint 規則两者皆可達成，不需要
額外用到 `banned-usage`。

`talker` 直接呼叫的限制同理：只要 `talker` 套件的 import 被限制在
log 門面檔案內，門面以外的程式碼物理上無法直接呼叫
`talker.xxx()`。

### (c) 空 catch／靜默吞錯

**官方 `empty_catches` 有明確、經官方文件證實的漏洞**：

- 官方文件：<https://dart.dev/tools/linter-rules/empty_catches>
- 規則文字：「AVOID empty catch blocks」，**但官方文件自己給出的
  合規寫法之一就是 `catch (_) { }`**——文件原文："the exception
  identifier can be named with underscores (_) to indicate that we
  intend to skip it"，也就是說**用底線命名的空 catch 是被這條規則
  視為「有意為之」而不會被標記**。
- 這與 FMP 的 ADR 0013 意圖直接衝突——ADR 0013 明講「禁止空 catch
  與靜默吞錯」，而不是「允許用底線變數名稱表示的有意跳過」。舊專案
  的 507 個 catch 中約 70 個是空的（`docs/audit/errors.md`
  背景數字），這類程式碼很可能一部分就是 `catch (_) {}` 形式，官方
  `empty_catches` 對這部分完全沒有防護力。

**FMP 需要更嚴格的規則，官方內建 lint 不夠，需要自訂**：一條自訂
`AnalysisRule`，邏輯是「catch 子句的 body 沒有任何會被觀測到的
副作用陳述式」（body 為空、或只有註解、或只有 `_ = e;` 這類假動作），
**不管 catch 變數叫什麼名字**。DCM 沒有現成對應規則名稱可以直接設定
達成這麼精確的語意（`banned-usage`／`avoid-banned-imports`
都不是為此設計），這條建議走**自寫 `analysis_server_plugin` 規則**
路線，理由見下方「建議」小節。

### (d) 禁止 `print`／`debugPrint`／`developer.log`／直接 `talker` 呼叫

- 官方 `avoid_print`（<https://dart.dev/tools/linter-rules/avoid_print>）
  只覆蓋 `print()`，且**只在 `flutter_lints` 套件的規則集裡，不在
  核心 `lints` 套件**（來源：官方文件 all-rules 頁面分類）。不覆蓋
  `debugPrint`、`developer.log`。
- DCM `banned-usage`（<https://dcm.dev/docs/rules/common/banned-usage>）
  是專門為「禁止呼叫特定函式／方法／建構子／屬性」設計的規則，
  設定為 `entries`，每筆有 `name`（或 `name-pattern` 正規表達式）、
  `description`、`paths`、`exclude-paths`、`severity`。**這正是 FMP
  需要的形狀**：四條 entries 分別禁止 `print`、`debugPrint`、
  `developer.log`（或其 `name-pattern`）、`Talker`／`Talker.new`
  之類的建構子呼叫，並用 `exclude-paths` 排除 log 門面自己的檔案。
  官方文件特別提醒：這條規則會連外部套件／核心函式庫的呼叫一併
  抓到，所以要給精確的 `name`（例如用 `'DateTime.now'` 而非
  `'now'`）避免誤傷。
  - **版本沿革**：DCM 1.21.0（2024-08 發布）把原本一體適用「用法＋
    命名」兩種情境的 `banned-usage`（前身叫 `ban-name`）拆成兩條：
    `banned-usage` 專管「用法」（方法呼叫、屬性存取），
    `avoid-banned-names`（<https://dcm.dev/docs/rules/common/avoid-banned-names/>）
    專管「宣告命名」。FMP 這條規則屬於「用法」，對應
    `banned-usage`，不是 `avoid-banned-types`（那條是禁止**型別參照**，
    例如禁止在某處寫出 `SomeType` 這個型別名稱，用途不同，容易混淆
    但語意不對）。
- **DCL（Bancolombia fork，`dart_code_linter`）也有對應機制**：舊名
  `ban-name`，DCM 1.21.0 已把它從 DCM 拿掉、但 DCL 是更早的 fork，
  規則索引頁 <https://dcl.apps.bancolombia.com/docs/rules/> 仍列出
  `ban-name`（「Configure some names that you want to ban」），
  規則詳細頁**查不到**（搜尋時該頁未被索引到，需要直接開
  <https://dcl.apps.bancolombia.com/docs/rules/dart/ban-name/> 核對
  欄位名稱，落地前必須重新查證，此處不假設它與 DCM 舊版格式完全
  相同）。

### (e) 音源 id 字串常數／特定音源型別限制（ADR 0014）——**沒有工具能直接做到**

這條規則跟前面四條本質不同：前四條都是「**import 或呼叫某個具名
符號**」，可以用「先擋 import，符號自然用不了」的方式一次性解決；
但「音源 id 字串常數」通常只是普通 `String` 值（例如
`if (sourceId == 'bilibili')`），**Dart 語言不要求你 import 什麼
才能寫一個字串字面值**，任何 import-based 或 usage-based 規則都
沒有掛勾點可以攔。

- DCM 的 `avoid-banned-types`（<https://dcm.dev/docs/rules/common/avoid-banned-types>）
  能禁止**型別參照**（例如禁止在 `lib/ui/` 出現某個具名型別），但
  管不到「這個變數剛好裝了字串 `'bilibili'`」這種值層級的東西。
  `banned-usage` 的 `name`／`name-pattern` 比對的是**符號名稱**
  （方法、屬性、建構子），同樣不比對字串字面值的內容。
- **唯一能讓現有工具生效的做法是先做架構設計，把「音源 id」從
  裸 `String` 改成一個獨立型別**（例如 `SourceId` 值物件，或直接
  用 `SourcePlugin` 實例本身當作能力查詢的 key，UI／service 永遠不
  在自己的程式碼裡寫出具名音源的比較邏輯，而是依 ADR 0014 決定 3
  「UI 依能力出現入口」——UI 只問「這個能力有沒有提供者」，不問
  「音源是不是 bilibili」）。一旦音源 id 有了自己的型別
  （而不是裸 `String`），"禁止在 `lib/ui/`／`lib/services/` 之外
  參照這個型別的具體建構" 或 "禁止 import 定義具名音源模組的檔案"
  就變回 (a)(b) 類規則，可以用 `avoid-banned-imports`／
  `avoid-banned-types` 解決。
- **這是本研究對 ADR 0014 落實方式的具體建議**：把「不得出現音源 id
  字串常數」翻譯成「音源 id 必須是一個不能在 `lib/ui/`、
  `lib/services/` 之外具現化字面值的型別」，讓可驗證的部分回到
  現有工具能力範圍內；真正「裸字串比對」的殘餘風險（例如有人硬是把
  `SourceId` 型別的 `.value` 屬性拿出來跟字面值比較）**只能靠自寫
  `analysis_server_plugin` 規則掃描字串字面值**去補，或者接受這是
  design review 要盯的邊界情況，不強求 100% 工具化。這點需要擁有者
  在架構設計階段確認方向，見最終報告的待決策清單。

---

## 第 1 點之四：候選工具總表與建議

| 工具 | 授權／費用 | 維護狀態（2026-09） | 能表達 (a)(b) | 能表達 (c) | 能表達 (d) | 能表達 (e) |
|---|---|---|---|---|---|---|
| 官方 `analysis_server_plugin`（自寫規則） | 免費、Dart SDK 內建 | 官方在維護，是未來方向；`flutter analyze` 目前有已知顯示 bug（見上） | 可以（需自己寫） | 可以（需自己寫，且能寫出比 `empty_catches` 更嚴格的語意） | 可以（需自己寫） | 部分可以（字串字面值掃描需自己寫，見上） |
| `custom_lint`（`invertase/dart_custom_lint`） | 免費、MIT | **已封存（2026-03-24）、SDK 已棄用其依賴協定、在 Dart 3.13 上會崩潰** | 不建議採用 | 不建議採用 | 不建議採用 | 不建議採用 |
| DCM（`dcm.dev`，前身 Dart Code Metrics） | Free（50k LOC）／Pro $16/mo（150k LOC）／Teams $80/mo 5 席（不限 LOC）／Enterprise，全部本機分析。來源：<https://dcm.dev/pricing/> | 積極維護，商業產品，規則集完整、文件詳盡 | `avoid-banned-imports`，開箱即用 | 無精確對應規則，仍需自寫或接受 `empty_catches` 等級的鬆散度 | `banned-usage`，開箱即用 | 不行（同上，值層級規則） |
| DCL（`bancolombia/dart-code-linter`，DCM 的免費 fork） | 免費 | 有維護（見其 CHANGELOG），但規則文件不如 DCM 完整、`ban-name` 詳細頁查證時未能直接核對 | `avoid-banned-imports`，開箱即用 | 同上 | `ban-name`（舊式），欄位格式待落地時核對 | 不行 |
| `import_lint` | 免費 | 已遷移至 `analysis_server_plugin`（2.x 起，確切版本號查不到），仍在維護 | 只做 import 限制，比 DCM 陽春但夠用 | 不適用（非它的範圍） | 不適用 | 不行 |
| `layerlens` | 免費 | 前次研究確認為依賴圖視覺化＋循環偵測工具，**不是強制執行工具**，只能畫圖、不能讓 CI fail | 不行（不是 enforcement 工具） | 不適用 | 不適用 | 不適用 |

### 建議：**官方 `analysis_server_plugin` 自建規則套件為主力，不引入 DCM／DCL**

理由：

1. FMP 需要的規則有一半（(c) 的嚴格版空 catch、(e) 音源 id 字串）
   **任何現成工具都做不到**，無論選 DCM 與否都必須自己寫至少兩條
   `AnalysisRule`。既然無法迴避「自己寫規則」這件事，团队就要具備
   `analysis_server_plugin` 的撰寫與測試能力；一旦具備了，(a)(b)(d)
   用同一套工具寫也不增加額外的學習或維運成本，不需要再疊加一個
   商業產品。
2. DCM 是持續計費的商業產品（即使 Free tier 目前的 50k LOC 額度對
   剛起步的 `app/` 專案夠用，長期維護的專案終究會超過，屆時要嘛
   付費要嘛遷移，屬於「先幫套件裝上以後要拆的相容層」的反面
   ——不符合使用者全域偏好「不為想像中的未來需求加抽象層」，這裡
   反過來說：不要為了眼前方便，引入一個未來勢必要遷移走的付費依賴）。
3. 官方路線的唯一已知缺點是 `flutter analyze` 目前無法可靠顯示
   plugin 診斷（上一節），但這個風險**與選哪個 lint 引擎無關**——
   DCM／DCL 都是各自獨立的 CLI（`dcm analyze`／DCL 自己的執行檔），
   本來就不透過 `flutter analyze` 呈現結果，所以這個風險不構成「改用
   DCM 就能迴避」的理由，只是提醒 FMP 的 CI 設計必須顯式呼叫
   `dart analyze`（若走官方路線）或該工具自己的 CLI（若走 DCM／DCL
   路線），不能只信任 `flutter analyze` 的退出碼。
4. 若日後（`app/` 規模變大、需要更細緻的架構規則、團隊擴編）發現
   自寫規則的維護成本超過預期，DCM 的 `avoid-banned-imports`／
   `banned-usage` 是現成、文件完整、成熟維護的替代/補充方案，**保留
   為之後可加購的選項**，不是現在就要下的決定。

### 需要自寫的規則清單（供 `implement.md` 規劃參考）

1. `no_empty_catch_body`：catch 子句 body 沒有任何有效副作用陳述式，
   不因變數命名為 `_` 或加註解而免責（除非該註解緊鄰在唯一一行、且
   FMP 決定要保留「有意跳過需寫理由」的例外——**這點需要擁有者確認
   要不要保留「有註解就放行」的例外，還是完全禁止空 body**，列入
   待決策清單）。
2. `no_direct_log_symbols`：禁止在 log 門面檔案以外的地方 import／
   呼叫 `print`、`debugPrint`、`dart:developer` 的 `log`、`talker`
   套件的具名符號。
3. `no_cross_project_import`：`app/` 不得 import 根目錄舊專案路徑
   （ADR 0008 決定 3 已指定由「測試策略 ADR」落實）。
4. `no_isar_outside_repositories`：`isar` 相關 import 只能出現在
   `lib/data/repositories/`（沿用既有 `AGENTS.md` 規則，從 regex
   測試改寫成 lint）。
5. `no_source_id_literal_outside_sources`（依賴上方「先做型別化」的
   架構前提）：音源 id 具名型別的建構式／字面值只能出現在
   `lib/data/sources/`。

---

## 第 1 點之五：lint 規則本身的「雙向變異測試」怎麼做

官方提供專用的單元測試框架 `analyzer_testing`
（<https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server_plugin/doc/testing_rules.md>），
機制如下：

- 測試類別繼承 `AnalysisRuleTest`（基於 `test_reflective_loader`，
  用 class 而非 `group`/`test` 閉包組織測試）；`setUp()` 裡指定
  `rule = MyRule()` 後呼叫 `super.setUp()`。
- `assertDiagnostics(source, [lint(offset, length)])`：餵一段刻意
  違規的原始碼，斷言在指定位置真的報出診斷——**這就是使用者全域
  偏好要求的「造一個違規證明它會紅」**。
- `assertNoDiagnostics(source)`：餵一段合規（或刻意做了無關的格式／
  命名變化）的原始碼，斷言完全不報診斷——**這就是「改一次無關的
  格式或命名證明它不會紅」**。
- 範例（來源同上）：

  ```dart
  @reflectiveTest
  class MyRuleTest extends AnalysisRuleTest {
    @override
    void setUp() {
      rule = MyRule();
      super.setUp();
    }

    void test_has_await() async {
      await assertDiagnostics(r'''
  void f(Future<int> p) async {
    await p;
  }
  ''', [lint(33, 5)]);
    }

    void test_no_await() async {
      await assertNoDiagnostics(r'''
  void f(Future<int> p) async {}
  ''');
    }
  }
  ```

**落地建議**：FMP 每條自寫規則至少配一對測試方法——
`test_violation_is_flagged`（違規版本，`assertDiagnostics`）與
`test_unrelated_change_is_not_flagged`（同一段程式碼做無關的變數
改名／換行／加註解，`assertNoDiagnostics`）——直接對應使用者全域
偏好「新加的靜態規則要在測試檔內做雙向變異驗證」的字面要求，且這個
框架是**官方一手提供**，不需要另外自己搭測試骨架。若 FMP 之後選擇
DCM／DCL 補強某些規則，兩者都是外部 CLI 工具，**查不到**它們有提供
對等的「規則單元測試」框架（DCM 文件裡看到的都是「規則設定」文件，
未見到「測試我自己寫的規則設定是否如預期觸發」的官方測試 API）——
這點也是傾向官方路線的一個加分點：自寫規則有官方測試框架可用，
買來的規則设定沒有。

---

## 待補查項（誠實列出）

- `flutter analyze` 是否顯示 plugin 診斷的 bug（`flutter/flutter#193203`
  / `#187999`）**修復進度**：查詢當下（2026-09-27）看到的 PR
  `dart-lang/sdk#63805` 討論串停在「已核准待 merge」與「有建置/測試
  失敗待處理」的狀態，**沒有查到明確的「已合併進某個 stable 版本」
  的證據**。落地 `app/` 的 CI 前，必須用當時的實際 Flutter/Dart
  版本重新驗證一次（建一個哨兵違規檔，比較 `flutter analyze` 與
  `dart analyze` 的輸出是否一致），不能沿用本文件查證當下的結論。
- DCL（Bancolombia fork）`ban-name` 規則的精確設定欄位（`entries`
  的欄位名稱是否與 DCM 舊版一致）**查不到**，本文件只查到規則存在
  於索引頁、其詳細頁未被搜尋索引到。若日後決定採用 DCL 作為
  DCM 的免費替代，需要直接開
  <https://dcl.apps.bancolombia.com/docs/rules/dart/ban-name/>
  核對。
- `import_lint` 遷移到 `analysis_server_plugin` 的確切版本號
  **查不到**（changelog 頁面查證時只讀到舊格式的條目，需要直接翻
  pub.dev 的 Versions 分頁逐版核對）。
- (e) 音源 id 字串常數規則若最終還是需要「掃描字串字面值」的自寫
  規則（架構型別化未能 100% 消除裸字串比較的情況），這條規則的
  誤判率（例如日誌訊息、i18n key 裡剛好出現音源名稱字串）需要在
  實作階段用真實程式碼樣本測過，本研究未做這個層級的驗證。
