import 'dart:math' as math;

import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 鍵盤焦點的外框（`docs/design/DESIGN.md`〈無障礙〉：`:focus-visible` 2px
/// 強調色、offset 2）：[visible] 時在 [child] 外面 2 的地方畫一圈 2 寬的線，
/// 圓角是 [radius] 加上外推的距離（同 CSS outline 跟著 border-radius）。
/// 畫在 [child] 的框外，不佔版面。
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.visible,
    required this.radius,
    required this.child,
  });

  final bool visible;

  /// [child] 自己的圓角；圓形或膠囊給大於短邊一半的值（例如 999）。
  final double radius;
  final Widget child;

  /// 外框和 [child] 的距離與線寬。
  static const offset = 2.0;
  static const width = 2.0;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: visible
        ? _RingPainter(context.fmpColors.accent, radius)
        : null,
    child: child,
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // 線的中心在離框 offset + width / 2 的地方。
    const out = FocusRing.offset + FocusRing.width / 2;
    final rect = (Offset.zero & size).inflate(out);
    final r = math.min(radius + out, rect.shortestSide / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = FocusRing.width,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.radius != radius;
}
