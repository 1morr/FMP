import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 書脊式進度（`docs/design/DESIGN.md`〈手機〉）：膠囊本身就是進度條。
/// 已播放的部分 [progress]（0–1）疊一層 15% 的玻璃字色，交界是 2 寬的強調色
/// 折線，只露出上下各 11，不切過文字。放在玻璃裡、內容底下。
class Spine extends StatelessWidget {
  const Spine({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        key: const Key('spine-played'),
        widthFactor: progress.clamp(0, 1),
        heightFactor: 1,
        child: CustomPaint(
          painter: _CreasePainter(
            fill: colors.glassInk.withValues(alpha: .15),
            crease: colors.accent,
          ),
        ),
      ),
    );
  }
}

class _CreasePainter extends CustomPainter {
  _CreasePainter({required this.fill, required this.crease});

  final Color fill;
  final Color crease;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    // `.played::after`：right -1、寬 2，遮罩只留上下各 11。
    final paint = Paint()..color = crease;
    final x = size.width - 1;
    canvas
      ..drawRect(Rect.fromLTWH(x, 0, 2, 11), paint)
      ..drawRect(Rect.fromLTWH(x, size.height - 11, 2, 11), paint);
  }

  @override
  bool shouldRepaint(_CreasePainter old) =>
      old.fill != fill || old.crease != crease;
}

/// [position] 佔 [duration] 的比例；長度不知道或是 0 時是 0。
double spineProgress(Duration position, Duration? duration) {
  if (duration == null || duration <= Duration.zero) return 0;
  return position.inMicroseconds / duration.inMicroseconds;
}
