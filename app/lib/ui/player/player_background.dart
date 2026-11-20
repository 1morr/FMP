import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/player/ambient_colors.dart';
import 'package:material_ui/material_ui.dart';

/// 播放頁的封面色場（`FMP.ambient`＋`.pl-scrim`，`docs/design/DESIGN.md`
/// 〈封面色只用在播放頁背景〉）：第一色鋪底，另兩色是三顆 60 模糊的色團，
/// 各以 24／31／37 秒緩慢漂移，再壓 28% 黑；最上面一層由上往下的暗層讓白字
/// 在淺色封面上也達 AA。換曲時色漸變過去。系統開「減少動態效果」時色團
/// 停在原位（`DESIGN.md`〈動態〉）。
class PlayerBackground extends StatefulWidget {
  const PlayerBackground({super.key, required this.colors});

  final AmbientColors colors;

  @override
  State<PlayerBackground> createState() => _PlayerBackgroundState();
}

class _PlayerBackgroundState extends State<PlayerBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);

  /// 上次停下時的秒數：動畫停了再開時從這裡接著漂。
  double _offset = 0;

  void _tick(Duration elapsed) =>
      _time.value = _offset + elapsed.inMicroseconds / 1e6;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !FmpMotion.reduced(context);
    if (animate && !_ticker.isActive) {
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _offset = _time.value;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<AmbientColors>(
        tween: _AmbientTween(end: widget.colors),
        duration: FmpMotion.mid,
        curve: FmpMotion.outCurve,
        builder: (context, colors, _) => CustomPaint(
          painter: _AmbientPainter(colors, _time),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              // `.pl-scrim`
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .3, .55, 1],
                colors: [
                  Color.fromRGBO(0, 0, 0, .26),
                  Color.fromRGBO(0, 0, 0, .1),
                  Color.fromRGBO(0, 0, 0, .2),
                  Color.fromRGBO(0, 0, 0, .5),
                ],
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _AmbientTween extends Tween<AmbientColors> {
  _AmbientTween({required AmbientColors end}) : super(end: end);

  @override
  AmbientColors lerp(double t) => AmbientColors.lerp(begin ?? end!, end!, t);
}

/// 一顆色團（`.ambient i`）：位置與大小是畫面的比例，漂移照 `@keyframes drift`。
class _Blob {
  const _Blob({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.opacity,
    required this.period,
    required this.useThird,
    this.reverse = false,
  });

  final double left, top, width, height, opacity;

  /// 一輪（0% → 100%）幾秒；`alternate` 來回。
  final double period;
  final bool useThird;

  /// `alternate-reverse`：從 100% 開始往回。
  final bool reverse;
}

// `FMP.ambient`：right、bottom 換算成 left、top。
const _blobs = [
  _Blob(
    left: -.10,
    top: -.15,
    width: .70,
    height: .75,
    opacity: .85,
    period: 24,
    useThird: false,
  ),
  _Blob(
    left: .50,
    top: .20,
    width: .65,
    height: .70,
    opacity: .55,
    period: 31,
    useThird: true,
    reverse: true,
  ),
  _Blob(
    left: .20,
    top: .65,
    width: .70,
    height: .60,
    opacity: .6,
    period: 37,
    useThird: false,
  ),
];

/// `@keyframes drift` 的三格：位移是色團自己寬高的比例。
const _frames = [(0.0, 0.0, 1.0), (.08, -.06, 1.15), (-.06, .08, .95)];

/// CSS 的 `ease-in-out`。
const _ease = Cubic(.42, 0, .58, 1);

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.colors, this.time) : super(repaint: time);

  final AmbientColors colors;
  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(bounds)
      ..drawRect(bounds, Paint()..color = colors.base);
    for (final blob in _blobs) {
      final (dx, dy, scale) = _drift(blob, time.value);
      final w = blob.width * size.width, h = blob.height * size.height;
      final center = Offset(
        blob.left * size.width + w / 2 + dx * w,
        blob.top * size.height + h / 2 + dy * h,
      );
      final color = blob.useThird ? colors.third : colors.second;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: w * scale, height: h * scale),
        Paint()
          ..color = color.withValues(alpha: blob.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
      );
    }
    canvas
      ..drawRect(bounds, Paint()..color = const Color.fromRGBO(0, 0, 0, .28))
      ..restore();
  }

  /// [seconds] 時 [blob] 的位移與縮放：每輪內分兩段，各段 ease-in-out；
  /// 單數輪倒著走。
  static (double, double, double) _drift(_Blob blob, double seconds) {
    final cycles = seconds / blob.period;
    var u = cycles - cycles.floorToDouble();
    final backwards = cycles.floor().isOdd != blob.reverse;
    if (backwards) u = 1 - u;
    final segment = u < .5 ? 0 : 1;
    final local = _ease.transform(math.min(1, (u - segment * .5) * 2));
    final a = _frames[segment], b = _frames[segment + 1];
    double mix(double x, double y) => x + (y - x) * local;
    return (mix(a.$1, b.$1), mix(a.$2, b.$2), mix(a.$3, b.$3));
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.colors != colors || old.time != time;
}
