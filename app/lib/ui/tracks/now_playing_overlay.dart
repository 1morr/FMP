import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 在封面上標出「正在播放」的那一列（ADR 0035 §決定 1，舊版 `NowPlayingCoverOverlay`）：
/// 主色 80% 的遮罩加 onPrimary 的動態指示器，指示器是封面邊長的 0.32。
/// 暫停或系統要求減少動態時指示器不動。佇列、歷史與其他曲目清單共用。
///
/// 放在封面（[ArtworkImage]）上方，用 `Stack` 疊上去；[size] 與封面同邊長。
class NowPlayingOverlay extends ConsumerWidget {
  const NowPlayingOverlay({super.key, required this.size});

  /// 封面的邊長（dp）。
  final double size;

  /// 測試以它找遮罩。
  static const overlayKey = ValueKey('now-playing-overlay');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value is Playing),
    );
    final animate = playing && !MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.of(context).radius.small),
        child: ColoredBox(
          key: overlayKey,
          color: scheme.primary.withValues(alpha: AppLayout.nowPlayingScrim),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: _PlayingBars(
                size: size * AppLayout.nowPlayingIndicatorRatio,
                color: scheme.onPrimary,
                animate: animate,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 三根跳動的長條（舊版 `NowPlayingIndicator`：從左到右依次波動）。
class _PlayingBars extends StatefulWidget {
  const _PlayingBars({
    required this.size,
    required this.color,
    required this.animate,
  });

  final double size;
  final Color color;
  final bool animate;

  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: AppLayout.nowPlayingLoop,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(_PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _BarsPainter(progress: _controller, color: widget.color),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.progress, required this.color})
    : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  static const _bars = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final barWidth = side * 0.18;
    final gap = side * 0.08;
    final maxHeight = side * 0.7;
    final total = _bars * barWidth + (_bars - 1) * gap;
    final left = (size.width - total) / 2;
    final bottom = (size.height + maxHeight) / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < _bars; i++) {
      // 相位依序延後，波從左傳到右；基礎高度 0.5，波動幅度 0.4。
      final phase = (progress.value - i * 0.2) % 1.0;
      final wave = (1 + math.sin(phase * 2 * math.pi)) / 2;
      final height = maxHeight * (0.5 + 0.4 * wave);
      final x = left + i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bottom - height, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) => oldDelegate.color != color;
}
