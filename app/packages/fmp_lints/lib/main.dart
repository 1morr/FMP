import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';

import 'src/rules/design_tokens.dart';
import 'src/rules/http_client_owner.dart';
import 'src/rules/ignore_reason.dart';
import 'src/rules/layer_imports.dart';
import 'src/rules/log_facade.dart';
import 'src/rules/material_import.dart';
import 'src/rules/no_empty_catch.dart';
import 'src/rules/no_for_testing.dart';
import 'src/rules/platform_checks.dart';
import 'src/rules/source_id_literal.dart';
import 'src/rules/test_waits.dart';
import 'src/rules/toast_entry.dart';
import 'src/rules/url_literal.dart';

/// analysis server 以這個頂層變數載入插件（analysis_server_plugin 的
/// `doc/writing_a_plugin.md`）。
final plugin = FmpLintsPlugin();

/// 全部規則。都註冊成 lint rule：預設關閉，由 `app/analysis_options.yaml`
/// 的 `diagnostics:` 逐條開啟。
List<AnalysisRule> fmpRules() => [
  LayerImports(),
  NoEmptyCatch(),
  LogFacade(),
  SourceIdLiteral(),
  UrlLiteral(),
  NoForTesting(),
  HttpClientOwner(),
  TestWaits(),
  IgnoreReason(),
  PlatformChecks(),
  ToastEntry(),
  DesignTokens(),
  MaterialImport(),
];

class FmpLintsPlugin extends Plugin {
  @override
  String get name => 'fmp_lints';

  @override
  void register(PluginRegistry registry) {
    for (final rule in fmpRules()) {
      registry.registerLintRule(rule);
    }
  }
}
