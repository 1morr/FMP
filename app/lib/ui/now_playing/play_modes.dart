import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/queue.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 循環的名字：不循環時是「循環」，開著時寫是哪一種。
String repeatLabel(Translations t, Repeat mode) => switch (mode) {
  Repeat.off => t.playMode.repeat.off,
  Repeat.all => t.playMode.repeat.all,
  Repeat.one => t.playMode.repeat.one,
};

/// 循環的圖示：單曲循環是帶 1 的那個。
FmpIcons repeatIcon(Repeat mode) =>
    mode == Repeat.one ? FmpIcons.repeat1 : FmpIcons.repeat;

/// 佇列頁的隨機、循環兩顆切換鈕（`quTogs`）。[glass] 時包在頂列的玻璃膠囊
/// （`.qu-bar`）裡，手機與平板用；否則是實心的兩顆，桌面與窄視窗放在清空
/// 旁邊。開關都直接改佇列，不打斷播放。
class PlayModeToggles extends ConsumerWidget {
  const PlayModeToggles({super.key, required this.glass});

  final bool glass;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final (shuffled, repeat) = ref.watch(
      queueProvider.select((queue) => (queue.shuffled, queue.repeat)),
    );
    final controller = ref.read(queueProvider.notifier);
    final toggles = [
      PlayModeToggle(
        icon: FmpIcons.shuffle,
        label: t.playMode.shuffle,
        on: shuffled,
        glass: glass,
        onTap: controller.toggleShuffle,
      ),
      SizedBox(width: glass ? 2 : 6),
      PlayModeToggle(
        icon: repeatIcon(repeat),
        label: repeatLabel(t, repeat),
        on: repeat != Repeat.off,
        glass: glass,
        onTap: controller.cycleRepeat,
      ),
    ];
    if (!glass) return Row(mainAxisSize: MainAxisSize.min, children: toggles);
    return Glass(
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: toggles),
        ),
      ),
    );
  }
}

/// 帶字的開關鈕（`.tog`，`docs/design/DESIGN.md`〈元件〉）：觸控高 34、
/// 滑鼠高 28；開著是強調實心底，不只靠顏色。[glass] 時關著是透明底、玻璃
/// 上的字色，滑過時 glass-press。
class PlayModeToggle extends StatelessWidget {
  const PlayModeToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.glass,
    required this.onTap,
  });

  final FmpIcons icon;
  final String label;
  final bool on;
  final bool glass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final touch = FormFactor.of(context).density == Density.touch;
    final (height, fontSize, iconSize, left, right) = touch
        ? (34.0, 14.0, 17.0, 11.0, 14.0)
        : (28.0, 12.5, 15.0, 9.0, 12.0);
    return Semantics(
      toggled: on,
      child: ShellButton(
        onTap: onTap,
        focusRadius: 999,
        // 觸控的點擊區補到 44（`DESIGN.md`〈稿內不一致與實作注意〉），
        // 看得到的膠囊照稿 34。
        hitPadding: touch
            ? EdgeInsets.symmetric(vertical: (44 - height) / 2)
            : null,
        builder: (context, hovered) {
          final Color? background;
          final Color foreground;
          if (on) {
            (background, foreground) = (colors.accentFill, colors.accentInk);
          } else if (glass) {
            (background, foreground) = (
              hovered ? colors.glassPress : null,
              colors.glassInk,
            );
          } else {
            (background, foreground) = (colors.fill, colors.label);
          }
          final pill = AnimatedContainer(
            duration: FmpMotion.fast,
            height: height,
            padding: EdgeInsets.only(left: left, right: right),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FmpIcon(icon, size: iconSize, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          );
          return pill;
        },
      ),
    );
  }
}

/// 播放膠囊的隨機或循環圖示鈕（`.transport .ibtn`）：開著用強調色，下面
/// 一個 4 的點（同播放頁 `.pl-dctl .ibtn.on`），沒有強調色時也分得出來。
class PlayModeIconButton extends ConsumerWidget {
  const PlayModeIconButton.shuffle({super.key, required this.touch})
    : _shuffle = true;

  const PlayModeIconButton.repeat({super.key, required this.touch})
    : _shuffle = false;

  final bool _shuffle;

  /// 平板：44 見方、圖示 22；滑鼠 32、圖示 18。
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final controller = ref.read(queueProvider.notifier);
    final FmpIcons icon;
    final String label;
    final bool on;
    final VoidCallback onTap;
    if (_shuffle) {
      on = ref.watch(queueProvider.select((queue) => queue.shuffled));
      (icon, label, onTap) = (
        FmpIcons.shuffle,
        t.playMode.shuffle,
        controller.toggleShuffle,
      );
    } else {
      final repeat = ref.watch(queueProvider.select((queue) => queue.repeat));
      on = repeat != Repeat.off;
      (icon, label, onTap) = (
        repeatIcon(repeat),
        repeatLabel(t, repeat),
        controller.cycleRepeat,
      );
    }
    final size = touch ? 44.0 : 32.0;
    final color = on ? colors.accent : colors.glassInk;
    return Semantics(
      toggled: on,
      child: ShellButton(
        onTap: onTap,
        tooltip: label,
        label: label,
        focusRadius: 999,
        pressScale: FmpMotion.iconPressScale,
        builder: (context, hovered) => AnimatedContainer(
          duration: FmpMotion.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: hovered ? colors.glassPress : null,
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              FmpIcon(icon, size: touch ? 22 : 18, color: color),
              if (on)
                Positioned(
                  bottom: touch ? 6 : 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
