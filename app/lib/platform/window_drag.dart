import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 拖動視窗的區域。macOS 的標題列是透明的、疊在內容上，點擊會進 Flutter，
/// 系統不會自己拖動視窗（`macos/Runner/MainFlutterWindow.swift`）；在這塊區域
/// 按住拖動就交給系統拖視窗，雙擊照系統慣例縮放。其他平台有原生標題列，
/// 只放 [child]。
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, this.child});

  final Widget? child;

  static const _channel = MethodChannel('fmp/window');

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
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
