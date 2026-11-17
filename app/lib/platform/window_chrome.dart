import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 桌面視窗外框與快捷鍵的平台差異（`docs/design/DESIGN.md`〈桌面〉）；畫面不自己
/// 判斷平台（architecture〈依賴規則〉）。
abstract final class WindowChrome {
  /// macOS 的標題列透明、疊在內容上（`macos/Runner/MainFlutterWindow.swift`），
  /// 側欄與細欄頂端要讓出紅綠燈的位置。
  static bool get insetTrafficLights =>
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Windows 的視窗沒有原生標題列（`windows/runner/window_frame.cpp`），
  /// 最小化、最大化、關閉由 App 畫在視窗右上。
  static bool get captionButtons =>
      defaultTargetPlatform == TargetPlatform.windows;

  /// 標題列由 App 自己處理（macOS 透明疊在內容上、Windows 沒有）：頂列的
  /// 空白處要能拖動視窗。
  static bool get drawsTitleBar => insetTrafficLights || captionButtons;

  /// 一顆視窗鈕的大小（`docs/design/DESIGN.md`〈桌面〉）。
  static const Size captionButtonSize = Size(46, 32);

  /// 視窗鈕那一列的高度：貼著視窗頂端、在視窗鈕底下的面板（詳情面板）
  /// 從這裡以下才開始放內容。
  static double get captionButtonsHeight =>
      captionButtons ? captionButtonSize.height : 0;

  /// 頂端貼著視窗右緣的東西要讓出的寬度：三顆視窗鈕。
  static double get captionButtonsWidth =>
      captionButtons ? 3 * captionButtonSize.width : 0;

  /// 快捷鍵的修飾鍵：macOS 是 ⌘，其他平台是 Ctrl。
  static bool get _usesCommandKey =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// 修飾鍵＋[key] 的快捷鍵。
  static SingleActivator shortcut(LogicalKeyboardKey key) => _usesCommandKey
      ? SingleActivator(key, meta: true)
      : SingleActivator(key, control: true);

  /// 快捷鍵寫給人看的樣子，例如「⌘K」「Ctrl K」。
  static String shortcutLabel(String key) =>
      _usesCommandKey ? '⌘$key' : 'Ctrl $key';

  /// 快捷鍵提示裡的 Alt 與 Enter：macOS 寫符號 ⌥、⏎，其他平台寫 Alt、Enter。
  static String get altKeyLabel => _usesCommandKey ? '⌥' : 'Alt';
  static String get enterKeyLabel => _usesCommandKey ? '⏎' : 'Enter';
}
