import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/ui/layouts/responsive_scaffold.dart';
import 'package:fmp/ui/router.dart';

/// 应用外壳 - 包含导航栏和迷你播放器
class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  void _showSnackBar(ToastMessage message) {
    ToastService.showSnackBarNow(
      context,
      ToastService.buildSnackBar(
        context,
        message: message.message,
        type: message.type,
      ),
    );
  }

  /// 导航到指定分支
  void _onDestinationSelected(int index) {
    _goTo(destinations[index].path);
  }

  void _goTo(String path) {
    // 關閉所有 popup 菜單（PopupMenuButton 等）
    // Shell 內的頁面切換使用 context.go()，不會觸發 Navigator.pop()
    // 因此需要手動關閉 popup 類型的路由
    // 使用 shellNavigatorKey 直接訪問 Shell Navigator 來關閉 popup
    shellNavigatorKey.currentState?.popUntil((route) => route is! PopupRoute);
    context.go(path);
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
      selectedIndex: navIndexForLocation(GoRouterState.of(context).uri.path),
      onDestinationSelected: _onDestinationSelected,
      onSettingsSelected: () => _goTo(settingsDestination.path),
      child: widget.child,
    );
  }
}
