import 'dart:math' as math;

import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 設定頁的群組列表（`.group`／`.gcell`，`docs/design/settings.html`）兩種
/// 密度的尺寸：觸控（手機、平板的窗格）與滑鼠（`.desk`）。
class SettingsStyle {
  const SettingsStyle._({
    required this.touch,
    required this.groupMargin,
    required this.groupRadius,
    required this.groupBorder,
    required this.cellHeight,
    required this.cellPadding,
    required this.cellText,
    required this.cellSmall,
    required this.head,
    required this.headMargin,
    required this.foot,
    required this.footMargin,
  });

  static SettingsStyle of({required bool touch}) => touch ? _touch : _mouse;

  static const _touch = SettingsStyle._(
    touch: true,
    groupMargin: 16,
    groupRadius: 16,
    groupBorder: false,
    cellHeight: 52,
    cellPadding: 16,
    cellText: TextStyle(fontSize: 16, height: 21 / 16, letterSpacing: 0),
    cellSmall: TextStyle(fontSize: 13, height: 17 / 13, letterSpacing: 0),
    head: TextStyle(fontSize: 13, height: 18 / 13, letterSpacing: 0),
    headMargin: EdgeInsets.fromLTRB(32, 28, 32, 7),
    foot: TextStyle(fontSize: 13, height: 18 / 13, letterSpacing: 0),
    footMargin: EdgeInsets.fromLTRB(32, 7, 32, 0),
  );

  static const _mouse = SettingsStyle._(
    touch: false,
    groupMargin: 0,
    groupRadius: 12,
    groupBorder: true,
    cellHeight: 40,
    cellPadding: 12,
    cellText: TextStyle(fontSize: 13, height: 17 / 13, letterSpacing: 0),
    cellSmall: TextStyle(fontSize: 11.5, height: 15 / 11.5, letterSpacing: 0),
    head: TextStyle(
      fontSize: 12,
      height: 18 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    headMargin: EdgeInsets.fromLTRB(4, 22, 4, 6),
    foot: TextStyle(fontSize: 12, height: 18 / 12, letterSpacing: 0),
    footMargin: EdgeInsets.fromLTRB(4, 6, 4, 0),
  );

  final bool touch;

  /// 群組離窗格左右的距離。
  final double groupMargin;
  final double groupRadius;

  /// 滑鼠版的群組有 0.5 的細框（`.desk .group`）。
  final bool groupBorder;
  final double cellHeight;
  final double cellPadding;
  final TextStyle cellText;
  final TextStyle cellSmall;
  final TextStyle head;
  final EdgeInsets headMargin;
  final TextStyle foot;
  final EdgeInsets footMargin;

  /// 列首灰底圖示方塊（`.gicon`）的邊長與圖示大小。
  double get iconBox => touch ? 30 : 22;
  double get iconSize => touch ? 18 : 14;
}

/// 群組上方的小標（`.ghead`）。
class SettingsHead extends StatelessWidget {
  const SettingsHead(this.text, {super.key, required this.style});

  final String text;
  final SettingsStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: style.headMargin,
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: style.head.copyWith(color: context.fmpColors.label2),
      ),
    ),
  );
}

/// 群組下方的說明（`.gfoot`）。
class SettingsFoot extends StatelessWidget {
  const SettingsFoot(this.text, {super.key, required this.style});

  final String text;
  final SettingsStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: style.footMargin,
    child: Text(
      text,
      style: style.foot.copyWith(color: context.fmpColors.label2),
    ),
  );
}

/// 實心的群組（`.group`）：[children] 之間畫細分隔線，從 [separatorInset]
/// 起（有列首圖示時讓到文字下面）。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.style,
    required this.children,
    this.separatorInset,
  });

  final SettingsStyle style;
  final List<Widget> children;

  /// null 時從列的左內距起。
  final double? separatorInset;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final inset = separatorInset ?? style.cellPadding;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: style.groupMargin),
      foregroundDecoration: style.groupBorder
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(style.groupRadius),
              border: Border.all(color: colors.sep, width: .5),
            )
          : null,
      decoration: BoxDecoration(
        color: colors.cell,
        borderRadius: BorderRadius.circular(style.groupRadius),
      ),
      // 不裁切：列的焦點外框畫在列外 2 的地方，裁掉就看不到。列的 hover
      // 底色自己照在群組裡的位置帶圓角（[_GroupSlot]）。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.only(left: inset),
                child: Container(height: .5, color: colors.sep),
              ),
            _GroupSlot(
              radius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? style.groupRadius : 0),
                bottom: Radius.circular(
                  i == children.length - 1 ? style.groupRadius : 0,
                ),
              ),
              child: child,
            ),
          ],
        ],
      ),
    );
  }

  /// 有列首圖示時分隔線的起點（`.st-ic`：手機 58、桌面 46）。
  static double iconInset(SettingsStyle style) =>
      style.cellPadding + style.iconBox + 12;
}

/// 列在群組裡的圓角：第一列上面、最後一列下面跟著群組圓。
class _GroupSlot extends InheritedWidget {
  const _GroupSlot({required this.radius, required super.child});

  final BorderRadius radius;

  static BorderRadius of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GroupSlot>()?.radius ??
      BorderRadius.zero;

  @override
  bool updateShouldNotify(_GroupSlot old) => old.radius != radius;
}

/// 群組裡的一列（`.gcell`）：列首圖示、標題與說明、列尾。[onTap] 給了就整列
/// 可點、鍵盤選得到。
class SettingsCell extends StatelessWidget {
  const SettingsCell({
    super.key,
    required this.style,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected,
  });

  final SettingsStyle style;
  final String title;
  final FmpIcons? icon;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 單選清單的一項：true 時列尾畫勾，螢幕閱讀器讀成已選。
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final radius = _GroupSlot.of(context);
    Widget row(bool hovered) => Container(
      constraints: BoxConstraints(minHeight: style.cellHeight),
      decoration: BoxDecoration(
        color: hovered && !style.touch ? colors.cellHover : null,
        borderRadius: radius,
      ),
      padding: EdgeInsets.symmetric(horizontal: style.cellPadding),
      child: Row(
        children: [
          if (icon case final icon?) ...[
            SettingsIconBox(icon: icon, style: style),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: style.touch ? 11 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: style.cellText.copyWith(color: colors.label),
                  ),
                  if (subtitle case final subtitle?) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: style.cellSmall.copyWith(color: colors.label2),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: 12),
            trailing,
          ],
          if (selected case final selected?) ...[
            const SizedBox(width: 12),
            SizedBox.square(
              dimension: 20,
              child: _SelectionCheck(selected: selected),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row(false);
    return ShellButton(
      onTap: onTap,
      selected: selected ?? false,
      focusRadius: 0,
      builder: (context, hovered) => row(hovered),
    );
  }
}

/// 單選列尾的勾：選中時 spring 長出來並淡入；減少動態效果時只淡入淡出
/// （`DESIGN.md`〈狀態變化對照〉的選取）。
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final motion = FmpMotion.selection(context);
    return AnimatedOpacity(
      opacity: selected ? 1 : 0,
      duration: motion.duration,
      curve: FmpMotion.outCurve,
      child: AnimatedScale(
        scale: selected || FmpMotion.reduced(context) ? 1 : .5,
        duration: motion.duration,
        curve: motion.curve,
        child: FmpIcon(
          FmpIcons.check,
          size: 20,
          color: context.fmpColors.accent,
        ),
      ),
    );
  }
}

/// 列首的灰底圖示方塊（`.gicon.st-gi`）：設定頁的圖示一律中性灰。
class SettingsIconBox extends StatelessWidget {
  const SettingsIconBox({super.key, required this.icon, required this.style});

  final FmpIcons icon;
  final SettingsStyle style;

  @override
  Widget build(BuildContext context) => Container(
    width: style.iconBox,
    height: style.iconBox,
    decoration: BoxDecoration(
      color: context.fmpColors.fill2,
      borderRadius: BorderRadius.circular(style.touch ? 8 : 6),
    ),
    alignment: Alignment.center,
    child: FmpIcon(icon, size: style.iconSize, color: context.fmpColors.label),
  );
}

/// 值換了的時候舊的淡出、新的淡入（`DESIGN.md`〈狀態變化對照〉的內容替換：
/// out 280 交叉淡出，減少動態效果時照樣）。[child] 的 key 要跟著值換。
class SettingsSwap extends StatelessWidget {
  const SettingsSwap({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: FmpMotion.mid,
    switchInCurve: FmpMotion.outCurve,
    switchOutCurve: FmpMotion.outCurve,
    layoutBuilder: (current, previous) =>
        Stack(alignment: alignment, children: [...previous, ?current]),
    child: child,
  );
}

/// 手機列尾的值加上下箭頭（`.gv` 與 `updown`）：點整列就地彈出選單。
class SettingsValue extends StatelessWidget {
  const SettingsValue(this.text, {super.key, required this.style});

  final String text;
  final SettingsStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSwap(
          alignment: Alignment.centerRight,
          child: Text(
            text,
            key: ValueKey(text),
            style: style.cellText.copyWith(color: colors.label2),
          ),
        ),
        const SizedBox(width: 4),
        FmpIcon(
          FmpIcons.updown,
          size: 14,
          strokeWidth: 2.4,
          color: colors.label4,
        ),
      ],
    );
  }
}

/// 點擊區至少多大：觸控 44、滑鼠 28（`DESIGN.md`〈無障礙〉）。
double _minTarget(BuildContext context, bool touch) =>
    touch ? context.fmpMetrics.minTarget : 28;

/// 桌面與平板的彈出選單鈕（`.st-pop`）：目前的值加上下箭頭，看起來 24 高，
/// 點擊區上下補到觸控 44、滑鼠 28。
class SettingsPopupButton extends StatelessWidget {
  const SettingsPopupButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.touch,
  });

  final String label;
  final VoidCallback onTap;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final face = Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
      decoration: BoxDecoration(
        color: colors.fill2,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSwap(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              key: ValueKey(label),
              style: TextStyle(
                fontSize: 12.5,
                height: 1,
                letterSpacing: 0,
                color: colors.label,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FmpIcon(FmpIcons.updown, size: 13, color: colors.label2),
        ],
      ),
    );
    return ShellButton(
      onTap: onTap,
      focusRadius: 7,
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(minHeight: _minTarget(context, touch)),
        child: Center(widthFactor: 1, child: face),
      ),
    );
  }
}

/// 桌面與平板的步進器（`.st-step`）：減、值、加。到了頭尾那一鈕停用。兩鈕
/// 看起來 26×24，點擊區補到觸控 44、滑鼠 28。
class SettingsStepper extends StatelessWidget {
  const SettingsStepper({
    super.key,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.touch,
  });

  final String value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final String decreaseLabel;
  final String increaseLabel;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final target = _minTarget(context, touch);
    Widget button(FmpIcons icon, String label, VoidCallback? onTap) =>
        ShellButton(
          onTap: onTap,
          label: label,
          tooltip: touch ? null : label,
          focusRadius: 7,
          builder: (context, _) => SizedBox.square(
            dimension: target,
            child: Center(
              child: Opacity(
                opacity: onTap == null ? .38 : 1,
                child: FmpIcon(icon, size: 13, color: colors.label2),
              ),
            ),
          ),
        );

    // 點擊區比底色大：底色只畫在中間 24 高、照稿 26 寬的兩鈕加值的範圍。
    final inset = (target - 26) / 2;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          left: inset,
          right: inset,
          child: Center(
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: colors.fill2,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(FmpIcons.minus, decreaseLabel, onDecrease),
            ConstrainedBox(
              // 值的欄照稿 46 寬，扣掉兩鈕點擊區多出來的。
              constraints: BoxConstraints(minWidth: 46 - 2 * inset),
              child: SettingsSwap(
                child: Text(
                  value,
                  key: ValueKey(value),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0,
                    color: colors.label,
                  ).tabular,
                ),
              ),
            ),
            button(FmpIcons.plus, increaseLabel, onIncrease),
          ],
        ),
      ],
    );
  }
}

/// 選中時出現的環（色點、主題預覽圖）：spring 從略小長到原大並淡入；減少動態
/// 效果時只淡入淡出（`DESIGN.md`〈狀態變化對照〉的選取）。
class SelectionRing extends StatelessWidget {
  const SelectionRing({
    super.key,
    required this.selected,
    required this.color,
    required this.width,
    required this.radius,
  });

  final bool selected;
  final Color color;
  final double width;

  /// 環外緣的圓角；圓形給大於短邊一半的值。
  final double radius;

  @override
  Widget build(BuildContext context) {
    final motion = FmpMotion.selection(context);
    final reduced = FmpMotion.reduced(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: selected ? 1 : 0,
        duration: motion.duration,
        curve: FmpMotion.outCurve,
        child: AnimatedScale(
          scale: selected || reduced ? 1 : .85,
          duration: motion.duration,
          curve: motion.curve,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: color, width: width),
            ),
          ),
        ),
      ),
    );
  }
}

/// 強調色的一個色點（`.st-acc`）：選中的外面一圈 2 寬的字色環，離色點 4
/// （稿的 `::after` inset -4 加 2px 陰影）。[labelBelow] 是桌面與平板色點下方
/// 的名字（`.st-accb`）。點擊區至少觸控 44、滑鼠 28；環畫在色點的框外，不佔
/// 版面。
class AccentSwatch extends StatelessWidget {
  const AccentSwatch({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.size,
    required this.touch,
    this.labelBelow,
  });

  final Color color;

  /// 螢幕閱讀器讀的名字。
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double size;
  final bool touch;
  final String? labelBelow;

  /// 色點的點擊框：觸控 44、滑鼠 28。
  static double targetOf(BuildContext context, {required bool touch}) =>
      _minTarget(context, touch);

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final dot = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -6,
            top: -6,
            right: -6,
            bottom: -6,
            child: SelectionRing(
              selected: selected,
              color: colors.label,
              width: 2,
              radius: 999,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: colors.sepStrong, width: .5),
              ),
            ),
          ),
        ],
      ),
    );
    final target = targetOf(context, touch: touch);
    return ShellButton(
      onTap: onTap,
      label: label,
      selected: selected,
      focusRadius: 999,
      builder: (context, _) {
        final hit = SizedBox.square(
          dimension: target,
          child: Center(child: dot),
        );
        final text = labelBelow;
        if (text == null) return hit;
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: target),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              hit,
              // 稿的色點到名字：觸控 8、滑鼠 6，扣掉點擊框比色點多出來的。
              SizedBox(
                height: math.max(0, (touch ? 8 : 6) - (target - size) / 2),
              ),
              ExcludeSemantics(
                child: AnimatedDefaultTextStyle(
                  duration: FmpMotion.mid,
                  curve: FmpMotion.outCurve,
                  style: TextStyle(
                    fontSize: touch ? 12 : 11.5,
                    height: 1.3,
                    letterSpacing: 0,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? colors.label : colors.label2,
                  ),
                  child: Text(text),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
