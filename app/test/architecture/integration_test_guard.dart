import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// [files]（路徑 → 原始碼）裡，頂層 `main()` 沒有呼叫 `installNoNetworkGuard()`
/// 的檔案。由 `integration_test_guard_test.dart` 執行；看 AST，不比對字串。
List<String> filesMissingNoNetworkGuard(Map<String, String> files) {
  return [
    for (final MapEntry(key: path, value: source) in files.entries)
      if (!_mainInstallsGuard(source)) path,
  ];
}

bool _mainInstallsGuard(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  for (final declaration in unit.declarations) {
    if (declaration is FunctionDeclaration &&
        declaration.name.lexeme == 'main') {
      final finder = _GuardCallFinder();
      declaration.accept(finder);
      return finder.found;
    }
  }
  return false;
}

class _GuardCallFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null &&
        node.methodName.name == 'installNoNetworkGuard') {
      found = true;
    }
    super.visitMethodInvocation(node);
  }
}
