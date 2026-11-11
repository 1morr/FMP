// Experiment (throwaway), M0 ticket 05b: one glass surface per candidate.
// Every variant draws the same shape at the same place, so screenshots and
// frame timings compare like for like.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart' as lge;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

/// Candidate × level. Names are the ids used in results/ and the README.
enum Variant {
  lgwPremium('lgw-premium'),
  lgwStandard('lgw-standard'),
  lgwMinimal('lgw-minimal'),
  lgeLens('lge-lens'),
  lgeLite('lge-lite'),
  ownRefract('own-refract'),
  ownBlur('own-blur'),
  solid('solid');

  const Variant(this.id);
  final String id;

  static Variant byId(String id) => values.firstWhere((v) => v.id == id);
}

/// Loaded once in main(); null when the program failed to load.
ui.FragmentProgram? refractProgram;

// Design tokens (docs/design/DESIGN.md §1.1, §1.4), dark theme.
const _fill = Color.fromRGBO(30, 29, 38, .42);
const _solid = Color(0xFF24232C);

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.variant,
    required this.width,
    required this.height,
    required this.radius,
    required this.child,
  });

  final Variant variant;
  final double width;
  final double height;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: width,
      height: height,
      child: Center(child: child),
    );
    switch (variant) {
      case Variant.lgwPremium:
      case Variant.lgwStandard:
      case Variant.lgwMinimal:
        return lgw.GlassContainer(
          width: width,
          height: height,
          shape: lgw.LiquidRoundedSuperellipse(borderRadius: radius),
          quality: switch (variant) {
            Variant.lgwPremium => lgw.GlassQuality.premium,
            Variant.lgwStandard => lgw.GlassQuality.standard,
            _ => lgw.GlassQuality.minimal,
          },
          useOwnLayer: true,
          // Package defaults are blur 5 / saturation 1.5 / clear fill; match
          // DESIGN.md §1.1 instead (refract pre-blur 5, other glass 16, fill .42).
          settings: lgw.LiquidGlassSettings(
            blur: variant == Variant.lgwPremium ? 5 : 16,
            saturation: 1.8,
            glassColor: _fill.withValues(alpha: variant == Variant.lgwPremium ? .18 : .42),
          ),
          child: content,
        );
      case Variant.lgeLens:
      case Variant.lgeLite:
        return SizedBox(
          width: width,
          height: height,
          child: lge.LiquidGlassLens(
            style: lge.LiquidGlassStyle(
              shape: lge.LiquidGlassShape(cornerRadius: radius),
              blur: variant == Variant.lgeLite ? 16 : 5,
              saturation: 1.8,
              dispersion: 0.4,
              color: _fill.withValues(alpha: .25),
              liteGlass: variant == Variant.lgeLite,
            ),
            child: content,
          ),
        );
      case Variant.ownRefract:
        if (!ui.ImageFilter.isShaderFilterSupported || refractProgram == null) {
          return _decorated(
            fill: _solid,
            child: content,
            label: 'refract unsupported',
          );
        }
        return _OwnRefract(radius: radius, child: _decorated(fill: _fill.withValues(alpha: .18), child: content));
      case Variant.ownBlur:
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.compose(
              outer: _saturate(1.8),
              inner: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            ),
            child: _decorated(fill: _fill, child: content),
          ),
        );
      case Variant.solid:
        return _decorated(fill: _solid, child: content);
    }
  }

  Widget _decorated({required Color fill, required Widget child, String? label}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: .22), width: 1),
        boxShadow: const [
          BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, 10)),
        ],
      ),
      child: label == null
          ? child
          : Stack(alignment: Alignment.center, children: [
              child,
              Text(label, style: const TextStyle(color: Colors.orange, fontSize: 10)),
            ]),
    );
  }
}

/// CSS `saturate(s)` as a colour matrix (W3C filter effects spec).
ui.ColorFilter _saturate(double s) {
  return ui.ColorFilter.matrix(<double>[
    0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
    0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
    0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}

/// BackdropFilter + ImageFilter.shader. The shader needs the glass rect in the
/// filter input's pixel space; we pass the global rect in physical pixels and
/// check the alignment with u_debug (REFRACT_DEBUG=true).
class _OwnRefract extends StatefulWidget {
  const _OwnRefract({required this.radius, required this.child});
  final double radius;
  final Widget child;

  @override
  State<_OwnRefract> createState() => _OwnRefractState();
}

class _OwnRefractState extends State<_OwnRefract> {
  Rect? _global;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r != _global) setState(() => _global = r);
    });
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final g = _global ?? Rect.zero;
    final shortSide = g.shortestSide;
    final shader = refractProgram!.fragmentShader()
      ..setFloat(2, g.left * dpr)
      ..setFloat(3, g.top * dpr)
      ..setFloat(4, g.width * dpr)
      ..setFloat(5, g.height * dpr)
      ..setFloat(6, widget.radius * dpr)
      // DESIGN.md §1.1: edge = min(short × 0.42, 22pt); displacement = min(56, short × 0.6).
      ..setFloat(7, (shortSide * .42).clamp(0, 22) * dpr)
      ..setFloat(8, (shortSide * .6).clamp(0, 56) * dpr * .5)
      ..setFloat(9, const bool.fromEnvironment('REFRACT_DEBUG') ? 1 : 0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: _saturate(1.9),
          inner: ui.ImageFilter.compose(
            outer: ui.ImageFilter.shader(shader),
            inner: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
