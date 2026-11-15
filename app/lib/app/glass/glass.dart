import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass_effect.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as lg;
import 'package:material_ui/material_ui.dart';

export 'package:fmp/app/glass/glass_effect.dart';

/// 「輕量」（standard 級）regular 與 clear 玻璃的模糊值，高斯 sigma（邏輯像素）。
/// 擁有者看過 Windows 的量測後定（票 04，`docs/research/` 的玻璃量測）。
const double standardBlur = 18;

/// 玻璃的三個變體（`docs/design/DESIGN.md`〈三個變體〉）。
enum GlassVariant {
  /// dock、頂列按鈕、側欄、播放膠囊。
  regular,

  /// 播放頁與封面上的按鈕；字固定白，底下要有暗層才讀得清。
  clear,

  /// 承載文字的浮層：選單、sheet、對話框、警示框、提示。不折射，每一級
  /// 都一樣厚（minimal 時一樣是實心）。
  thick,
}

/// 浮在內容上的玻璃（`docs/design/DESIGN.md`〈材質：Liquid Glass〉）。三級都藏在這個元件後面：
/// 折射級是 `liquid_glass_easy` 的 `LiquidGlassLens`，standard 是它的 lite
/// glass，minimal 是自己畫的實心填色（brief〈介面〉）。邊光、頂部光暈與陰影
/// 三級共用，由這裡畫；套件只負責讀 backdrop。
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
    final solidFill = context.fmpColors.glassSolid;
    final ink = variant == GlassVariant.clear
        ? const Color(0xFFFFFFFF)
        : context.fmpColors.glassInk;
    final cornerRadius = radius ?? double.infinity;

    return CustomPaint(
      painter: _ShadowPainter(cornerRadius, palette.shadow),
      child: ClipPath(
        clipper: _RRectClipper(cornerRadius),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, box) => _backdrop(
                  effective,
                  palette,
                  solidFill,
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
              foregroundPainter: _RimPainter(
                cornerRadius,
                palette.rimA,
                palette.rimB,
              ),
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
    _Palette palette,
    Color solidFill,
    double cornerRadius,
    double shortSide,
  ) {
    if (tier == GlassTier.minimal) {
      return ColoredBox(
        color: variant == GlassVariant.clear
            ? const Color.fromRGBO(20, 18, 28, .72)
            : solidFill,
      );
    }
    final shape = lg.LiquidGlassShape.roundedRectangle(
      cornerRadius: cornerRadius,
    );
    final fill = switch (variant) {
      GlassVariant.regular => palette.fill,
      GlassVariant.clear => palette.clearFill,
      GlassVariant.thick => palette.fillStrong,
    };
    if (tier == GlassTier.standard || variant == GlassVariant.thick) {
      // lite glass 沒有飽和度參數，設計稿的 saturate 做不到（票 04 Comments）。
      return lg.LiquidGlassLite(
        shape: shape,
        // 邊光由 _RimPainter 畫，關掉套件自己的。
        borderAlpha: 0,
        blur: variant == GlassVariant.thick ? 28 : standardBlur,
        color: fill,
      );
    }
    // 折射：邊緣寬 min(短邊 × 0.42, 22)，位移量上限 regular 56、clear 70，
    // 紅藍各偏 ±6% 的位移量（DESIGN.md〈構成〉〈三個變體〉）。
    final clear = variant == GlassVariant.clear;
    final displacement = clear
        ? math.min(70, shortSide * 0.75)
        : math.min(56, shortSide * 0.6);
    return lg.LiquidGlassLens(
      style: lg.LiquidGlassStyle(
        shape: shape,
        specular: const lg.LiquidGlassLight.specular(intensity: 0),
        refractionWidth: math.min(shortSide * 0.42, 22),
        dispersion: displacement * 0.06,
        blur: clear ? 0.6 : 5,
        saturation: clear ? 1.5 : 1.9,
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

class _RRectClipper extends CustomClipper<Path> {
  const _RRectClipper(this.radius);

  final double radius;

  @override
  Path getClip(Size size) => Path()..addRRect(_rrect(size, radius));

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

/// 邊光：1px、150° 的斜向漸層，左上最亮、右下次亮、中段透明；外加 0.5px 的
/// 內框線（`.lg::before` 與 `inset 0 0 0 .5px`）。
class _RimPainter extends CustomPainter {
  const _RimPainter(this.radius, this.rimA, this.rimB);

  final double radius;
  final Color rimA;
  final Color rimB;

  static const _angle = 150 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = _rrect(size, radius);
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
      old.radius != radius || old.rimA != rimA || old.rimB != rimB;
}
