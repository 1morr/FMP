import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/toast_entry.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(ToastEntryTest));
}

@reflectiveTest
class ToastEntryTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => ToastEntry();

  @override
  void addStubPackages() {
    newPackage('material_ui').addFile('lib/material_ui.dart', '''
class SnackBar {
  const SnackBar();
}
class SnackBarTheme {
  const SnackBarTheme();
}
class ScaffoldMessengerState {
  void showSnackBar(SnackBar bar) {}
  void clearSnackBars() {}
}
class ScaffoldMessenger {
  static ScaffoldMessengerState of(Object context) => ScaffoldMessengerState();
  static ScaffoldMessengerState? maybeOf(Object context) => null;
}
class Scaffold {
  static Object? maybeOf(Object context) => null;
}
''');
  }

  // 報

  Future<void> test_directSnackBar() =>
      assertLints('lib/ui/search/page.dart', '''
import 'package:material_ui/material_ui.dart';

void f(Object context) {
  final messenger = ScaffoldMessenger.[!of!](context);
  ScaffoldMessenger.[!maybeOf!](context)?.[!clearSnackBars!]();
  messenger.[!showSnackBar!](const [!SnackBar!]());
  messenger.[!clearSnackBars!]();
}
''');

  Future<void> test_withImportPrefix() =>
      assertLints('lib/ui/search/page.dart', '''
import 'package:material_ui/material_ui.dart' as m;

void f(Object context) {
  m.ScaffoldMessenger.[!of!](context);
  m.ScaffoldMessenger.[!maybeOf!](context);
  const m.[!SnackBar!]();
}
''');

  // 不報

  Future<void> test_insideToast() =>
      assertLints('lib/ui/toast/toast_host.dart', '''
import 'package:material_ui/material_ui.dart';

void f(Object context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar());
}
''');

  Future<void> test_nearMisses() => assertLints('lib/ui/search/page.dart', '''
import 'package:material_ui/material_ui.dart';

// ScaffoldMessenger.of(context).showSnackBar(const SnackBar());
const theme = SnackBarTheme();
const text = 'showSnackBar';
Object? of(Object o) => o;
final value = of(1);
Object? maybeOf(Object o) => o;
final scaffold = Scaffold.maybeOf(1);
final other = maybeOf(2);
''');
}
