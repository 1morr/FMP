import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('Chinese carries its script so the engine picks the right glyphs', () {
    expect(
      [for (final locale in LocaleSetting.values) flutterLocaleOf(locale)],
      [
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'CN',
        ),
        const Locale('en'),
      ],
    );
    expect(supportedFlutterLocales, hasLength(LocaleSetting.values.length));
  });

  test('each setting maps to its slang and font language', () {
    expect(
      [for (final locale in LocaleSetting.values) appLocaleOf(locale)],
      [AppLocale.zhTw, AppLocale.zhCn, AppLocale.en],
    );
    expect(
      [for (final locale in LocaleSetting.values) fontLanguageOf(locale)],
      [FontLanguage.zhTw, FontLanguage.zhCn, FontLanguage.en],
    );
  });

  // Material 的內建字串依書寫系統選：zh_Hant_TW 是台灣用語，zh_Hans 是簡中。
  for (final (locale, ok, back) in [
    (LocaleSetting.zhTw, '確定', '返回'),
    (LocaleSetting.zhCn, '确定', '返回'),
    (LocaleSetting.en, 'OK', 'Back'),
  ]) {
    testWidgets('${locale.name} gets matching Material strings', (
      tester,
    ) async {
      late MaterialLocalizations strings;
      await tester.pumpWidget(
        MaterialApp(
          locale: flutterLocaleOf(locale),
          supportedLocales: supportedFlutterLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) {
              strings = MaterialLocalizations.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(strings.okButtonLabel, ok);
      expect(strings.backButtonTooltip, back);
    });
  }

  test('language names are written in their own language', () {
    expect(
      [for (final locale in LocaleSetting.values) localeEndonym(locale)],
      ['繁體中文', '简体中文', 'English'],
    );
  });
}
