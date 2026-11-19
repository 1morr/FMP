import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:material_ui/material_ui.dart';

/// 外殼裡可點的一塊：滑鼠移上去時 [builder] 拿到 hover，鍵盤與螢幕閱讀器
/// 當成按鈕。
class ShellButton extends StatefulWidget {
  const ShellButton({
    super.key,
    required this.onTap,
    required this.builder,
    this.label,
    this.selected = false,
    this.tooltip,
  });

  /// null 時停用：點不了，螢幕閱讀器讀成停用；外觀由 [builder] 自己畫。
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  /// 給螢幕閱讀器的名字；看得到的文字已經夠時留 null。
  final String? label;
  final bool selected;

  /// 只有圖示時給滑鼠 hover 與長按看的說明。
  final String? tooltip;

  @override
  State<ShellButton> createState() => _ShellButtonState();
}

class _ShellButtonState extends State<ShellButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _hovered),
      ),
    );
    child = Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      child: child,
    );
    if (widget.tooltip case final tooltip?) {
      child = Tooltip(message: tooltip, child: child);
    }
    return child;
  }
}

/// 頂列的玻璃圓鈕（`FMP.gbtn`）：觸控 44、滑鼠 34。[onTap] 為 null 時停用
/// （40% 透明、點不了）。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.touch,
  });

  final FmpIcons icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final side = touch ? 44.0 : 34.0;
    return ShellButton(
      onTap: onTap,
      tooltip: tooltip,
      label: tooltip,
      builder: (context, _) => Opacity(
        opacity: onTap == null ? .4 : 1,
        child: Glass(
          child: SizedBox.square(
            dimension: side,
            child: Center(child: FmpIcon(icon, size: touch ? 20 : 17)),
          ),
        ),
      ),
    );
  }
}

/// 實心面上的圖示鈕（`.ibtn`）：hover 時填色。
class PlainIconButton extends StatelessWidget {
  const PlainIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.size,
  });

  final FmpIcons icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return ShellButton(
      onTap: onTap,
      tooltip: tooltip,
      label: tooltip,
      builder: (context, hovered) => AnimatedContainer(
        duration: FmpMotion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hovered ? colors.fill : null,
          borderRadius: BorderRadius.circular(size / 2),
        ),
        alignment: Alignment.center,
        child: FmpIcon(icon, size: 18, color: colors.label),
      ),
    );
  }
}

/// 頁面要外殼藏起手機的 dock（導覽、搜尋欄與迷你播放器），讓位給頁面自己
/// 的浮動動作列（搜尋結果多選時，`docs/design/search.html`〈更多與多選〉）。
final dockHiddenProvider = NotifierProvider<DockHidden, bool>(DockHidden.new);

class DockHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool hidden) {
    // 頁面卸載時才還 dock，整個 App 也可能正好一起收掉。
    if (ref.mounted) state = hidden;
  }
}
