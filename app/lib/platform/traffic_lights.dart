import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/platform/window_chrome.dart';

/// macOS 紅綠燈燈位的提供方，掛在 App 的根（`buildRoot`）。底下的
/// [TrafficLightsArea] 向它登記；每一幀結束時，有看得到的燈位就經 `fmp/window`
/// 的 `setTrafficLights` 送它的位置，一個都沒有（沒有側欄或細欄的畫面、被不透明
/// 的頁蓋住）就送 null，原生端（`macos/Runner/MainFlutterWindow.swift`）把紅綠燈
/// 放回系統原位，畫面不必各自記得送。同一幀裡側欄換成細欄不會先送 null。
/// 版面是哪一級由 Dart 決定，原生端不重抄斷點。其他平台只放 [child]。
class TrafficLights extends StatefulWidget {
  const TrafficLights({super.key, required this.child});

  final Widget child;

  @override
  State<TrafficLights> createState() => _TrafficLightsState();
}

class _TrafficLightsState extends State<TrafficLights> {
  static const _channel = MethodChannel('fmp/window');
  static const _unsent = Object();

  final _areas = <_TrafficLightsAreaState>{};
  bool _scheduled = false;

  /// 上一次送出的燈位（null 是沒有燈位）；沒變就不再送。
  Object? _sent = _unsent;

  @override
  void initState() {
    super.initState();
    _changed();
  }

  /// 燈位可能變了：這一幀排版完再量。
  void _changed() {
    if (!WindowChrome.insetTrafficLights || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _report())
      ..ensureVisualUpdate();
  }

  void _report() {
    _scheduled = false;
    if (!mounted) return;
    final spot = _areas.map((area) => area._measure()).nonNulls.firstOrNull;
    if (_sent != _unsent && mapEquals(spot, _sent as Map<String, double>?)) {
      return;
    }
    _sent = spot;
    _channel.invokeMethod<void>('setTrafficLights', spot);
  }

  @override
  Widget build(BuildContext context) =>
      _TrafficLightsScope(state: this, child: widget.child);
}

class _TrafficLightsScope extends InheritedWidget {
  const _TrafficLightsScope({required this.state, required super.child});

  final _TrafficLightsState state;

  @override
  bool updateShouldNotify(_TrafficLightsScope oldWidget) => false;
}

/// 側欄或細欄頂端讓給紅綠燈的那一列。量出它在視窗裡的框交給 [TrafficLights]：
/// 第一顆按鈕的左上角照稿放在離這一列左上 [spot] 的地方；原生按鈕比稿上的燈大，
/// 照稿會超出這一列時，原生端改成在 `minX`…`maxX` 裡置中（事實 M13）。
class TrafficLightsArea extends StatefulWidget {
  const TrafficLightsArea({super.key, required this.spot, required this.child});

  final Offset spot;
  final Widget child;

  @override
  State<TrafficLightsArea> createState() => _TrafficLightsAreaState();
}

class _TrafficLightsAreaState extends State<TrafficLightsArea> {
  _TrafficLightsState? _lights;

  @override
  Widget build(BuildContext context) {
    _lights = context
        .getInheritedWidgetOfExactType<_TrafficLightsScope>()
        ?.state;
    // 被不透明的頁蓋住時 Overlay 把它的 TickerMode 關掉，當作看不到。
    if (TickerMode.valuesOf(context).enabled) {
      _lights?._areas.add(this);
    } else {
      _lights?._areas.remove(this);
    }
    _lights?._changed();
    return widget.child;
  }

  @override
  void dispose() {
    _lights?._areas.remove(this);
    _lights?._changed();
    super.dispose();
  }

  Map<String, double>? _measure() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return {
      'x': topLeft.dx + widget.spot.dx,
      'y': topLeft.dy + widget.spot.dy,
      'minX': topLeft.dx,
      'maxX': topLeft.dx + box.size.width,
    };
  }
}
