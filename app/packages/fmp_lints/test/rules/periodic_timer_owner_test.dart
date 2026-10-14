import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/periodic_timer_owner.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(PeriodicTimerOwnerTest));
}

@reflectiveTest
class PeriodicTimerOwnerTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => PeriodicTimerOwner();

  // 報

  Future<void> test_timerOutsideOwners() async {
    for (final path in [
      'lib/radio/radio_service.dart',
      'lib/ui/search/page.dart',
      'lib/core/network/network_status.dart',
      // 名稱以允許目錄開頭的別的目錄、檔案不算（不是字串前綴比對）。
      'lib/scheduler_extras/x.dart',
      'lib/playback_helpers.dart',
    ]) {
      await assertLints(path, '''
import 'dart:async';

void a() {
  [!Timer.periodic!](const Duration(seconds: 1), (_) {});
}
''');
    }
  }

  Future<void> test_streamOutsideOwners() =>
      assertLints('lib/radio/radio_service.dart', '''
import 'dart:async';

final a = [!Stream.periodic!](const Duration(seconds: 1));
final b = [!Stream<int>.periodic!](const Duration(seconds: 1), (n) => n);
''');

  Future<void> test_prefixedAndTearOff() =>
      assertLints('lib/ui/search/page.dart', '''
import 'dart:async' as async;

void a() {
  [!async.Timer.periodic!](const Duration(seconds: 1), (_) {});
}

final b = [!Timer.periodic!];
''');

  // 不報

  Future<void> test_insideOwners() async {
    for (final path in [
      'lib/scheduler/background_scheduler.dart',
      'lib/playback/queue_store.dart',
    ]) {
      await assertLints(path, '''
import 'dart:async';

void a() {
  Timer.periodic(const Duration(seconds: 1), (_) {});
}

final b = Stream.periodic(const Duration(seconds: 1));
''');
    }
  }

  Future<void> test_outsideLib() => assertLints('test/x_test.dart', '''
import 'dart:async';

void a() {
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
''');

  // 同名前綴的自訂方法、一次性計時器、註解與字串都不報；改變格式也不影響。
  Future<void> test_nearMisses() =>
      assertLints('lib/radio/radio_service.dart', '''
import 'dart:async';

class Timer2 {
  static void periodicLike() {}
  static void periodically() {}
}

class Stream2 {
  static void periodic() {}
}

// Timer.periodic(d, f)
const text = 'Stream.periodic';

/// 文件註解的引用：[Timer.periodic]、[Stream.periodic]。

void a() {
  Timer2.periodicLike();
  Timer2.periodically();
  Stream2.periodic();
  Timer.run(() {});
  Timer(const Duration(seconds: 1), () {});
  Stream.fromIterable([1]);
  final periodic = 1;
  periodic.toString();
}
''');

  // 換行與空白不影響：拆成多行照樣報（範圍跨行），在允許目錄照樣不報。
  Future<void> test_formattingDoesNotMatter() async {
    await assertLints('lib/radio/x.dart', '''
import 'dart:async';

void a() {
  [!Timer
      .periodic!](
        const Duration(seconds: 1),
        (_) {},
      );
}
''');
    await assertLints('lib/scheduler/x.dart', '''
import 'dart:async';

void a() {
  Timer
      .periodic(
        const Duration(seconds: 1),
        (_) {},
      );
}
''');
  }
}
