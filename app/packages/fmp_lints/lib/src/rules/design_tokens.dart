import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// 規則管的範圍：`lib/ui/`，但不含定義 token 的 [themeDirectory]。
const uiDirectory = 'lib/ui';
const themeDirectory = 'lib/ui/theme';

/// `SizedBox` 裡算尺寸的具名參數。
const _sizedBoxDimensions = {'width', 'height', 'dimension'};

/// `fmp_design_tokens`（ADR 0024）：[uiDirectory] 內（[themeDirectory]
/// 除外），`EdgeInsets.*`／`EdgeInsetsDirectional.*` 的參數、`SizedBox` 的寬高
/// 與傳給它的 `Size`、`BorderRadius.circular`／`.all`、
/// `BorderRadiusDirectional.*`、`Radius.circular`／`.elliptical`、任何
/// `fontSize:` 不得用 `0` 以外的數字字面值；`Color(…)`、`Color.fromARGB`／
/// `fromRGBO`／`from` 不得有數字字面值（含 `0`）；不得寫 `Colors.*`。以名稱判斷。
class DesignTokens extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_design_tokens',
    '{0} is a raw design value.',
    correctionMessage:
        'Use AppTokens / AppLayout or the ColorScheme from '
        '$themeDirectory/.',
    severity: DiagnosticSeverity.WARNING,
  );

  DesignTokens()
    : super(name: 'fmp_design_tokens', description: 'UI uses design tokens.');

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
      ..addNamedArgument(this, visitor)
      ..addSimpleIdentifier(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  bool get _applies {
    final path = PackagePath.of(context);
    return path != null && path.isIn(uiDirectory) && !path.isIn(themeDirectory);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    final constructor = node.constructorName.name?.name;
    final arguments = node.argumentList.arguments;
    final label = constructor == null ? type : '$type.$constructor';
    switch ((type, constructor)) {
      case ('EdgeInsets' || 'EdgeInsetsDirectional', _):
      case ('BorderRadius', 'circular' || 'all'):
      case ('BorderRadiusDirectional', _):
      case ('Radius', 'circular' || 'elliptical'):
        // BorderRadius.only(topLeft: Radius.circular(8)) 這類巢狀寫法由
        // 內層的 Radius 自己報。
        _reportLiterals(label, arguments);
      case ('SizedBox', _):
        _reportLiterals(label, [
          for (final argument in arguments)
            if (argument is NamedArgument &&
                _sizedBoxDimensions.contains(argument.name.lexeme))
              argument,
        ]);
        // SizedBox.fromSize(size: Size(8, 8))：只管傳給 SizedBox 的 Size。
        for (final argument in arguments) {
          if (argument.argumentExpression
              case InstanceCreationExpression(
                :final constructorName,
                :final argumentList,
              )
              when constructorName.type.name.lexeme == 'Size') {
            _reportLiterals('Size', argumentList.arguments);
          }
        }
      case ('Color', null || 'fromARGB' || 'fromRGBO' || 'from'):
        // 顏色的 0 也是寫死的值，不豁免。
        final raw = arguments.any((a) => _isNumber(a.argumentExpression));
        if (raw && _applies) {
          rule.reportAtNode(node, arguments: ['$label(<number>)']);
        }
    }
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (node.name.lexeme == 'fontSize') _reportLiterals('fontSize', [node]);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'Colors' && _applies) {
      rule.reportAtNode(node, arguments: ['Colors']);
    }
  }

  void _reportLiterals(String label, Iterable<Argument> arguments) {
    for (final argument in arguments) {
      final value = argument.argumentExpression;
      if (_isNonZeroNumber(value) && _applies) {
        rule.reportAtNode(value, arguments: ['A number literal in $label']);
      }
    }
  }

  static bool _isNonZeroNumber(Expression expression) => switch (expression) {
    IntegerLiteral(:final value) => value != 0,
    DoubleLiteral(:final value) => value != 0,
    PrefixExpression(:final operand) => _isNonZeroNumber(operand),
    ParenthesizedExpression(:final expression) => _isNonZeroNumber(expression),
    _ => false,
  };

  static bool _isNumber(Expression expression) => switch (expression) {
    IntegerLiteral() || DoubleLiteral() => true,
    PrefixExpression(:final operand) => _isNumber(operand),
    ParenthesizedExpression(:final expression) => _isNumber(expression),
    _ => false,
  };
}
