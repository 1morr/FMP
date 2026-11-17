import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 正在播放的等化器（`.eq`）：三條 3 寬的條，[playing] 時各自跳動（高 4–12，
/// 一輪 900ms，錯開 300ms）；停住或系統要求減少動態時固定高 8。
class Equalizer extends StatefulWidget {
  const Equalizer({super.key, required this.playing, required this.label});

  final bool playing;

  /// 給螢幕閱讀器的名字。
  final String label;

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _sync(reduceMotion: false);
  }

  void _sync({required bool reduceMotion}) {
    if (widget.playing && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(reduceMotion: MediaQuery.disableAnimationsOf(context));
  }

  @override
  void didUpdateWidget(Equalizer old) {
    super.didUpdateWidget(old);
    _sync(reduceMotion: MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0..1 的相位換成 4..12：0 與 1 在 4，0.5 在 12，ease-in-out。
  static double _height(double phase) {
    final p = phase - phase.floorToDouble();
    final t = p < .5 ? p * 2 : (1 - p) * 2;
    return 4 + 8 * Curves.easeInOut.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final color = context.fmpColors.accent;
    final animating =
        widget.playing && !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: widget.label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 13,
          height: 12,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Container(
                    width: 3,
                    height: animating ? _height(_controller.value - i / 3) : 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
