import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../package_path.dart';

/// 外部套件只准在哪個目錄 import。鍵是套件名，也涵蓋 `<鍵>_` 開頭的同系列
/// 套件（`drift` 含 `drift_flutter`）。
final externalPackageOwners = <String, String>{
  // ADR 0010：isar 只給舊資料匯入。
  'isar_community': 'lib/legacy_import',
  'drift': 'lib/data',
  'sqlite3': 'lib/data',
  // ADR 0018：兩個播放後端。
  'just_audio': 'lib/playback/backends',
  'media_kit': 'lib/playback/backends',
  // ADR 0012：HTTP client 與 cookie 只在網路層；`dio_cookie_manager` 算在
  // `dio` 系列裡。
  'dio': 'lib/core/network',
  'cookie_jar': 'lib/core/network',
  'flutter_js': 'lib/plugins/runtime',
  // M6 才有，先列入。
  'background_downloader': 'lib/downloads',
  for (final name in platformPackages) name: 'lib/platform',
};

/// 平台套件（ADR 0009）：只准在平台層。之後的 ADR 在這裡加。
const platformPackages = [
  'path_provider',
  'window_manager',
  'tray_manager',
  'hotkey_manager',
  'launch_at_startup',
  'desktop_multi_window',
  'flutter_overlay_window',
  'permission_handler',
  'smtc_windows',
  'audio_service',
  'audio_service_mpris',
  'connectivity_plus',
  'file_picker',
  'package_info_plus',
  'flutter_inappwebview',
  'flutter_secure_storage',
];

/// 左邊目錄內的檔案不得 import 右邊的目錄。
const forbiddenLayerImports = <String, List<String>>{
  'lib/core': _upperLayers,
  'lib/domain': _upperLayers,
  'lib/data': ['lib/ui'],
};

const _upperLayers = [
  'lib/ui',
  'lib/playback',
  'lib/plugins',
  'lib/data',
  'lib/settings',
];

/// 只有自己目錄內能 import 的目錄（ADR 0010）。
const sealedDirectories = ['lib/legacy_import'];

/// 只准列出的位置 import 的檔案或目錄：被匯入端 → 允許的匯入端（檔案或目錄）。
/// 被匯入端是目錄時，目錄內的檔案彼此 import 也要列出來。
const restrictedImports = <String, List<String>>{
  // ADR 0018：串流存取的窄介面只給 PlaybackSession；組裝點建後端實例。
  'lib/playback/backends/audio_backend.dart': [
    'lib/playback/backends',
    'lib/playback/playback_session.dart',
    'lib/playback/playback_providers.dart',
  ],
  // ADR 0018：結束原因（TrackEndReason）只給後端與路由器。
  'lib/playback/backends/backend_rules.dart': [
    'lib/playback/backends',
    'lib/playback/playback_event_router.dart',
  ],
};

/// `fmp_layer_imports`：依賴方向表（ADR 0015 §決定 2）。
class LayerImports extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_layer_imports',
    "'{0}' can't be imported from here: {1}.",
    correctionMessage:
        'Move the code to the owning layer, or update the table in '
        'fmp_lints/lib/src/rules/layer_imports.dart with an ADR.',
    severity: DiagnosticSeverity.WARNING,
  );

  LayerImports()
    : super(name: 'fmp_layer_imports', description: 'Layer dependency table.');

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addImportDirective(this, visitor)
      ..addExportDirective(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);

  void _check(NamespaceDirective node) {
    final from = PackagePath.of(context);
    if (from == null) return;
    final libraryUri = context.libraryElement?.uri;
    final ownPackage = libraryUri != null && libraryUri.isScheme('package')
        ? libraryUri.pathSegments.first
        : null;
    for (final literal in [
      node.uri,
      for (final c in node.configurations) c.uri,
    ]) {
      final uri = literal.stringValue;
      if (uri == null) continue;
      final reason = layerViolation(from, uri, ownPackage: ownPackage);
      if (reason != null) {
        rule.reportAtNode(literal, arguments: [uri, reason]);
      }
    }
  }
}

/// [from] import [uri] 違反依賴方向表時回傳原因，否則 `null`。
///
/// [ownPackage] 是 [from] 所屬 package 的名稱；只有 `lib/` 內的檔案有。
String? layerViolation(PackagePath from, String uri, {String? ownPackage}) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.isScheme('dart')) return null;

  PackagePath? target;
  if (parsed.isScheme('package')) {
    final segments = parsed.pathSegments;
    if (segments.isEmpty) return null;
    final name = segments.first;
    if (name != ownPackage) return _externalViolation(from, name);
    target = PackagePath('lib/${segments.skip(1).join('/')}');
  } else if (parsed.hasScheme) {
    return 'only package: and relative URIs inside this package are allowed';
  } else {
    target = from.resolve(uri);
    if (target == null) {
      return 'it leaves this package (the legacy project lives outside app/)';
    }
  }
  return _internalViolation(from, target);
}

String? _externalViolation(PackagePath from, String packageName) {
  if (!from.isInLib) return null;
  for (final MapEntry(key: family, value: owner)
      in externalPackageOwners.entries) {
    final inFamily =
        packageName == family || packageName.startsWith('${family}_');
    if (inFamily && !from.isIn(owner)) {
      return "package:$family* is only allowed in $owner/";
    }
  }
  return null;
}

String? _internalViolation(PackagePath from, PackagePath target) {
  if (!from.isInLib || !target.isInLib) return null;
  for (final sealed in sealedDirectories) {
    if (target.isIn(sealed) && !from.isIn(sealed)) {
      return '$sealed/ is only imported from inside itself';
    }
  }
  for (final MapEntry(key: restricted, value: allowed)
      in restrictedImports.entries) {
    if (target.isIn(restricted) && !from.isInAny(allowed)) {
      return '$restricted is only imported from ${allowed.join(', ')}';
    }
  }
  for (final MapEntry(key: layer, value: forbidden)
      in forbiddenLayerImports.entries) {
    if (!from.isIn(layer)) continue;
    for (final upper in forbidden) {
      if (target.isIn(upper)) return '$layer/ must not import $upper/';
    }
  }
  return null;
}
