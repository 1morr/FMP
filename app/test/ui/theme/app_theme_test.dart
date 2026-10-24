import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/theme/theme_presets.dart';
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

  group('seed color and font', () {
    ThemeData build({Color? seed, String? font, Brightness? brightness}) =>
        buildAppTheme(
          brightness ?? Brightness.light,
          fontFamilyFallback: const ['CJK A', 'CJK B'],
          textLocale: _hant,
          seedColor: seed,
          fontFamily: font,
        );

    test('a chosen color is the primary itself, as in the legacy theme', () {
      for (final preset in themePresets) {
        for (final brightness in Brightness.values) {
          final theme = build(seed: preset.color, brightness: brightness);
          final scheme = theme.colorScheme;
          expect(scheme.primary, preset.color, reason: preset.id);
          expect(scheme.surfaceTint, preset.color);
          expect(scheme.onPrimary, foregroundColorFor(preset.color));
          expect(
            scheme.primaryContainer,
            Color.alphaBlend(
              preset.color.withValues(
                alpha: brightness == Brightness.light ? 0.18 : 0.32,
              ),
              scheme.surface,
            ),
          );
          expect(
            scheme.onPrimaryContainer,
            foregroundColorFor(scheme.primaryContainer),
          );
          // 其餘角色仍是 fromSeed 的。
          expect(
            scheme.secondary,
            ColorScheme.fromSeed(
              seedColor: preset.color,
              brightness: brightness,
            ).secondary,
          );
        }
      }
    });

    test('a custom color works the same way', () {
      final theme = build(seed: const Color(0xFF336699));
      expect(theme.colorScheme.primary, const Color(0xFF336699));
      expect(theme.colorScheme.onPrimary, Colors.white);
    });

    test('the foreground is black on yellow and white on indigo', () {
      expect(foregroundColorFor(const Color(0xFFF9A825)), Colors.black);
      expect(foregroundColorFor(const Color(0xFF3F51B5)), Colors.white);
      expect(
        build(seed: const Color(0xFFF9A825)).colorScheme.onPrimary,
        Colors.black,
      );
      expect(
        build(seed: const Color(0xFF3F51B5)).colorScheme.onPrimary,
        Colors.white,
      );
    });

    test('tokens are fed by the final scheme', () {
      for (final preset in themePresets) {
        final theme = build(seed: preset.color);
        expect(
          theme.extension<AppTokens>(),
          AppTokens.forScheme(theme.colorScheme),
        );
      }
      final chosen = build(seed: const Color(0xFFBA1A1A));
      expect(
        chosen.extension<AppTokens>()!.focusRingColor,
        const Color(0xFFBA1A1A),
      );
    });

    test('no chosen color is the plain default scheme', () {
      for (final brightness in Brightness.values) {
        final scheme = build(brightness: brightness).colorScheme;
        expect(
          scheme,
          ColorScheme.fromSeed(seedColor: appSeedColor, brightness: brightness),
        );
      }
    });

    test('the default seed is the legacy purple', () {
      expect(appSeedColor, const Color(0xFF6750A4));
      expect(themePresets.first.color, appSeedColor);
      expect(
        build().colorScheme,
        ColorScheme.fromSeed(seedColor: appSeedColor),
      );
    });

    test('a chosen font goes first and the CJK fallback stays after it', () {
      final theme = build(font: 'serif');
      expect(theme.textTheme.bodyMedium?.fontFamily, 'serif');
      expect(theme.textTheme.titleLarge?.fontFamily, 'serif');
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, [
        'CJK A',
        'CJK B',
      ]);
    });

    test('no font leaves the system default', () {
      final theme = build();
      expect(theme.textTheme.bodyMedium?.fontFamily, isNot('serif'));
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, [
        'CJK A',
        'CJK B',
      ]);
    });
  });

  group('legacy component themes', () {
    for (final brightness in Brightness.values) {
      test('$brightness: card, input, list tile, app bar, navigation', () {
        final theme = buildAppTheme(
          brightness,
          fontFamilyFallback: const [],
          textLocale: _hant,
        );
        final scheme = theme.colorScheme;
        expect(theme.appBarTheme.centerTitle, isTrue);
        expect(theme.appBarTheme.backgroundColor, scheme.surface);
        expect(theme.cardTheme.color, scheme.surfaceContainerHighest);
        expect(
          (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(radius.medium),
        );
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(
          theme.inputDecorationTheme.fillColor,
          scheme.surfaceContainerHighest,
        );
        expect(
          (theme.listTileTheme.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(radius.small),
        );
        expect(
          theme.navigationBarTheme.indicatorColor,
          scheme.secondaryContainer,
        );
        expect(
          theme.navigationRailTheme.indicatorColor,
          scheme.secondaryContainer,
        );
        expect(
          theme.navigationDrawerTheme.indicatorColor,
          scheme.secondaryContainer,
        );
        expect(theme.navigationBarTheme.backgroundColor, scheme.surface);
        expect(
          theme.navigationBarTheme.labelBehavior,
          NavigationDestinationLabelBehavior.alwaysShow,
        );
        expect(theme.sliderTheme.activeTrackColor, scheme.primary);
        expect(
          theme.sliderTheme.inactiveTrackColor,
          scheme.surfaceContainerHighest,
        );
        expect(theme.sliderTheme.thumbColor, scheme.primary);
        expect(
          theme.sliderTheme.overlayColor,
          scheme.primary.withValues(alpha: 0.12),
        );
        expect(theme.cardTheme.elevation, 0);
      });
    }
  });

  test('presets are the legacy eight plus the default, with unique ids', () {
    expect(
      [for (final p in themePresets) p.color.toARGB32()],
      [
        0xFF6750A4,
        0xFF3F51B5,
        0xFF0061A4,
        0xFF006A6A,
        0xFF006E1C,
        0xFFF9A825,
        0xFF7C5800,
        0xFFBA1A1A,
        0xFF984061,
      ],
    );
    expect({for (final p in themePresets) p.id}, hasLength(9));
    expect(themePresetOf(const Color(0xFF0061A4))?.id, 'blue');
    expect(themePresetOf(const Color(0xFF0061A5)), isNull);
  });
}

const _hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
