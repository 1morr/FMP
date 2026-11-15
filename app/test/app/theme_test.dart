import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:material_ui/material_ui.dart';

/// 主題的 token 對到 `docs/design/DESIGN.md`〈顏色〉〈字體、間距、圓角、動態〉；
/// 期望值抄自設計稿的表（深色的 label-2/3/4 照 `docs/design/assets/fmp.css`）。
void main() {
  ThemeData theme(
    Brightness brightness, {
    Density density = Density.touch,
    Accent accent = Accent.none,
  }) => buildTheme(brightness: brightness, density: density, accent: accent);

  group('dark colors', () {
    final colors = theme(Brightness.dark).extension<FmpColors>()!;

    test('match the neutral and functional tokens', () {
      expect(colors.bg, const Color(0xFF0D0C11));
      expect(colors.cell, const Color(0xFF19181F));
      expect(colors.label, const Color(0xFFF5F4FA));
      expect(colors.label2, const Color.fromRGBO(238, 236, 247, .62));
      expect(colors.sep, const Color.fromRGBO(255, 255, 255, .09));
      expect(colors.danger, const Color(0xFFFF6961));
      expect(colors.scrim, const Color.fromRGBO(0, 0, 0, .5));
      expect(colors.glassPress, const Color.fromRGBO(255, 255, 255, .14));
    });

    test('use a light fill with dark ink when there is no accent', () {
      expect(colors.accent, const Color(0xFFFFFFFF));
      expect(colors.accentFill, const Color(0xFFF5F4FA));
      expect(colors.accentInk, const Color(0xFF15141A));
      expect(colors.accentSoft, const Color.fromRGBO(255, 255, 255, .16));
    });

    test('use the 300 tone for text and the 500 tone for fills', () {
      final violet = theme(
        Brightness.dark,
        accent: Accent.violet,
      ).extension<FmpColors>()!;
      expect(violet.accent, const Color(0xFFA396FF));
      expect(violet.accentFill, const Color(0xFF5E4BFF));
      expect(violet.accentInk, const Color(0xFFFFFFFF));
    });
  });

  group('light colors', () {
    final colors = theme(Brightness.light).extension<FmpColors>()!;

    test('match the neutral and functional tokens', () {
      expect(colors.bg, const Color(0xFFFFFFFF));
      expect(colors.bgGrouped, const Color(0xFFF2F1F6));
      expect(colors.label, const Color(0xFF15141A));
      expect(colors.label3, const Color.fromRGBO(21, 20, 26, .40));
      expect(colors.fill2, const Color.fromRGBO(21, 20, 26, .10));
      expect(colors.ok, const Color(0xFF148A4C));
      expect(colors.scrim, const Color.fromRGBO(20, 16, 40, .28));
      expect(colors.glassSolid, const Color(0xFFF7F6FA));
    });

    test('use the 500 tone for text and fills', () {
      expect(colors.accent, const Color(0xFF15141A));
      expect(colors.accentInk, const Color(0xFFFFFFFF));
      final teal = theme(
        Brightness.light,
        accent: Accent.teal,
      ).extension<FmpColors>()!;
      expect(teal.accent, const Color(0xFF00786F));
      expect(teal.accentFill, const Color(0xFF00786F));
      expect(teal.accentSoft, const Color.fromRGBO(0, 120, 111, .10));
    });
  });

  test('the Material theme follows the tokens', () {
    final dark = theme(Brightness.dark);
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, const Color(0xFF0D0C11));
    expect(dark.colorScheme.onSurface, const Color(0xFFF5F4FA));
    final light = theme(Brightness.light, accent: Accent.indigo);
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.primary, const Color(0xFF3D5BD9));
    expect(light.colorScheme.error, const Color(0xFFE5372B));
  });

  group('text styles', () {
    test('use the phone column on touch', () {
      final text = theme(Brightness.dark).extension<FmpText>()!;
      _expectStyle(text.large, size: 34, line: 41, weight: FontWeight.w700);
      expect(text.large.letterSpacing, closeTo(-0.34, 1e-9));
      _expectStyle(text.head, size: 17, line: 22, weight: FontWeight.w600);
      _expectStyle(text.body, size: 17, line: 22, weight: FontWeight.w400);
      _expectStyle(text.cap2, size: 11, line: 13, weight: FontWeight.w400);
      expect(text.body.letterSpacing ?? 0, 0);
    });

    test('use the desktop column on pointer', () {
      final text = theme(
        Brightness.light,
        density: Density.pointer,
      ).extension<FmpText>()!;
      _expectStyle(text.large, size: 26, line: 32, weight: FontWeight.w700);
      _expectStyle(text.title1, size: 28, line: 34, weight: FontWeight.w700);
      _expectStyle(text.body, size: 14, line: 19, weight: FontWeight.w400);
      _expectStyle(text.cap, size: 11, line: 14, weight: FontWeight.w400);
    });

    test('body is the default text style', () {
      final textTheme = theme(Brightness.dark).textTheme;
      expect(textTheme.bodyMedium!.fontSize, 17);
      expect(textTheme.bodyMedium!.color, const Color(0xFFF5F4FA));
    });
  });

  group('metrics', () {
    test('use the phone values on touch', () {
      final metrics = theme(Brightness.dark).extension<FmpMetrics>()!;
      expect(metrics.minTarget, 44);
      expect(metrics.pagePadding, 16);
      expect(metrics.radii.group, 16);
      expect(metrics.radii.dialog, 26);
      expect(metrics.radii.coverCard, 12);
      expect(metrics.radii.field, 12);
    });

    test('use the desktop values on pointer', () {
      final metrics = theme(
        Brightness.dark,
        density: Density.pointer,
      ).extension<FmpMetrics>()!;
      expect(metrics.minTarget, 28);
      expect(metrics.pagePadding, 32);
      expect(metrics.radii.group, 12);
      expect(metrics.radii.menu, 14);
      expect(metrics.radii.capsule, 999);
      expect(metrics.radii.thumbnail, 6);
    });
  });

  test('spacing is the 4pt grid', () {
    expect(
      [
        FmpSpace.s1,
        FmpSpace.s2,
        FmpSpace.s3,
        FmpSpace.s4,
        FmpSpace.s5,
        FmpSpace.s6,
        FmpSpace.s8,
        FmpSpace.s10,
        FmpSpace.s14,
      ],
      [4, 8, 12, 16, 20, 24, 32, 40, 56],
    );
  });

  test('motion matches the design durations and curves', () {
    expect(FmpMotion.morph, const Duration(milliseconds: 520));
    expect(FmpMotion.morphCurve, const Cubic(.32, .72, 0, 1));
    expect(FmpMotion.springCurve, const Cubic(.32, 1.28, .52, 1));
    expect(FmpMotion.fast, const Duration(milliseconds: 160));
    expect(FmpMotion.mid, const Duration(milliseconds: 280));
    expect(FmpMotion.outCurve, const Cubic(.22, 1, .36, 1));
  });

  testWidgets('a screen reads the tokens from context', (tester) async {
    late FmpColors colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(Brightness.light),
        home: Builder(
          builder: (context) {
            colors = context.fmpColors;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(colors.bg, const Color(0xFFFFFFFF));
  });
}

void _expectStyle(
  TextStyle style, {
  required double size,
  required double line,
  required FontWeight weight,
}) {
  expect(style.fontSize, size);
  expect(style.fontSize! * style.height!, closeTo(line, 1e-9));
  expect(style.fontWeight, weight);
}
