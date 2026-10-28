import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 視窗鈕（最小化、最大化、關閉）由誰畫。
enum CaptionButtons {
  /// App 在標題列右邊畫三顆鈕（Windows）。
  drawn,

  /// 系統的紅綠燈留在標題列左邊（macOS，ADR 0036 §決定 6）：App 不畫鈕，「FMP」置中。
  systemLeading,
}

/// 自繪標題列要的視窗動作（ADR 0035 §決定 6）。系統標題列已隱藏，標題列的鈕與拖曳區自己
/// 呼叫這些動作。實作是 `window_manager_chrome.dart`（Windows、macOS），由 `platform.dart` 組裝。
abstract interface class WindowChrome {
  /// 視窗鈕由 App 畫還是系統畫；標題列依它排版，UI 不判斷平台。
  CaptionButtons get captionButtons;

  /// 標題列的高度（邏輯像素）；`null` 是 App 的預設（`AppLayout.titleBarHeight`，36）。
  ///
  /// macOS 是系統標題區的高度（macOS 27 是 32）：紅綠燈由系統放在那一段的正中間，App 的標題列
  /// 和它一樣高，紅綠燈就在列的正中間，不必用原生碼移動它們（AppKit 每次重排標題區都會放回原位）。
  double? get titleBarHeight;

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
