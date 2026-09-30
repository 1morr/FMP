import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:material_ui/material_ui.dart';

/// WCAG 2 的對比度。
double _contrast(Color a, Color b) {
  final (lighter, darker) = (
    math.max(a.computeLuminance(), b.computeLuminance()),
    math.min(a.computeLuminance(), b.computeLuminance()),
  );
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const spacing = AppSpacing();
  const radius = AppRadius();

  test('spacing is the ADR 0024 scale', () {
    expect(
      [
        spacing.x1,
        spacing.x2,
        spacing.x3,
        spacing.x4,
        spacing.x5,
        spacing.x6,
        spacing.x8,
        spacing.x10,
        spacing.x12,
      ],
      [4, 8, 12, 16, 20, 24, 32, 40, 48],
    );
  });

  test('radii are the M3 shape scale', () {
    expect(
      [
        radius.extraSmall,
        radius.small,
        radius.medium,
        radius.large,
        radius.extraLarge,
      ],
      [4, 8, 12, 16, 28],
    );
  });

  test('the toast is at most 560 wide', () {
    expect(AppLayout.toastMaxWidth, 560);
  });

  for (final brightness in Brightness.values) {
    group('$brightness theme', () {
      final theme = buildAppTheme(
        brightness,
        fontFamilyFallback: const ['A', 'B'],
        textLocale: _hant,
      );
      final tokens = theme.extension<AppTokens>()!;

      test('is Material 3 from the seed and carries the tokens', () {
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, brightness);
        expect(
          theme.colorScheme,
          ColorScheme.fromSeed(seedColor: appSeedColor, brightness: brightness),
        );
        expect(tokens, AppTokens.forScheme(theme.colorScheme));
      });

      test('the focus ring is 2dp of primary, 2dp outside', () {
        expect(tokens.focusRingColor, theme.colorScheme.primary);
        expect(tokens.focusRingWidth, 2);
        expect(tokens.focusRingOffset, 2);
      });

      test('semantic colors pair with enough contrast', () {
        for (final colors in [tokens.success, tokens.warning]) {
          expect(
            _contrast(colors.container, colors.onContainer),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(colors.color, colors.onColor),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      test('every text style gets the font fallback', () {
        final styles = [
          theme.textTheme.bodyMedium,
          theme.textTheme.titleLarge,
          theme.textTheme.labelSmall,
        ];
        for (final style in styles) {
          expect(style?.fontFamilyFallback, ['A', 'B']);
        }
      });

      test('snack bars float', () {
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      });
    });
  }

  // 漢字的繁簡字形跟著樣式的 locale（研究檔 §6）：元件自己的樣式也要從主題
  // 繼承到它，英文字不受影響。
  for (final textLocale in [
    _hant,
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ]) {
    testWidgets('widgets inherit the text locale $textLocale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: buildAppTheme(
            Brightness.light,
            fontFamilyFallback: const [],
            textLocale: textLocale,
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('標題')),
            body: Column(
              children: [
                const Text('內文'),
                const TextField(),
                ElevatedButton(onPressed: () {}, child: const Text('按鈕')),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 0, label: Text('分段'))],
                  selected: const {0},
                  onSelectionChanged: (_) {},
                ),
                const ListTile(title: Text('清單')),
              ],
            ),
          ),
        ),
      );
      Locale? styleLocale(String text) => tester
          .widget<RichText>(
            find.descendant(
              of: find.text(text),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.locale;

      for (final text in ['標題', '內文', '按鈕', '分段', '清單']) {
        expect(styleLocale(text), textLocale, reason: text);
      }
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).style.locale,
        textLocale,
      );
    });
  }

  test('no fonts leaves the fallback to the engine', () {
    final theme = buildAppTheme(
      Brightness.light,
      fontFamilyFallback: const [],
      textLocale: _hant,
    );

    expect(theme.textTheme.bodyMedium?.fontFamilyFallback, isNull);
  });

  test('tokens interpolate between light and dark', () {
    final light = AppTokens.forScheme(
      ColorScheme.fromSeed(seedColor: appSeedColor),
    );
    final dark = AppTokens.forScheme(
      ColorScheme.fromSeed(
        seedColor: appSeedColor,
        brightness: Brightness.dark,
      ),
    );

    expect(light.lerp(dark, 0), light);
    expect(light.lerp(dark, 1), dark);
    expect(light.lerp(null, 0.5), light);
    expect(light.copyWith(), light);
  });

  test('theme modes map one to one', () {
    expect(
      [for (final mode in ThemeModeSetting.values) themeModeOf(mode)],
      [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
    );
  });
}

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
