# Lint 規則（`app/packages/fmp_lints/`）

改或加 `fmp_` 規則時適用。每條規則守什麼、允許清單在哪，見 `app/AGENTS.md` § Lint；
為什麼是這些規則，見 ADR 0015 §決定 2。這裡只寫怎麼寫。

## 一條規則的形狀

- 一條規則一個檔案：`lib/src/rules/<規則名去掉 fmp_>.dart`，裡面是 `AnalysisRule` 子類別加
  `SimpleAstVisitor`。
- `LintCode` 放成 `static const`（唯一實例，`// ignore:` 才對得上），名稱 `fmp_…`，
  `severity: DiagnosticSeverity.WARNING`。訊息用英文，比照 log 字串。
- 允許清單、套件清單寫成同一個檔案頂端的具名常數，路徑一律相對 package 根、以 `/`
  分隔、不帶結尾斜線（`lib/ui/toast`）。
- 判斷檔案位置只用 `PackagePath.of(context)`（`lib/src/package_path.dart`）與它的
  `isIn`／`isInLib`／`isInTest`，不自己處理分隔符。
- 名稱比對帶 import 前綴的寫法（`m.ScaffoldMessenger`）用 `lib/src/ast_names.dart` 的
  `isNamedReference`。
- 在 `lib/main.dart` 的 `fmpRules()` 登記，並在 `app/analysis_options.yaml` 的
  `diagnostics:` 開啟；`test/plugin_test.dart` 會比對兩邊。

## 測試（雙向變異）

每條規則一個 `test/rules/<規則>_test.dart`，繼承 `test/support/rule_test_base.dart` 的
`FmpRuleTest`：

```dart
Future<void> test_rawValuesInUi() => assertLints('lib/ui/search/page.dart', '''
const a = EdgeInsets.all([!8!]);
''');
```

- `[!…!]` 標出預期的診斷範圍；沒有標記就是斷言不報。只比對受測規則的診斷，未解析的
  名稱等編譯錯誤不參與。
- 至少一個「報」的案例，和至少一個相鄰但不該報的案例：允許目錄內、改名、改格式，或
  在註解與字串裡提到同樣的字。
- 依賴解析結果的寫法（`Dio()` 要解析成建構子呼叫）在 `addStubPackages` 裡用
  `newPackage(...)` 造最小的假套件。假宣告要照真套件的形狀：Flutter 的 `debugPrint` 是
  函式型別的頂層變數，呼叫解析成 `FunctionExpressionInvocation` 而不是
  `MethodInvocation`；名稱沒解析到時兩者都是 `MethodInvocation`，測試會綠、實際卻漏報。
- 同一個測試方法裡，每個路徑只 `assertLints` 一次：對同一個路徑再寫一次內容，analyzer 仍回
  第一次的解析結果，第二個斷言比對的是舊內容。要多種寫法就換路徑（迴圈裡各給一個檔名）。
- 本機在 Windows 上跑的是 Windows 路徑；CI 另外以 `TEST_ANALYZER_WINDOWS_PATHS=true` 再跑一次。

## 依賴表（`fmp_layer_imports`）

限制「誰能 import 某個檔案或目錄」加在 `rules/layer_imports.dart` 的 `restrictedImports`
（被匯入端 → 允許的匯入端），不另寫規則。兩邊都用 `PackagePath.isIn` 比對，檔案與目錄
都可以；只看 `lib/` 內的匯入端，`test/` 不受限。測試照上面的雙向變異，另外放一個同前綴
的匯入端（`backends_helpers.dart` 之於 `backends/`、`playback_session_helpers.dart` 之於
`playback_session.dart`）證明不是字串前綴比對。

## 哨兵

在 `app/tool/lint_sentinel.dart` 的 `_violations` 加一行違反新規則的程式碼。沒加的話，
哨兵會因為「開啟的規則沒被報」而失敗。

在既有規則裡加一張表（`restrictedImports` 這類）時規則名已經被別的行報出，哨兵分不出新表
有沒有接上：違規行之外，再把新診斷訊息裡固定的一段加進 `_expectedMessages`。

## Quality Check

- `packages/fmp_lints/` 內 `dart test` 全綠。
- `app/` 內 `dart analyze --fatal-infos` 乾淨，`dart run tool/lint_sentinel.dart` 通過。
- `app/AGENTS.md` § Lint 的表格有新規則的一列。
