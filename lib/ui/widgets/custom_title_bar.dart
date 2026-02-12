import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 自定义标题栏 - 替代系统默认标题栏，融入应用主题风格
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initMaximizeState();
  }

  Future<void> _initMaximizeState() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = isMaximized);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 36,
      color: colorScheme.surface,
      child: Row(
        children: [
          // 可拖拽的标题区域
          Expanded(
            child: DragToMoveArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 72,
                  child: Center(
                    child: Text(
                      'FMP',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 最小化
          _TitleBarButton(
            icon: Icons.remove,
            onPressed: windowManager.minimize,
          ),
          // 最大化 / 还原
          _TitleBarButton(
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            iconSize: _isMaximized ? 13 : 15,
            onPressed: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          // 关闭（最小化到托盘）
          _TitleBarButton(
            icon: Icons.close,
            onPressed: windowManager.close,
            isClose: true,
          ),
        ],
      ),
    );
  }
}

/// 标题栏窗口控制按钮
class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;
  final bool isClose;

  const _TitleBarButton({
    required this.icon,
    this.iconSize = 15,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 36,
          color: _isHovered
              ? (widget.isClose
                  ? Colors.red
                  : colorScheme.onSurface.withValues(alpha: 0.08))
              : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _isHovered && widget.isClose
                  ? Colors.white
                  : colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}
