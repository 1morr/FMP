import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/platform/window_chrome.dart';

/// macOS 紅綠燈的燈位。包住側欄或細欄頂端讓出來的那一列，量出它在視窗裡的框，
/// 經 `fmp/window` 的 `setTrafficLights` 告訴原生端
/// （`macos/Runner/MainFlutterWindow.swift`）：第一顆按鈕的左上角照稿放在離這一列
/// 左上 [spot] 的地方；原生按鈕比稿上的燈大，照稿會超出這一列時，原生端改成在
/// `minX`…`maxX` 裡置中（事實 M13）。版面是哪一級由 Dart 決定，原生端不重抄斷點。
/// 其他平台只放 [child]。
class TrafficLightsArea extends StatefulWidget {
  const TrafficLightsArea({super.key, required this.spot, required this.child});

  final Offset spot;
  final Widget child;

  @override
  State<TrafficLightsArea> createState() => _TrafficLightsAreaState();
}

class _TrafficLightsAreaState extends State<TrafficLightsArea> {
  static const _channel = MethodChannel('fmp/window');

  /// 上一次送出的燈位；沒變就不再送。
  Map<String, double>? _sent;

  @override
  Widget build(BuildContext context) {
    if (WindowChrome.insetTrafficLights) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
    return widget.child;
  }

  void _report() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final spot = {
      'x': topLeft.dx + widget.spot.dx,
      'y': topLeft.dy + widget.spot.dy,
      'minX': topLeft.dx,
      'maxX': topLeft.dx + box.size.width,
    };
    if (mapEquals(spot, _sent)) return;
    _sent = spot;
    _channel.invokeMethod<void>('setTrafficLights', spot);
  }
}
