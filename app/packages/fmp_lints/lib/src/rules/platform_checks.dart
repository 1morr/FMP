import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../ast_names.dart';
import '../package_path.dart';

/// 平台層（ADR 0009）：唯一可以判斷平台的地方。
const platformDirectory = 'lib/platform';

/// 不論怎麼用都算平台判斷的識別字。
const _platformIdentifiers = {'defaultTargetPlatform', 'TargetPlatform'};

/// `fmp_platform_checks`：`lib/` 內 `Platform.isXxx`、
/// `Platform.operatingSystem`、`defaultTargetPlatform`、`TargetPlatform`
/// 只准在 [platformDirectory]。以名稱判斷，不看它來自哪個函式庫。
class PlatformChecks extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_platform_checks',
    "'{0}' is a platform check outside $platformDirectory/.",
    correctionMessage:
        'Ask the platform layer for the capability instead of the platform.',
    severity: DiagnosticSeverity.WARNING,
  );

  PlatformChecks()
    : super(
        name: 'fmp_platform_checks',
        description: 'Platform checks live in the platform layer.',
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
      ..addSimpleIdentifier(this, visitor)
      ..addNamedType(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  bool get _applies {
    final path = PackagePath.of(context);
    return path != null && path.isInLib && !path.isIn(platformDirectory);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (_platformIdentifiers.contains(name) || _isPlatformGetter(node)) {
      if (_applies) rule.reportAtNode(node, arguments: [name]);
    }
  }

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (_platformIdentifiers.contains(name) && _applies) {
      rule.reportAtToken(node.name, arguments: [name]);
    }
  }

  /// `Platform.isXxx`／`Platform.operatingSystem` 的屬性名（含 `io.Platform.…`）。
  static bool _isPlatformGetter(SimpleIdentifier node) {
    final name = node.name;
    final isGetter =
        name == 'operatingSystem' ||
        (name.length > 2 &&
            name.startsWith('is') &&
            name[2].toUpperCase() == name[2]);
    if (!isGetter) return false;
    final target = switch (node.parent) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier == node =>
        prefix,
      PropertyAccess(:final target?, :final propertyName)
          when propertyName == node =>
        target,
      _ => null,
    };
    return isNamedReference(target, 'Platform');
  }
}
