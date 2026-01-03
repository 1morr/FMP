import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/breakpoints.dart';
import 'router.dart';
import 'layouts/responsive_scaffold.dart';

/// 应用外壳 - 包含导航栏和迷你播放器
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
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
    final selectedIndex = _getSelectedIndex(context);

    return ResponsiveScaffold(
      selectedIndex: selectedIndex,
      onDestinationSelected: _onDestinationSelected,
      child: widget.child,
    );
  }
}
