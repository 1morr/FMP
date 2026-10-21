import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/domain/developer.dart';
import 'package:fmp/ui/debug/debug_overview.dart';
import 'package:fmp/ui/format/home_path.dart';
import 'package:fmp/ui/debug/debug_page.dart';
import 'package:fmp/ui/debug/debug_plugin_dev.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

void main() {
  /// 開設定頁。[developerMode] 不是 `null` 就先寫進資料庫。
  Future<ShellHarness> openSettings(
    WidgetTester tester, {
    AppFlavor flavor = AppFlavor.dev,
    LogLevelSetting buildLogLevel = LogLevelSetting.info,
    bool? developerMode,
    bool pluginDevTools = false,
    double width = 1000,
  }) async {
    final h = ShellHarness(
      flavor: flavor,
      buildLogLevel: buildLogLevel,
      pluginDevTools: pluginDevTools,
      // 插件開發區塊用遮蔽函式顯示路徑。
      redactor: pluginDevTools ? Redactor() : null,
    );
    await h.pumpShell(tester, size: Size(width, 800), collapsePanel: true);
    if (developerMode != null) {
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(developerMode: developerMode),
      );
    }
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    return h;
  }

  final debugEntry = find.widgetWithText(ListTile, 'Debug');

  Future<void> openDebug(WidgetTester tester, ShellHarness h) async {
    await tester.tap(debugEntry);
    await h.loadSettings(tester);
    await tester.pumpAndSettle();
  }

  Future<DeveloperSettings> stored(WidgetTester tester, ShellHarness h) async =>
      (await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .read(),
      ))!;

  group('the settings entry', () {
    testWidgets('shows only while developer mode is on', (tester) async {
      final h = await openSettings(tester, flavor: AppFlavor.prod);
      expect(debugEntry, findsNothing);

      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(developerMode: true),
      );
      await h.loadSettings(tester);
      expect(debugEntry, findsOneWidget);
      // 清單的最後一列，在「關於」之後。
      expect(
        tester.getTopLeft(debugEntry).dy,
        greaterThan(
          tester.getTopLeft(find.widgetWithText(ListTile, 'About')).dy,
        ),
      );
    });

    testWidgets('a dev build shows it by default', (tester) async {
      await openSettings(tester);

      expect(debugEntry, findsOneWidget);
    });
  });

  group('the route gate (ADR 0025 §決定 1)', () {
    testWidgets('opening it with developer mode off goes back to Settings', (
      tester,
    ) async {
      final h = await openSettings(tester, flavor: AppFlavor.prod);
      unawaited(
        openDebugPage(
          tester.element(find.byType(SettingsPage)),
          onShowCacheSettings: () {},
        ),
      );
      await tester.pump();
      // 設定讀出來之前與之後都不顯示任何工具。
      expect(find.byType(DebugOverview), findsNothing);
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(find.byType(DebugPage), findsNothing);
      expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
    });

    testWidgets('the master switch turns developer mode off in one write, '
        'closes the page and hides the entry', (tester) async {
      final h = await openSettings(tester);
      await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .write(logLevel: LogLevelSetting.debug, pluginDevFolder: 'dev'),
      );
      await openDebug(tester, h);
      expect(find.byType(DebugOverview), findsOneWidget);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Developer mode'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(
        await stored(tester, h),
        const DeveloperSettings(developerMode: false),
      );
      expect(find.byType(DebugPage), findsNothing);
      expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
      expect(debugEntry, findsNothing);
    });
  });

  group('the plugin development section (ADR 0025 §如何確認)', () {
    final entry = find.widgetWithText(ListTile, 'Plugin development');

    testWidgets('is neither listed nor shown on a platform without '
        'pluginDevTools', (tester) async {
      final h = await openSettings(tester);
      await openDebug(tester, h);

      expect(entry, findsNothing);
      expect(find.byType(DebugPluginDev), findsNothing);
    });

    testWidgets('sits between the health check and the database when the '
        'platform declares it', (tester) async {
      final h = await openSettings(tester, pluginDevTools: true);
      await openDebug(tester, h);

      expect(entry, findsOneWidget);
      double top(String name) =>
          tester.getTopLeft(find.widgetWithText(ListTile, name)).dy;
      expect(top('Source health check'), lessThan(top('Plugin development')));
      expect(top('Plugin development'), lessThan(top('Database')));
      await tester.tap(entry);
      await h.loadSettings(tester);
      await tester.pumpAndSettle();
      expect(find.byType(DebugPluginDev), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('1000 wide: the sections on the left, the overview on the '
        'right', (tester) async {
      final h = await openSettings(tester);
      await openDebug(tester, h);

      expect(find.byType(VerticalDivider), findsOneWidget);
      final overview = find.widgetWithText(ListTile, 'Overview');
      expect(tester.widget<ListTile>(overview).selected, isTrue);
      expect(find.byType(DebugOverview), findsOneWidget);
      expect(
        tester.getCenter(overview).dx,
        lessThan(tester.getTopLeft(find.byType(DebugOverview)).dx),
      );

      // 標題列的返回鈕關掉這一頁。
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(DebugPage), findsNothing);
    });

    testWidgets('400 wide: the list, then the overview; the back key goes '
        'back to the list, then to Settings', (tester) async {
      final h = await openSettings(tester, width: 400);
      await openDebug(tester, h);

      expect(find.byType(DebugOverview), findsNothing);
      expect(find.byType(VerticalDivider), findsNothing);

      await tester.tap(find.widgetWithText(ListTile, 'Overview'));
      await h.loadSettings(tester);
      expect(find.byType(DebugOverview), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Overview'),
        ),
        findsOneWidget,
      );

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(DebugOverview), findsNothing);
      expect(find.byType(DebugPage), findsOneWidget);

      // 標題列的返回鈕也一樣回到清單。
      await tester.tap(find.widgetWithText(ListTile, 'Overview'));
      await h.loadSettings(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(find.byType(DebugOverview), findsNothing);
      expect(find.byType(DebugPage), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(DebugPage), findsNothing);
      expect(find.byType(SettingsPage).hitTestable(), findsOneWidget);
    });
  });

  group('the overview', () {
    testWidgets('shows the version, flavor, platform and the data directory '
        'under ~', (tester) async {
      final h = await openSettings(tester);
      await openDebug(tester, h);

      for (final (label, value) in [
        ('Version', '1.2.3'),
        ('Flavor', 'dev'),
        ('Platform', 'Windows'),
        ('Data directory', '~/fmp-dev'),
      ]) {
        final row = find.widgetWithText(ListTile, label);
        expect(
          find.descendant(of: row, matching: find.text(value)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(find.textContaining('/home/tester'), findsNothing);
    });

    RadioGroup<LogLevelSetting> levels(WidgetTester tester) =>
        tester.widget(find.byType(RadioGroup<LogLevelSetting>));

    testWidgets('in a release build info is the default; choosing debug '
        'writes it', (tester) async {
      final h = await openSettings(tester);
      await openDebug(tester, h);
      expect(levels(tester).groupValue, LogLevelSetting.info);
      expect(find.text('info (default)'), findsOneWidget);
      expect(find.text('debug'), findsOneWidget);

      await tester.tap(find.text('debug'));
      await h.loadSettings(tester);

      expect(levels(tester).groupValue, LogLevelSetting.debug);
      expect((await stored(tester, h)).logLevel, LogLevelSetting.debug);
    });

    testWidgets('in a debug build debug is the default and is shown as the '
        'level; choosing info writes it', (tester) async {
      final h = await openSettings(
        tester,
        buildLogLevel: LogLevelSetting.debug,
      );
      await openDebug(tester, h);
      expect(levels(tester).groupValue, LogLevelSetting.debug);
      expect(find.text('debug (default)'), findsOneWidget);
      expect(find.text('info'), findsOneWidget);
      expect((await stored(tester, h)).logLevel, isNull);

      await tester.tap(find.text('info'));
      await h.loadSettings(tester);

      expect(levels(tester).groupValue, LogLevelSetting.info);
      expect((await stored(tester, h)).logLevel, LogLevelSetting.info);
    });

    testWidgets('cache usage closes the page and opens Settings › Network', (
      tester,
    ) async {
      final h = await openSettings(tester);
      await openDebug(tester, h);

      await tester.tap(find.widgetWithText(ListTile, 'Cache usage'));
      await h.loadSettings(tester);
      await tester.pumpAndSettle();

      expect(find.byType(DebugPage), findsNothing);
      expect(find.byType(NetworkControls), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Network'))
            .selected,
        isTrue,
      );
    });
  });

  group('homeRelativePath', () {
    test('replaces the home directory with ~', () {
      expect(
        homeRelativePath(
          r'C:\Users\tester\AppData\Roaming\com.personal\fmp-dev',
          r'C:\Users\tester',
        ),
        r'~\AppData\Roaming\com.personal\fmp-dev',
      );
      expect(homeRelativePath('/home/tester/fmp', '/home/tester/'), '~/fmp');
      expect(homeRelativePath(r'C:\Users\tester', r'C:\Users\tester'), '~');
    });

    test('ignores case like Windows paths do', () {
      expect(
        homeRelativePath(r'c:\users\TESTER\fmp', r'C:\Users\tester'),
        r'~\fmp',
      );
    });

    test('leaves other paths alone', () {
      for (final (path, home) in [
        // 同前綴、不同的目錄。
        (r'C:\Users\testers\fmp', r'C:\Users\tester'),
        (r'D:\FMP\userdata-dev', r'C:\Users\tester'),
        ('/data/user/0/com.personal.fmp.dev/files', null),
        (r'C:\fmp', ''),
      ]) {
        expect(homeRelativePath(path, home), path, reason: '$path in $home');
      }
    });
  });
}
