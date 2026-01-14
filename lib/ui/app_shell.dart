import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/services/toast_service.dart';
import 'router.dart';
import 'layouts/responsive_scaffold.dart';

/// 应用外壳 - 包含导航栏和迷你播放器
class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

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

  /// 根据路由路径获取导航索引
  int _getSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith(RoutePaths.search)) return 1;
    if (location.startsWith(RoutePaths.queue)) return 2;
    if (location.startsWith(RoutePaths.library)) return 3;
    if (location.startsWith(RoutePaths.settings)) return 4;
    return 0; // home
  }

  /// 导航到指定页面
  void _onDestinationSelected(int index) {
    switch (index) {
      case 0:
        context.go(RoutePaths.home);
        break;
      case 1:
        context.go(RoutePaths.search);
        break;
      case 2:
        context.go(RoutePaths.queue);
        break;
      case 3:
        context.go(RoutePaths.library);
        break;
      case 4:
        context.go(RoutePaths.settings);
        break;
    }
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

    final selectedIndex = _getSelectedIndex(context);

    return ResponsiveScaffold(
      selectedIndex: selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      child: widget.child,
    );
  }
}
