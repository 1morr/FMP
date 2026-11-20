import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/platform/window_controls.dart';
import 'package:fmp/ui/common/inert.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// Windows 的最小化、最大化（還原）、關閉（`docs/design/DESIGN.md`〈桌面〉的
/// Windows 那一點）：各 [WindowChrome.captionButtonSize]、圖示 16，貼在視窗
/// 右上；外殼只在 [WindowChrome.captionButtons] 時放它。
///
/// 中寬度另有第四顆「顯示詳情面板」（[onShowDetail]），同款平面鈕，緊貼在
/// 最小化左邊；面板打開時淡出（[showDetailVisible]），位置留著。
class CaptionButtons extends ConsumerStatefulWidget {
  const CaptionButtons({
    super.key,
    this.onShowDetail,
    this.showDetailVisible = true,
  });

  /// 叫出詳情面板；null 時沒有第四顆（寬版的叫出鈕在頂列）。
  final VoidCallback? onShowDetail;
  final bool showDetailVisible;

  @override
  ConsumerState<CaptionButtons> createState() => _CaptionButtonsState();
}

class _CaptionButtonsState extends ConsumerState<CaptionButtons> {
  @override
  void initState() {
    super.initState();
    // 三顆鈕貼在視窗右上，最大化鈕的右緣離視窗右緣一顆鈕寬。
    ref
        .read(windowControlsProvider.notifier)
        .reportMaximizeButton(
          right: WindowChrome.captionButtonSize.width,
          top: 0,
          size: WindowChrome.captionButtonSize,
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t.shell.window;
    final window = ref.watch(windowControlsProvider);
    final controls = ref.read(windowControlsProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onShowDetail case final onShowDetail?)
          _ShowDetailButton(
            onTap: onShowDetail,
            visible: widget.showDetailVisible,
          ),
        CaptionButton(
          icon: FmpIcons.minus,
          label: t.minimize,
          onTap: controls.minimize,
        ),
        // 滑鼠在這顆上時是 Windows 在處理（Snap Layouts），點擊也由原生端
        // 做；Flutter 只照它回報的狀態畫。onTap 是 Windows 沒接手時的退路。
        CaptionButton(
          icon: window.maximized
              ? FmpIcons.windowRestore
              : FmpIcons.windowMaximize,
          label: window.maximized ? t.restore : t.maximize,
          onTap: controls.toggleMaximize,
          hovered: window.maximizeHovered,
          pressed: window.maximizePressed,
        ),
        CaptionButton(
          icon: FmpIcons.close,
          label: t.close,
          onTap: controls.close,
          destructive: true,
        ),
      ],
    );
  }
}

/// 一顆視窗鈕。hover 與按下的樣子照 Windows 11 的視窗鈕：最小化、最大化
/// 填淡色，關閉填紅底白圖示。[hovered]、[pressed] 是外面（Windows）說的
/// 狀態，和 Flutter 自己看到的取聯集。
class CaptionButton extends StatefulWidget {
  const CaptionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.hovered = false,
    this.pressed = false,
    this.destructive = false,
  });

  final FmpIcons icon;
  final String label;
  final VoidCallback onTap;
  final bool hovered;
  final bool pressed;

  /// 關閉鈕：hover 時紅底。
  final bool destructive;

  /// Windows 11 關閉鈕的紅（WinUI 的 `CloseButtonBackgroundPointerOver`）。
  static const _closeRed = Color(0xFFC42B1C);

  @override
  State<CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final hovered = widget.hovered || _hovered;
    final pressed = widget.pressed || _pressed;
    final Color? fill;
    final Color ink;
    if (widget.destructive && (hovered || pressed)) {
      fill = pressed
          ? CaptionButton._closeRed.withValues(alpha: .9)
          : CaptionButton._closeRed;
      ink = const Color(0xFFFFFFFF);
    } else {
      fill = pressed
          ? colors.fill2
          : hovered
          ? colors.fill
          : null;
      ink = colors.label2;
    }
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: FmpMotion.fast,
            width: WindowChrome.captionButtonSize.width,
            height: WindowChrome.captionButtonSize.height,
            color: fill ?? const Color(0x00000000),
            alignment: Alignment.center,
            child: FmpIcon(widget.icon, size: 16, color: ink),
          ),
        ),
      ),
    );
  }
}

/// 視窗鈕列的「顯示詳情面板」：外觀同 [CaptionButton]（46×32、圖示 16、hover
/// 整格填淡色、按下填深一點），但和頂列其他控制項一樣 Tab 走得到、有焦點外框
/// （貼著視窗頂端，外框畫在格子裡面）與 tooltip。面板打開時淡出（out 280，
/// 減少動態效果時照樣淡出，見 [AnimationBehavior.preserve]），淡出時點不到、
/// Tab 不到。
class _ShowDetailButton extends StatefulWidget {
  const _ShowDetailButton({required this.onTap, required this.visible});

  final VoidCallback onTap;
  final bool visible;

  @override
  State<_ShowDetailButton> createState() => _ShowDetailButtonState();
}

class _ShowDetailButtonState extends State<_ShowDetailButton>
    with SingleTickerProviderStateMixin {
  // 不用 AnimatedOpacity：它的 controller 在減少動態效果時縮成 1/20，等於
  // 直接消失；稿上小元件這時仍要淡入淡出。
  late final _fade = AnimationController(
    vsync: this,
    duration: FmpMotion.mid,
    value: widget.visible ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final _opacity = CurvedAnimation(
    parent: _fade,
    curve: FmpMotion.outCurve,
  );
  bool _pressed = false;

  @override
  void didUpdateWidget(_ShowDetailButton old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      widget.visible ? _fade.forward() : _fade.reverse();
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final label = context.t.shell.detail.show;
    return FadeTransition(
      opacity: _opacity,
      child: Inert(
        inert: !widget.visible,
        child: Listener(
          onPointerDown: (_) => _press(true),
          onPointerUp: (_) => _press(false),
          onPointerCancel: (_) => _press(false),
          child: ShellButton(
            onTap: widget.onTap,
            tooltip: label,
            label: label,
            focusRadius: 0,
            focusInset: true,
            builder: (context, hovered) => AnimatedContainer(
              duration: FmpMotion.fast,
              width: WindowChrome.captionButtonSize.width,
              height: WindowChrome.captionButtonSize.height,
              color: _pressed
                  ? colors.fill2
                  : hovered
                  ? colors.fill
                  : const Color(0x00000000),
              alignment: Alignment.center,
              child: FmpIcon(FmpIcons.sidebarR, size: 16, color: colors.label2),
            ),
          ),
        ),
      ),
    );
  }
}
