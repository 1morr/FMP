# fmp_lints 研究筆記

- 日期：2026-09-29
- 環境：Flutter 3.47.5／Dart 3.13.4，Windows 11
- context7 在實作子代理的環境裡沒有提供，改讀官方文件（Dart SDK repo 的
  `pkg/analysis_server_plugin/doc/*.md`，main 分支）、pub.dev JSON API，與 pub cache 內
  套件原始碼。每條後面附來源。

## 1. 版本：為什麼不是 pub.dev 最新的一組

pub.dev 當日最新：`analysis_server_plugin` 0.3.23、`analyzer_testing` 0.4.2（兩者都釘
`analyzer` 14.4.0）、`test` 1.32.0（`https://pub.dev/api/packages/<pkg>`）。

`fmp_lints` 是 `app/` workspace 的成員（PRD §1），和 `flutter_test` 共用一次解析：

- Flutter 3.47.5 的 `flutter_test` 釘 `test_api` 0.7.12、`matcher` 0.12.20。
- `test_api` 0.7.12 只配得上 `test` 1.31.1，而 `test` 1.31.1 要 `analyzer >=8.0.0 <14.0.0`
  （pub cache `test-1.31.1/pubspec.yaml`；`test` 1.31.2 起改釘 `test_api` 0.7.13）。
- `analyzer_testing` 依賴 `test ^1.25.0`，所以整個 workspace 的 `analyzer` 上限是 13.x。
- `flutter pub get` 的實際錯誤（加 `test: any` 後）：
  `every version of flutter_test from sdk requires test_api 0.7.11 or 0.7.13 or 0.7.14 …
  flutter_test from sdk which depends on test_api 0.7.12, version solving failed.`

三個套件逐版互相釘死（pub.dev 版本清單）：

| analysis_server_plugin | analyzer_testing | analyzer |
|---|---|---|
| 0.3.18 | 0.3.2 | 13.3.0 |
| 0.3.19 | 0.3.3 | 14.0.0 |
| 0.3.23 | 0.4.2 | 14.4.0 |

採用能解出來的最新一組：`analysis_server_plugin` 0.3.18、`analyzer` 13.3.0、
`analyzer_testing` 0.3.2（`test` 解到 1.31.1）。

- `analyzer` 13.3.0 的 `_fe_analyzer_shared` 103.0.0 `defaultLanguageVersion` 是 3.13
  （`lib/src/experiments/flags.dart:9`），`app/` 的語言版本分析得了。
- 插件在 analysis server 裡另外解析一個 synthetic package（見 §2），`fmp_lints` 的
  pubspec 釘 13.3.0，所以執行期也是 13.3.0，不會和測試用的版本分岔。
- 升級條件：`flutter_test` 的 `test_api` 釘版到 0.7.13 以上（新 Flutter stable）時，
  三個一起升到當時最新，並依 analyzer 的 AST 變動改規則。

另一條路是把 `fmp_lints` 移出 workspace（自己一份 lock），可以用 14.4.0；沒採用，因為
PRD §1 要求加進 workspace，而且 13.3.0 對目前的規則沒有缺的 API。

## 2. 插件怎麼接

來源：`pkg/analysis_server_plugin/doc/using_plugins.md`、`writing_a_plugin.md`、
`writing_rules.md`、`testing_rules.md`（Dart SDK main）。

- 插件是一般 Dart package，入口固定是 `lib/main.dart` 的頂層變數 `plugin`（`Plugin` 子類別，
  覆寫 `register(PluginRegistry)`）。
- `registry.registerWarningRule(rule)`：預設開啟；`registry.registerLintRule(rule)`：預設
  關閉，要在 `diagnostics:` 開。PRD 要逐條開，所以全部用 `registerLintRule`。
- `analysis_options.yaml` 用**頂層** `plugins:`（不是 `analyzer:` 底下），只能寫在 package 或
  workspace 根；值和 pubspec 依賴同格式（版本字串、`path:`、或 `version:` 加其他鍵的 map）。
  實測 `path: packages/fmp_lints` 的相對路徑可用。
- analysis server 為所有插件建一個 synthetic package，以 `dart pub upgrade` 解析，編成 AOT
  snapshot 放在 `%LOCALAPPDATA%\.dartServer\.plugin_manager\`。實測插件編譯失敗時
  `dart analyze` 只印出錯誤訊息、照樣分析其他檔案 → 這就是哨兵要存在的原因。
- 規則：`AnalysisRule` 子類別，`static const LintCode`（唯一實例，`// ignore:` 才對得上），
  `registerNodeProcessors` 裡把 `SimpleAstVisitor` 註冊到 `RuleVisitorRegistry.addXxx`；
  回報用 `reportAtNode`／`reportAtToken`／`reportAtOffset`（`analyzer-13.3.0/lib/src/analysis_rule/analysis_rule.dart`）。
- `LintCode` 的 `severity` 預設 `INFO`（`analyzer-13.3.0/lib/src/dart/error/lint_codes.dart:61`）。
  全部設 `WARNING`：`dart analyze` 不加旗標也會失敗（exit 2），`--fatal-infos` 自然也失敗。
- 路徑：`RuleContext.currentUnit.file` 與 `RuleContext.package.root`
  （`analyzer-13.3.0/lib/analysis_rule/rule_context.dart`、`workspace/workspace.dart`）；以
  `file.provider.pathContext` 算相對路徑再轉成 `/`，規則只比對 `lib/ui/...` 這種字串。
- analyzer 13 的 AST：引數是 sealed `Argument`（`Expression` 或 `NamedArgument`），
  `NamedArgument.name` 是 `Token`，登記用 `addNamedArgument`（沒有 `addNamedExpression`）。
- 忽略語法是 `// ignore: fmp_lints/<規則名>`（`using_plugins.md` §Suppressing）。名稱清單之後
  的文字，analyzer 解析成 `IgnoredDiagnosticComment`，不影響忽略本身
  （`analyzer-13.3.0/lib/src/ignore_comments/ignore_info.dart` 的 `ignoredElements`），
  所以 `— 理由` 可以直接接在後面。實測：`fmp_lints/lib/src/rules/source_id_literal.dart` 的
  `'bilibili'` 以帶理由的 ignore 放行，`dart analyze` 乾淨。
- 巢狀的 `packages/fmp_lints/analysis_options.yaml`（`include: ../../analysis_options.yaml`
  再關 `non_constant_identifier_names`）不影響插件：實測插件照樣分析 `fmp_lints` 自己的檔案。

## 3. analyzer_testing

來源：`testing_rules.md`；`analyzer_testing-0.3.2/lib/analysis_rule/analysis_rule.dart`、
`src/analysis_rule/pub_package_resolution.dart`、`resource_provider_mixin.dart`。

- `AnalysisRuleTest`（`test_reflective_loader` 的 `@reflectiveTest`，方法名 `test_` 開頭）。
  `setUp` 設 `rule = …` 再 `super.setUp()`；它會把規則登記進 `Registry.ruleRegistry` 並寫一份
  只開這條規則的 analysis options。
- 記憶體檔案系統：test package 在 `/home/test`（`testPackageRootPath`），`newFile(path, …)`
  可以放在任意相對位置，例如 `$testPackageRootPath/lib/ui/page.dart`，再
  `resolveFile(convertPath(path))`。`assertDiagnosticsIn(diagnostics, [lint(offset, length)])`
  比對；失敗訊息會讀 `result` 欄位，所以要先把 `result` 設好。
- `newPackage('dio').addFile('lib/dio.dart', …)` 造假套件，要在 `super.setUp()` 之前呼叫。
  mock SDK 有 `dart:io`（含 `Platform.isAndroid`），沒有 `dart:developer`。
- **Windows 路徑**：`ResourceProviderMixin` 在 Windows 上，或環境變數
  `TEST_ANALYZER_WINDOWS_PATHS=true` 時，用 `path.windows` 的 `MemoryResourceProvider`。
  CI（ubuntu）因此跑兩次 `dart test`：預設 posix 一次、設這個變數一次。本機（Windows）的
  一次跑的就是 Windows 路徑。

## 4. riverpod_lint

- 3.1.9 依賴 `analysis_server_plugin ^0.3.0`、`analyzer >=13.0.0 <15.0.0`
  （pub.dev API），README §Installing：`plugins: riverpod_lint: <version>`。
- 它的規則全部是 `registerWarningRule`（預設開啟；riverpod repo `packages/riverpod_lint/lib/main.dart`）。
- 實測：和 `fmp_lints`（analyzer 13.3.0）一起放進 `plugins:` 能解析、能載入。
  `missing_provider_scope` 對 `lib/main.dart` 的 `runApp(FmpApp(...))` 報錯——`app/` 還沒有
  Riverpod。以 `diagnostics: missing_provider_scope: false` 暫時關掉；同一個 map 寫法把它切回
  `true` 會再報，證明插件有載入。第一個加 `ProviderScope` 的 PR 刪掉這一條。

## 5. `flutter analyze` 與 `dart analyze`（PRD §7 實測）

同一個檔案 `lib/core/zz_measure.dart`（`catch (_) {}`）：

```
$ dart analyze --fatal-infos
Analyzing app...

warning - lib\core\zz_measure.dart:4:15 - Empty catch block. Handle the error: log it through the facade, rethrow, or map it to an AppError. - fmp_no_empty_catch

1 issue found.
(exit 2)

$ flutter analyze
Analyzing app...
No issues found! (ran in 8.8s)
(exit 0)
```

flutter/flutter#187999（open）描述的就是這個現象。
