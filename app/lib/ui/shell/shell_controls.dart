import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:material_ui/material_ui.dart';

/// 外殼裡可點的一塊：滑鼠移上去時 [builder] 拿到 hover，鍵盤與螢幕閱讀器
/// 當成按鈕。
class ShellButton extends StatefulWidget {
  const ShellButton({
    super.key,
    required this.onTap,
    required this.builder,
    this.onLongPress,
    this.label,
    this.selected = false,
    this.tooltip,
    this.focusRadius,
    this.focusInset = false,
    this.hitPadding,
  });

  /// null 時停用：點不了，螢幕閱讀器讀成停用；外觀由 [builder] 自己畫。
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  /// 觸控長按（例如搜尋結果進入多選）；鍵盤沒有對應。
  final VoidCallback? onLongPress;

  /// 給螢幕閱讀器的名字；看得到的文字已經夠時留 null。
  final String? label;
  final bool selected;

  /// 只有圖示時給滑鼠 hover 與長按看的說明。
  final String? tooltip;

  /// 給了就能用鍵盤選到：Tab 移過來時畫焦點外框（[FocusRing]，圓角是這個
  /// 值；圓形與膠囊給 999），Enter 按下（Space 在 App 裡是播放／暫停，見
  /// `PlaybackShortcuts`，不按按鈕；對話框與選單裡照常按，見
  /// [buttonShortcuts]）。null 時鍵盤選不到。
  final double? focusRadius;

  /// 外框畫在框裡面（[FocusRing.inset]），滿版的列表列用。
  final bool focusInset;

  /// 看得到的部分四周補的透明點擊區（`DESIGN.md`〈無障礙〉：觸控 44、滑鼠
  /// 28）：點得到、螢幕閱讀器的框也包含它，焦點外框仍畫在看得到的部分外面。
  final EdgeInsets? hitPadding;

  @override
  State<ShellButton> createState() => _ShellButtonState();
}

class _ShellButtonState extends State<ShellButton> {
  bool _hovered = false;
  bool _focused = false;

  /// 外框只畫在焦點真的在這顆的時候：裡面還有可聚焦的按鈕（例如迷你播放器
  /// 的播放鈕）時，焦點移進去外層就不畫。
  late final _focus = FocusNode(debugLabel: 'ShellButton')
    ..addListener(() {
      if (mounted) setState(() {});
    });

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    Widget child = widget.builder(context, _hovered);
    if (widget.focusRadius case final radius?) {
      child = FocusRing(
        visible: _focused && enabled && _focus.hasPrimaryFocus,
        radius: radius,
        inset: widget.focusInset,
        child: child,
      );
    }
    if (widget.hitPadding case final padding?) {
      child = Padding(padding: padding, child: child);
    }
    child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: child,
    );
    if (widget.focusRadius != null) {
      child = FocusableActionDetector(
        focusNode: _focus,
        shortcuts: buttonShortcuts(context),
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap?.call(),
          ),
        },
        child: child,
      );
    } else {
      child = MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: child,
      );
    }
    // 自成一個節點：直接放在外殼的 Stack 裡時（搜尋圓鈕、詳情面板鈕），不然
    // 名字與點擊會併進外層整個畫面的節點，螢幕閱讀器的框蓋住全螢幕。
    child = Semantics(
      container: true,
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
    this.variant = GlassVariant.regular,
  });

  final FmpIcons icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool touch;

  /// 播放頁的色場上用清玻璃。
  final GlassVariant variant;

  @override
  Widget build(BuildContext context) {
    final side = touch ? 44.0 : 34.0;
    return ShellButton(
      onTap: onTap,
      tooltip: tooltip,
      label: tooltip,
      focusRadius: 999,
      builder: (context, _) => Opacity(
        opacity: onTap == null ? .4 : 1,
        child: Glass(
          variant: variant,
          child: SizedBox.square(
            dimension: side,
            child: Center(child: FmpIcon(icon, size: touch ? 20 : 17)),
          ),
        ),
      ),
    );
  }
}

/// 實心面上的圖示鈕（`.ibtn`）：hover 時填色。[focusable] 時鍵盤選得到、畫
/// 焦點外框（[ShellButton.focusRadius]）。
class PlainIconButton extends StatelessWidget {
  const PlainIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.size,
    this.focusable = false,
  });

  final FmpIcons icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final bool focusable;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return ShellButton(
      onTap: onTap,
      tooltip: tooltip,
      label: tooltip,
      focusRadius: focusable ? 999 : null,
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

/// [width]×[height] 看得到的控制補到點擊區至少 [min] 見方要的透明四周
/// （[ShellButton.hitPadding]）；已經夠大的那一邊不補。
EdgeInsets targetPadding(double width, double height, double min) =>
    EdgeInsets.symmetric(
      horizontal: width < min ? (min - width) / 2 : 0,
      vertical: height < min ? (min - height) / 2 : 0,
    );
