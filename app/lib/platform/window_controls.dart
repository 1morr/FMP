import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Windows 自繪視窗鈕要的視窗狀態（`docs/design/DESIGN.md`〈桌面〉）。
@immutable
class WindowState {
  const WindowState({
    this.maximized = false,
    this.maximizeHovered = false,
    this.maximizePressed = false,
  });

  final bool maximized;

  /// 滑鼠停在最大化鈕上、按著它：由 Windows 回報。最大化鈕那一塊是
  /// Windows 的（它才能在上面開 Snap Layouts，事實 W12），Flutter 收不到
  /// 那裡的滑鼠事件。
  final bool maximizeHovered;
  final bool maximizePressed;

  WindowState copyWith({
    bool? maximized,
    bool? maximizeHovered,
    bool? maximizePressed,
  }) => WindowState(
    maximized: maximized ?? this.maximized,
    maximizeHovered: maximizeHovered ?? this.maximizeHovered,
    maximizePressed: maximizePressed ?? this.maximizePressed,
  );

  @override
  bool operator ==(Object other) =>
      other is WindowState &&
      other.maximized == maximized &&
      other.maximizeHovered == maximizeHovered &&
      other.maximizePressed == maximizePressed;

  @override
  int get hashCode => Object.hash(maximized, maximizeHovered, maximizePressed);
}

/// 視窗的最小化、最大化、關閉與狀態，經 `fmp/window` 頻道和原生端
/// （`windows/runner/window_frame.cpp`）來回。只在自己畫視窗鈕的平台讀
/// （`WindowChrome.captionButtons`）。
final windowControlsProvider = NotifierProvider<WindowControls, WindowState>(
  WindowControls.new,
);

class WindowControls extends Notifier<WindowState> {
  static const _channel = MethodChannel('fmp/window');

  @override
  WindowState build() {
    _channel.setMethodCallHandler(_fromNative);
    ref.onDispose(() => _channel.setMethodCallHandler(null));
    // 熱重啟時視窗可能已經是最大化的，先問一次；之後由原生端推。
    _channel.invokeMethod<bool>('isMaximized').then((value) {
      if (ref.mounted && value != null) {
        state = state.copyWith(maximized: value);
      }
    });
    return const WindowState();
  }

  Future<void> _fromNative(MethodCall call) async {
    switch (call.method) {
      case 'maximized':
        state = state.copyWith(maximized: call.arguments as bool);
      case 'maximizeButton':
        final args = call.arguments as Map<Object?, Object?>;
        state = state.copyWith(
          maximizeHovered: args['hovered'] as bool,
          maximizePressed: args['pressed'] as bool,
        );
    }
  }

  void minimize() => _channel.invokeMethod<void>('minimize');

  /// 最大化或還原。
  void toggleMaximize() => _channel.invokeMethod<void>('zoom');

  /// 和按系統的關閉一樣，會經過 App 的結束流程（事實 W11）。
  void close() => _channel.invokeMethod<void>('close');

  /// 告訴原生端最大化鈕在哪：量的是離視窗右上角的距離（[right] 是鈕的右緣
  /// 離視窗右緣多遠、[top] 是上緣離頂端多遠，[size] 是鈕的大小），單位是
  /// 邏輯像素，視窗改變大小時不用重報。
  void reportMaximizeButton({
    required double right,
    required double top,
    required Size size,
  }) => _channel.invokeMethod<void>('setMaximizeButtonRect', {
    'right': right,
    'top': top,
    'width': size.width,
    'height': size.height,
  });
}
