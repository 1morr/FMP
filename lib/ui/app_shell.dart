import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' show StatefulNavigationShell;

import '../core/constants/app_constants.dart';
import '../core/services/toast_service.dart';
import 'layouts/responsive_scaffold.dart';

/// 应用外壳 - 包含导航栏和迷你播放器
class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  void _showSnackBar(ToastMessage message) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Color backgroundColor;
    IconData icon;
    
    switch (message.type) {
      case ToastType.success:
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
      case ToastType.warning:
        backgroundColor = Colors.orange;
        icon = Icons.warning;
      case ToastType.error:
        backgroundColor = colorScheme.error;
        icon = Icons.error;
      case ToastType.info:
        backgroundColor = colorScheme.primary;
        icon = Icons.info;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: AppConstants.toastDuration,
      ),
    );
  }

  /// 获取当前导航索引（直接从 navigationShell 获取）
  int get _selectedIndex => widget.navigationShell.currentIndex;

  /// 导航到指定分支
  void _onDestinationSelected(int index) {
    // 使用 goBranch 切换分支，保持每个分支的状态
    widget.navigationShell.goBranch(
      index,
      // 如果点击当前分支，返回到该分支的初始路由
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听 Toast 消息
    ref.listen<AsyncValue<ToastMessage>>(toastStreamProvider, (previous, next) {
      next.whenData((message) {
        if (!mounted) return;
        _showSnackBar(message);
      });
    });

    return ResponsiveScaffold(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      child: widget.navigationShell,
    );
  }
}
