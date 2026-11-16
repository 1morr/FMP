import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/window_controls.dart';
import 'package:material_ui/material_ui.dart';

/// Windows 的最小化、最大化（還原）、關閉（`docs/design/DESIGN.md`〈桌面〉的
/// Windows 那一點）：各 46×32、圖示 16，貼在視窗右上；外殼只在
/// `WindowChrome.captionButtons` 時放它。
class CaptionButtons extends ConsumerStatefulWidget {
  const CaptionButtons({super.key});

  static const Size buttonSize = Size(46, 32);

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
          right: CaptionButtons.buttonSize.width,
          top: 0,
          size: CaptionButtons.buttonSize,
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
          child: ColoredBox(
            color: fill ?? const Color(0x00000000),
            child: SizedBox.fromSize(
              size: CaptionButtons.buttonSize,
              child: Center(child: FmpIcon(widget.icon, size: 16, color: ink)),
            ),
          ),
        ),
      ),
    );
  }
}
