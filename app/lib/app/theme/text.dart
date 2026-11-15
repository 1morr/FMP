import 'package:fmp/platform/form_factor.dart';
import 'package:material_ui/material_ui.dart';

/// 字級（`docs/design/DESIGN.md`〈字體〉）：觸控用手機那一欄（iOS 文字樣式），
/// 滑鼠用桌面那一欄。不指定字型，用各平台的系統字；不帶顏色，顏色跟著
/// `DefaultTextStyle` 或由畫面從 `FmpColors` 給。
@immutable
class FmpText extends ThemeExtension<FmpText> {
  const FmpText({
    required this.large,
    required this.title1,
    required this.title2,
    required this.title3,
    required this.head,
    required this.body,
    required this.callout,
    required this.sub,
    required this.foot,
    required this.cap,
    required this.cap2,
  });

  factory FmpText.of(Density density) {
    final touch = density == Density.touch;
    return FmpText(
      large: touch ? _display(34, 41) : _display(26, 32),
      title1: _display(28, 34),
      title2: touch ? _display(22, 28) : _display(19, 24),
      title3: _style(20, 25, FontWeight.w600),
      head: touch
          ? _style(17, 22, FontWeight.w600)
          : _style(14, 18, FontWeight.w600),
      body: touch ? _style(17, 22) : _style(14, 19),
      callout: _style(16, 21),
      sub: touch ? _style(15, 20) : _style(13, 17),
      foot: touch ? _style(13, 18) : _style(12, 16),
      cap: touch ? _style(12, 16) : _style(11, 14),
      cap2: _style(11, 13),
    );
  }

  /// 頁面標題。
  final TextStyle large;
  final TextStyle title1;
  final TextStyle title2;
  final TextStyle title3;

  /// 列表標題、對話框標題。
  final TextStyle head;

  /// 內文，也是預設的文字樣式。
  final TextStyle body;
  final TextStyle callout;
  final TextStyle sub;
  final TextStyle foot;
  final TextStyle cap;
  final TextStyle cap2;

  /// token 只由 [FmpText.of] 產生，不逐欄覆寫。
  @override
  FmpText copyWith() => this;

  @override
  FmpText lerp(FmpText? other, double t) {
    if (other == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return FmpText(
      large: l(large, other.large),
      title1: l(title1, other.title1),
      title2: l(title2, other.title2),
      title3: l(title3, other.title3),
      head: l(head, other.head),
      body: l(body, other.body),
      callout: l(callout, other.callout),
      sub: l(sub, other.sub),
      foot: l(foot, other.foot),
      cap: l(cap, other.cap),
      cap2: l(cap2, other.cap2),
    );
  }
}

/// [size]/[line] 照設計稿的「字級/行高」寫；letter-spacing 明寫 0，蓋掉
/// Material 預設字級表的字距。
TextStyle _style(
  double size,
  double line, [
  FontWeight weight = FontWeight.w400,
]) => TextStyle(
  fontSize: size,
  height: line / size,
  fontWeight: weight,
  letterSpacing: 0,
);

/// 大標題與 title1／2：Bold、letter-spacing -0.01em。
TextStyle _display(double size, double line) =>
    _style(size, line, FontWeight.w700).copyWith(letterSpacing: -0.01 * size);

/// 數字用等寬字（`font-variant-numeric: tabular-nums`），時長、進度這類
/// 會跳動的數字才不會左右晃。
extension TabularFigures on TextStyle {
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
