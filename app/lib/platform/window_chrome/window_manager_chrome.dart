import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fmp/platform/window_chrome/window_chrome.dart';

/// 以 `window_manager` 實作的 [WindowChrome]（Windows）。
///
/// 標題字串不動：單一實例（`windows/runner/main.cpp`）以視窗類別加標題找第一個實例，
/// `TitleBarStyle.hidden` 只隱藏標題列，不改視窗標題。
final class WindowManagerChrome with WindowListener implements WindowChrome {
  WindowManagerChrome._(this._manager, {required bool maximized})
    : _maximized = ValueNotifier(maximized);

  /// 隱藏系統標題列並開始聽最大化的變化。`main()` 在 `runApp` 之前呼叫一次。
  ///
  /// [manager] 預設是 `window_manager` 的全域實例（測試換成假的）。
  static Future<WindowManagerChrome> init({WindowManager? manager}) async {
    final windowManager = manager ?? WindowManager.instance;
    await windowManager.ensureInitialized();
    // callback 套件不會等它跑完，所以不用它：隱藏標題列之後再顯示並取得焦點。
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(titleBarStyle: TitleBarStyle.hidden),
    );
    await windowManager.show();
    await windowManager.focus();
    final chrome = WindowManagerChrome._(
      windowManager,
      maximized: await windowManager.isMaximized(),
    );
    windowManager.addListener(chrome);
    return chrome;
  }

  final WindowManager _manager;
  final ValueNotifier<bool> _maximized;

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
