import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/ui_constants.dart';
import '../core/services/toast_service.dart';
import 'layouts/responsive_scaffold.dart';
import 'router.dart';

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
        duration: message.type == ToastType.error || message.type == ToastType.warning
            ? ToastDurations.long
            : ToastDurations.short,
      ),
    );
  }

  /// 根据当前路由路径获取导航索引
  int _getSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    if (location.startsWith(RoutePaths.settings)) return 5;
    if (location.startsWith(RoutePaths.radio)) return 4;
    if (location.startsWith(RoutePaths.library)) return 3;
    if (location.startsWith(RoutePaths.queue)) return 2;
    if (location.startsWith(RoutePaths.search)) return 1;
    return 0; // home
  }

  /// 导航到指定分支
  void _onDestinationSelected(int index) {
    // 關閉所有 popup 菜單（PopupMenuButton 等）
    // Shell 內的頁面切換使用 context.go()，不會觸發 Navigator.pop()
    // 因此需要手動關閉 popup 類型的路由
    // 使用 shellNavigatorKey 直接訪問 Shell Navigator 來關閉 popup
    shellNavigatorKey.currentState?.popUntil((route) => route is! PopupRoute);

    switch (index) {
      case 0:
        context.go(RoutePaths.home);
      case 1:
        context.go(RoutePaths.search);
      case 2:
        context.go(RoutePaths.queue);
      case 3:
        context.go(RoutePaths.library);
      case 4:
        context.go(RoutePaths.radio);
      case 5:
        context.go(RoutePaths.settings);
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

    return ResponsiveScaffold(
      selectedIndex: _getSelectedIndex(context),
      onDestinationSelected: _onDestinationSelected,
      child: widget.child,
    );
  }
}
