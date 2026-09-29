import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/no_for_testing.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(NoForTestingTest));
}

@reflectiveTest
class NoForTestingTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => NoForTesting();

  // 報

  Future<void> test_members() => assertLints('lib/playback/queue.dart', '''
int [!counterForTesting!] = 0;

void [!resetForTesting!]() {}

class Queue {
  Queue();
  Queue.[!forTesting!]();

  static int [!sizeForTesting!] = 0;
  int get [!lengthForTesting!] => 0;
  void [!_clearForTesting!]() {}
}
''');

  // 不報

  Future<void> test_inTests() => assertLints(
    'test/playback/queue_test.dart',
    'void resetForTesting() {}\n',
  );

  Future<void> test_nearMisses() => assertLints('lib/playback/queue.dart', '''
// resetForTesting 已經刪掉
void forTestingPurposes() {}

void f() {
  final valueForTesting = 1;
  void localForTesting() {}
  localForTesting();
  print(valueForTesting);
}
''');
}
