import 'package:flutter/material.dart';

import '../../core/constants/breakpoints.dart';

/// 导航目的地定义
class NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 导航目的地列表
const List<NavDestination> destinations = [
  NavDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: '首页',
  ),
  NavDestination(
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    label: '搜索',
  ),
  NavDestination(
    icon: Icons.queue_music_outlined,
    selectedIcon: Icons.queue_music,
    label: '队列',
  ),
  NavDestination(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    label: '音乐库',
  ),
  NavDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: '设置',
  ),
];

/// 响应式 Scaffold - 根据屏幕宽度选择不同布局
class ResponsiveScaffold extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const ResponsiveScaffold({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutType = Breakpoints.getLayoutType(constraints.maxWidth);

        return switch (layoutType) {
          LayoutType.mobile => _MobileLayout(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              child: child,
            ),
          LayoutType.tablet => _TabletLayout(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              child: child,
            ),
          LayoutType.desktop => _DesktopLayout(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              child: child,
            ),
        };
      },
    );
  }
}

/// 手机布局 - 底部导航栏
class _MobileLayout extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _MobileLayout({
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}

/// 平板布局 - 侧边导航栏
class _TabletLayout extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _TabletLayout({
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            destinations: destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 桌面布局 - 展开的侧边导航栏 + 三栏布局
class _DesktopLayout extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _DesktopLayout({
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          // 侧边导航栏
          NavigationDrawer(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
                child: Text(
                  'FMP',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(indent: 28, endIndent: 28),
              ...destinations.map((d) => NavigationDrawerDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  )),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // 主内容区
          Expanded(
            flex: 2,
            child: child,
          ),
          // 右侧播放器面板（预留位置）
          // const VerticalDivider(width: 1, thickness: 1),
          // Expanded(
          //   flex: 1,
          //   child: _PlayerPanel(),
          // ),
        ],
      ),
    );
  }
}
