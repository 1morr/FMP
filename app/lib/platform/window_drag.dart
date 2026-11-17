import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/platform/window_chrome.dart';

/// 拖動視窗的區域。macOS 的標題列是透明的、疊在內容上，點擊會進 Flutter，
/// 系統不會自己拖動視窗（`macos/Runner/MainFlutterWindow.swift`）；Windows
/// 沒有原生標題列（`windows/runner/window_frame.cpp`）。在這塊區域按住拖動就
/// 交給系統拖視窗，雙擊照系統慣例縮放（Windows 是最大化與還原）。手機只放
/// [child]。
///
/// 它包在內容外面，不疊在上面：裡面的按鈕先拿到點擊，點下立刻反應；只有
/// 沒有別人要的點擊（頂列的空白處）才算進雙擊。內建的雙擊辨識在第一下之後
/// 會佔住手勢競技場，底下按鈕的點擊要等雙擊逾時才算數，所以不用它。
/// [height] 不是 null 時只有離頂 [height] 以內是拖動區。
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, this.height, this.child});

  final double? height;
  final Widget? child;

  static const _channel = MethodChannel('fmp/window');

  @override
  Widget build(BuildContext context) {
    final child = this.child ?? const SizedBox.expand();
    if (!WindowChrome.drawsTitleBar) return child;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _AreaPanRecognizer:
            GestureRecognizerFactoryWithHandlers<_AreaPanRecognizer>(
              () => _AreaPanRecognizer(height),
              (recognizer) => recognizer
                ..height = height
                ..onStart = (_) => _channel.invokeMethod<void>('startDrag'),
            ),
        _UnclaimedDoubleClickRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _UnclaimedDoubleClickRecognizer
            >(
              () => _UnclaimedDoubleClickRecognizer(height),
              (recognizer) => recognizer
                ..height = height
                ..onDoubleClick = () => _channel.invokeMethod<void>('zoom'),
            ),
      },
      child: child,
    );
  }
}

bool _inArea(PointerEvent event, double? height) =>
    height == null || event.localPosition.dy < height;

/// 只在拖動區裡起手的拖動。
class _AreaPanRecognizer extends PanGestureRecognizer {
  _AreaPanRecognizer(this.height);

  double? height;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      _inArea(event, height) && super.isPointerAllowed(event);
}

/// 沒人要的兩下點擊：每一下都進競技場但不佔住它，裡面的按鈕先登記，掃場時
/// 先贏；只剩這個辨識器時它才贏，那一下才算數。兩下都算數、間隔不超過
/// [kDoubleTapTimeout]、位置差不超過 [kDoubleTapSlop] 就是雙擊。中間有一下被
/// 別人拿走，就重新算。
class _UnclaimedDoubleClickRecognizer extends GestureRecognizer {
  _UnclaimedDoubleClickRecognizer(this.height);

  double? height;
  VoidCallback? onDoubleClick;

  final _clicks = <int, _Click>{};

  /// 上一下算數的點擊；等第二下。
  _Click? _first;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _inArea(event, height) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final click = _Click(event.timeStamp, event.position);
    _clicks[event.pointer] = click;
    GestureBinding.instance.pointerRouter.addRoute(event.pointer, _handle);
    click.entry = GestureBinding.instance.gestureArena.add(event.pointer, this);
  }

  void _handle(PointerEvent event) {
    final click = _clicks[event.pointer];
    if (click == null) return;
    if (event is PointerMoveEvent &&
        (event.position - click.down).distance > kDoubleTapSlop) {
      click.entry?.resolve(GestureDisposition.rejected);
    } else if (event is PointerUpEvent) {
      click.up = event.timeStamp;
      _stopRoute(event.pointer);
      _settle(event.pointer);
    } else if (event is PointerCancelEvent) {
      click.entry?.resolve(GestureDisposition.rejected);
    }
  }

  @override
  void acceptGesture(int pointer) {
    _clicks[pointer]?.accepted = true;
    _settle(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _stopRoute(pointer);
    _clicks.remove(pointer);
    _first = null;
  }

  /// 贏了而且放開了，這一下才算數。
  void _settle(int pointer) {
    final click = _clicks[pointer];
    if (click == null || !click.accepted || click.up == null) return;
    _clicks.remove(pointer);
    final first = _first;
    if (first != null &&
        click.downTime - first.up! <= kDoubleTapTimeout &&
        (click.down - first.down).distance <= kDoubleTapSlop) {
      _first = null;
      invokeCallback<void>('onDoubleClick', () => onDoubleClick?.call());
    } else {
      _first = click;
    }
  }

  void _stopRoute(int pointer) {
    final click = _clicks[pointer];
    if (click == null || !click.routed) return;
    click.routed = false;
    GestureBinding.instance.pointerRouter.removeRoute(pointer, _handle);
  }

  @override
  void dispose() {
    for (final pointer in [..._clicks.keys]) {
      _stopRoute(pointer);
    }
    _clicks.clear();
    super.dispose();
  }

  @override
  String get debugDescription => 'unclaimed double click';
}

class _Click {
  _Click(this.downTime, this.down);

  final Duration downTime;
  final Offset down;
  GestureArenaEntry? entry;
  bool routed = true;
  Duration? up;
  bool accepted = false;
}
