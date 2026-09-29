import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/material_import.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(MaterialImportTest));
}

@reflectiveTest
class MaterialImportTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => MaterialImport();

  // 報

  Future<void> test_frozenLibrariesInLib() =>
      assertLints('lib/app/fmp_app.dart', '''
import [!'package:flutter/material.dart'!];
import [!"package:flutter/cupertino.dart"!] as c;
export [!'package:flutter/material.dart'!] show Colors;
''');

  Future<void> test_frozenLibraryInTest() => assertLints(
    'test/app/fmp_app_test.dart',
    "import [!'package:flutter/material.dart'!];\n",
  );

  // 不報

  Future<void> test_standalonePackagesAndOtherFlutterLibraries() =>
      assertLints('lib/app/fmp_app.dart', '''
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

// import 'package:flutter/material.dart';
/// 見 package:flutter/material.dart 的凍結版本。
const text = "import 'package:flutter/material.dart';";
''');
}
