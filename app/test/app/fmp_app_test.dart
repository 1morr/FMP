import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:material_ui/material_ui.dart';

import '../plugins/plugin_harness.dart';
import '../support/memory_database.dart';

void main() {
  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;

  /// 以身分頁啟動 App；回傳它的 log，讀記憶體歷史用。
  Future<Log> pumpApp(
    WidgetTester tester, {
    AppDatabase? database,
    PlatformCapabilities capabilities = PlatformCapabilities.none,
  }) async {
    final redactor = Redactor();
    final log = Log(redactor: redactor, minimumLevel: LogLevel.debug);
    await tester.pumpWidget(
      appProviderScope(
        overrides: [
          dataDirectoryProvider.overrideWithValue(Directory('/data/fmp-dev')),
          appDatabaseProvider.overrideWithValue(database ?? memoryDatabase()),
          redactorProvider.overrideWithValue(redactor),
          logProvider.overrideWithValue(log),
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ],
        child: const FmpApp(flavor: AppFlavor.dev),
      ),
    );
    return log;
  }

  /// 外觀設定從資料庫讀出來之後的畫面（drift 的串流要真的事件迴圈）。
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the app name, flavor, data directory and plugins', (
    tester,
  ) async {
    final database = memoryDatabase();
    await tester.runAsync(
      () => PluginRepository(database).install(
        InstalledPlugin(
          id: 'fmp-test',
          version: '1.0.0',
          manifestJson: '{}',
          script: testPluginFile.readAsStringSync(),
          installedAt: DateTime.utc(2026, 9, 30),
        ),
      ),
    );

    await pumpApp(tester, database: database);
    // 插件在背景 isolate 載入：spawn 與 port 的訊息要真的事件迴圈，所以在
    // runAsync 裡讓它跑，直到清單出現。
    final plugin = find.text('fmp-test 1.0.0');
    for (var round = 0; round < 100 && plugin.evaluate().isEmpty; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.text('FMP Dev'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('/data/fmp-dev'), findsOneWidget);
    expect(plugin, findsOneWidget);
  });

  group('appearance', () {
    setUp(() {
      dispatcher.localesTestValue = [const Locale('en', 'US')];
      addTearDown(dispatcher.clearLocalesTestValue);
    });

    Locale appLocale(WidgetTester tester) =>
        Localizations.localeOf(tester.element(find.text('FMP Dev')));

    testWidgets('an unset language follows the system', (tester) async {
      await pumpApp(tester);
      await settle(tester);

      expect(appLocale(tester), const Locale('en'));
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('switching the language re-renders the page and back', (
      tester,
    ) async {
      await pumpApp(tester);
      await settle(tester);

      await tester.tap(find.text('繁體中文'));
      await settle(tester);
      expect(
        appLocale(tester),
        const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
          countryCode: 'TW',
        ),
      );
      expect(find.text('主題'), findsOneWidget);
      // Material 的內建字串也是繁中。
      expect(
        MaterialLocalizations.of(tester.element(find.text('FMP Dev')))
            .okButtonLabel,
        '確定',
      );

      await tester.tap(find.text('简体中文'));
      await settle(tester);
      expect(find.text('主题'), findsOneWidget);

      // 主題也有「跟随系统」；點語言的那一個。
      await tester.tap(
        find.widgetWithText(RadioListTile<LocaleSetting?>, '跟随系统'),
      );
      await settle(tester);
      expect(appLocale(tester), const Locale('en'));
      expect(find.text('FMP Dev'), findsOneWidget);
    });

    testWidgets('CJK text takes the glyphs of the UI language', (tester) async {
      // 文字實際用的 locale：樣式的優先，再來是 Text.locale，最後是 App 的。
      // Android 不指名字型，漢字的繁簡字形只看它（研究檔 §6）。
      Locale textLocale(Finder text) {
        final rich = tester.widget<RichText>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        return rich.text.style?.locale ??
            rich.locale ??
            Localizations.localeOf(tester.element(text));
      }

      const hant = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      );
      const hans = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      );
      final endonyms = {
        for (final (name, locale) in [('繁體中文', hant), ('简体中文', hans)])
          find.text(name): locale,
      };
      await pumpApp(tester);
      await settle(tester);

      // 英文介面：漢字用繁中字形（ADR 0024 §決定 2），英文的 Material 字串不變。
      expect(appLocale(tester), const Locale('en'));
      expect(textLocale(find.text('FMP Dev')), hant);
      expect(textLocale(find.text('Dark')), hant);
      for (final MapEntry(key: text, value: locale) in endonyms.entries) {
        expect(textLocale(text), locale, reason: 'endonyms keep their own');
      }

      await tester.tap(find.text('简体中文'));
      await settle(tester);
      expect(textLocale(find.text('FMP Dev')), hans);
      expect(textLocale(find.text('深色')), hans);
      for (final MapEntry(key: text, value: locale) in endonyms.entries) {
        expect(textLocale(text), locale, reason: 'endonyms keep their own');
      }

      await tester.tap(find.text('繁體中文'));
      await settle(tester);
      expect(textLocale(find.text('FMP Dev')), hant);
      expect(textLocale(find.text('深色')), hant);
    });

    testWidgets('switching the theme changes the brightness', (tester) async {
      await pumpApp(tester);
      await settle(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.text('FMP Dev'))).brightness;

      await tester.tap(find.text('Dark'));
      await settle(tester);
      expect(brightness(), Brightness.dark);

      await tester.tap(find.text('Light'));
      await settle(tester);
      expect(brightness(), Brightness.light);
      expect(find.text('FMP Dev'), findsOneWidget);
    });

    testWidgets('the theme uses the platform fonts for the UI language', (
      tester,
    ) async {
      const capabilities = PlatformCapabilities(
        dataDirectory: true,
        singleInstance: false,
        fontFallback: FontFallback(
          traditionalChinese: ['TC Font'],
          simplifiedChinese: ['SC Font'],
        ),
        playback: null,
      );
      final log = await pumpApp(tester, capabilities: capabilities);
      await settle(tester);
      List<String>? fallback() =>
          Theme.of(tester.element(find.text('FMP Dev')))
              .textTheme
              .bodyMedium
              ?.fontFamilyFallback;

      // 英文介面：繁中在前（ADR 0024 §決定 2）。
      expect(fallback(), ['TC Font', 'SC Font']);
      await tester.tap(find.text('简体中文'));
      await settle(tester);
      expect(fallback(), ['SC Font']);
      await tester.tap(find.text('繁體中文'));
      await settle(tester);
      expect(fallback(), ['TC Font']);
      await tester.tap(find.text('English'));
      await settle(tester);
      expect(fallback(), ['TC Font', 'SC Font']);
      await tester.tap(find.text('简体中文'));
      await settle(tester);
      expect(fallback(), ['SC Font']);

      // 啟動與每次換語言各記一筆，實機對照用；記的清單是那個語言的，不是
      // 上一個語言的（listener 裡 read 相依的 provider 會讀到舊值）。
      final applied = [
        for (final record in log.history)
          if (record.message == 'UI locale applied') record.fields,
      ];
      expect(applied, [
        for (final (locale, fonts) in [
          ('en', ['TC Font', 'SC Font']),
          ('zh-Hans-CN', ['SC Font']),
          ('zh-Hant-TW', ['TC Font']),
          ('en', ['TC Font', 'SC Font']),
          ('zh-Hans-CN', ['SC Font']),
        ])
          {'locale': locale, 'fontFallback': fonts},
      ]);
    });
  });
}
