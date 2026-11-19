import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/glass/glass_effect.dart';
import 'package:fmp/app/i18n/language.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/storage.dart';
import 'package:fmp/app/theme/appearance.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/data/settings_store.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

/// 設定跨重啟保存：在一個 [ProviderContainer] 裡改設定，關掉它與資料庫，再用
/// 同一個資料庫檔照 `main` 的做法（[openStorage]）讀回、開第二個 container。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Log log;
  late AppDatabase database;
  late ProviderContainer container;

  File databaseFile() => File('${dir.path}/fmp.sqlite');

  Future<void> launch() async {
    final storage = await openStorage(databaseFile(), log);
    database = storage.database!;
    container = ProviderContainer(
      overrides: [
        logProvider.overrideWithValue(log),
        appDatabaseProvider.overrideWithValue(database),
        savedSettingsProvider.overrideWithValue(storage.settings),
      ],
    );
  }

  Future<void> restart() async {
    container.dispose();
    await database.close();
    await launch();
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fmp_settings_');
    log = await Log.open(
      Directory('${dir.path}/logs'),
      minimumLevel: LogLevel.debug,
    );
    await launch();
  });
  tearDown(() async {
    container.dispose();
    await database.close();
    await log.close();
    dir.deleteSync(recursive: true);
    LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale);
  });

  test('a new database starts with every default', () {
    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(container.read(accentProvider), Accent.none);
    expect(container.read(languageProvider), isNull);
    expect(container.read(glassEffectProvider), GlassTier.refract);
    expect(
      container.read(temporaryPlayRewindProvider),
      const Duration(seconds: 10),
    );
  });

  test('the theme is kept across a restart', () async {
    await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
    await restart();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('the accent is kept across a restart', () async {
    await container.read(accentProvider.notifier).set(Accent.teal);
    await restart();
    expect(container.read(accentProvider), Accent.teal);
  });

  test('the language is kept across a restart', () async {
    await container.read(languageProvider.notifier).set(AppLocale.en);
    await restart();
    expect(container.read(languageProvider), AppLocale.en);
  });

  test('going back to following the system is kept across a restart', () async {
    await container.read(languageProvider.notifier).set(AppLocale.en);
    await container.read(languageProvider.notifier).set(null);
    await restart();
    expect(container.read(languageProvider), isNull);
  });

  test('the glass effect is kept across a restart', () async {
    await container.read(glassEffectProvider.notifier).set(GlassTier.minimal);
    await restart();
    expect(container.read(glassEffectProvider), GlassTier.minimal);
  });

  test('the temporary play rewind is kept across a restart', () async {
    await container
        .read(temporaryPlayRewindProvider.notifier)
        .set(const Duration(seconds: 30));
    await restart();
    expect(
      container.read(temporaryPlayRewindProvider),
      const Duration(seconds: 30),
    );
  });

  test('each choice is stored as its own fixed string, not a name in the '
      'code', () async {
    Future<String?> stored<T>(
      NotifierProvider<SavedSetting<T>, T> provider,
      String key,
      T value,
    ) async {
      await container.read(provider.notifier).set(value);
      return (await SettingsStore(database).load())[key];
    }

    final expected = <(Future<String?> Function(), String)>[
      for (final (mode, raw) in [
        (ThemeMode.light, 'light'),
        (ThemeMode.dark, 'dark'),
        (ThemeMode.system, 'system'),
      ])
        (() => stored(themeModeProvider, 'appearance.theme', mode), raw),
      for (final (accent, raw) in [
        (Accent.violet, 'violet'),
        (Accent.indigo, 'indigo'),
        (Accent.teal, 'teal'),
        (Accent.none, 'none'),
      ])
        (() => stored(accentProvider, 'appearance.accent', accent), raw),
      for (final (locale, raw) in [
        (AppLocale.zhTw, 'zh-TW'),
        (AppLocale.zhCn, 'zh-CN'),
        (AppLocale.en, 'en'),
        (null, 'system'),
      ])
        (() => stored(languageProvider, 'appearance.language', locale), raw),
      for (final (tier, raw) in [
        (GlassTier.standard, 'lite'),
        (GlassTier.minimal, 'off'),
        (GlassTier.refract, 'full'),
      ])
        (() => stored(glassEffectProvider, 'appearance.glass', tier), raw),
      for (final (seconds, raw) in [
        (0, '0'),
        (3, '3'),
        (5, '5'),
        (15, '15'),
        (30, '30'),
        (10, '10'),
      ])
        (
          () => stored(
            temporaryPlayRewindProvider,
            'playback.temporaryPlayRewindSeconds',
            Duration(seconds: seconds),
          ),
          raw,
        ),
    ];
    for (final (save, raw) in expected) {
      expect(await save(), raw);
    }
  });

  test('a stored value this version does not know falls back to the '
      'default', () async {
    final store = SettingsStore(database);
    await store.write('appearance.theme', 'sepia');
    await store.write('appearance.accent', 'gold');
    await store.write('appearance.language', 'ja');
    await store.write('appearance.glass', 'refract');
    await store.write('playback.temporaryPlayRewindSeconds', '7');
    await restart();

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(container.read(accentProvider), Accent.none);
    expect(container.read(languageProvider), isNull);
    expect(container.read(glassEffectProvider), GlassTier.refract);
    expect(
      container.read(temporaryPlayRewindProvider),
      const Duration(seconds: 10),
    );
    await log.close();
    final logged = File('${dir.path}/logs/${Log.fileName}').readAsStringSync();
    for (final key in [
      'appearance.theme',
      'appearance.accent',
      'appearance.language',
      'appearance.glass',
      'playback.temporaryPlayRewindSeconds',
    ]) {
      expect(
        logged,
        contains('WARNING Unknown stored value for the setting $key'),
      );
    }
    log = await Log.open(
      Directory('${dir.path}/logs'),
      minimumLevel: LogLevel.debug,
    );
  });

  test('without a database a change still takes effect', () async {
    final memory = ProviderContainer();
    addTearDown(memory.dispose);
    await memory.read(accentProvider.notifier).set(Accent.violet);
    expect(memory.read(accentProvider), Accent.violet);
  });

  test('choosing a language switches the interface at once', () async {
    await container.read(languageProvider.notifier).set(AppLocale.zhCn);
    expect(LocaleSettings.currentLocale, AppLocale.zhCn);
  });

  test('the saved language is applied before the first frame', () {
    LanguageSetting.applySaved({'appearance.language': 'en'});
    expect(LocaleSettings.currentLocale, AppLocale.en);
  });

  group('following the system', () {
    test('Traditional Chinese, or Chinese in Taiwan, Hong Kong or Macau, is '
        'zh-TW', () {
      for (final locale in const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale('zh', 'TW'),
        Locale('zh', 'HK'),
        Locale('zh', 'MO'),
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'CN',
        ),
      ]) {
        expect(appLocaleFor(locale), AppLocale.zhTw, reason: '$locale');
      }
    });

    test('other Chinese is zh-CN', () {
      for (final locale in const [
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        Locale('zh', 'CN'),
        Locale('zh', 'SG'),
        Locale('zh'),
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'HK',
        ),
      ]) {
        expect(appLocaleFor(locale), AppLocale.zhCn, reason: '$locale');
      }
    });

    test('English is en', () {
      expect(appLocaleFor(const Locale('en', 'GB')), AppLocale.en);
      expect(appLocaleFor(const Locale('en')), AppLocale.en);
    });

    test('a language outside the three is zh-TW', () {
      expect(appLocaleFor(const Locale('ja', 'JP')), AppLocale.zhTw);
      expect(appLocaleFor(const Locale('fr')), AppLocale.zhTw);
    });
  });
}
