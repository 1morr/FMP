import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/platform/form_factor.dart';

/// 手機固定直向，平板可以轉（brief〈介面〉的寬度分級）。iPhone 由
/// `ios/Runner/Info.plist` 只列直向；Android 的 manifest 沒設方向，在這裡看
/// 螢幕短邊：觸控裝置短邊不到中寬度的下限（600）就鎖直向。
Future<void> lockPhoneToPortrait() async {
  if (Density.current != Density.touch) return;
  final display = WidgetsBinding.instance.platformDispatcher.displays.first;
  final shortest = display.size.shortestSide / display.devicePixelRatio;
  if (shortest < WidthClass.mediumFrom) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
}
