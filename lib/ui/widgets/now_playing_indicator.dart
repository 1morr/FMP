import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/ui_constants.dart';

/// 正在播放指示器 - 显示动态音频波形动画（从左到右依次波动）
class NowPlayingIndicator extends StatefulWidget {
  final Color? color;
  final double size;
  final bool isPlaying;

  const NowPlayingIndicator({
    super.key,
    this.color,
    this.size = 24,
    this.isPlaying = true,
  });

  @override
  State<NowPlayingIndicator> createState() => _NowPlayingIndicatorState();
}

class _NowPlayingIndicatorState extends State<NowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AnimationDurations.loop,
      vsync: this,
    );

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(NowPlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 计算每个条形的高度，从左到右依次波动
  double _getBarHeight(int index, double progress) {
    // 从左到右：index 越小，延迟越小（先动）
    const delayPerBar = 0.2;
    
    // 计算这个条形的相位（负号让动画从左到右传播）
    final barPhase = (progress - index * delayPerBar) % 1.0;
    
    // 使用正弦波创建平滑的上下波动
    final wave = math.sin(barPhase * 2 * math.pi);
    
    // 基础高度 0.5，波动幅度 0.4
    return 0.5 + 0.4 * ((wave + 1) / 2);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Colors.white;
    final barWidth = widget.size * 0.18;
    final gap = widget.size * 0.08;
    final maxBarHeight = widget.size * 0.7;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        // 使用 CustomPaint 避免每帧重建 widget 树
        // AnimatedBuilder 的 child 参数用于缓存不变的部分
        child: SizedBox(width: widget.size, height: widget.size),
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _BarsPainter(
              color: color,
              barWidth: barWidth,
              gap: gap,
              maxBarHeight: maxBarHeight,
              borderRadius: 2.0,
              heights: List.generate(3, (i) => _getBarHeight(i, _controller.value)),
            ),
          );
        },
      ),
    );
  }
}

/// CustomPainter for the animated bars - avoids rebuilding widget tree every frame
class _BarsPainter extends CustomPainter {
  final Color color;
  final double barWidth;
  final double gap;
  final double maxBarHeight;
  final double borderRadius;
  final List<double> heights;

  _BarsPainter({
    required this.color,
    required this.barWidth,
    required this.gap,
    required this.maxBarHeight,
    required this.borderRadius,
    required this.heights,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final totalWidth = barWidth * heights.length + gap * (heights.length - 1);
    var x = (size.width - totalWidth) / 2;
    final centerY = size.height / 2;

    for (final h in heights) {
      final barHeight = maxBarHeight * h;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(borderRadius),
      );
      canvas.drawRRect(rect, paint);
      x += barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true; // always repaint during animation
}
