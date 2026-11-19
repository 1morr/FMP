import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 書脊式進度（`docs/design/DESIGN.md`〈手機〉）：膠囊本身就是進度條。
/// 已播放的部分 [progress]（0–1）疊一層 15% 的玻璃字色，交界是 2 寬的強調色
/// 折線，只露出上下各 11，不切過文字。放在玻璃裡、內容底下。
///
/// 桌面的播放膠囊可以改進度：滑鼠移到空白處時 [hovered] 讓折線加粗到 3，
/// [hint] 是滑鼠位置（0–1），在那裡畫一條淡刻線（同折線只露上下各 11）。
class Spine extends StatelessWidget {
  const Spine({
    super.key,
    required this.progress,
    this.hovered = false,
    this.hint,
  });

  final double progress;
  final bool hovered;
  final double? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final played = Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        key: const Key('spine-played'),
        widthFactor: progress.clamp(0, 1),
        heightFactor: 1,
        child: CustomPaint(
          painter: _CreasePainter(
            fill: colors.glassInk.withValues(alpha: .15),
            crease: colors.accent,
            width: hovered ? 3 : 2,
          ),
        ),
      ),
    );
    final hint = this.hint;
    if (hint == null) return played;
    return Stack(
      fit: StackFit.expand,
      children: [
        played,
        CustomPaint(
          key: const Key('spine-hint'),
          painter: _HintPainter(hint, colors.accent.withValues(alpha: .45)),
        ),
      ],
    );
  }
}

class _CreasePainter extends CustomPainter {
  _CreasePainter({
    required this.fill,
    required this.crease,
    required this.width,
  });

  final Color fill;
  final Color crease;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    // `.played::after`：right -1、寬 2，遮罩只留上下各 11。
    _drawCrease(canvas, size, size.width - width / 2, width, crease);
  }

  @override
  bool shouldRepaint(_CreasePainter old) =>
      old.fill != fill || old.crease != crease || old.width != width;
}

/// 滑鼠位置的淡刻線。
class _HintPainter extends CustomPainter {
  _HintPainter(this.at, this.color);

  final double at;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      _drawCrease(canvas, size, size.width * at.clamp(0, 1) - 1, 2, color);

  @override
  bool shouldRepaint(_HintPainter old) => old.at != at || old.color != color;
}

void _drawCrease(Canvas canvas, Size size, double x, double w, Color color) {
  final paint = Paint()..color = color;
  canvas
    ..drawRect(Rect.fromLTWH(x, 0, w, 11), paint)
    ..drawRect(Rect.fromLTWH(x, size.height - 11, w, 11), paint);
}

/// [position] 佔 [duration] 的比例；長度不知道或是 0 時是 0。
double spineProgress(Duration position, Duration? duration) {
  if (duration == null || duration <= Duration.zero) return 0;
  return position.inMicroseconds / duration.inMicroseconds;
}
