import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_layout.dart';
import '../../core/constants/breakpoints.dart';
import '../../core/constants/ui_constants.dart';
import '../../i18n/strings.g.dart';
import '../../providers/audio/audio_player_selectors.dart';
import '../../services/radio/radio_controller.dart';
import '../router.dart';
import '../widgets/player/mini_player.dart';
import '../widgets/radio/radio_mini_player.dart';
import '../widgets/panels/track_detail_panel.dart';
import '../../providers/settings/layout_settings_provider.dart';

/// 导航目的地定义
class NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// 這個目的地的路由。以前索引與路徑的對應寫在 `app_shell.dart` 的兩個
  /// switch 裡，刪一個目的地要記得同時改三處位置編號。
  final String path;

  const NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.path,
  });
}

/// 导航目的地列表
///
/// **五個，不是六個。** M3 的 navigation bar 規範是 3–5 個目的地（"Avoid
/// putting more than five navigation items"），而「設定」是六個裡最少用、
/// 卻和「首頁」佔一樣寬度的那一個。它移到 [settingsDestination]。
List<NavDestination> get destinations => [
      NavDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: t.nav.home,
        path: RoutePaths.home,
      ),
      NavDestination(
        icon: Icons.search_outlined,
        selectedIcon: Icons.search,
        label: t.nav.search,
        path: RoutePaths.search,
      ),
      NavDestination(
        icon: Icons.queue_music_outlined,
        selectedIcon: Icons.queue_music,
        label: t.nav.queue,
        path: RoutePaths.queue,
      ),
      NavDestination(
        icon: Icons.library_music_outlined,
        selectedIcon: Icons.library_music,
        label: t.nav.library,
        path: RoutePaths.library,
      ),
      NavDestination(
        icon: Icons.radio_outlined,
        selectedIcon: Icons.radio,
        label: t.nav.radio,
        path: RoutePaths.radio,
      ),
    ];

/// 「設定」的入口：導覽軌底部（有軌的視窗）與首頁右上角（手機）。
///
/// 決策 04-D3 的最小版本。代價寫在這裡免得下次有人想搬回去：從「搜尋」進設定
/// 從一下變成兩下。換到的是導覽列符合規範，而且最常用的五個目的地各自變寬。
NavDestination get settingsDestination => NavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: t.nav.settings,
      path: RoutePaths.settings,
    );

/// [location] 對應導覽列的第幾個目的地。
///
/// 對不上就回首頁（0）—— `/settings`、`/explore`、`/history` 都落在這裡。
/// 那是刻意的：它們是從首頁推進去的子頁，高亮留在首頁（見 `lib/ui/AGENTS.md`
/// 的 Page Conventions）。
///
/// 比對用「完全相等或以 `路徑/` 開頭」而不是 `startsWith(路徑)`，否則
/// `/radio-player` 會被算成電台分頁。
int navIndexForLocation(String location) {
  for (var i = 0; i < destinations.length; i++) {
    final path = destinations[i].path;
    if (path == RoutePaths.home) continue;
    if (location == path || location.startsWith('$path/')) return i;
  }
  return 0;
}

/// 响应式 Scaffold - 根据屏幕宽度选择不同布局
class ResponsiveScaffold extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// 導覽軌底部的「設定」。手機沒有軌，入口在首頁右上角。
  final VoidCallback onSettingsSelected;

  const ResponsiveScaffold({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSettingsSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 使用 MediaQuery 而不是 LayoutBuilder 来避免与 go_router Navigator 的布局冲突
    final width = MediaQuery.of(context).size.width;
    final layout = switch (WindowClass.of(width)) {
      WindowClass.compact => _CompactLayout(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          onSettingsSelected: onSettingsSelected,
          child: child,
        ),
      WindowClass.medium => _MediumLayout(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          onSettingsSelected: onSettingsSelected,
          child: child,
        ),
      WindowClass.expanded ||
      WindowClass.large ||
      WindowClass.extraLarge =>
        _ExpandedLayout(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          onSettingsSelected: onSettingsSelected,
          child: child,
        ),
    };

    return layout;
  }
}

/// 手机布局 - 底部导航栏
class _CompactLayout extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettingsSelected;

  const _CompactLayout({
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSettingsSelected,
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
class _MediumLayout extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettingsSelected;

  const _MediumLayout({
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSettingsSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: AppLayout.railCollapsed,
            child: Container(
              color: colorScheme.surfaceContainerLow,
              child: NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.transparent,
                trailing: _RailSettingsButton(onPressed: onSettingsSelected),
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
class _ExpandedLayout extends ConsumerStatefulWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettingsSelected;

  const _ExpandedLayout({
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSettingsSelected,
  });

  @override
  ConsumerState<_ExpandedLayout> createState() => _ExpandedLayoutState();
}

class _ExpandedLayoutState extends ConsumerState<_ExpandedLayout> {
  // 版面狀態持久化在 Settings 裡，由 layoutSettingsProvider 讀寫 ——
  // 這三個值以前是純 widget state，每次啟動都重置。
  LayoutSettingsState get _layout => ref.watch(layoutSettingsProvider);
  LayoutSettingsNotifier get _layoutNotifier =>
      ref.read(layoutSettingsProvider.notifier);

  bool get _isNavExpanded => _layout.railExpanded;
  bool get _isDetailPanelExpanded => _layout.detailPanelExpanded;
  double get _detailPanelWidth => _layout.detailPanelWidth;

  bool _isHoveredOnCollapsedBar = false;
  bool _isDraggingPanelWidth = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentTrack = ref.watch(currentTrackProvider);
    final showRadioPlaybackUi = ref.watch(showRadioPlaybackUiProvider);
    final hasTrack = currentTrack != null || showRadioPlaybackUi;
    final windowWidth = MediaQuery.sizeOf(context).width;
    // 存下來的寬度只有相對於視窗才有意義：同一個 412 在 840dp 上該渲染成 336。
    final panelWidth = AppLayout.detailPanelWidthFor(
      _detailPanelWidth,
      windowWidth,
    );

    return Scaffold(
      body: Row(
        children: [
          // 可收起的侧边导航栏
          ClipRect(
            child: AnimatedAlign(
              duration: AnimationDurations.medium,
              alignment: Alignment.centerLeft,
              widthFactor: _isNavExpanded
                  ? 1.0
                  : AppLayout.railCollapsed / AppLayout.railExpanded,
              child: SizedBox(
                width: AppLayout.railExpanded,
                child: _isNavExpanded
                    ? _buildExpandedNav()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: AppLayout.railCollapsed,
                          child: _buildCollapsedNav(),
                        ),
                      ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // 主内容区
          Expanded(child: widget.child),
          // 仅当有歌曲时显示右侧面板
          if (hasTrack)
            _buildDetailPanelContainer(colorScheme, panelWidth, windowWidth),
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
                  onPressed: () => _layoutNotifier.setRailExpanded(false),
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
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: AppRadius.borderRadiusPill,
              child: InkWell(
                borderRadius: AppRadius.borderRadiusPill,
                onTap: widget.onSettingsSelected,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        settingsDestination.icon,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          settingsDestination.label,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 统一的详情面板容器 — spacer + TrackDetailPanel 始终在 widget tree 中
  Widget _buildDetailPanelContainer(
    ColorScheme colorScheme,
    double panelWidth,
    double windowWidth,
  ) {
    // 展開時總寬 = pane spacer + 面板寬；收起時是一條 36dp 的長條（滑鼠停留
    // 時 54dp）。整個面板始終以完整寬度佈局、由外層裁切，所以收合不會重排
    // 面板內容。
    final totalWidth = _isDetailPanelExpanded
        ? panelWidth + AppLayout.paneSpacer
        : (_isHoveredOnCollapsedBar
            ? AppLayout.collapsedStripHovered
            : AppLayout.collapsedStrip);

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
                  _layoutNotifier.setDetailPanelExpanded(true);
                  _isHoveredOnCollapsedBar = false;
                }),
        child: AnimatedContainer(
          // 拖拽调整宽度时不需要动画，避免延迟
          duration: _isDraggingPanelWidth
              ? Duration.zero
              : AnimationDurations.fastest,
          curve: Curves.easeInOut,
          width: totalWidth,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: Stack(
            children: [
              // 底层：spacer + 真实的 TrackDetailPanel
              // 使用 OverflowBox 让内容忽略父级宽度约束，
              // 始终按完整宽度布局，外层 clip 裁剪溢出部分。
              Align(
                alignment: Alignment.topLeft,
                child: OverflowBox(
                  maxWidth: panelWidth + AppLayout.paneSpacer,
                  minWidth: panelWidth + AppLayout.paneSpacer,
                  alignment: Alignment.topLeft,
                  child: Row(
                    children: [
                      _buildPaneSpacer(colorScheme, panelWidth, windowWidth),
                      // 详情面板
                      Expanded(
                        child: TrackDetailPanel(
                          onCollapse: () =>
                              _layoutNotifier.setDetailPanelExpanded(false),
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

  /// 兩個 pane 之間的間隔，裡面是拖動把手。
  ///
  /// M3 規定 large / extra-large 版面的 pane spacer 是 24dp，且「pane 可以調整
  /// 大小時 spacer 內要放一個 drag handle」。這裡原本是 6dp 的命中區裡一條 1dp
  /// 的線：只有滑鼠移上去游標會變，觸控與鍵盤使用者無從發現它可以拖。
  Widget _buildPaneSpacer(
    ColorScheme colorScheme,
    double panelWidth,
    double windowWidth,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) {
          setState(() => _isDraggingPanelWidth = true);
        },
        onHorizontalDragUpdate: (details) {
          // 拖曳期間只更新記憶體，放開時才寫資料庫 —— 否則一次調整會寫進
          // 數百個交易。從渲染寬度（不是存下來的值）起算，兩者在視窗變窄
          // 之後會不一樣，用存的值會讓把手在第一下就跳走。
          _layoutNotifier.previewDetailPanelWidth(
            (panelWidth - details.delta.dx).clamp(
              AppLayout.detailPanelMin,
              AppLayout.detailPanelMaxFor(windowWidth),
            ),
          );
        },
        onHorizontalDragEnd: (_) {
          setState(() => _isDraggingPanelWidth = false);
          _layoutNotifier.commitDetailPanelWidth(_detailPanelWidth);
        },
        // 沒有這一條，被取消的拖曳會讓動畫永遠停在 Duration.zero。
        onHorizontalDragCancel: () {
          setState(() => _isDraggingPanelWidth = false);
        },
        child: Container(
          width: AppLayout.paneSpacer,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: AppRadius.borderRadiusXs,
              ),
            ),
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
            onPressed: () => _layoutNotifier.setRailExpanded(true),
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
              trailing:
                  _RailSettingsButton(onPressed: widget.onSettingsSelected),
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

/// 導覽軌底部的「設定」。
///
/// 它不是 `NavigationRailDestination`：設定不參與導覽列的選中狀態，
/// `/settings` 的高亮留在首頁（見 [navIndexForLocation]）。
class _RailSettingsButton extends StatelessWidget {
  const _RailSettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: IconButton(
        icon: Icon(settingsDestination.icon),
        onPressed: onPressed,
        tooltip: settingsDestination.label,
      ),
    );
  }
}

/// 迷你播放器切換器 - 根據當前播放模式顯示音樂或電台迷你播放器
class _MiniPlayerSwitch extends ConsumerWidget {
  const _MiniPlayerSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showRadioPlaybackUi = ref.watch(showRadioPlaybackUiProvider);

    if (showRadioPlaybackUi) {
      return const RadioMiniPlayer();
    }

    return const MiniPlayer();
  }
}
