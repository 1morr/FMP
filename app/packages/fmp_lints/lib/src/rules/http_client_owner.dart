import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// 網路模組：唯一建立 HTTP client 的地方（ADR 0012）。
const networkDirectory = 'lib/core/network';

/// `fmp_http_client_owner`：`lib/` 內建立 `Dio`（任何建構子）只准在
/// [networkDirectory]。
class HttpClientOwner extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_http_client_owner',
    'Dio is only constructed in $networkDirectory/.',
    correctionMessage: 'Get the client from the network module.',
    severity: DiagnosticSeverity.WARNING,
  );

  HttpClientOwner()
    : super(
        name: 'fmp_http_client_owner',
        description: 'One owner of HTTP clients.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addInstanceCreationExpression(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme != 'Dio') return;
    final path = PackagePath.of(context);
    if (path == null || !path.isInLib || path.isIn(networkDirectory)) return;
    rule.reportAtNode(node.constructorName);
  }
}
