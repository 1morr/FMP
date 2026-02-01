import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/breakpoints.dart';
import '../../services/audio/audio_provider.dart';
import '../../services/radio/radio_controller.dart';
import '../widgets/player/mini_player.dart';
import '../widgets/radio/radio_mini_player.dart';
import '../widgets/track_detail_panel.dart';

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
    icon: Icons.radio_outlined,
    selectedIcon: Icons.radio,
    label: '电台',
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
    // 使用 MediaQuery 而不是 LayoutBuilder 来避免与 go_router Navigator 的布局冲突
    final width = MediaQuery.of(context).size.width;
    final layoutType = Breakpoints.getLayoutType(width);

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
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MiniPlayerSwitch(),
          NavigationBar(
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
        ],
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
      bottomNavigationBar: const _MiniPlayerSwitch(),
    );
  }
}

/// 桌面布局 - 可收起的侧边导航栏 + 三栏布局 + 可拖动分割线
class _DesktopLayout extends ConsumerStatefulWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _DesktopLayout({
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  ConsumerState<_DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends ConsumerState<_DesktopLayout> {
  bool _isNavExpanded = false; // 默认收起
  double _detailPanelWidth = 380; // 默认宽度
  static const double _minPanelWidth = 280;
  static const double _maxPanelWidth = 500;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final hasTrack = currentTrack != null;

    return Scaffold(
      body: Row(
        children: [
          // 可收起的侧边导航栏
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.centerLeft,
              widthFactor: _isNavExpanded ? 1.0 : 72 / 256,
              child: SizedBox(
                width: 256,
                child: _isNavExpanded
                    ? _buildExpandedNav()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 72,
                          child: _buildCollapsedNav(),
                        ),
                      ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // 主内容区
          Expanded(
            flex: 2,
            child: widget.child,
          ),
          // 仅当有歌曲时显示右侧面板
          if (hasTrack) ...[
            // 可拖动的分割线
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _detailPanelWidth -= details.delta.dx;
                    _detailPanelWidth = _detailPanelWidth.clamp(_minPanelWidth, _maxPanelWidth);
                  });
                },
                child: Container(
                  width: 6,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 1,
                      color: colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
            // 右侧歌曲详情面板
            SizedBox(
              width: _detailPanelWidth,
              child: const TrackDetailPanel(),
            ),
          ],
        ],
      ),
      bottomNavigationBar: const _MiniPlayerSwitch(),
    );
  }

  Widget _buildExpandedNav() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Text(
                  'FMP',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.menu_open),
                  onPressed: () => setState(() => _isNavExpanded = false),
                  tooltip: '收起导航栏',
                ),
              ],
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: destinations.asMap().entries.map((entry) {
                final index = entry.key;
                final d = entry.value;
                final isSelected = index == widget.selectedIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: isSelected
                        ? colorScheme.secondaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(28),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => widget.onDestinationSelected(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? d.selectedIcon : d.icon,
                              color: isSelected
                                  ? colorScheme.onSecondaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                d.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onSecondaryContainer
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedNav() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => setState(() => _isNavExpanded = true),
            tooltip: '展开导航栏',
          ),
          const SizedBox(height: 8),
          const Divider(indent: 12, endIndent: 12),
          Expanded(
            child: NavigationRail(
              selectedIndex: widget.selectedIndex,
              onDestinationSelected: widget.onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.transparent,
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 迷你播放器切換器 - 根據當前播放模式顯示音樂或電台迷你播放器
class _MiniPlayerSwitch extends ConsumerWidget {
  const _MiniPlayerSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRadioPlaying = ref.watch(isRadioPlayingProvider);
    final hasRadioStation = ref.watch(radioControllerProvider).hasCurrentStation;

    // 電台正在播放或有電台站點時，顯示電台迷你播放器
    if (isRadioPlaying || hasRadioStation) {
      return const RadioMiniPlayer();
    }

    // 否則顯示普通音樂迷你播放器
    return const MiniPlayer();
  }
}
