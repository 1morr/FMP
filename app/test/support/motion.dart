import 'package:flutter_test/flutter_test.dart';

/// 系統開「減少動態效果」：經 platformDispatcher 的 accessibilityFeatures 設
/// （不是只包一層 MediaQuery），預設的 AnimationController 會像在手機上一樣把
/// 時長縮成 5%（事實 K35），測得到「直接跳過」。測試結束時還原。
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}
