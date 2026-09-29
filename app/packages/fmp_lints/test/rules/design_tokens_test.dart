import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:fmp_lints/src/rules/design_tokens.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/rule_test_base.dart';

void main() {
  defineReflectiveSuite(() => defineReflectiveTests(DesignTokensTest));
}

@reflectiveTest
class DesignTokensTest extends FmpRuleTest {
  @override
  AnalysisRule createRule() => DesignTokens();

  @override
  void addStubPackages() {
    newPackage('material_ui').addFile('lib/material_ui.dart', '''
class EdgeInsets {
  const EdgeInsets.all(double value);
  const EdgeInsets.only({double left = 0, double top = 0});
  const EdgeInsets.symmetric({double horizontal = 0, double vertical = 0});
}
class EdgeInsetsDirectional {
  const EdgeInsetsDirectional.only({double start = 0, double end = 0});
  const EdgeInsetsDirectional.all(double value);
}
class Size {
  const Size(double width, double height);
  const Size.square(double dimension);
}
class SizedBox {
  const SizedBox({double? width, double? height, Object? child});
  const SizedBox.square({double? dimension});
  const SizedBox.fromSize({Size? size});
}
class Radius {
  const Radius.circular(double radius);
  const Radius.elliptical(double x, double y);
  static const zero = Radius.circular(0);
}
class BorderRadius {
  const BorderRadius.circular(double radius);
  const BorderRadius.all(Radius radius);
  const BorderRadius.only({Radius topLeft = Radius.zero});
}
class BorderRadiusDirectional {
  const BorderRadiusDirectional.circular(double radius);
  const BorderRadiusDirectional.only({Radius topStart = Radius.zero});
}
class Layout {
  const Layout({Size? size});
}
class TextStyle {
  const TextStyle({double? fontSize, double? height});
}
class Color {
  const Color(int value);
  const Color.fromARGB(int a, int r, int g, int b);
  const Color.fromRGBO(int r, int g, int b, double opacity);
  const Color.from({required double alpha, required double red,
      required double green, required double blue});
  static Color? lerp(Color? a, Color? b, double t) => a;
}
class Colors {
  static const red = Color(0xFFFF0000);
}
class AppTokens {
  static const double gap = 8;
  static const int argb = 0xFF123456;
  static const int alpha = 255;
}
''');
  }

  // 報

  Future<void> test_rawValuesInUi() =>
      assertLints('lib/ui/search/page.dart', '''
import 'package:material_ui/material_ui.dart';

const a = EdgeInsets.all([!8!]);
const b = EdgeInsets.only(left: [!4.5!], top: 0);
const c = EdgeInsets.symmetric(horizontal: [!-2!]);
const d = SizedBox(width: [!16!], height: [!24!]);
const e = SizedBox.square(dimension: [!40!]);
const f = BorderRadius.circular([!12!]);
const g = TextStyle(fontSize: [!14!]);
const h = [!Color(0xFF123456)!];
const i = [!Colors!].red;
const j = EdgeInsets.all([!(8)!]);
''');

  Future<void> test_neighbouringConstructors() =>
      assertLints('lib/ui/search/page.dart', '''
import 'package:material_ui/material_ui.dart';

const a = EdgeInsetsDirectional.only(start: [!8!], end: 0);
const b = EdgeInsetsDirectional.all([!-4!]);
const c = Radius.circular([!8!]);
const d = Radius.elliptical([!4!], [!6.5!]);
const e = BorderRadius.all(Radius.circular([!12!]));
const f = BorderRadius.only(topLeft: Radius.circular([!2!]));
const g = BorderRadiusDirectional.circular([!10!]);
const h = BorderRadiusDirectional.only(topStart: Radius.circular([!3!]));
const i = SizedBox.fromSize(size: Size([!48!], [!0.5!]));
const j = SizedBox.fromSize(size: Size.square([!24!]));
''');

  Future<void> test_colorConstructors() =>
      assertLints('lib/ui/search/page.dart', '''
import 'package:material_ui/material_ui.dart';

const a = [!Color.fromARGB(255, 0, 0, 0)!];
const b = [!Color.fromRGBO(12, 34, 56, 0.5)!];
const c = [!Color.from(alpha: 1, red: 0, green: 0, blue: 0)!];
const d = [!Color(0)!];
''');

  // 不報

  Future<void> test_themeDirectory() =>
      assertLints('lib/ui/theme/app_tokens.dart', '''
import 'package:material_ui/material_ui.dart';

const a = EdgeInsets.all(8);
const b = TextStyle(fontSize: 14);
const c = Color(0xFF123456);
const d = Colors.red;
''');

  Future<void> test_outsideUi() =>
      assertLints('lib/playback/controller.dart', '''
import 'package:material_ui/material_ui.dart';

const a = EdgeInsets.all(8);
const b = Colors.red;
''');

  Future<void> test_tokensZeroAndOtherArguments() =>
      assertLints('lib/ui/search/page.dart', '''
import 'package:material_ui/material_ui.dart';

const a = EdgeInsets.all(AppTokens.gap);
const b = EdgeInsets.all(0);
const b2 = EdgeInsets.all((0));
const c = SizedBox(width: AppTokens.gap, height: 0.0);
const d = TextStyle(height: 1.4);
const e = BorderRadius.only();
const f = Color(AppTokens.argb);
Color g(int a, int r, int gr, int b) => Color.fromARGB(a, r, gr, b);
const h = EdgeInsetsDirectional.only(start: AppTokens.gap, end: 0);
const i = Radius.circular(0);
const j = Radius.elliptical(AppTokens.gap, 0);
const k = BorderRadius.all(Radius.zero);
const l = BorderRadiusDirectional.circular(AppTokens.gap);
const m = SizedBox.fromSize(size: Size(AppTokens.gap, 0));
// Size 只在傳給 SizedBox 時才管
const n = Size(48, 48);
const o = Layout(size: Size(48, 48));
final p = Color.lerp(null, null, 0.5);
// EdgeInsets.all(8) 與 Colors.red、Radius.circular(8)
const text = 'fontSize: 14';
''');
}
