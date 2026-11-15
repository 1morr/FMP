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

  /// 按下時按鈕與圖示鈕縮放到的比例。
  static const pressScale = 0.96;
  static const iconPressScale = 0.92;
}
