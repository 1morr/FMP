import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// 框架內凍結的設計系統函式庫，與取代它們的獨立套件（ADR 0024 §決定 1）。
const frozenDesignLibraries = {
  'package:flutter/material.dart': 'package:material_ui/material_ui.dart',
  'package:flutter/cupertino.dart': 'package:cupertino_ui/cupertino_ui.dart',
};

/// `fmp_material_import`：package 內任何檔案都不得 import 或 export
/// [frozenDesignLibraries] 的鍵。接手 PR 2 的
/// `test/static_rules/material_import_static_rule_test.dart`（那支掃 `lib/`
/// 與 `test/`），所以不限 `lib/`。
class MaterialImport extends AnalysisRule {
  static const LintCode code = LintCode(
    'fmp_material_import',
    "'{0}' is frozen in the framework.",
    correctionMessage: "Import '{1}' instead.",
    severity: DiagnosticSeverity.WARNING,
  );

  MaterialImport()
    : super(
        name: 'fmp_material_import',
        description: 'Use the standalone material_ui / cupertino_ui packages.',
      );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry
      ..addImportDirective(this, visitor)
      ..addExportDirective(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule);

  final AnalysisRule rule;

  @override
  void visitImportDirective(ImportDirective node) => _check(node);

  @override
  void visitExportDirective(ExportDirective node) => _check(node);

  void _check(NamespaceDirective node) {
    final uri = node.uri.stringValue;
    final replacement = frozenDesignLibraries[uri];
    if (uri != null && replacement != null) {
      rule.reportAtNode(node.uri, arguments: [uri, replacement]);
    }
  }
}
