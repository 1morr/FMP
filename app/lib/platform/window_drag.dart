import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/platform/window_chrome.dart';

/// 拖動視窗的區域。macOS 的標題列是透明的、疊在內容上，點擊會進 Flutter，
/// 系統不會自己拖動視窗（`macos/Runner/MainFlutterWindow.swift`）；Windows
/// 沒有原生標題列（`windows/runner/window_frame.cpp`）。在這塊區域按住拖動就
/// 交給系統拖視窗，雙擊照系統慣例縮放（Windows 是最大化與還原）。手機只放
/// [child]。
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, this.child});

  final Widget? child;

  static const _channel = MethodChannel('fmp/window');

  @override
  Widget build(BuildContext context) {
    if (!WindowChrome.drawsTitleBar) {
      return child ?? const SizedBox.expand();
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _channel.invokeMethod<void>('startDrag'),
      onDoubleTap: () => _channel.invokeMethod<void>('zoom'),
      child: child ?? const SizedBox.expand(),
    );
  }
}
