import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/platform/traffic_lights.dart';
import 'package:fmp/platform/window_drag.dart';
import 'package:fmp/ui/search/search_field.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面左側的浮動玻璃側欄（`FMP.side`，`docs/design/DESIGN.md`〈桌面〉）：搜尋欄、
/// 首頁、音樂庫、佇列，底部設定。歌單清單在 M3 才有，現在不出現。外框寬
/// [width]，圓角 12。
class SideBar extends StatelessWidget {
  const SideBar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onSearch,
  });

  /// 外框寬度（內容 232 加左右 8）。
  static const double width = 248;

  final Destination current;
  final ValueChanged<Destination> onSelect;

  /// 點搜尋欄或送出時：進搜尋頁。
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget item(Destination d) => _NavItem(
      destination: d,
      label: d.label(t),
      selected: d == current,
      onTap: () => onSelect(d),
    );
    return Glass(
      radius: context.fmpMetrics.radii.sidebar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 紅綠燈的位置（`.side .lights`：上內距 14、左內縮 8，加高 40），
            // 也是拖動視窗的地方。
            TrafficLightsArea(
              spot: const Offset(8, 14),
              child: WindowDragArea(
                child: SizedBox(
                  height: WindowChrome.insetTrafficLights ? 54 : 8,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
              child: SearchField(
                placement: SearchFieldPlacement.sidebar,
                active: current == Destination.search,
                onTap: onSearch,
                onSubmitted: onSearch,
              ),
            ),
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: t.shell.nav.label,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  item(Destination.home),
                  item(Destination.library),
                  item(Destination.queue),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: item(Destination.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Destination destination;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return ShellButton(
      onTap: onTap,
      selected: selected,
      builder: (context, hovered) => AnimatedContainer(
        duration: FmpMotion.fast,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: selected
              ? colors.glassInk.withValues(alpha: .11)
              : hovered
              ? colors.glassPress
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            FmpIcon(destination.icon, size: 17, color: colors.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: colors.glassInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
