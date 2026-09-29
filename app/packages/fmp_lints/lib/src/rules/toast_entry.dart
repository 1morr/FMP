import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../ast_names.dart';
import '../package_path.dart';

/// Toast 的唯一入口（ADR 0023）。
const toastDirectory = 'lib/ui/toast';

const _snackBarMethods = {'showSnackBar', 'clearSnackBars'};

const _messengerLookups = {'of', 'maybeOf'};

/// `fmp_toast_entry`：`lib/` 內 `SnackBar(`、`ScaffoldMessenger.of`／
/// `.maybeOf`、`showSnackBar`、`clearSnackBars` 只准在 [toastDirectory]。
/// 以名稱判斷。
class ToastEntry extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_toast_entry',
    "'{0}' bypasses the toast entry in $toastDirectory/.",
    correctionMessage: 'Show messages through the toast API.',
    severity: DiagnosticSeverity.WARNING,
  );

  ToastEntry()
    : super(name: 'fmp_toast_entry', description: 'One entry for toasts.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  bool get _applies {
    final path = PackagePath.of(context);
    return path != null && path.isInLib && !path.isIn(toastDirectory);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name;
    if (type.lexeme == 'SnackBar' && _applies) {
      rule.reportAtToken(type, arguments: ['SnackBar']);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final isMessengerOf =
        _messengerLookups.contains(name) &&
        isNamedReference(node.target, 'ScaffoldMessenger');
    if ((isMessengerOf || _snackBarMethods.contains(name)) && _applies) {
      final label = isMessengerOf ? 'ScaffoldMessenger.$name' : name;
      rule.reportAtNode(node.methodName, arguments: [label]);
    }
  }
}
