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
    final barWidth = widget.size * 0.18; // 更宽的长方形
    final gap = widget.size * 0.08;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (index) {
              final heightFactor = _getBarHeight(index, _controller.value);
              return Container(
                width: barWidth,
                height: widget.size * 0.7 * heightFactor,
                margin: EdgeInsets.only(right: index < 2 ? gap : 0),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2), // 小圆角，更像长方形
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
