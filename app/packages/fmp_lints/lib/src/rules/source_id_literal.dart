import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// 官方插件的 id。M3 加 `youtube`、`netease`。
const officialPluginIds = {
  // ignore: fmp_lints/fmp_source_id_literal — 規則本身的清單
  'bilibili',
};

/// 可以寫官方插件 id 的地方：舊資料匯入要對應舊資料的音源，測試要造資料。
const sourceIdAllowedDirectories = ['lib/legacy_import', 'test'];

/// `fmp_source_id_literal`：字串字面值整個等於官方插件 id 就報
/// （ADR 0014；UI 與 service 不得依音源分支）。
class SourceIdLiteral extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_source_id_literal',
    "The official plugin id '{0}' is written as a literal.",
    correctionMessage:
        'Branch on plugin capabilities, not on a plugin id. Ids are only '
        'allowed in lib/legacy_import/ and test/.',
    severity: DiagnosticSeverity.WARNING,
  );

  SourceIdLiteral()
    : super(
        name: 'fmp_source_id_literal',
        description: 'No official plugin id literals.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addSimpleStringLiteral(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    if (!officialPluginIds.contains(value)) return;
    final path = PackagePath.of(context);
    if (path == null || path.isInAny(sourceIdAllowedDirectories)) return;
    rule.reportAtNode(node, arguments: [value]);
  }
}
