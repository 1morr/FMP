import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 自繪標題列要的視窗動作（ADR 0035 §決定 6）。系統標題列已隱藏，標題列的三顆鈕與拖曳
/// 區自己呼叫這些動作。實作只有 Windows（`window_manager_chrome.dart`），由 `platform.dart`
/// 組裝；Mac 的自繪列由 macOS 平台任務接上。
abstract interface class WindowChrome {
  /// 視窗目前是不是最大化（最大化鈕的圖示與提示跟著變）。
  ValueListenable<bool> get maximized;

  Future<void> minimize();

  /// 最大化中就還原，否則最大化（雙擊標題列、最大化鈕）。
  Future<void> toggleMaximize();

  Future<void> close();

  /// 開始以滑鼠拖曳視窗（標題列與播放頁頂端的空白處按下並移動時）。
  Future<void> startDragging();
}

/// 平台的視窗動作；平台沒有自繪標題列（`PlatformCapabilities.customTitleBar` 為假）時為
/// `null`。`main()` 以 `AppPlatform.windowChrome` override；沒 override 就讀會拋錯。
final windowChromeProvider = Provider<WindowChrome?>(
  (ref) => throw UnimplementedError(
    'windowChromeProvider is overridden by main() with the platform '
    'implementation',
  ),
);
