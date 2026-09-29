import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// `fmp_no_empty_catch`：catch 本體沒有陳述式就違規；只有註解也算空，
/// 變數名 `_` 不豁免（ADR 0015 §決定 2）。沒有允許清單。
class NoEmptyCatch extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_no_empty_catch',
    'Empty catch block.',
    correctionMessage:
        'Handle the error: log it through the facade, rethrow, or map it to '
        'an AppError.',
    severity: DiagnosticSeverity.WARNING,
  );

  NoEmptyCatch()
    : super(name: 'fmp_no_empty_catch', description: 'No empty catch blocks.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCatchClause(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitCatchClause(CatchClause node) {
    if (node.body.statements.isEmpty) rule.reportAtNode(node.body);
  }
}
