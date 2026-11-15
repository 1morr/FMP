import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass_effect.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as lg;
import 'package:material_ui/material_ui.dart';

export 'package:fmp/app/glass/glass_effect.dart';

/// 「輕量」（standard 級）regular 與 clear 玻璃的模糊值，高斯 sigma（邏輯像素）。
/// 擁有者看過 Windows 的量測後定；成本和模糊值無關（事實 K21）。
const double standardBlur = 18;

/// 玻璃的三個變體（`docs/design/DESIGN.md`〈三個變體〉）。
enum GlassVariant {
  /// dock、頂列按鈕、側欄、播放膠囊。
  regular(
    _VariantSpec(
      preBlur: 5,
      saturation: 1.9,
      maxDisplacement: 56,
      displacementRatio: 0.6,
      liteBlur: standardBlur,
    ),
  ),

  /// 播放頁與封面上的按鈕；字固定白，底下要有暗層才讀得清。
  clear(
    _VariantSpec(
      preBlur: 0.6,
      saturation: 1.5,
      maxDisplacement: 70,
      // 設計稿 `assets/glass.js` 的 clear：min(70, 短邊 × 0.75)。
      displacementRatio: 0.75,
      liteBlur: standardBlur,
      ink: Color(0xFFFFFFFF),
      minimalFill: Color.fromRGBO(20, 18, 28, .72),
    ),
  ),

  /// 承載文字的浮層：選單、sheet、對話框、警示框、提示。不折射，每一級
  /// 都一樣厚（minimal 時一樣是實心）。
  thick(_VariantSpec(refracts: false, liteBlur: 28));

  const GlassVariant(this._spec);

  final _VariantSpec _spec;
}

/// 一個變體在各級的參數（`docs/design/DESIGN.md`〈構成〉〈三個變體〉）；
/// 填色在 [_Palette]，因為它跟深淺色走。
class _VariantSpec {
  const _VariantSpec({
    this.refracts = true,
    this.preBlur = 0,
    this.saturation = 1,
    this.maxDisplacement = 0,
    this.displacementRatio = 0,
    required this.liteBlur,
    this.ink,
    this.minimalFill,
  });

  /// false 時折射級也畫 lite glass。
  final bool refracts;

  /// 折射級的預模糊與飽和。
  final double preBlur;
  final double saturation;

  /// 位移量 = min([maxDisplacement], 短邊 × [displacementRatio])，設計稿 SVG
  /// `feDisplacementMap` 的 scale。
  final double maxDisplacement;
  final double displacementRatio;

  /// lite glass 的模糊；lite glass 沒有飽和度參數，設計稿的 saturate 做不到
  /// （事實 K21）。
  final double liteBlur;

  /// 固定的字色；null 用主題的玻璃字色。
  final Color? ink;

  /// minimal 的填色；null 用主題的玻璃實心色。
  final Color? minimalFill;

  double displacement(double shortSide) =>
      math.min(maxDisplacement, shortSide * displacementRatio);
}

/// 位移量換成套件的 `refractionIndex`（套件沒有和 SVG 位移量一對一的參數）：
/// 擁有者 M0 看過的 probe（`scripts/experiments/glass/`）在 dock 大小（短邊
/// 約 60、位移量 36）用 1.1，其他位移量照比例。
double _refractionIndex(double displacement) => 1 + 0.1 * displacement / 36;

/// 浮在內容上的玻璃（`docs/design/DESIGN.md`〈材質：Liquid Glass〉）。三級都
/// 藏在這個元件後面：折射級是 `liquid_glass_easy` 的 `LiquidGlassLens`，
/// standard 是它的 lite glass，minimal 是自己畫的實心填色（brief〈介面〉）。
/// 邊光、頂部光暈與陰影三級共用，由這裡畫；套件只負責讀 backdrop。
///
/// 級數跟著 App 的「玻璃效果」（[glassEffectProvider]），[tier] 可以讓這個
/// 實例再往下降。換級時版面不變，只有材質變。大小由 [child] 決定。
class Glass extends ConsumerWidget {
  const Glass({
    super.key,
    this.variant = GlassVariant.regular,
    this.radius,
    this.tier,
    required this.child,
  });

  final GlassVariant variant;

  /// 圓角；null 是膠囊。大於短邊一半時取短邊一半。
  final double? radius;

  /// 這個實例最高到哪一級，例如捲動時降到 standard；null 跟著「玻璃效果」。
  /// 比「玻璃效果」高時取「玻璃效果」。
  final GlassTier? tier;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effective = ref.watch(glassEffectProvider).atMost(tier);
    final palette = _Palette.of(Theme.of(context).brightness);
    final colors = context.fmpColors;
    final spec = variant._spec;
    final ink = spec.ink ?? colors.glassInk;
    final cornerRadius = radius ?? double.infinity;

    return CustomPaint(
      painter: _ShadowPainter(cornerRadius, palette.shadow),
      child: ClipRRect(
        clipper: _RRectClipper(cornerRadius),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) => _backdrop(
                  effective,
                  spec.minimalFill ?? colors.glassSolid,
                  palette.fillOf(variant),
                  _clampRadius(cornerRadius, box.biggest),
                  box.biggest.shortestSide,
                ),
              ),
            ),
            CustomPaint(
              // minimal 關掉頂部光暈（`::after`），邊光與陰影保留。
              painter: effective == GlassTier.minimal
                  ? null
                  : _SheenPainter(cornerRadius, palette.sheen),
              foregroundPainter: _RimPainter(cornerRadius, palette),
              child: IconTheme.merge(
                data: IconThemeData(color: ink),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: ink),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backdrop(
    GlassTier tier,
    Color minimalFill,
    Color fill,
    double cornerRadius,
    double shortSide,
  ) {
    if (tier == GlassTier.minimal) return ColoredBox(color: minimalFill);
    final spec = variant._spec;
    final shape = lg.LiquidGlassShape.roundedRectangle(
      cornerRadius: cornerRadius,
    );
    if (tier == GlassTier.standard || !spec.refracts) {
      return lg.LiquidGlassLite(
        shape: shape,
        // 邊光由 _RimPainter 畫，關掉套件自己的。
        borderAlpha: 0,
        blur: spec.liteBlur,
        color: fill,
      );
    }
    // 邊緣寬 min(短邊 × 0.42, 22)；紅藍各偏 ±6% 的位移量。
    final displacement = spec.displacement(shortSide);
    return lg.LiquidGlassLens(
      style: lg.LiquidGlassStyle(
        shape: shape,
        specular: const lg.LiquidGlassLight.specular(intensity: 0),
        refractionIndex: _refractionIndex(displacement),
        refractionWidth: math.min(shortSide * 0.42, 22),
        dispersion: displacement * 0.06,
        blur: spec.preBlur,
        saturation: spec.saturation,
        color: fill,
      ),
    );
  }
}

/// 玻璃自己的色值（`docs/design/assets/fmp.css` 的 `--glass-*`、
/// `--shadow-float`）；實心底與字色在主題的 [FmpColors]。
class _Palette {
  const _Palette({
    required this.fill,
    required this.fillStrong,
    required this.clearFill,
    required this.rimA,
    required this.rimB,
    required this.sheen,
    required this.shadow,
  });

  static _Palette of(Brightness brightness) => switch (brightness) {
    Brightness.dark => _dark,
    Brightness.light => _light,
  };

  static const _dark = _Palette(
    fill: Color.fromRGBO(30, 29, 38, .42),
    fillStrong: Color.fromRGBO(30, 29, 38, .84),
    clearFill: Color.fromRGBO(255, 255, 255, .10),
    rimA: Color.fromRGBO(255, 255, 255, .55),
    rimB: Color.fromRGBO(255, 255, 255, .10),
    sheen: Color.fromRGBO(255, 255, 255, .10),
    shadow: [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, .45),
        offset: Offset(0, 10),
        blurRadius: 30,
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, .35),
        offset: Offset(0, 2),
        blurRadius: 6,
      ),
    ],
  );

  static const _light = _Palette(
    fill: Color.fromRGBO(255, 255, 255, .46),
    fillStrong: Color.fromRGBO(250, 249, 252, .86),
    clearFill: Color.fromRGBO(255, 255, 255, .16),
    rimA: Color.fromRGBO(255, 255, 255, .95),
    rimB: Color.fromRGBO(255, 255, 255, .35),
    sheen: Color.fromRGBO(255, 255, 255, .35),
    shadow: [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, .14),
        offset: Offset(0, 10),
        blurRadius: 30,
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, .08),
        offset: Offset(0, 2),
        blurRadius: 6,
      ),
    ],
  );

  final Color fill;
  final Color fillStrong;

  Color fillOf(GlassVariant variant) => switch (variant) {
    GlassVariant.regular => fill,
    GlassVariant.clear => clearFill,
    GlassVariant.thick => fillStrong,
  };

  final Color clearFill;
  final Color rimA;
  final Color rimB;
  final Color sheen;
  final List<BoxShadow> shadow;
}

double _clampRadius(double radius, Size size) =>
    math.min(radius, size.shortestSide / 2);

RRect _rrect(Size size, double radius) => RRect.fromRectAndRadius(
  Offset.zero & size,
  Radius.circular(_clampRadius(radius, size)),
);

class _RRectClipper extends CustomClipper<RRect> {
  const _RRectClipper(this.radius);

  final double radius;

  @override
  RRect getClip(Size size) => _rrect(size, radius);

  @override
  bool shouldReclip(_RRectClipper oldClipper) => oldClipper.radius != radius;
}

/// `--shadow-float`。像 CSS 的 box-shadow 一樣只畫在外面：半透明的玻璃底下
/// 不能透出自己的陰影，backdrop 也不能讀到它。
class _ShadowPainter extends CustomPainter {
  const _ShadowPainter(this.radius, this.shadows);

  final double radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = _rrect(size, radius);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect((Offset.zero & size).inflate(100))
          ..addRRect(rrect),
      );
    for (final shadow in shadows) {
      canvas.drawRRect(
        rrect.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) =>
      old.radius != radius || old.shadows != shadows;
}

/// 頂部光暈：`radial-gradient(120% 70% at 30% -10%, sheen, transparent 60%)`。
class _SheenPainter extends CustomPainter {
  const _SheenPainter(this.radius, this.color);

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas
      ..save()
      ..clipRRect(_rrect(size, radius))
      ..translate(size.width * .3, -size.height * .1)
      ..scale(size.width * 1.2, size.height * .7)
      ..drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            1,
            [color, color.withValues(alpha: 0)],
            [0, .6],
          ),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_SheenPainter old) =>
      old.radius != radius || old.color != color;
}

/// 邊光：1px、150° 的斜向漸層，左上最亮、右下次亮、中段透明（`.lg::before`）；
/// 外加 0.5px 的內框線與頂部 1px 的內緣高光（`docs/design/assets/fmp.css` 的
/// `.lg` box-shadow：`inset 0 0 0 .5px`、`inset 0 1px 1px var(--glass-sheen)`）。
class _RimPainter extends CustomPainter {
  const _RimPainter(this.radius, this.palette);

  final double radius;
  final _Palette palette;

  static const _angle = 150 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = _rrect(size, radius);
    // 內緣高光：形狀外面往下 1px 的影子，只留在形狀裡面的部分。
    canvas
      ..save()
      ..clipRRect(rrect)
      ..drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect((Offset.zero & size).inflate(4))
          ..addRRect(rrect.shift(const Offset(0, 1))),
        Paint()
          ..color = palette.sheen
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            Shadow.convertRadiusToSigma(1),
          ),
      )
      ..restore();
    canvas.drawRRect(
      rrect.deflate(.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5
        ..color = const Color.fromRGBO(255, 255, 255, .06),
    );
    // CSS 的漸層線：過中心、沿角度方向，長度讓兩個角剛好落在 0% 與 100%。
    final direction = Offset(math.sin(_angle), -math.cos(_angle));
    final half =
        ((size.width * math.sin(_angle)).abs() +
            (size.height * math.cos(_angle)).abs()) /
        2;
    final center = size.center(Offset.zero);
    final (rimA, rimB) = (palette.rimA, palette.rimB);
    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          center - direction * half,
          center + direction * half,
          [rimA, rimB, rimB.withValues(alpha: 0), rimB, rimA],
          [0, .28, .52, .78, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || !identical(old.palette, palette);
}
