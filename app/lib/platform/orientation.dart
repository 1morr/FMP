import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/platform/form_factor.dart';

/// 手機固定直向，平板可以轉（`docs/design/DESIGN.md`〈待確認〉第 27 條）。iPhone 由
/// `ios/Runner/Info.plist` 只列直向；Android 的 manifest 分不出手機與平板，
/// 所以啟動時看螢幕短邊：觸控裝置短邊不到中寬度的下限（600）就鎖直向。
Future<void> lockPhoneToPortrait() async {
  if (Density.current != Density.touch) return;
  final display = WidgetsBinding.instance.platformDispatcher.displays.first;
  final shortest = display.size.shortestSide / display.devicePixelRatio;
  if (shortest < WidthClass.mediumFrom) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
}
