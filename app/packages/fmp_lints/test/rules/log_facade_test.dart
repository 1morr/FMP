import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/log_facade.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(LogFacadeTest));
}

@reflectiveTest
class LogFacadeTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => LogFacade();

  /// 照 Flutter 的宣告：`debugPrint` 是函式型別的頂層變數，呼叫它解析成
  /// FunctionExpressionInvocation，不是 MethodInvocation。
  @override
  void addStubPackages() {
    newPackage('flutter').addFile('lib/foundation.dart', '''
typedef DebugPrintCallback = void Function(String? message);
DebugPrintCallback debugPrint = (String? message) {};
''');
  }

  // 報

  Future<void> test_printAndDebugPrint() => assertLints('lib/ui/page.dart', '''
void f() {
  [!print!]('x');
  [!debugPrint!]('y');
}
''');

  Future<void> test_resolvedDebugPrintAndImportPrefix() =>
      assertLints('lib/ui/page.dart', '''
import 'dart:core' as core;
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' as foundation;

void f() {
  [!debugPrint!]('x');
  foundation.[!debugPrint!]('y');
  core.[!print!]('z');
}
''');

  Future<void> test_developerAndTalkerImports() =>
      assertLints('lib/playback/controller.dart', '''
import [!'dart:developer'!];
import [!'dart:developer'!] as dev show log, Timeline;
import [!'package:talker/talker.dart'!];
import [!'package:talker_flutter/talker_flutter.dart'!];
''');

  // 不報

  Future<void> test_insideTheFacade() =>
      assertLints('lib/core/logging/log.dart', '''
import 'dart:developer';
import 'package:talker/talker.dart';

void f() => print('x');
''');

  Future<void> test_outsideLib() async {
    await assertLints('test/ui/page_test.dart', "void f() => print('x');\n");
    await assertLints('tool/lint_sentinel.dart', "void f() => print('x');\n");
  }

  Future<void> test_developerWithoutLog() => assertLints('lib/ui/page.dart', '''
import 'dart:developer' show Timeline;
import 'dart:developer' hide log;
''');

  Future<void> test_renamedOrWithTarget() => assertLints('lib/ui/page.dart', '''
import 'package:talkers/talkers.dart';

void printLine(String s) {}

void f(StringBuffer out, void Function(String) debugPrinter) {
  printLine('x');
  out.print('y');
  debugPrinter('z');
}

extension on StringBuffer {
  void print(String s) => write(s);
}
''');

  Future<void> test_mentionsInCommentsAndStrings() =>
      assertLints('lib/ui/page.dart', '''
// print('x');
const text = "debugPrint('x') import 'dart:developer';";
''');
}
