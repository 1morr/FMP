import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/ui/common/focus_ring.dart';
import 'package:material_ui/material_ui.dart';

/// 按鈕的變體（`docs/design/DESIGN.md`〈按鈕〉）。
enum FmpButtonVariant {
  /// 強調底，一個畫面最多一顆。
  primary,

  /// 強調色 12% 的底。
  tinted,
  gray,

  /// 破壞性動作：danger 色 14% 的底。
  danger,
}

enum FmpButtonSize {
  /// `.btn`：手機 44、桌面 32。
  normal,

  /// `.btn-sm`：手機 32、桌面 28。
  small,
}

/// 帶字的膠囊按鈕（`.btn`）。尺寸與字級跟密度走；[onTap] 為 null 時停用
/// （38% 透明、點不了）。[height] 蓋掉預設的高，警示框的按鈕用。
class FmpButton extends StatefulWidget {
  const FmpButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = FmpButtonVariant.gray,
    this.size = FmpButtonSize.normal,
    this.icon,
    this.height,
    this.touchTarget = false,
  });

  final String label;
  final VoidCallback? onTap;
  final FmpButtonVariant variant;
  final FmpButtonSize size;
  final FmpIcons? icon;
  final double? height;

  /// 觸控時把點擊區上下補到 44，看得到的膠囊照原本的高（`DESIGN.md`
  /// 〈稿內不一致與實作注意〉第 2 點：`.btn-sm` 32）。
  final bool touchTarget;

  @override
  State<FmpButton> createState() => _FmpButtonState();
}

class _FmpButtonState extends State<FmpButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final touch = FormFactor.of(context).density == Density.touch;
    final small = widget.size == FmpButtonSize.small;
    final enabled = widget.onTap != null;
    final (height, fontSize, padding) = switch ((touch, small)) {
      (true, false) => (44.0, 16.0, 20.0),
      (true, true) => (32.0, 14.0, 14.0),
      (false, false) => (32.0, 13.0, 14.0),
      (false, true) => (28.0, 12.5, 12.0),
    };
    final (background, foreground) = switch (widget.variant) {
      FmpButtonVariant.primary => (colors.accentFill, colors.accentInk),
      FmpButtonVariant.tinted => (colors.accentSoft, colors.accent),
      FmpButtonVariant.gray => (
        _hovered && enabled ? colors.fill2 : colors.fill,
        colors.label,
      ),
      FmpButtonVariant.danger => (
        colors.danger.withValues(alpha: .14),
        colors.danger,
      ),
    };
    // 鍵盤選得到：Tab 移過來畫焦點外框，Enter 按下（`DESIGN.md`〈無障礙〉；
    // Space 在 App 裡是播放／暫停，見 `PlaybackShortcuts`）。
    return Semantics(
      button: true,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap?.call(),
          ),
        },
        child: FocusRing(
          visible: _focused && enabled,
          radius: 999,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: _padded(
              context,
              touch,
              Opacity(
                opacity: enabled ? 1 : .38,
                child: AnimatedScale(
                  scale: _pressed ? FmpMotion.pressScale : 1,
                  duration: FmpMotion.fast,
                  curve: FmpMotion.outCurve,
                  child: AnimatedContainer(
                    duration: FmpMotion.fast,
                    height: widget.height ?? height,
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon case final icon?) ...[
                          FmpIcon(
                            icon,
                            size: small ? 16 : 20,
                            color: foreground,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                              color: foreground,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `touchTarget` 時觸控的點擊區上下補到 44。
  Widget _padded(BuildContext context, bool touch, Widget child) {
    if (!touch || !widget.touchTarget) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: context.fmpMetrics.minTarget),
      child: Center(widthFactor: 1, child: child),
    );
  }
}
