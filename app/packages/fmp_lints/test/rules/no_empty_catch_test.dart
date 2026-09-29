import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/no_empty_catch.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(NoEmptyCatchTest));
}

@reflectiveTest
class NoEmptyCatchTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => NoEmptyCatch();

  // 報

  Future<void> test_emptyCatchWithUnderscore() =>
      assertLints('lib/ui/page.dart', '''
void f() {
  try {
    f();
  } catch (_) [!{}!]
}
''');

  Future<void> test_onlyAComment() => assertLints('lib/data/database.dart', '''
void f() {
  try {
    f();
  } on StateError [!{
    // 沒事
  }!]
}
''');

  Future<void> test_inTests() => assertLints('test/data/database_test.dart', '''
void f() {
  try {
    f();
  } catch (e, s) [!{}!]
}
''');

  // 不報

  Future<void> test_bodyWithAStatement() => assertLints('lib/ui/page.dart', '''
void f() {
  try {
    f();
  } catch (_) {
    return;
  }
  try {
    f();
  } on StateError {
    rethrow;
  }
}
''');

  Future<void> test_mentionsInCommentsAndStrings() =>
      assertLints('lib/ui/page.dart', '''
// try { f(); } catch (_) {}
const text = 'try { f(); } catch (_) {}';
''');
}
