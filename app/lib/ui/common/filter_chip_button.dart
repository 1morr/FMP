import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 篩選 chip（`.chip`，搜尋的音源篩選與首頁的榜音源）：選中的是實心
/// `--label` 底；出錯的音源帶警示符號。觸控 32 高（[height] 可換），滑鼠 26。
/// [touchTarget] 時點擊區上下補到觸控 44、滑鼠 28（`DESIGN.md`〈稿內不一致與
/// 實作注意〉第 2 點、〈無障礙〉），會多佔版面。鍵盤選得到，Enter 選它。
class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.label,
    required this.on,
    required this.table,
    required this.onTap,
    this.pluginId,
    this.count,
    this.warn = false,
    this.height,
    this.touchTarget = false,
  });

  final String label;
  final bool on;

  /// 滑鼠密度（桌面欄的大小）。
  final bool table;
  final VoidCallback onTap;
  final String? pluginId;
  final int? count;
  final bool warn;
  final double? height;
  final bool touchTarget;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final ink = on ? colors.bg : colors.label;
    final visual = height ?? (table ? 26.0 : 32.0);
    return Semantics(
      selected: on,
      child: ShellButton(
        onTap: onTap,
        label: label,
        focusRadius: 999,
        hitPadding: touchTarget && visual < context.fmpMetrics.minTarget
            ? EdgeInsets.symmetric(
                vertical: (context.fmpMetrics.minTarget - visual) / 2,
              )
            : null,
        builder: (context, hovered) {
          final chip = Container(
            height: visual,
            padding: EdgeInsets.symmetric(horizontal: table ? 11 : 13),
            decoration: BoxDecoration(
              color: on ? colors.label : (hovered ? colors.fill2 : colors.fill),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pluginId case final id?) ...[
                  SourceMarkIcon(pluginId: id, size: table ? 13 : 15),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: table ? 12.5 : 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: ink,
                  ),
                ),
                if (warn) ...[
                  const SizedBox(width: 6),
                  FmpIcon(
                    FmpIcons.warn,
                    size: table ? 14 : 16,
                    color: on ? ink : colors.warn,
                  ),
                ] else if (count case final count?) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                      color: ink.withValues(alpha: .6),
                    ).tabular,
                  ),
                ],
              ],
            ),
          );
          return chip;
        },
      ),
    );
  }
}
