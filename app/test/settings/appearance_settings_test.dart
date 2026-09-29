import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/settings/appearance_settings.dart';

import '../support/memory_database.dart';

void main() {
  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;

  /// 設定系統的語言偏好清單；只有一個語言時就是 `[locale]`。
  void setSystemLocales(List<Locale> locales) {
    dispatcher.localesTestValue = locales;
    addTearDown(dispatcher.clearLocalesTestValue);
  }

  void setSystemLocale(Locale locale) => setSystemLocales([locale]);

  ProviderContainer containerFor(AppDatabase database) =>
      ProviderContainer.test(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );

  /// 訂閱 [appearanceProvider]，依序取得它發出的值。
  StreamIterator<Appearance> appearances(ProviderContainer container) {
    final controller = StreamController<Appearance>();
    container.listen(appearanceProvider, (_, next) {
      if (next case AsyncData(:final value)) controller.add(value);
    }, fireImmediately: true);
    final iterator = StreamIterator(controller.stream);
    addTearDown(() async {
      await iterator.cancel();
      await controller.close();
    });
    return iterator;
  }

  group('supportedLocaleFor', () {
    for (final (system, expected) in [
      (const Locale('zh', 'TW'), LocaleSetting.zhTw),
      (const Locale('zh', 'HK'), LocaleSetting.zhTw),
      (const Locale('zh', 'MO'), LocaleSetting.zhTw),
      (
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        LocaleSetting.zhTw,
      ),
      (const Locale('zh', 'CN'), LocaleSetting.zhCn),
      (const Locale('zh', 'SG'), LocaleSetting.zhCn),
      (const Locale('zh', 'MY'), LocaleSetting.zhCn),
      (
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        LocaleSetting.zhCn,
      ),
      // 書寫系統優先於地區。
      (
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'HK',
        ),
        LocaleSetting.zhCn,
      ),
      (const Locale('en', 'US'), LocaleSetting.en),
      (const Locale('en', 'GB'), LocaleSetting.en),
      (const Locale('en'), LocaleSetting.en),
      // 不帶地區的 zh 仍是中文，用 base locale 繁中。
      (const Locale('zh'), LocaleSetting.zhTw),
      // 其他語言不支援。
      (const Locale('ja', 'JP'), null),
      (const Locale('fr'), null),
    ]) {
      test('$system maps to ${expected?.name}', () {
        expect(supportedLocaleFor(system), expected);
      });
    }
  });

  group('localeForSystem walks the preference list', () {
    for (final (preferred, expected) in [
      ([const Locale('fr'), const Locale('en')], LocaleSetting.en),
      ([const Locale('fr'), const Locale('ja')], LocaleSetting.zhTw),
      ([const Locale('en'), const Locale('zh', 'TW')], LocaleSetting.en),
      ([const Locale('ja'), const Locale('zh', 'CN')], LocaleSetting.zhCn),
      (<Locale>[], LocaleSetting.zhTw),
    ]) {
      test('$preferred picks ${expected.name}', () {
        expect(localeForSystem(preferred), expected);
      });
    }
  });

  group('defaults apply only to unset fields (ADR 0011)', () {
    test('a user value survives a change of the program default', () async {
      final repository = AppearanceSettingsRepository(memoryDatabase());
      await repository.write(themeMode: ThemeModeSetting.dark);
      final stored = await repository.read();

      for (final (defaultThemeMode, defaultLocale) in [
        (ThemeModeSetting.system, LocaleSetting.zhTw),
        (ThemeModeSetting.light, LocaleSetting.en),
      ]) {
        final appearance = resolveAppearance(
          stored,
          defaultThemeMode: defaultThemeMode,
          defaultLocale: defaultLocale,
        );
        // 使用者設過的主題不變；沒設過的語言跟著新預設。
        expect(appearance.themeMode, ThemeModeSetting.dark);
        expect(appearance.locale, defaultLocale);
        expect(appearance.stored, stored);
      }
    });

    test('nothing is written for fields the user never set', () async {
      final database = memoryDatabase();
      final container = containerFor(database);
      setSystemLocale(const Locale('en', 'US'));

      await container
          .read(appearanceProvider.notifier)
          .setThemeMode(ThemeModeSetting.light);

      final row = await database
          .customSelect('SELECT theme_mode, locale FROM appearance_settings')
          .getSingle();
      expect(row.data, {'theme_mode': 'light', 'locale': null});
    });
  });

  group('AppearanceNotifier', () {
    test('unset fields read as the system theme and language', () async {
      setSystemLocale(const Locale('zh', 'CN'));
      final values = appearances(containerFor(memoryDatabase()));

      expect(await values.moveNext(), isTrue);
      expect(
        values.current,
        const Appearance(
          themeMode: ThemeModeSetting.system,
          locale: LocaleSetting.zhCn,
          stored: AppearanceSettings.empty,
        ),
      );
    });

    test('an unset language follows the system as it changes', () async {
      setSystemLocale(const Locale('en', 'US'));
      final values = appearances(containerFor(memoryDatabase()));
      expect(await values.moveNext(), isTrue);
      expect(values.current.locale, LocaleSetting.en);

      setSystemLocale(const Locale('zh', 'HK'));

      expect(await values.moveNext(), isTrue);
      expect(values.current.locale, LocaleSetting.zhTw);
    });

    test(
      'an unset language uses the first supported system language',
      () async {
        setSystemLocales([const Locale('fr'), const Locale('en', 'US')]);
        final values = appearances(containerFor(memoryDatabase()));
        expect(await values.moveNext(), isTrue);
        expect(values.current.locale, LocaleSetting.en);

        setSystemLocales([const Locale('fr'), const Locale('ja')]);

        expect(await values.moveNext(), isTrue);
        expect(values.current.locale, LocaleSetting.zhTw);
      },
    );

    test('a language the user set ignores the system language', () async {
      setSystemLocale(const Locale('en', 'US'));
      final container = containerFor(memoryDatabase());
      final values = appearances(container);
      expect(await values.moveNext(), isTrue);

      await container
          .read(appearanceProvider.notifier)
          .setLocale(LocaleSetting.zhCn);
      expect(await values.moveNext(), isTrue);
      expect(values.current.locale, LocaleSetting.zhCn);
      expect(values.current.stored.locale, LocaleSetting.zhCn);

      setSystemLocale(const Locale('zh', 'TW'));
      expect(await values.moveNext(), isTrue);
      expect(values.current.locale, LocaleSetting.zhCn);
    });

    test('each setter writes only its own field', () async {
      setSystemLocale(const Locale('en', 'US'));
      final container = containerFor(memoryDatabase());
      final values = appearances(container);
      expect(await values.moveNext(), isTrue);
      final notifier = container.read(appearanceProvider.notifier);

      await notifier.setLocale(LocaleSetting.zhTw);
      expect(await values.moveNext(), isTrue);
      await notifier.setThemeMode(ThemeModeSetting.dark);
      expect(await values.moveNext(), isTrue);

      expect(
        values.current.stored,
        const AppearanceSettings(
          themeMode: ThemeModeSetting.dark,
          locale: LocaleSetting.zhTw,
        ),
      );
    });
  });
}
