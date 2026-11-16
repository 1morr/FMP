import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/window_chrome.dart';

/// 視窗外框的平台差異（`docs/design/DESIGN.md`〈桌面〉的 Windows 那一點）：
/// 只有 Windows 自己畫視窗鈕，頂列右端讓出三顆鈕的寬度 138。
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Windows draws its own caption buttons and gives up 138 at the top '
      'right', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(WindowChrome.captionButtons, isTrue);
    expect(WindowChrome.captionButtonsWidth, 138);
  });

  test('other platforms draw none and give up nothing', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(WindowChrome.captionButtons, isFalse, reason: '$platform');
      expect(WindowChrome.captionButtonsWidth, 0, reason: '$platform');
    }
  });
}
