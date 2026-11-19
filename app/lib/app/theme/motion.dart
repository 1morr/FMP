import 'package:material_ui/material_ui.dart';

/// 動態的時長與曲線（`docs/design/DESIGN.md`〈動態〉）。
abstract final class FmpMotion {
  /// sheet 升起、播放頁左右滑換畫面。
  static const morph = Duration(milliseconds: 520);
  static const morphCurve = Cubic(.32, .72, 0, 1);

  /// 選取膠囊滑動與拉長、開關、播放頁頁面點點。
  static const spring = Duration(milliseconds: 520);
  static const springCurve = Cubic(.32, 1.28, .52, 1);

  /// hover、顏色（[fast]）與明暗翻轉（[mid]）。
  static const fast = Duration(milliseconds: 160);
  static const mid = Duration(milliseconds: 280);
  static const outCurve = Cubic(.22, 1, .36, 1);

  /// 系統開了「減少動態效果」（`docs/design/DESIGN.md`〈狀態變化對照〉：讀它
  /// 只經一個共用入口）。
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// 選取、開關的動法：spring；減少動態效果時 out 280、不彈跳。曲線會超過 1，
  /// 只給位置、大小這類能超出的值，透明度用 [outCurve]。
  static ({Duration duration, Curve curve}) selection(BuildContext context) =>
      reduced(context)
      ? (duration: mid, curve: outCurve)
      : (duration: spring, curve: springCurve);

  /// 按下時按鈕與圖示鈕縮放到的比例。
  static const pressScale = 0.96;
  static const iconPressScale = 0.92;
}
