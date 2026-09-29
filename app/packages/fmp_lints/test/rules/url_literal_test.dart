import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/url_literal.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(UrlLiteralTest));
}

@reflectiveTest
class UrlLiteralTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => UrlLiteral();

  // 報

  Future<void> test_urlInLib() => assertLints('lib/plugins/host_api.dart', '''
const api = [!'https://api.example.com/x'!];
const insecure = [!'HTTP://example.com'!];
''');

  Future<void> test_urlInInterpolation() =>
      assertLints('lib/data/sync.dart', r'''
String url(String host) => [!'https://!]$host/x';
''');

  // 不報

  Future<void> test_endpointsFile() => assertLints(
    'lib/core/endpoints.dart',
    "const api = 'https://api.example.com';\n",
  );

  Future<void> test_outsideLib() async {
    await assertLints('test/data/sync_test.dart', "const u = 'https://x';\n");
    await assertLints('tool/demo.dart', "const u = 'https://x';\n");
  }

  Future<void> test_nearMisses() => assertLints('lib/ui/page.dart', '''
// 見 https://api.example.com
const scheme = 'https';
const text = 'http:';
''');
}
