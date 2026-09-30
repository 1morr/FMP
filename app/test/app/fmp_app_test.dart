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
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../plugins/plugin_harness.dart';
import '../support/memory_database.dart';

void main() {
  final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;

  /// 啟動 App（外殼）；回傳它的 log，讀記憶體歷史用。
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

  testWidgets('opens on search; installed plugins are the sources', (
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
    // runAsync 裡讓它跑，直到音源出現。
    Future<void> until(Finder finder) async {
      for (var round = 0; round < 100 && finder.evaluate().isEmpty; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    final source = find.widgetWithText(ChoiceChip, 'FMP Test Plugin');
    await until(source);
    expect(source, findsOneWidget);

    // 內附測試插件的搜尋（真的 QuickJS）：離線也有結果。
    await tester.enterText(find.byType(TextField), 'tone');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final result = find.text('Test tone 220 Hz (tone)');
    await until(result);
    expect(result, findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
  });

  group('appearance', () {
    setUp(() {
      dispatcher.localesTestValue = [const Locale('en', 'US')];
      addTearDown(dispatcher.clearLocalesTestValue);
    });

    Locale appLocale(WidgetTester tester) =>
        Localizations.localeOf(tester.element(find.byType(AppShell)));

    /// 開到設定頁（外觀設定在那裡）。
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await settle(tester);
    }

    testWidgets('an unset language follows the system', (tester) async {
      await pumpApp(tester);
      await settle(tester);
      await openSettings(tester);

      expect(appLocale(tester), const Locale('en'));
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('switching the language re-renders the page and back', (
      tester,
    ) async {
      await pumpApp(tester);
      await settle(tester);
      await openSettings(tester);

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
        MaterialLocalizations.of(tester.element(find.byType(AppShell)))
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
      expect(find.text('Theme'), findsOneWidget);
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
      await openSettings(tester);

      // 英文介面：漢字用繁中字形（ADR 0024 §決定 2），英文的 Material 字串不變。
      expect(appLocale(tester), const Locale('en'));
      expect(textLocale(find.text('Theme')), hant);
      expect(textLocale(find.text('Dark')), hant);
      for (final MapEntry(key: text, value: locale) in endonyms.entries) {
        expect(textLocale(text), locale, reason: 'endonyms keep their own');
      }

      await tester.tap(find.text('简体中文'));
      await settle(tester);
      expect(textLocale(find.text('主题')), hans);
      expect(textLocale(find.text('深色')), hans);
      for (final MapEntry(key: text, value: locale) in endonyms.entries) {
        expect(textLocale(text), locale, reason: 'endonyms keep their own');
      }

      await tester.tap(find.text('繁體中文'));
      await settle(tester);
      expect(textLocale(find.text('主題')), hant);
      expect(textLocale(find.text('深色')), hant);
    });

    testWidgets('switching the theme changes the brightness', (tester) async {
      await pumpApp(tester);
      await settle(tester);
      await openSettings(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(AppShell))).brightness;

      await tester.tap(find.text('Dark'));
      await settle(tester);
      expect(brightness(), Brightness.dark);

      await tester.tap(find.text('Light'));
      await settle(tester);
      expect(brightness(), Brightness.light);
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
      await openSettings(tester);
      List<String>? fallback() =>
          Theme.of(tester.element(find.byType(AppShell)))
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
