import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// plan §1.3 的依賴規則。由 `dependency_rules_test.dart` 執行；不做成
/// analyzer lint 套件（flutter/flutter#187999）。
enum Rule {
  /// `ui/` 不能直接碰 `data/`。
  uiReachesData,

  /// `ui/` 只能用 `plugins/` 的公開檔，不能碰 `plugins/src/`。
  uiReachesPluginInternals,

  /// 只有 `data/` 能 import drift 這類資料庫套件。
  dataPackageOutsideData,

  /// 只有 `platform/` 能 import 平台套件；音訊播放器套件另外允許
  /// `playback/backends/`（[PackageScope.audioBackend]）。
  platformPackageOutsidePlatform,

  /// 只有 `platform/` 能用 `Platform.isXxx`。
  platformCheckOutsidePlatform,

  /// Dart 端不能拿音源識別碼的字面值做分支（ADR 0038）；音源邏輯在
  /// `app/plugins/` 的插件裡。
  sourceIdBranch,

  /// import 了 [packageScopes] 沒分類的套件。
  unclassifiedPackage,
}

/// 套件可以在 `lib/` 的哪裡被 import。
enum PackageScope {
  anywhere,
  dataOnly,
  platformOnly,

  /// 音訊播放器（just_audio、media_kit）：`platform/` 與音訊後端的兩個實作
  /// `playback/backends/`（plan §1.3 的例外）。`playback/` 其他檔只依賴介面。
  audioBackend,
}

/// 每個 `lib/` 用得到的套件都要在這裡分類；沒分類的會被 [Rule.unclassifiedPackage]
/// 擋下。drift 與音訊播放器先列著，因為它們的規則（plan §1.3）在加依賴前就定了。
const packageScopes = <String, PackageScope>{
  'fmp': PackageScope.anywhere,
  'flutter': PackageScope.anywhere,
  'flutter_localizations': PackageScope.anywhere,
  'flutter_riverpod': PackageScope.anywhere,
  'riverpod': PackageScope.anywhere,
  'slang': PackageScope.anywhere,
  'slang_flutter': PackageScope.anywhere,
  'drift': PackageScope.dataOnly,
  'sqlite3': PackageScope.dataOnly,
  'path_provider': PackageScope.platformOnly,
  'just_audio': PackageScope.audioBackend,
  'media_kit': PackageScope.audioBackend,
};

/// 音源與歌詞源的識別碼，比對時不分大小寫。
const sourceIds = {'bilibili', 'youtube', 'netease', 'lrclib'};

class Violation {
  Violation(this.path, this.line, this.rule, this.message);

  final String path;
  final int line;
  final Rule rule;
  final String message;

  @override
  String toString() => 'lib/$path:$line ${rule.name}: $message';
}

/// 讀 `lib/` 底下手寫的 Dart 檔（略過產生的 `*.g.dart`），key 是相對
/// `lib/` 的路徑。
Map<String, String> readLibSources(Directory lib) {
  final root = lib.absolute.uri;
  return {
    for (final file in lib.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') && !file.path.endsWith('.g.dart'))
        root.resolveUri(file.absolute.uri).path.substring(root.path.length):
            file.readAsStringSync(),
  };
}

/// [files] 的 key 是相對 `lib/` 的路徑，例如 `ui/home/home_page.dart`。
List<Violation> checkDependencyRules(
  Map<String, String> files, {
  Map<String, PackageScope> packages = packageScopes,
}) {
  final violations = <Violation>[];
  files.forEach((path, source) {
    final result = parseString(content: source, throwIfDiagnostics: false);
    result.unit.accept(
      _Visitor(path, result.lineInfo, packages, violations.add),
    );
  });
  return violations;
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.path, this.lineInfo, this.packages, this.report)
    : module = path.split('/').first;

  final String path;
  final String module;
  final LineInfo lineInfo;
  final Map<String, PackageScope> packages;
  final void Function(Violation) report;

  void _flag(AstNode node, Rule rule, String message) {
    final line = lineInfo.getLocation(node.offset).lineNumber;
    report(Violation(path, line, rule, message));
  }

  @override
  void visitImportDirective(ImportDirective node) {
    _checkUri(node, node.uri.stringValue);
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _checkUri(node, node.uri.stringValue);
    super.visitExportDirective(node);
  }

  void _checkUri(AstNode node, String? raw) {
    if (raw == null) return;
    final uri = Uri.parse('package:fmp/$path').resolve(raw);
    if (uri.scheme != 'package') return;
    final segments = uri.pathSegments;
    final package = segments.first;

    if (package == 'fmp') {
      final target = segments.skip(1).join('/');
      if (module == 'ui' && target.startsWith('data/')) {
        _flag(node, Rule.uiReachesData, 'ui/ must not reach $target');
      }
      if (module == 'ui' && target.startsWith('plugins/src/')) {
        _flag(
          node,
          Rule.uiReachesPluginInternals,
          'ui/ must use the plugins/ public library, not $target',
        );
      }
      return;
    }

    switch (packages[package]) {
      case null:
        _flag(
          node,
          Rule.unclassifiedPackage,
          'classify package:$package in packageScopes '
          '(test/architecture/dependency_rules.dart)',
        );
      case PackageScope.dataOnly when module != 'data':
        _flag(
          node,
          Rule.dataPackageOutsideData,
          'only data/ may import package:$package',
        );
      case PackageScope.platformOnly when module != 'platform':
        _flag(
          node,
          Rule.platformPackageOutsidePlatform,
          'only platform/ may import package:$package',
        );
      case PackageScope.audioBackend
          when module != 'platform' && !path.startsWith('playback/backends/'):
        _flag(
          node,
          Rule.platformPackageOutsidePlatform,
          'only platform/ and playback/backends/ may import package:$package',
        );
      default:
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _checkPlatform(node, node.prefix.name, node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is PrefixedIdentifier) {
      // `io.Platform.isWindows`
      _checkPlatform(node, target.identifier.name, node.propertyName.name);
    }
    super.visitPropertyAccess(node);
  }

  void _checkPlatform(AstNode node, String receiver, String member) {
    if (module == 'platform') return;
    if (receiver == 'Platform' && RegExp(r'^is[A-Z]').hasMatch(member)) {
      _flag(
        node,
        Rule.platformCheckOutsidePlatform,
        'only platform/ may use Platform.$member',
      );
    }
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type;
    if (op == TokenType.EQ_EQ || op == TokenType.BANG_EQ) {
      for (final operand in [node.leftOperand, node.rightOperand]) {
        _checkSourceLiteral(operand);
      }
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitConstantPattern(ConstantPattern node) {
    // 涵蓋 switch 敘述、switch 運算式與 if-case。
    _checkSourceLiteral(node.expression);
    super.visitConstantPattern(node);
  }

  void _checkSourceLiteral(Expression expression) {
    if (expression is! SimpleStringLiteral) return;
    final value = expression.value.toLowerCase();
    if (sourceIds.contains(value)) {
      _flag(
        expression,
        Rule.sourceIdBranch,
        "branching on '$value' belongs in the plugin (ADR 0038)",
      );
    }
  }
}
