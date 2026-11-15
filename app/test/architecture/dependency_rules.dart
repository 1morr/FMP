import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// architecture〈依賴規則〉 的依賴規則。由 `dependency_rules_test.dart` 執行；不做成
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

  /// 只有 log 門面 `core/log/` 能 import log 套件（brief〈錯誤、log 與診斷〉 的單一 log 門面）。
  logPackageOutsideLogFacade,

  /// 只有插件宿主 `plugins/` 能 import JS 引擎與 HTTP 套件（[PackageScope.pluginsOnly]）。
  pluginPackageOutsidePlugins,

  /// 只有玻璃元件 `app/glass/` 能 import 玻璃套件（[PackageScope.glassOnly]）。
  glassPackageOutsideGlass,

  /// 只有 `platform/` 能用 `Platform.isXxx`。
  platformCheckOutsidePlatform,

  /// 只有 `platform/` 能用 `defaultTargetPlatform`，也只有它能讀預設等於它的
  /// `ThemeData.platform`（`Theme.of(context).platform`、存成變數或名稱含
  /// theme 的變數再讀 `.platform`）；畫面要的平台差異（寬度分級、密度）由
  /// `platform/` 提供。
  targetPlatformOutsidePlatform,

  /// `domain/` 是純 Dart：不能 import Flutter（`dart:ui` 與
  /// [PackageScope.flutter] 的套件），經 fmp 其他檔間接帶進來也不行：從
  /// `domain/` 沿 `package:fmp/` 的 import 往下走，整條鏈上都不能出現 Flutter。
  flutterInDomain,

  /// 不用 Flutter 內建的 `package:flutter/material.dart`、`cupertino.dart`
  /// （3.50 起 deprecated），改用 `material_ui`、`cupertino_ui`（事實 T1）。
  builtinDesignLibrary,

  /// Dart 端不能拿音源識別碼的字面值做分支（ADR 0038）；音源邏輯在
  /// `app/plugins/` 的插件裡。
  sourceIdBranch,

  /// import 了 [packageScopes] 沒分類的套件。
  unclassifiedPackage,
}

/// 套件可以在 `lib/` 的哪裡被 import。
enum PackageScope {
  /// 純 Dart 套件，哪裡都能用。
  anywhere,

  /// Flutter 與依賴 Flutter 的套件：`domain/` 以外都能用
  /// （[Rule.flutterInDomain]）。
  flutter,
  dataOnly,
  platformOnly,

  /// 音訊播放器（just_audio、media_kit）：`platform/` 與音訊後端的兩個實作
  /// `playback/backends/`（architecture〈依賴規則〉 的例外）。`playback/` 其他檔只依賴介面。
  audioBackend,

  /// log 套件（logger）：只有 log 門面 `core/log/`，其他模組經門面寫 log。
  logFacade,

  /// JS 引擎（fjs）與 HTTP（dio）：只有插件宿主 `plugins/`。插件引擎只開
  /// 白名單內建模組（`test/plugins/js_engine_builtins_test.dart`），別處不該
  /// 自己建引擎；連網都經宿主網路層的網域白名單（ADR 0038），別處不該自己
  /// 開 HTTP client。
  pluginsOnly,

  /// 玻璃套件（liquid_glass_easy）：只有玻璃元件 `app/glass/`。三級包在同一個
  /// 元件後面，日後換套件只改一處（brief〈介面〉）。
  glassOnly,
}

/// 每個 `lib/` 用得到的套件都要在這裡分類；沒分類的會被 [Rule.unclassifiedPackage]
/// 擋下。drift 與音訊播放器先列著，因為它們的規則（architecture〈依賴規則〉）在加依賴前就定了。
const packageScopes = <String, PackageScope>{
  'fmp': PackageScope.anywhere,
  'flutter': PackageScope.flutter,
  'material_ui': PackageScope.flutter,
  'flutter_riverpod': PackageScope.flutter,
  'riverpod': PackageScope.anywhere,
  'slang': PackageScope.anywhere,
  'slang_flutter': PackageScope.flutter,
  'drift': PackageScope.dataOnly,
  'sqlite3': PackageScope.dataOnly,
  'just_audio': PackageScope.audioBackend,
  'media_kit': PackageScope.audioBackend,
  'logger': PackageScope.logFacade,
  'path_provider': PackageScope.platformOnly,
  'dio': PackageScope.pluginsOnly,
  'fjs': PackageScope.pluginsOnly,
  'liquid_glass_easy': PackageScope.glassOnly,
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
  final units = {
    for (final MapEntry(key: path, value: source) in files.entries)
      path: parseString(content: source, throwIfDiagnostics: false),
  };
  final graph = _ImportGraph({
    for (final e in units.entries) e.key: e.value.unit,
  }, packages);
  final violations = <Violation>[];
  units.forEach((path, result) {
    result.unit.accept(
      _Visitor(path, result.lineInfo, packages, graph, violations.add),
    );
  });
  return violations;
}

/// import 或 export 的主網址與條件式 import 的每個候選網址
/// （`if (dart.library.ui) '…'`），相對路徑解析成 `package:` 網址。
Iterable<Uri> _directiveUris(String path, NamespaceDirective node) sync* {
  for (final raw in [
    node.uri.stringValue,
    for (final c in node.configurations) c.uri.stringValue,
  ]) {
    if (raw != null) yield Uri.parse('package:fmp/$path').resolve(raw);
  }
}

bool _isFlutter(Uri uri, Map<String, PackageScope> packages) =>
    uri.scheme == 'dart'
    ? uri.path == 'ui'
    : uri.scheme == 'package' &&
          packages[uri.pathSegments.first] == PackageScope.flutter;

/// `lib/` 裡 fmp 檔之間的 import 關係，用來找從某個檔一路帶進 Flutter 的鏈。
class _ImportGraph {
  _ImportGraph(Map<String, CompilationUnit> units, this.packages) {
    units.forEach((path, unit) {
      final targets = <String>[];
      for (final node in unit.directives.whereType<NamespaceDirective>()) {
        for (final uri in _directiveUris(path, node)) {
          if (uri.scheme == 'package' && uri.pathSegments.first == 'fmp') {
            targets.add(uri.pathSegments.skip(1).join('/'));
          } else if (_isFlutter(uri, packages)) {
            _flutterImport[path] ??= uri.toString();
          }
        }
      }
      _imports[path] = targets;
    });
  }

  final Map<String, PackageScope> packages;
  final _imports = <String, List<String>>{};
  final _flutterImport = <String, String>{};

  /// 從 [start] 沿 fmp 的 import 走到 Flutter 的一條鏈（`[start, …, Flutter
  /// 的網址]`）；整條都是純 Dart 時是 null。不在 `lib/` 裡的檔不往下走。
  List<String>? chainToFlutter(String start) {
    final visited = <String>{};
    List<String>? walk(String path) {
      if (!visited.add(path) || !_imports.containsKey(path)) return null;
      if (_flutterImport[path] case final flutter?) return [path, flutter];
      for (final next in _imports[path]!) {
        if (walk(next) case final chain?) return [path, ...chain];
      }
      return null;
    }

    return walk(start);
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.path, this.lineInfo, this.packages, this.graph, this.report)
    : module = path.split('/').first;

  final String path;
  final String module;
  final LineInfo lineInfo;
  final Map<String, PackageScope> packages;
  final _ImportGraph graph;
  final void Function(Violation) report;

  /// 這個檔裡以 `Theme.of(…)` 初始化的變數名稱。
  final _themeVariables = <String>{};

  void _flag(AstNode node, Rule rule, String message) {
    final line = lineInfo.getLocation(node.offset).lineNumber;
    report(Violation(path, line, rule, message));
  }

  @override
  void visitImportDirective(ImportDirective node) {
    _checkDirective(node);
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _checkDirective(node);
    super.visitExportDirective(node);
  }

  void _checkDirective(NamespaceDirective node) {
    for (final uri in _directiveUris(path, node)) {
      _checkUri(node, uri);
    }
  }

  void _checkUri(AstNode node, Uri uri) {
    if (uri.scheme == 'dart' && uri.path == 'ui' && module == 'domain') {
      _flag(node, Rule.flutterInDomain, 'domain/ must not import dart:ui');
    }
    if (uri.scheme != 'package') return;
    final segments = uri.pathSegments;
    final package = segments.first;

    if (package == 'fmp') {
      final target = segments.skip(1).join('/');
      // domain/ 裡的檔各自檢查自己的 import，這裡只往 domain/ 外面追。
      if (module == 'domain' && !target.startsWith('domain/')) {
        if (graph.chainToFlutter(target) case final chain?) {
          _flag(
            node,
            Rule.flutterInDomain,
            'domain/ is pure Dart; reaches Flutter via ${chain.join(' -> ')}',
          );
        }
      }
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

    const designLibraries = {'material', 'cupertino'};
    if (package == 'flutter' &&
        (designLibraries.contains(segments[1].replaceAll('.dart', '')) ||
            segments[1] == 'src' &&
                segments.length > 2 &&
                designLibraries.contains(segments[2]))) {
      _flag(
        node,
        Rule.builtinDesignLibrary,
        'use package:material_ui or package:cupertino_ui instead of $uri',
      );
    }

    switch (packages[package]) {
      case null:
        _flag(
          node,
          Rule.unclassifiedPackage,
          'classify package:$package in packageScopes '
          '(test/architecture/dependency_rules.dart)',
        );
      case PackageScope.flutter when module == 'domain':
        _flag(
          node,
          Rule.flutterInDomain,
          'domain/ is pure Dart; must not import package:$package',
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
      case PackageScope.logFacade when !path.startsWith('core/log/'):
        _flag(
          node,
          Rule.logPackageOutsideLogFacade,
          'only core/log/ may import package:$package; log through Log',
        );
      case PackageScope.pluginsOnly when module != 'plugins':
        _flag(
          node,
          Rule.pluginPackageOutsidePlugins,
          'only plugins/ may import package:$package',
        );
      case PackageScope.glassOnly when !path.startsWith('app/glass/'):
        _flag(
          node,
          Rule.glassPackageOutsideGlass,
          'only app/glass/ may import package:$package; use the Glass widget',
        );
      default:
    }
  }

  @override
  void visitCommentReference(CommentReference node) {
    // `[defaultTargetPlatform]` 這類文件註解的引用不是程式碼，不往下看。
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'defaultTargetPlatform' && module != 'platform') {
      _flag(
        node,
        Rule.targetPlatformOutsidePlatform,
        'only platform/ may read defaultTargetPlatform; '
        'get width class and density from platform/',
      );
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_isThemeOf(node.initializer)) _themeVariables.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  static bool _isThemeOf(Expression? e) =>
      e is MethodInvocation &&
      e.methodName.name == 'of' &&
      e.target is SimpleIdentifier &&
      (e.target! as SimpleIdentifier).name == 'Theme';

  /// 沒有型別資訊，以寫法認 `ThemeData`：`Theme.of(…)`、以它初始化的變數、
  /// 名稱含 theme 的變數或屬性。
  bool _looksLikeThemeData(Expression e) => switch (e) {
    _ when _isThemeOf(e) => true,
    SimpleIdentifier(:final name) =>
      _themeVariables.contains(name) || name.toLowerCase().contains('theme'),
    PrefixedIdentifier(:final identifier) =>
      identifier.name.toLowerCase().contains('theme'),
    PropertyAccess(:final propertyName) =>
      propertyName.name.toLowerCase().contains('theme'),
    _ => false,
  };

  /// `ThemeData.platform` 預設就是 defaultTargetPlatform。
  void _checkThemePlatform(
    AstNode node,
    Expression target,
    SimpleIdentifier member,
  ) {
    if (module == 'platform' || member.name != 'platform') return;
    if (!_looksLikeThemeData(target)) return;
    _flag(
      node,
      Rule.targetPlatformOutsidePlatform,
      'only platform/ may read ThemeData.platform; '
      'get width class and density from platform/',
    );
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _checkThemePlatform(node, node.prefix, node.identifier);
    _checkPlatform(node, node.prefix.name, node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target != null) _checkThemePlatform(node, target, node.propertyName);
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
