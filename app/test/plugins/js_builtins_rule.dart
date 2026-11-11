import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:fjs/fjs.dart';

/// 插件引擎可以開的 fjs 內建模組（`JsBuiltinOptions` 的欄位名）。要加新的
/// 先確認它不連網、不碰檔案系統與行程（ADR 0038、brief 事實 K11）。
const allowedBuiltins = {'timers'};

/// [options] 開了哪些內建模組。從 freezed 產生的 `toString()`
/// （`JsBuiltinOptions(abort: null, …, timers: true, …)`）讀，所以 fjs 之後
/// 新增的模組也算得到，不必在這裡列出全部欄位。
Set<String> enabledBuiltins(JsBuiltinOptions options) => {
  for (final m in RegExp(r'(\w+): true').allMatches('$options')) m[1]!,
};

/// `lib/` 裡建立 fjs 引擎的地方都要是 `JsEngine.create(builtins:
/// pluginBuiltins, …)`；直接建 `JsAsyncRuntime`、`JsRuntime`（不經
/// `JsEngine`、可自己指定內建模組）一律不行。[files] 的 key 是相對 `lib/`
/// 的路徑，回傳 `<路徑>:<行>: <原因>`。
List<String> engineCreationViolations(Map<String, String> files) {
  final violations = <String>[];
  files.forEach((path, source) {
    final result = parseString(content: source, throwIfDiagnostics: false);
    result.unit.accept(
      _Visitor((node, reason) {
        final line = result.lineInfo.getLocation(node.offset).lineNumber;
        violations.add('$path:$line: $reason');
      }),
    );
  });
  return violations;
}

const _runtimeClasses = {'JsAsyncRuntime', 'JsRuntime'};

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.report);

  final void Function(AstNode node, String reason) report;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = switch (node.target) {
      SimpleIdentifier(:final name) => name,
      PrefixedIdentifier(:final identifier) => identifier.name,
      _ => null,
    };
    final method = node.methodName.name;
    if (target == 'JsEngine' && method == 'create') {
      final builtins = node.argumentList.arguments
          .whereType<NamedArgument>()
          .where((a) => a.name.lexeme == 'builtins')
          .map((a) => a.argumentExpression)
          .firstOrNull;
      if (builtins is! SimpleIdentifier || builtins.name != 'pluginBuiltins') {
        report(node, 'JsEngine.create must pass builtins: pluginBuiltins');
      }
    }
    // `JsAsyncRuntime.create(…)`，以及不加 new 的 `JsRuntime()`。
    if (_runtimeClasses.contains(target) ||
        (node.target == null && _runtimeClasses.contains(method))) {
      report(node, 'create plugin engines through JsEngine.create');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_runtimeClasses.contains(node.constructorName.type.name.lexeme)) {
      report(node, 'create plugin engines through JsEngine.create');
    }
    super.visitInstanceCreationExpression(node);
  }
}
