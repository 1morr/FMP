import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/window_drag.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 右側的實心詳情面板（`FMP.detailPanel`，`docs/design/DESIGN.md`〈桌面〉
/// 〈中寬度〉）。現在只有標頭「正在播放」與收起鈕；內容在曲目資訊那張票。
///
/// 寬級貼在視窗右邊（[floating] false）；中寬度浮在內容上，帶圓角與陰影。
class DetailPanel extends StatelessWidget {
  const DetailPanel({
    super.key,
    required this.onHide,
    required this.touch,
    this.floating = false,
    this.topInset = 0,
    this.endInset = 0,
  });

  /// 寬度：320，觸控浮動時 360。
  static double widthOf({required bool touch, required bool floating}) =>
      touch && floating ? 360 : 320;

  final VoidCallback onHide;
  final bool touch;
  final bool floating;

  /// 貼齊視窗頂端時讓出的狀態列高度。
  final double topInset;

  /// 標頭右端再讓出的寬度（Windows 的視窗鈕）。
  final double endInset;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final t = context.t;
    final big = touch && floating;
    final head = Container(
      height: big ? 60 : 52,
      padding: EdgeInsets.fromLTRB(big ? 20 : 16, 8, 10 + endInset, 0),
      child: Row(
        children: [
          Expanded(
            child: WindowDragArea(
              child: Semantics(
                header: true,
                child: Text(
                  t.shell.detail.title,
                  style: TextStyle(
                    fontSize: big ? 17 : 13,
                    fontWeight: FontWeight.w700,
                    color: colors.label,
                  ),
                ),
              ),
            ),
          ),
          PlainIconButton(
            icon: FmpIcons.sidebarR,
            tooltip: t.shell.detail.hide,
            onTap: onHide,
            size: touch ? 44 : 32,
          ),
        ],
      ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: topInset),
        head,
      ],
    );
    if (!floating) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border(left: BorderSide(color: colors.sep, width: .5)),
        ),
        child: body,
      );
    }
    final radius = BorderRadius.circular(touch ? 22 : 14);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: radius,
        border: Border.all(color: colors.sepStrong, width: .5),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, .45),
                  offset: Offset(0, 10),
                  blurRadius: 30,
                ),
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, .35),
                  offset: Offset(0, 2),
                  blurRadius: 6,
                ),
              ]
            : const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, .14),
                  offset: Offset(0, 10),
                  blurRadius: 30,
                ),
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, .08),
                  offset: Offset(0, 2),
                  blurRadius: 6,
                ),
              ],
      ),
      child: ClipRRect(borderRadius: radius, child: body),
    );
  }
}
