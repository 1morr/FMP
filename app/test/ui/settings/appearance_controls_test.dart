import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/settings/custom_color_dialog.dart';
import 'package:fmp/ui/theme/theme_presets.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

const _fonts = ['serif', 'monospace'];

void main() {
  Future<ShellHarness> openAppearance(WidgetTester tester) async {
    final h = ShellHarness(fontChoices: _fonts);
    await h.pumpShell(tester, size: const Size(1000, 900), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
    await h.loadSettings(tester);
    expect(find.byType(AppearanceControls), findsOneWidget);
    return h;
  }

  Future<AppearanceSettings> stored(
    WidgetTester tester,
    ShellHarness h,
  ) async => (await tester.runAsync(
    () => h.container(tester).read(appearanceSettingsRepositoryProvider).read(),
  ))!;

  Future<void> settle(WidgetTester tester, ShellHarness h) async {
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('shows nine presets plus custom, with the default selected', (
    tester,
  ) async {
    await openAppearance(tester);

    for (final name in [
      'Default purple',
      'Indigo',
      'Ocean blue',
      'Teal',
      'Forest green',
      'Sun yellow',
      'Amber orange',
      'Ruby red',
      'Rose pink',
      'Custom',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where(
          (s) => s.properties.selected == true && s.properties.button == true,
        )
        .map((s) => s.properties.label);
    expect(selected, contains('Default purple'));
    expect(selected, isNot(contains('Custom')));
  });

  testWidgets('picking a preset stores its color, the default clears it', (
    tester,
  ) async {
    final h = await openAppearance(tester);

    await tester.tap(find.text('Ocean blue'));
    await settle(tester, h);
    expect((await stored(tester, h)).seedColor, const Color(0xFF0061A4));
    // 主題跟著換。
    final theme = Theme.of(tester.element(find.byType(AppearanceControls)));
    expect(theme.colorScheme.primary, const Color(0xFF0061A4));

    // 預設色寫回「沒設定過」，不是存一個值。
    await tester.tap(find.text('Default purple'));
    await settle(tester, h);
    expect((await stored(tester, h)).seedColor, isNull);
  });

  testWidgets('a custom color from the dialog is stored and selected', (
    tester,
  ) async {
    final h = await openAppearance(tester);

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('Custom theme color'), findsOneWidget);

    // 不合法的色碼擋住「套用」。
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    expect(find.text('Enter 6 hex digits, for example 6750A4'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), '#336699');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await settle(tester, h);

    expect((await stored(tester, h)).seedColor, const Color(0xFF336699));
    final selected = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where(
          (s) => s.properties.selected == true && s.properties.button == true,
        )
        .map((s) => s.properties.label);
    expect(selected, contains('Custom'));
  });

  testWidgets('cancelling the custom dialog changes nothing', (tester) async {
    final h = await openAppearance(tester);

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester, h);

    expect((await stored(tester, h)).seedColor, isNull);
  });

  testWidgets('the sliders and the hex field stay in step', (tester) async {
    await openAppearance(tester);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    // 預設紫起頭。
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '6750A4',
    );
    // 把明度拉到最低：色碼變黑。
    final value = find.byType(Slider).last;
    await tester.drag(value, const Offset(-2000, 0));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '000000',
    );
  });

  testWidgets('the font list is the platform choices, default first', (
    tester,
  ) async {
    final h = await openAppearance(tester);

    expect(find.text('Default font'), findsOneWidget);
    expect(find.text('Serif'), findsOneWidget);
    expect(find.text('Monospace'), findsOneWidget);
    expect(
      tester
          .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
          .groupValue,
      isNull,
    );

    await tester.tap(find.text('Serif'));
    await settle(tester, h);
    expect((await stored(tester, h)).fontFamily, 'serif');
    expect(
      Theme.of(tester.element(find.byType(AppearanceControls)))
          .textTheme
          .bodyMedium
          ?.fontFamily,
      'serif',
    );
    expect(
      tester
          .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
          .groupValue,
      'serif',
    );

    // 回到系統預設寫回 null。
    await tester.tap(find.text('Default font'));
    await settle(tester, h);
    expect((await stored(tester, h)).fontFamily, isNull);
  });

  testWidgets(
    'a stored font the platform does not offer shows default selected',
    (tester) async {
      final h = ShellHarness(fontChoices: _fonts);
      await h.pumpShell(
        tester,
        size: const Size(1000, 900),
        collapsePanel: true,
      );
      await tester.runAsync(
        () => h
            .container(tester)
            .read(appearanceSettingsRepositoryProvider)
            .write(fontFamily: 'SimSun'),
      );
      await tester.tap(find.text('Settings').first);
      await h.loadSettings(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
      await settle(tester, h);

      expect(
        tester
            .widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>))
            .groupValue,
        isNull,
      );
      expect(
        Theme.of(tester.element(find.byType(AppearanceControls)))
            .textTheme
            .bodyMedium
            ?.fontFamily,
        isNot('SimSun'),
      );
    },
  );

  test('hex parsing accepts six digits with or without #', () {
    expect(parseHexColor('336699'), const Color(0xFF336699));
    expect(parseHexColor(' #3366aa '), const Color(0xFF3366AA));
    expect(parseHexColor('3366'), isNull);
    expect(parseHexColor('33669Z'), isNull);
    expect(hexOf(const Color(0xFF00AA0F)), '00AA0F');
  });

  test('every preset id has a translated name', () {
    // 名稱查表在 appearance_controls；id 變了而忘了補會落到原樣顯示。
    expect(themePresets.map((p) => p.id), [
      'defaultPurple',
      'indigo',
      'blue',
      'teal',
      'green',
      'yellow',
      'orange',
      'red',
      'pink',
    ]);
  });
}
