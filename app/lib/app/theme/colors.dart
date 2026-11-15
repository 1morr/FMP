import 'package:fmp/app/theme/accent.dart';
import 'package:material_ui/material_ui.dart';

const _ink = Color(0xFF15141A);
const _white = Color(0xFFFFFFFF);
const _paper = Color(0xFFF5F4FA);

/// 中性色、功能色與強調色的 token（`docs/design/DESIGN.md`〈顏色〉），深淺色
/// 各一份。畫面讀 `context.fmpColors`，不寫死色值。
///
/// 玻璃的邊光與高光（`--glass-rim-a/b`、`--glass-sheen`）屬於玻璃元件，不在這裡。
@immutable
class FmpColors extends ThemeExtension<FmpColors> {
  const FmpColors({
    required this.bg,
    required this.bgGrouped,
    required this.cell,
    required this.cell2,
    required this.cellHover,
    required this.label,
    required this.label2,
    required this.label3,
    required this.label4,
    required this.sep,
    required this.sepStrong,
    required this.fill,
    required this.fill2,
    required this.danger,
    required this.warn,
    required this.ok,
    required this.scrim,
    required this.glassSolid,
    required this.glassInk,
    required this.glassInk2,
    required this.glassPress,
    required this.accent,
    required this.accentFill,
    required this.accentInk,
    required this.accentSoft,
  });

  factory FmpColors.of(Brightness brightness, Accent accent) =>
      switch (brightness) {
        Brightness.dark => FmpColors(
          bg: const Color(0xFF0D0C11),
          bgGrouped: const Color(0xFF0D0C11),
          cell: const Color(0xFF19181F),
          cell2: const Color(0xFF23222B),
          cellHover: const Color(0xFF22212A),
          label: _paper,
          label2: const Color.fromRGBO(238, 236, 247, .62),
          label3: const Color.fromRGBO(238, 236, 247, .40),
          label4: const Color.fromRGBO(238, 236, 247, .22),
          sep: const Color.fromRGBO(255, 255, 255, .09),
          sepStrong: const Color.fromRGBO(255, 255, 255, .16),
          fill: const Color.fromRGBO(255, 255, 255, .08),
          fill2: const Color.fromRGBO(255, 255, 255, .13),
          danger: const Color(0xFFFF6961),
          warn: const Color(0xFFFFC23D),
          ok: const Color(0xFF42D88A),
          scrim: const Color.fromRGBO(0, 0, 0, .5),
          glassSolid: const Color(0xFF24232C),
          glassInk: _white,
          glassInk2: const Color.fromRGBO(255, 255, 255, .66),
          glassPress: const Color.fromRGBO(255, 255, 255, .14),
          accent: accent.tone300,
          // 無強調色時深色的按鈕底改淺色、字改墨色。
          accentFill: accent == Accent.none ? _paper : accent.tone500,
          accentInk: accent == Accent.none ? _ink : _white,
          accentSoft: accent.softDark,
        ),
        Brightness.light => FmpColors(
          bg: _white,
          bgGrouped: const Color(0xFFF2F1F6),
          cell: _white,
          cell2: const Color(0xFFF2F1F6),
          cellHover: const Color(0xFFF5F4F8),
          label: _ink,
          label2: const Color.fromRGBO(21, 20, 26, .60),
          label3: const Color.fromRGBO(21, 20, 26, .40),
          label4: const Color.fromRGBO(21, 20, 26, .18),
          sep: const Color.fromRGBO(21, 20, 26, .10),
          sepStrong: const Color.fromRGBO(21, 20, 26, .18),
          fill: const Color.fromRGBO(21, 20, 26, .06),
          fill2: const Color.fromRGBO(21, 20, 26, .10),
          danger: const Color(0xFFE5372B),
          warn: const Color(0xFFB87800),
          ok: const Color(0xFF148A4C),
          scrim: const Color.fromRGBO(20, 16, 40, .28),
          glassSolid: const Color(0xFFF7F6FA),
          glassInk: _ink,
          glassInk2: const Color.fromRGBO(21, 20, 26, .62),
          glassPress: const Color.fromRGBO(21, 20, 26, .07),
          accent: accent.tone500,
          accentFill: accent.tone500,
          accentInk: _white,
          accentSoft: accent.softLight,
        ),
      };

  /// 頁面底色；群組列表（設定這類）的襯底是 [bgGrouped]。
  final Color bg;
  final Color bgGrouped;

  /// 實心內容的底；[cell2] 是封面佔位、縮圖底。
  final Color cell;
  final Color cell2;
  final Color cellHover;

  /// 文字：主要，以及次要、第三、第四層。
  final Color label;
  final Color label2;
  final Color label3;
  final Color label4;

  final Color sep;
  final Color sepStrong;
  final Color fill;
  final Color fill2;

  final Color danger;
  final Color warn;
  final Color ok;
  final Color scrim;

  /// 玻璃效果「關閉」與厚玻璃的實心底。
  final Color glassSolid;

  /// 玻璃上的文字、次要文字、按下與選取的底。
  final Color glassInk;
  final Color glassInk2;
  final Color glassPress;

  /// 強調色的文字與圖示、按鈕與開啟中的底、底上的字、tinted 底。
  final Color accent;
  final Color accentFill;
  final Color accentInk;
  final Color accentSoft;

  /// token 只由 [FmpColors.of] 產生，不逐欄覆寫。
  @override
  FmpColors copyWith() => this;

  /// 深淺色切換時 `MaterialApp` 用它做過場。
  @override
  FmpColors lerp(FmpColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return FmpColors(
      bg: l(bg, other.bg),
      bgGrouped: l(bgGrouped, other.bgGrouped),
      cell: l(cell, other.cell),
      cell2: l(cell2, other.cell2),
      cellHover: l(cellHover, other.cellHover),
      label: l(label, other.label),
      label2: l(label2, other.label2),
      label3: l(label3, other.label3),
      label4: l(label4, other.label4),
      sep: l(sep, other.sep),
      sepStrong: l(sepStrong, other.sepStrong),
      fill: l(fill, other.fill),
      fill2: l(fill2, other.fill2),
      danger: l(danger, other.danger),
      warn: l(warn, other.warn),
      ok: l(ok, other.ok),
      scrim: l(scrim, other.scrim),
      glassSolid: l(glassSolid, other.glassSolid),
      glassInk: l(glassInk, other.glassInk),
      glassInk2: l(glassInk2, other.glassInk2),
      glassPress: l(glassPress, other.glassPress),
      accent: l(accent, other.accent),
      accentFill: l(accentFill, other.accentFill),
      accentInk: l(accentInk, other.accentInk),
      accentSoft: l(accentSoft, other.accentSoft),
    );
  }
}
