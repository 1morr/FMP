import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/test_waits.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(TestWaitsTest));
}

@reflectiveTest
class TestWaitsTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => TestWaits();

  // 報

  Future<void> test_directCallInTest() =>
      assertLints('test/playback/queue_test.dart', '''
Future<void> f() async {
  await [!pumpEventQueue!]();
  await [!pumpEventQueue!](times: 5);
}
''');

  // 不報

  Future<void> test_waitHelper() => assertLints(
    'test/support/pump_until.dart',
    'Future<void> drainEventQueue() => pumpEventQueue();\n',
  );

  Future<void> test_nearMisses() =>
      assertLints('test/playback/queue_test.dart', '''
// pumpEventQueue();
const text = 'pumpEventQueue()';
Future<void> f() async {
  await pumpUntil(() => true);
  await drainEventQueue();
}
''');
}
