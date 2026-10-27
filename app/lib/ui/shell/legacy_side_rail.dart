import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 一個導覽項在導覽元件上的圖示、文字與（底部導覽列的）tooltip。
typedef ShellDestinationLabel = ({
  IconData icon,
  IconData selectedIcon,
  String label,
  String? tooltip,
});

/// 舊版的可展開側欄（ADR 0035 §決定 2；舊版 `responsive_scaffold.dart` 的 `_ExpandedLayout`）：
/// 收合 72dp（圖示加文字標籤）、展開 256dp（FMP 名稱、圖示加文字）。medium 以上各寬度同一個，
/// 取代 `NavigationRail` 與常駐的 `NavigationDrawer`。
///
/// 畫成展開或收合由外殼傳進來的 `expanded` 決定：外殼依記住的狀態（`layout_state.rail_expanded`，沒記過是
/// 收合）與右側面板放不放得下算出來（[railYieldsToPanel]），所以記住展開、畫面上卻是收合是正常的；
/// 展開鈕與收合鈕只呼叫 `onExpand`、`onCollapse`，寫入由外殼做。高度不夠（橫向手機）時項目
/// 可以捲動，頂端的展開／收合鈕不動，「設定」才一直按得到。展開、收合有寬度動畫；系統要求減少
/// 動態時直接切換。
///
/// 展開鈕與收合鈕共用一個 `FocusNode`：兩者在不同的子樹，按下後舊的那顆就拆掉，不共用的話
/// 鍵盤使用者按了之後焦點掉回導覽區本身，要重新找位置。
class LegacySideRail extends ConsumerStatefulWidget {
  const LegacySideRail({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    required this.expanded,
    required this.onExpand,
    required this.onCollapse,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<ShellDestinationLabel> destinations;

  /// 畫面上是否展開（已把「面板放不下」算進去）。
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;

  @override
  ConsumerState<LegacySideRail> createState() => _LegacySideRailState();
}

class _LegacySideRailState extends ConsumerState<LegacySideRail> {
  final _toggleFocus = FocusNode(debugLabel: 'Side rail toggle');

  /// 上一次 build 時記住的版面狀態已經讀到了。
  var _loaded = false;

  @override
  void dispose() {
    _toggleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = widget.selectedIndex;
    final onSelected = widget.onSelected;
    final destinations = widget.destinations;
    final expanded = widget.expanded;
    final scheme = Theme.of(context).colorScheme;
    // 啟動時第一次讀到記住的狀態直接到位：那不是使用者按的，不要每次開 App 都看它展開一次。
    final loaded = ref.watch(layoutStateProvider.select((s) => s.hasValue));
    final animate = _loaded && !MediaQuery.disableAnimationsOf(context);
    _loaded = loaded;
    // 舊版的做法：內容永遠以完整寬度排版，外層用 widthFactor 裁切，所以動畫中不會因為變窄而溢出。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: ClipRect(
          child: AnimatedAlign(
            duration: animate ? AppLayout.railDuration : Duration.zero,
            curve: Curves.easeInOut,
            alignment: Alignment.centerLeft,
            widthFactor: expanded
                ? 1
                : AppLayout.railCollapsed / AppLayout.railExpanded,
            child: SizedBox(
              width: AppLayout.railExpanded,
              child: expanded
                  ? _Expanded(
                      selectedIndex: selectedIndex,
                      onSelected: onSelected,
                      destinations: destinations,
                      toggleFocus: _toggleFocus,
                      onCollapse: widget.onCollapse,
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: AppLayout.railCollapsed,
                        child: _Collapsed(
                          selectedIndex: selectedIndex,
                          onSelected: onSelected,
                          destinations: destinations,
                          toggleFocus: _toggleFocus,
                          onExpand: widget.onExpand,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 收合：展開鈕在頂端（`leading`，不隨捲動離開），下面是圖示加標籤的項目，高度不夠時可以捲。
class _Collapsed extends ConsumerWidget {
  const _Collapsed({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    required this.toggleFocus,
    required this.onExpand,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<ShellDestinationLabel> destinations;
  final FocusNode toggleFocus;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = AppTokens.of(context).spacing;
    final t = ref.watch(translationsProvider).shell;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: NavigationRailLabelType.all,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      scrollable: true,
      leading: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            focusNode: toggleFocus,
            icon: const Icon(Icons.menu),
            tooltip: t.railExpandTooltip,
            onPressed: onExpand,
          ),
          SizedBox(height: spacing.x2),
          Divider(indent: spacing.x3, endIndent: spacing.x3),
        ],
      ),
      destinations: [
        for (final item in destinations)
          NavigationRailDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: Text(item.label),
          ),
      ],
    );
  }
}

/// 展開：FMP 名稱與收合鈕，下面一列一個項目（選中的是 `secondaryContainer` 的膠囊）。
class _Expanded extends ConsumerWidget {
  const _Expanded({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    required this.toggleFocus,
    required this.onCollapse,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<ShellDestinationLabel> destinations;
  final FocusNode toggleFocus;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final t = ref.watch(translationsProvider).shell;
    final pill = BorderRadius.circular(tokens.radius.extraLarge);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.x4,
            end: spacing.x2,
            top: spacing.x3,
            bottom: spacing.x2,
          ),
          child: Row(
            children: [
              // App 名稱不翻譯（同標題列與舊版）。
              Text(
                'FMP',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                focusNode: toggleFocus,
                icon: const Icon(Icons.menu_open),
                tooltip: t.railCollapseTooltip,
                onPressed: onCollapse,
              ),
            ],
          ),
        ),
        Divider(indent: spacing.x4, endIndent: spacing.x4),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.x3,
              vertical: spacing.x1,
            ),
            children: [
              for (var index = 0; index < destinations.length; index++)
                _ExpandedItem(
                  item: destinations[index],
                  selected: index == selectedIndex,
                  shape: pill,
                  onTap: () => onSelected(index),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandedItem extends StatelessWidget {
  const _ExpandedItem({
    required this.item,
    required this.selected,
    required this.shape,
    required this.onTap,
  });

  final ShellDestinationLabel item;
  final bool selected;
  final BorderRadius shape;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spacing = AppTokens.of(context).spacing;
    final color = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppLayout.railItemGap / 2),
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLow,
          borderRadius: shape,
          child: InkWell(
            borderRadius: shape,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.x4,
                vertical: spacing.x3,
              ),
              child: Row(
                children: [
                  Icon(selected ? item.selectedIcon : item.icon, color: color),
                  SizedBox(width: spacing.x3),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
