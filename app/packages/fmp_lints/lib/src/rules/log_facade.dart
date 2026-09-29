import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// log 門面所在的目錄（ADR 0011）。
const logFacadeDirectory = 'lib/core/logging';

const _printFunctions = {'print', 'debugPrint'};

/// `fmp_log_facade`：`lib/` 內，`print`、`debugPrint`、`dart:developer` 的
/// `log`、`package:talker*` 只准在 log 門面。
///
/// `dart:developer` 看 import：沒有以 `show` 排除 `log` 的 import 就報。
class LogFacade extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_log_facade',
    "'{0}' is only allowed in $logFacadeDirectory/.",
    correctionMessage: 'Log through the facade in $logFacadeDirectory/.',
    severity: DiagnosticSeverity.WARNING,
  );

  LogFacade()
    : super(
        name: 'fmp_log_facade',
        description: 'Logging goes through the facade.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addMethodInvocation(this, visitor)
      ..addFunctionExpressionInvocation(this, visitor)
      ..addImportDirective(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  bool get _applies {
    final path = PackagePath.of(context);
    return path != null && path.isInLib && !path.isIn(logFacadeDirectory);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isImportPrefix(node.target) || node.target == null) {
      _check(node.methodName);
    }
  }

  /// `debugPrint` 是函式型別的頂層變數，解析後的呼叫是
  /// [FunctionExpressionInvocation]，不是 [MethodInvocation]。
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    switch (node.function) {
      case SimpleIdentifier function:
        _check(function);
      case PrefixedIdentifier(:final prefix, :final identifier)
          when _isImportPrefix(prefix):
        _check(identifier);
    }
  }

  void _check(SimpleIdentifier name) {
    if (_printFunctions.contains(name.name) && _applies) {
      rule.reportAtNode(name, arguments: [name.name]);
    }
  }

  /// `foundation.debugPrint` 的 `foundation`：import 前綴，不是物件。
  static bool _isImportPrefix(Expression? target) =>
      target is SimpleIdentifier && target.element is PrefixElement;

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri == null || !_applies) return;
    if (_isTalker(uri) || (uri == 'dart:developer' && _mayImportLog(node))) {
      rule.reportAtNode(node.uri, arguments: [uri]);
    }
  }

  static bool _isTalker(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || !parsed.isScheme('package')) return false;
    final name = parsed.pathSegments.firstOrNull;
    return name == 'talker' || (name?.startsWith('talker_') ?? false);
  }

  static bool _mayImportLog(ImportDirective node) {
    for (final combinator in node.combinators) {
      if (combinator is ShowCombinator &&
          !combinator.shownNames.any((n) => n.name == 'log')) {
        return false;
      }
      if (combinator is HideCombinator &&
          combinator.hiddenNames.any((n) => n.name == 'log')) {
        return false;
      }
    }
    return true;
  }
}
