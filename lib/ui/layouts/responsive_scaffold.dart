import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/breakpoints.dart';
import '../../core/constants/ui_constants.dart';
import '../../i18n/strings.g.dart';
import '../../services/audio/audio_provider.dart';
import '../../services/radio/radio_controller.dart';
import '../widgets/custom_title_bar.dart';
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
List<NavDestination> get destinations => [
  NavDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: t.nav.home,
  ),
  NavDestination(
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    label: t.nav.search,
  ),
  NavDestination(
    icon: Icons.queue_music_outlined,
    selectedIcon: Icons.queue_music,
    label: t.nav.queue,
  ),
  NavDestination(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    label: t.nav.library,
  ),
  NavDestination(
    icon: Icons.radio_outlined,
    selectedIcon: Icons.radio,
    label: t.nav.radio,
  ),
  NavDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: t.nav.settings,
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

    Widget layout = switch (layoutType) {
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

    // Windows 平台使用自定义标题栏替代系统默认标题栏
    if (Platform.isWindows) {
      layout = Column(
        children: [
          const CustomTitleBar(),
          Expanded(child: layout),
        ],
      );
    }

    return layout;
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

/// 平板布局 - 侧边导航栏（与桌面模式收起状态一致）
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 72, // 与桌面模式收起状态一致
            child: Container(
              color: colorScheme.surfaceContainerLow,
              child: NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
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
  bool _isDetailPanelExpanded = true; // 详情面板默认展开
  double _detailPanelWidth = 380; // 默认宽度
  static const double _minPanelWidth = 280.0;
  static const double _maxPanelWidth = 500.0;
  bool _isHoveredOnCollapsedBar = false;
  bool _isDraggingPanelWidth = false;


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final radioState = ref.watch(radioControllerProvider);
    final hasTrack = currentTrack != null || radioState.hasCurrentStation;

    return Scaffold(
      body: Row(
        children: [
          // 可收起的侧边导航栏
          ClipRect(
            child: AnimatedAlign(
              duration: AnimationDurations.medium,
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
          // 仅当有歌曲时显示右侧面板
          if (hasTrack)
            _buildDetailPanelContainer(colorScheme),
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
                  tooltip: t.nav.collapseNav,
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
                    borderRadius: AppRadius.borderRadiusPill,
                    child: InkWell(
                      borderRadius: AppRadius.borderRadiusPill,
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

  /// 统一的详情面板容器 — 分割线 + TrackDetailPanel 始终在 widget tree 中
  Widget _buildDetailPanelContainer(ColorScheme colorScheme) {
    // 展开时总宽度 = 分割线(6) + 面板宽度
    // 收起时总宽度 = 48 / 120（hover）
    final totalWidth = _isDetailPanelExpanded
        ? _detailPanelWidth + 6
        : (_isHoveredOnCollapsedBar ? 54.0 : 36.0);

    return MouseRegion(
      cursor: _isDetailPanelExpanded
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: _isDetailPanelExpanded
          ? null
          : (_) => setState(() => _isHoveredOnCollapsedBar = true),
      onExit: _isDetailPanelExpanded
          ? null
          : (_) => setState(() => _isHoveredOnCollapsedBar = false),
      child: GestureDetector(
        onTap: _isDetailPanelExpanded
            ? null
            : () => setState(() {
                _isDetailPanelExpanded = true;
                _isHoveredOnCollapsedBar = false;
              }),
        child: AnimatedContainer(
          // 拖拽调整宽度时不需要动画，避免延迟
          duration: _isDraggingPanelWidth ? Duration.zero : AnimationDurations.fastest,
          curve: Curves.easeInOut,
          width: totalWidth,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Stack(
            children: [
              // 底层：分割线 + 真实的 TrackDetailPanel
              // 使用 OverflowBox 让内容忽略父级宽度约束，
              // 始终按完整宽度布局，外层 clip 裁剪溢出部分。
              Align(
                alignment: Alignment.topLeft,
                child: OverflowBox(
                  maxWidth: _detailPanelWidth + 6,
                  minWidth: _detailPanelWidth + 6,
                  alignment: Alignment.topLeft,
                  child: Row(
                    children: [
                      // 可拖动的分割线
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          onHorizontalDragStart: (_) {
                            _isDraggingPanelWidth = true;
                          },
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _detailPanelWidth -= details.delta.dx;
                              _detailPanelWidth = _detailPanelWidth.clamp(
                                _minPanelWidth, _maxPanelWidth,
                              );
                            });
                          },
                          onHorizontalDragEnd: (_) {
                            _isDraggingPanelWidth = false;
                          },
                          child: Container(
                            width: 6,
                            color: Colors.transparent,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 1,
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 详情面板
                      Expanded(
                        child: TrackDetailPanel(
                          onCollapse: () => setState(() {
                            _isDetailPanelExpanded = false;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 顶层：半透明遮罩（仅收起时显示）
              if (!_isDetailPanelExpanded)
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: AnimationDurations.fast,
                    opacity: _isHoveredOnCollapsedBar ? 0.3 : 1.0,
                    child: Container(
                      color: colorScheme.surfaceContainerLow,
                      child: Center(
                        child: Icon(
                          Icons.first_page,
                          color: colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
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
            tooltip: t.nav.expandNav,
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
