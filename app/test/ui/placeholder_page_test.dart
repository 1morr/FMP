import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';

void main() {
  tearDown(
    () => LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale),
  );

  const expected = {
    AppLocale.zhTw: '新版開發中',
    AppLocale.zhCn: '新版开发中',
    AppLocale.en: 'New version in development',
  };

  for (final MapEntry(key: locale, value: subtitle) in expected.entries) {
    testWidgets('placeholder shows the app name in ${locale.languageTag}', (
      tester,
    ) async {
      LocaleSettings.setLocaleSync(locale);
      await tester.pumpWidget(buildRoot());

      expect(find.text('FMP'), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);
    });
  }

  test('every supported locale is covered above', () {
    expect(expected.keys.toSet(), AppLocale.values.toSet());
  });
}
