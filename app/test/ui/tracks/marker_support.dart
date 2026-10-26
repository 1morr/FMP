import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/tracks/now_playing_overlay.dart';
import 'package:material_ui/material_ui.dart';

// 「正在播放」標示的測試輔助（曲目清單共用，ADR 0035 B-01、B-34）。

/// 在播的指示器會一直動，`pumpAndSettle` 等不到停：先要求系統減少動態（測試結束還原）。
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// [row] 底下的在播遮罩。
Finder overlayIn(Finder row) => find.descendant(
  of: row,
  matching: find.byKey(NowPlayingOverlay.overlayKey),
);

/// [title]（一個 `Text`）是不是在播的樣子：主色、粗體。
bool isPlayingTitle(WidgetTester tester, Finder title) {
  final text = tester.widget<Text>(title);
  final scheme = Theme.of(tester.element(title)).colorScheme;
  return text.style?.fontWeight == FontWeight.bold &&
      text.style?.color == scheme.primary;
}
