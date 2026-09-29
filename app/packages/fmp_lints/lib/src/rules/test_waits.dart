import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// 等待助手：唯一直接呼叫 `pumpEventQueue` 的檔案。
const waitHelperFile = 'test/support/pump_until.dart';

/// `fmp_test_waits`：`test/` 內直接呼叫 `pumpEventQueue` 只准在
/// [waitHelperFile]。
class TestWaits extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_test_waits',
    'pumpEventQueue is only called from $waitHelperFile.',
    correctionMessage: 'Wait with the helpers in $waitHelperFile.',
    severity: DiagnosticSeverity.WARNING,
  );

  TestWaits()
    : super(name: 'fmp_test_waits', description: 'One owner of test waits.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addMethodInvocation(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'pumpEventQueue') return;
    final path = PackagePath.of(context);
    if (path == null || !path.isInTest || path.value == waitHelperFile) return;
    rule.reportAtNode(node.methodName);
  }
}
