import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// `// ignore:` 或 `// ignore_for_file:` 之後的診斷名稱清單與其餘文字。
final _ignoreComment = RegExp(
  r'^//+\s*ignore(?:_for_file)?:\s*'
  r'(?<names>[\w/]+(?:\s*,\s*[\w/]+)*)(?<rest>.*)$',
);

/// 名稱清單之後的理由：` — ` 或 ` - ` 加文字。
final _reason = RegExp(r'^\s+[—-]\s+\S');

/// `fmp_ignore_reason`：忽略任何 `fmp_` 規則的 `// ignore:`／
/// `// ignore_for_file:` 註解，同一行的規則名之後要寫理由。
///
/// 理由接在名稱之後不影響 ignore 本身：analyzer 把名稱清單之後的文字當成
/// 註解（`package:analyzer/src/ignore_comments/ignore_info.dart`）。
class IgnoreReason extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_ignore_reason',
    'An ignore comment for an fmp_ rule needs a reason.',
    correctionMessage:
        "Append the reason after the rule name: '// ignore: "
        "fmp_lints/fmp_… — why'.",
    severity: DiagnosticSeverity.WARNING,
  );

  IgnoreReason()
    : super(
        name: 'fmp_ignore_reason',
        description: 'Ignoring an fmp_ rule states why.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(this, _Visitor(this));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    Token? token = node.beginToken;
    while (token != null) {
      for (
        Token? comment = token.precedingComments;
        comment != null;
        comment = comment.next
      ) {
        if (lacksReason(comment.lexeme)) {
          rule.reportAtOffset(comment.offset, comment.length);
        }
      }
      if (token.isEof) break;
      token = token.next;
    }
  }
}

/// [comment] 是忽略 `fmp_` 規則的 ignore 註解且沒寫理由。
bool lacksReason(String comment) {
  final match = _ignoreComment.firstMatch(comment);
  if (match == null) return false;
  final names = match.namedGroup('names')!.split(',');
  final ignoresFmpRule = names.any(
    (name) => name.trim().split('/').last.startsWith('fmp_'),
  );
  return ignoresFmpRule && !_reason.hasMatch(match.namedGroup('rest')!);
}
