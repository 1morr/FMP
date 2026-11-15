import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 桌面視窗外框與快捷鍵的平台差異（`docs/design/DESIGN.md`〈桌面〉）；畫面不自己
/// 判斷平台（architecture〈依賴規則〉）。
abstract final class WindowChrome {
  /// macOS 的標題列透明、疊在內容上（`macos/Runner/MainFlutterWindow.swift`），
  /// 側欄與細欄頂端要讓出紅綠燈的位置。Windows 用原生標題列，不用讓。
  static bool get insetTrafficLights =>
      defaultTargetPlatform == TargetPlatform.macOS;

  /// 快捷鍵的修飾鍵：macOS 是 ⌘，其他平台是 Ctrl。
  static bool get usesCommandKey =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// 修飾鍵＋[key] 的快捷鍵。
  static SingleActivator shortcut(LogicalKeyboardKey key) => usesCommandKey
      ? SingleActivator(key, meta: true)
      : SingleActivator(key, control: true);

  /// 快捷鍵寫給人看的樣子，例如「⌘K」「Ctrl K」。
  static String shortcutLabel(String key) =>
      usesCommandKey ? '⌘$key' : 'Ctrl $key';
}
