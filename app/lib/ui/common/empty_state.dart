import 'dart:math' as math;

import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

/// 全 App 共用的空狀態（`docs/design/DESIGN.md`〈空狀態〉）：72 的圓角方塊
/// （圓角 22、`fill` 底、圖示 34、`label-2`）、標題、選用的說明與動作。
///
/// 是一個 sliver，放在頁面捲動區的頁首後面。圖示不跟著頁首多高走，而是排在
/// 離內容頂端（[ShellInsets] 的上緣，大標題開始的地方）固定的距離
/// （[topOf]），換頁時圖示不動；頁首比那裡高時至少離它 [minGap]。標題的
/// 字級照各頁的稿（[titleStyle]）。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.titleStyle,
    this.body,
    this.action,
    this.iconStrokeWidth = 1.8,
  });

  /// 圓角方塊，測試用來量位置與形狀。
  static const iconKey = Key('empty-state-icon');

  /// 圖示頂端離內容頂端的距離：取搜尋頁的頁首（手機是大標題、中寬度是頂端
  /// 的搜尋欄、桌面寬版是「…的搜尋結果」，都再加音源篩選列，是最高的頁首）
  /// 底下再留 120。觸控的篩選列高 44，所以觸控（手機、平板、13 吋 iPad）
  /// 一個值；桌面依中寬度、寬版的頁首各一個值。
  static double topOf(FormFactor form) => switch (form) {
    FormFactor(density: Density.touch) => 215,
    FormFactor(widthClass: WidthClass.wide) => 200,
    _ => 194,
  };

  /// 頁首比 [topOf] 還高時，圖示離頁首至少這麼遠。
  static const minGap = 40.0;

  final FmpIcons icon;
  final String title;

  /// 沒給時是 `title3`。
  final TextStyle? titleStyle;
  final String? body;

  /// 說明下面的按鈕。
  final Widget? action;

  /// 稿上個別圖示調細的線寬（例如佇列的 1.6）；預設同 [FmpIcon]。
  final double iconStrokeWidth;

  @override
  Widget build(BuildContext context) {
    final top = ShellInsets.of(context).top + topOf(FormFactor.of(context));
    return SliverLayoutBuilder(
      // 前面的 sliver（含捲動區上方讓出的高度）佔掉的長度就是頁首底部離
      // 捲動區頂端多遠，和現在捲到哪裡無關。
      builder: (context, constraints) => SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            40,
            math.max(minGap, top - constraints.precedingScrollExtent),
            40,
            0,
          ),
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 稿：方塊 margin-bottom 10＋flex gap 8。
        DecoratedBox(
          key: iconKey,
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(22),
          ),
          child: SizedBox.square(
            dimension: 72,
            child: Center(
              child: FmpIcon(
                icon,
                size: 34,
                strokeWidth: iconStrokeWidth,
                color: colors.label2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: (titleStyle ?? text.title3).copyWith(color: colors.label),
        ),
        if (body case final body?) ...[
          const SizedBox(height: FmpSpace.s2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: text.sub.copyWith(color: colors.label2),
          ),
        ],
        // 稿（佇列）：flex gap 8＋按鈕組 margin-top 18。
        if (action case final action?) ...[const SizedBox(height: 26), action],
      ],
    );
  }
}
