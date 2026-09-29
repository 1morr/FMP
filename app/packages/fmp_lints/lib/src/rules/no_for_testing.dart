import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// `xForTesting`，以及具名建構子 `Foo.forTesting`。
final _forTesting = RegExp(r'(^f|F)orTesting$');

/// `fmp_no_for_testing`：`lib/` 不得宣告 `*ForTesting` 的成員（方法、欄位、
/// getter／setter、具名建構子、頂層函式與變數）。要替換的東西經建構子或
/// provider 注入（ADR 0015 §決定 1）。
class NoForTesting extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_no_for_testing',
    "'{0}' is a test hook in production code.",
    correctionMessage:
        'Inject the dependency through a constructor or a provider override.',
    severity: DiagnosticSeverity.WARNING,
  );

  NoForTesting()
    : super(name: 'fmp_no_for_testing', description: 'No *ForTesting members.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addMethodDeclaration(this, visitor)
      ..addFunctionDeclaration(this, visitor)
      ..addConstructorDeclaration(this, visitor)
      ..addFieldDeclaration(this, visitor)
      ..addTopLevelVariableDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitMethodDeclaration(MethodDeclaration node) => _check(node.name);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // 區域函式不是成員；頂層函式的父節點是 CompilationUnit。
    if (node.parent is CompilationUnit) _check(node.name);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.name case final name?) _check(name);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) =>
      _checkVariables(node.fields);

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) =>
      _checkVariables(node.variables);

  void _checkVariables(VariableDeclarationList list) {
    for (final variable in list.variables) {
      _check(variable.name);
    }
  }

  void _check(Token name) {
    if (!_forTesting.hasMatch(name.lexeme)) return;
    final path = PackagePath.of(context);
    if (path == null || !path.isInLib) return;
    rule.reportAtToken(name, arguments: [name.lexeme]);
  }
}
