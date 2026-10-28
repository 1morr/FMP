import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/window_chrome/window_chrome.dart';
import 'package:fmp/platform/window_chrome/window_manager_chrome.dart';
import 'package:window_manager/window_manager.dart';

// U PR 15：`WindowManagerChrome` 把 `WindowChrome` 的動作轉給 `window_manager`。真的標題列隱藏、拖曳
// 只能在 Windows 實機驗；這裡核對呼叫順序與最大化狀態。

void main() {
  // 不 show、不 focus：視窗由 runner 在第一個畫面出來時顯示（runApp 之前顯示會先露出空白視窗）。
  test(
    'init hides the title bar and leaves showing the window to the runner',
    () async {
      final manager = _FakeManager();

      await WindowManagerChrome.init(manager: manager);

      expect(manager.calls, [
        'ensureInitialized',
        'waitUntilReadyToShow hidden',
        'isMaximized',
      ]);
      expect(manager.addedListeners, hasLength(1));
    },
  );

  test('Windows draws its buttons at the default height', () async {
    final chrome = await WindowManagerChrome.init(manager: _FakeManager());

    expect(chrome.captionButtons, CaptionButtons.drawn);
    expect(chrome.titleBarHeight, isNull);
  });

  // macOS（ADR 0036 §決定 6）：隱藏之前先量系統標題區（隱藏之後內容延伸到頂端，量到 0）。
  test('macOS measures the system title bar before hiding it', () async {
    final manager = _FakeManager()..systemTitleBarHeight = 32;

    final chrome = await WindowManagerChrome.init(
      manager: manager,
      captionButtons: CaptionButtons.systemLeading,
    );

    expect(manager.calls, [
      'ensureInitialized',
      'getTitleBarHeight',
      'waitUntilReadyToShow hidden',
      'isMaximized',
    ]);
    expect(chrome.captionButtons, CaptionButtons.systemLeading);
    expect(chrome.titleBarHeight, 32);
  });

  test('a zero measurement falls back to the default height', () async {
    final manager = _FakeManager()..systemTitleBarHeight = 0;

    final chrome = await WindowManagerChrome.init(
      manager: manager,
      captionButtons: CaptionButtons.systemLeading,
    );

    expect(chrome.titleBarHeight, isNull);
  });

  test('maximized starts from the window and follows its events', () async {
    final manager = _FakeManager()..isMaximizedNow = true;
    final chrome = await WindowManagerChrome.init(manager: manager);
    expect(chrome.maximized.value, isTrue);

    manager.addedListeners.single.onWindowUnmaximize();
    expect(chrome.maximized.value, isFalse);
    manager.addedListeners.single.onWindowMaximize();
    expect(chrome.maximized.value, isTrue);
  });

  test(
    'toggleMaximize restores a maximized window and maximizes otherwise',
    () async {
      final manager = _FakeManager();
      final chrome = await WindowManagerChrome.init(manager: manager);
      manager.calls.clear();

      await chrome.toggleMaximize();
      manager.isMaximizedNow = true;
      await chrome.toggleMaximize();

      expect(manager.calls, [
        'isMaximized',
        'maximize',
        'isMaximized',
        'unmaximize',
      ]);
    },
  );

  test('minimize, close and startDragging go straight through', () async {
    final manager = _FakeManager();
    final chrome = await WindowManagerChrome.init(manager: manager);
    manager.calls.clear();

    await chrome.minimize();
    await chrome.close();
    await chrome.startDragging();

    expect(manager.calls, ['minimize', 'close', 'startDragging']);
  });
}

/// 只做這個實作用到的幾個方法；其他呼叫是測試寫錯了，`noSuchMethod` 會直接拋錯。
final class _FakeManager implements WindowManager {
  final calls = <String>[];
  final addedListeners = <WindowListener>[];
  var isMaximizedNow = false;
  var systemTitleBarHeight = 28;

  @override
  Future<int> getTitleBarHeight() async {
    calls.add('getTitleBarHeight');
    return systemTitleBarHeight;
  }

  @override
  Future<void> ensureInitialized() async => calls.add('ensureInitialized');

  @override
  Future<void> waitUntilReadyToShow([
    WindowOptions? options,
    VoidCallback? callback,
  ]) async {
    calls.add('waitUntilReadyToShow ${options?.titleBarStyle?.name}');
  }

  @override
  Future<bool> isMaximized() async {
    calls.add('isMaximized');
    return isMaximizedNow;
  }

  @override
  void addListener(WindowListener listener) => addedListeners.add(listener);

  @override
  Future<void> maximize({bool vertically = false}) async =>
      calls.add('maximize');

  @override
  Future<void> unmaximize() async => calls.add('unmaximize');

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> startDragging() async => calls.add('startDragging');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
