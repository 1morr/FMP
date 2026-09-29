import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// `lib/` 內唯一可以寫網址的檔案（第一個需要網址的 PR 建立）。
const endpointsFile = 'lib/core/endpoints.dart';

final _url = RegExp('https?://', caseSensitive: false);

/// `fmp_url_literal`：`lib/` 內含 `http://`、`https://` 的字串字面值只准在
/// [endpointsFile]。
class UrlLiteral extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_url_literal',
    'URL literals are only allowed in $endpointsFile.',
    correctionMessage: 'Move the URL to $endpointsFile.',
    severity: DiagnosticSeverity.WARNING,
  );

  UrlLiteral()
    : super(name: 'fmp_url_literal', description: 'URLs live in one file.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addSimpleStringLiteral(this, visitor)
      ..addInterpolationString(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) =>
      _check(node, node.value);

  @override
  void visitInterpolationString(InterpolationString node) =>
      _check(node, node.value);

  void _check(AstNode node, String value) {
    if (!_url.hasMatch(value)) return;
    final path = PackagePath.of(context);
    if (path == null || !path.isInLib || path.value == endpointsFile) return;
    rule.reportAtNode(node);
  }
}
