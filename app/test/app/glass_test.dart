import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

/// 玻璃元件的三級、三種變體與「玻璃效果」切換（`docs/design/DESIGN.md`
/// 〈三個變體〉〈三級與平台〉）。級數從畫出來的東西認：折射級是 `LiquidGlassLens`，standard
/// 是 `LiquidGlassLite`，minimal 兩者都沒有、只有實心填色。
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.dark,
  }) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(brightness: brightness, density: Density.touch),
        themeAnimationDuration: Duration.zero,
        home: Center(child: child),
      ),
    ),
  );

  Widget glass({
    Key? key,
    GlassVariant variant = GlassVariant.regular,
    GlassTier? tier,
  }) => Glass(
    key: key,
    variant: variant,
    tier: tier,
    child: const SizedBox(width: 200, height: 56, child: Text('glass')),
  );

  Finder inGlass(Key key, Type type) =>
      find.descendant(of: find.byKey(key), matching: find.byType(type));

  /// 這個實例畫成哪一級。
  GlassTier tierOf(WidgetTester tester, Key key) {
    if (inGlass(key, LiquidGlassLens).evaluate().isNotEmpty) {
      return GlassTier.refract;
    }
    if (inGlass(key, LiquidGlassLite).evaluate().isNotEmpty) {
      return GlassTier.standard;
    }
    return GlassTier.minimal;
  }

  /// minimal 的實心填色。
  Color solidFillOf(WidgetTester tester, Key key) =>
      tester.widget<ColoredBox>(inGlass(key, ColoredBox).first).color;

  const a = Key('a');

  FmpColors colorsOf(Brightness brightness) => buildTheme(
    brightness: brightness,
    density: Density.touch,
  ).extension<FmpColors>()!;

  test('the glass effect starts at full (refract)', () {
    expect(container.read(glassEffectProvider), GlassTier.refract);
  });

  testWidgets('every glass follows the glass effect together', (tester) async {
    const keys = [Key('a'), Key('b'), Key('c')];
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          glass(key: keys[0]),
          glass(key: keys[1], variant: GlassVariant.clear),
          glass(key: keys[2]),
        ],
      ),
    );
    for (final tier in [
      GlassTier.refract,
      GlassTier.standard,
      GlassTier.minimal,
      GlassTier.refract,
    ]) {
      container.read(glassEffectProvider.notifier).set(tier);
      await tester.pump();
      expect([for (final k in keys) tierOf(tester, k)], [tier, tier, tier]);
    }
  });

  testWidgets('an instance can lower its own tier at runtime', (tester) async {
    await pump(tester, glass(key: a, tier: GlassTier.standard));
    expect(tierOf(tester, a), GlassTier.standard);

    await pump(tester, glass(key: a));
    expect(tierOf(tester, a), GlassTier.refract);
  });

  testWidgets('an instance never goes above the glass effect', (tester) async {
    container.read(glassEffectProvider.notifier).set(GlassTier.minimal);
    await pump(tester, glass(key: a, tier: GlassTier.refract));
    expect(tierOf(tester, a), GlassTier.minimal);
  });

  testWidgets('regular glass refracts with a 5 px pre-blur', (tester) async {
    await pump(tester, glass(key: a));
    final style = tester
        .widget<LiquidGlassLens>(inGlass(a, LiquidGlassLens))
        .style;
    expect(style.liteGlass, isFalse);
    expect(style.blur, 5);
    expect(style.saturation, 1.9);
  });

  testWidgets('standard glass blurs by the lite blur value', (tester) async {
    container.read(glassEffectProvider.notifier).set(GlassTier.standard);
    await pump(tester, glass(key: a));
    expect(
      tester.widget<LiquidGlassLite>(inGlass(a, LiquidGlassLite)).blur,
      standardBlur,
    );
  });

  testWidgets('clear glass refracts with a 0.6 px pre-blur', (tester) async {
    await pump(tester, glass(key: a, variant: GlassVariant.clear));
    final style = tester
        .widget<LiquidGlassLens>(inGlass(a, LiquidGlassLens))
        .style;
    expect(style.blur, 0.6);
    expect(style.saturation, 1.5);
  });

  testWidgets('thick glass never refracts and blurs 28 px', (tester) async {
    await pump(tester, glass(key: a, variant: GlassVariant.thick));
    expect(tierOf(tester, a), GlassTier.standard);
    expect(
      tester.widget<LiquidGlassLite>(inGlass(a, LiquidGlassLite)).blur,
      28,
    );
  });

  testWidgets('clear glass bends harder than regular at the same size', (
    tester,
  ) async {
    const b = Key('b');
    await pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          glass(key: a),
          glass(key: b, variant: GlassVariant.clear),
        ],
      ),
    );
    LiquidGlassStyle styleOf(Key key) =>
        tester.widget<LiquidGlassLens>(inGlass(key, LiquidGlassLens)).style;
    expect(styleOf(b).refractionIndex, greaterThan(styleOf(a).refractionIndex));
    expect(styleOf(b).dispersion, greaterThan(styleOf(a).dispersion));
  });

  testWidgets('thick glass stays 28 px thick at standard', (tester) async {
    container.read(glassEffectProvider.notifier).set(GlassTier.standard);
    await pump(tester, glass(key: a, variant: GlassVariant.thick));
    expect(
      tester.widget<LiquidGlassLite>(inGlass(a, LiquidGlassLite)).blur,
      28,
    );
  });

  testWidgets('minimal thick glass is the solid glass colour', (tester) async {
    container.read(glassEffectProvider.notifier).set(GlassTier.minimal);
    await pump(tester, glass(key: a, variant: GlassVariant.thick));
    expect(inGlass(a, BackdropFilter), findsNothing);
    expect(solidFillOf(tester, a), colorsOf(Brightness.dark).glassSolid);
  });

  testWidgets('minimal glass is the solid glass colour', (tester) async {
    container.read(glassEffectProvider.notifier).set(GlassTier.minimal);
    await pump(tester, glass(key: a));
    expect(inGlass(a, BackdropFilter), findsNothing);
    expect(solidFillOf(tester, a), colorsOf(Brightness.dark).glassSolid);

    await pump(tester, glass(key: a), brightness: Brightness.light);
    expect(solidFillOf(tester, a), colorsOf(Brightness.light).glassSolid);
  });

  testWidgets('minimal clear glass is a dark translucent fill', (tester) async {
    container.read(glassEffectProvider.notifier).set(GlassTier.minimal);
    await pump(tester, glass(key: a, variant: GlassVariant.clear));
    expect(solidFillOf(tester, a), const Color.fromRGBO(20, 18, 28, .72));
  });

  testWidgets('text on clear glass is white in light theme too', (
    tester,
  ) async {
    await pump(
      tester,
      glass(key: a, variant: GlassVariant.clear),
      brightness: Brightness.light,
    );
    final text = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('glass'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(text.style.color, const Color(0xFFFFFFFF));
  });

  testWidgets('text on regular glass uses the glass ink', (tester) async {
    await pump(tester, glass(key: a), brightness: Brightness.light);
    final text = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('glass'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(text.style.color, colorsOf(Brightness.light).glassInk);
  });
}
