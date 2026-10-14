import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../ast_names.dart';
import '../package_path.dart';

/// 週期計時器的擁有者（ADR 0017 §如何確認、ADR 0018 §決定 11）：背景排程器
/// 與播放核心。
const periodicTimerOwners = ['lib/scheduler', 'lib/playback'];

/// `fmp_periodic_timer_owner`：`lib/` 內 `Timer.periodic`、`Stream.periodic`
/// 只准在 [periodicTimerOwners]。以名稱判斷（含建構子與函式引用的寫法），不看它
/// 來自哪個函式庫。
class PeriodicTimerOwner extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_periodic_timer_owner',
    "'{0}.periodic' is only used in lib/scheduler/ and lib/playback/.",
    correctionMessage: 'Register a job with the BackgroundScheduler, or chain one-shot timers.',
    severity: DiagnosticSeverity.WARNING,
  );

  PeriodicTimerOwner()
    : super(
        name: 'fmp_periodic_timer_owner',
        description: 'Periodic timers live in the scheduler and playback.',
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
      ..addConstructorName(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor);
  }
}

const _owners = ['Timer', 'Stream'];

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  bool get _applies {
    final path = PackagePath.of(context);
    return path != null && path.isInLib && !path.isInAny(periodicTimerOwners);
  }

  void _report(AstNode node, String owner) {
    if (_inComment(node)) return;
    if (_applies) rule.reportAtNode(node, arguments: [owner]);
  }

  /// 文件註解的 `[Timer.periodic]` 也是 AST 節點（`CommentReference`），不是呼叫。
  static bool _inComment(AstNode node) =>
      node.thisOrAncestorOfType<Comment>() != null;

  /// 名稱解析不到時 `Timer.periodic(…)` 是方法呼叫。
  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'periodic') return;
    final target = node.target;
    if (target == null) return;
    for (final owner in _owners) {
      if (isNamedReference(target, owner) && _applies) {
        // 只標 `Timer.periodic`，不含引數。
        rule.reportAtOffset(
          target.offset,
          node.methodName.end - target.offset,
          arguments: [owner],
        );
      }
    }
  }

  /// 解析後 `Timer.periodic(…)` 是建構子呼叫（含 `new`、`const`、
  /// `Timer.periodic` 當函式引用）。
  @override
  void visitConstructorName(ConstructorName node) {
    if (node.name?.name != 'periodic') return;
    final owner = node.type.name.lexeme;
    if (_owners.contains(owner)) _report(node, owner);
  }

  /// `final f = Timer.periodic;` 這類函式引用。呼叫的寫法由上面兩個接。
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.identifier.name != 'periodic') return;
    for (final owner in _owners) {
      if (node.prefix.name == owner) _report(node, owner);
    }
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (node.propertyName.name != 'periodic') return;
    for (final owner in _owners) {
      if (isNamedReference(node.target, owner)) _report(node, owner);
    }
  }
}
