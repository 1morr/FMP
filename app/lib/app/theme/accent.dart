import 'package:material_ui/material_ui.dart';

/// 強調色（`docs/design/DESIGN.md`〈強調色〉）：預設無，設定的「外觀」可選
/// 一個。只用在主要動作、選取與開啟中的狀態、正在播放、連結。
enum Accent {
  none(
    tone500: Color(0xFF15141A),
    tone300: Color(0xFFFFFFFF),
    softDark: Color.fromRGBO(255, 255, 255, .16),
    softLight: Color.fromRGBO(21, 20, 26, .08),
  ),
  violet(
    tone500: Color(0xFF5E4BFF),
    tone300: Color(0xFFA396FF),
    softDark: Color.fromRGBO(124, 107, 255, .22),
    softLight: Color.fromRGBO(94, 75, 255, .12),
  ),
  indigo(
    tone500: Color(0xFF3D5BD9),
    tone300: Color(0xFF8EA6FF),
    softDark: Color.fromRGBO(110, 138, 255, .22),
    softLight: Color.fromRGBO(61, 91, 217, .11),
  ),
  teal(
    tone500: Color(0xFF00786F),
    tone300: Color(0xFF5AD4C8),
    softDark: Color.fromRGBO(90, 212, 200, .18),
    softLight: Color.fromRGBO(0, 120, 111, .10),
  );

  const Accent({
    required this.tone500,
    required this.tone300,
    required this.softDark,
    required this.softLight,
  });

  /// 淺色的文字與圖示、兩種外觀的按鈕底（白字 ≥ 5:1）。
  final Color tone500;

  /// 深色的文字與圖示、播放頁（媒體）上的強調色。
  final Color tone300;

  /// tinted 按鈕、文字選取的底，深淺各一。
  final Color softDark;
  final Color softLight;
}
