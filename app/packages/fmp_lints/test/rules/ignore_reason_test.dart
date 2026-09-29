import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/ignore_reason.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(IgnoreReasonTest));
}

@reflectiveTest
class IgnoreReasonTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => IgnoreReason();

  // 報

  Future<void> test_withoutReason() => assertLints('lib/ui/page.dart', '''
[!// ignore_for_file: fmp_lints/fmp_url_literal!]
void f() {
  [!// ignore: fmp_lints/fmp_no_empty_catch!]
  try {
    f();
  } catch (_) {}
  final a = 1; [!// ignore: unused_local_variable, fmp_design_tokens!]
  [!// ignore: fmp_lints/fmp_log_facade 理由沒有破折號!]
  print(a);
}
''');

  Future<void> test_inTests() => assertLints('test/ui/page_test.dart', '''
[!// ignore: fmp_lints/fmp_test_waits!]
void f() {}
''');

  // 不報

  Future<void> test_withReason() => assertLints('lib/ui/page.dart', '''
// ignore_for_file: fmp_lints/fmp_url_literal — 這個檔案是示範
void f() {
  // ignore: fmp_lints/fmp_log_facade - 啟動前 log 門面還沒建立
  print(1);
  // ignore: unused_local_variable, fmp_lints/fmp_design_tokens — 系統規定的尺寸
  final a = 1;
}
''');

  Future<void> test_nonFmpIgnoreAndMentions() =>
      assertLints('lib/ui/page.dart', '''
// ignore: unused_element
void _f() {}

/// 忽略寫法：`// ignore: fmp_lints/fmp_… — 理由`
const text = '// ignore: fmp_lints/fmp_url_literal';
''');
}
