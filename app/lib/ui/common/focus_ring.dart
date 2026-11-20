import 'dart:math' as math;

import 'package:fmp/app/theme/theme.dart';
import 'package:flutter/services.dart';
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
    this.inset = false,
  });

  final bool visible;

  /// 畫在 [child] 的框裡面、離邊 2：滿版的列表列（左右貼著畫面邊緣，畫在
  /// 外面會被裁掉、上下壓到隔壁列）用。
  final bool inset;

  /// [child] 自己的圓角；圓形或膠囊給大於短邊一半的值（例如 999）。
  final double radius;
  final Widget child;

  /// 外框和 [child] 的距離與線寬。
  static const offset = 2.0;
  static const width = 2.0;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: visible
        ? _RingPainter(context.fmpColors.accent, radius, inset)
        : null,
    child: child,
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.radius, this.inset);

  final Color color;
  final double radius;
  final bool inset;

  @override
  void paint(Canvas canvas, Size size) {
    // 線的中心在離框 offset + width / 2 的地方（[inset] 時往裡）。
    final out = (FocusRing.offset + FocusRing.width / 2) * (inset ? -1 : 1);
    final rect = (Offset.zero & size).inflate(out);
    final r = math.max(0.0, math.min(radius + out, rect.shortestSide / 2));
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
      old.color != color || old.radius != radius || old.inset != inset;
}

/// 鍵盤選到的按鈕的快捷鍵：Space 在 App 裡是播放／暫停（`PlaybackShortcuts`），
/// 不再同時按下按鈕，按鈕用 Enter 按。對話框與選單裡 Space 不是播放鍵，照
/// 框架預設按下按鈕。給 `FocusableActionDetector.shortcuts` 用。
Map<ShortcutActivator, Intent>? buttonShortcuts(BuildContext context) =>
    ModalRoute.of(context) is PopupRoute
    ? null
    : const {
        SingleActivator(LogicalKeyboardKey.space):
            DoNothingAndStopPropagationIntent(),
      };
