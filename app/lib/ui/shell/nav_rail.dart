import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/platform/traffic_lights.dart';
import 'package:fmp/platform/window_drag.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 中寬度的玻璃細欄（`FMP.rail`，`docs/design/DESIGN.md`〈中寬度〉）：搜尋、首頁、
/// 音樂庫、佇列，底部設定。搜尋是項目不是欄位。歌單在 M3 才有，所以沒有
/// 分隔線、歌單封面與新建鈕。外框寬 72（觸控 80）。
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.current,
    required this.touch,
    required this.onSelect,
  });

  /// 外框寬度。
  static double widthOf({required bool touch}) => touch ? 80 : 72;

  final Destination current;
  final bool touch;
  final ValueChanged<Destination> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget item(Destination d) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _RailItem(
        destination: d,
        label: d.label(t),
        selected: d == current,
        touch: touch,
        onTap: () => onSelect(d),
      ),
    );
    final lights = !touch && WindowChrome.insetTrafficLights;
    return Glass(
      radius: touch ? 22 : 16,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: t.shell.nav.label,
        child: Padding(
          padding: touch
              ? const EdgeInsets.fromLTRB(6, 6, 6, 8)
              : const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 紅綠燈的位置（`.rail .lights`：上內距 14、左內縮 7，加高 38），
              // 也是拖動視窗的地方。
              if (!touch)
                TrafficLightsArea(
                  spot: const Offset(7, 14),
                  child: WindowDragArea(
                    child: SizedBox(height: lights ? 52 : 6),
                  ),
                ),
              item(Destination.search),
              item(Destination.home),
              item(Destination.library),
              item(Destination.queue),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: item(Destination.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.label,
    required this.selected,
    required this.touch,
    required this.onTap,
  });

  final Destination destination;
  final String label;
  final bool selected;
  final bool touch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final color = selected ? colors.accent : colors.glassInk;
    return ShellButton(
      onTap: onTap,
      selected: selected,
      builder: (context, hovered) => AnimatedContainer(
        duration: FmpMotion.fast,
        height: touch ? 58 : 50,
        decoration: BoxDecoration(
          color: selected || hovered ? colors.glassPress : null,
          borderRadius: BorderRadius.circular(touch ? 17 : 13),
          border: selected
              ? Border.all(
                  color: const Color.fromRGBO(255, 255, 255, .22),
                  width: .5,
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FmpIcon(
              destination.icon,
              size: touch ? 24 : 20,
              strokeWidth: 1.7,
              color: color,
            ),
            SizedBox(height: touch ? 3 : 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: touch ? 11 : 10,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: touch ? .11 : .1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
