import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fmp/platform/window_chrome/window_chrome.dart';

/// 以 `window_manager` 實作的 [WindowChrome]（Windows、macOS）。
///
/// - Windows：App 畫三顆視窗鈕（[CaptionButtons.drawn]）。標題字串不動：單一實例
///   （`windows/runner/main.cpp`）以視窗類別加標題找第一個實例，`TitleBarStyle.hidden` 只隱藏
///   標題列，不改視窗標題。
/// - macOS：`TitleBarStyle.hidden` 隱藏標題文字、保留紅綠燈（[CaptionButtons.systemLeading]，
///   ADR 0036 §決定 6）。標題列和系統的標題區一樣高（[titleBarHeight]），紅綠燈就在列的正中間。
final class WindowManagerChrome with WindowListener implements WindowChrome {
  WindowManagerChrome._(
    this._manager, {
    required bool maximized,
    required this.captionButtons,
    required this.titleBarHeight,
  }) : _maximized = ValueNotifier(maximized);

  /// 隱藏系統標題列並開始聽最大化的變化。`main()` 在 `runApp` 之前呼叫一次。
  ///
  /// [manager] 預設是 `window_manager` 的全域實例（測試換成假的）。[captionButtons] 是平台的
  /// 視窗鈕畫法：Windows 是預設的 [CaptionButtons.drawn]，macOS 是 [CaptionButtons.systemLeading]，
  /// 後者在隱藏標題列之前先量系統標題區的高度（隱藏之後內容延伸到頂端，量不到）。
  static Future<WindowManagerChrome> init({
    WindowManager? manager,
    CaptionButtons captionButtons = CaptionButtons.drawn,
  }) async {
    final windowManager = manager ?? WindowManager.instance;
    await windowManager.ensureInitialized();
    double? titleBarHeight;
    if (captionButtons == CaptionButtons.systemLeading) {
      final systemHeight = await windowManager.getTitleBarHeight();
      if (systemHeight > 0) titleBarHeight = systemHeight.toDouble();
    }
    // 只隱藏標題列，不 show／focus：這時還沒有 runApp，視窗也還沒顯示；runner 在第一個畫面
    // 出來時才顯示並啟用它（`windows/runner/flutter_window.cpp` 的 `SetNextFrameCallback`）。
    // 在這裡 show 會先露出一個沒有內容的視窗，第一個畫面出來時 runner 再顯示一次。
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(titleBarStyle: TitleBarStyle.hidden),
    );
    final chrome = WindowManagerChrome._(
      windowManager,
      maximized: await windowManager.isMaximized(),
      captionButtons: captionButtons,
      titleBarHeight: titleBarHeight,
    );
    windowManager.addListener(chrome);
    return chrome;
  }

  final WindowManager _manager;
  final ValueNotifier<bool> _maximized;

  @override
  final CaptionButtons captionButtons;

  @override
  final double? titleBarHeight;

  @override
  ValueListenable<bool> get maximized => _maximized;

  @override
  void onWindowMaximize() => _maximized.value = true;

  @override
  void onWindowUnmaximize() => _maximized.value = false;

  @override
  Future<void> minimize() => _manager.minimize();

  @override
  Future<void> toggleMaximize() async {
    if (await _manager.isMaximized()) {
      await _manager.unmaximize();
    } else {
      await _manager.maximize();
    }
  }

  @override
  Future<void> close() => _manager.close();

  @override
  Future<void> startDragging() => _manager.startDragging();
}
