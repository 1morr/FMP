import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/settings/playback_settings.dart';
import 'package:fmp/ui/accounts/accounts_section.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/plugins/plugins_page.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/memory_database.dart';
import '../support/plugin_page_harness.dart';
import '../support/shell_harness.dart';

void main() {
  Future<ShellHarness> openSettings(WidgetTester tester, double width) async {
    final h = ShellHarness();
    // 面板收起：這裡測的是設定頁在內容區寬度下的版面。
    await h.pumpShell(tester, size: Size(width, 800), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    return h;
  }

  // 內容區的寬度：視窗減掉導覽（rail 80、抽屜 360）。
  testWidgets(
    'expanded and wider: groups on the left, the first group on the right',
    (tester) async {
      final h = await openSettings(tester, 1000);

      // 第一組是帳號（design §6.7 的順序）。
      expect(find.byType(AccountsSection), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Accounts'))
            .selected,
        isTrue,
      );
      expect(
        tester.getTopLeft(find.widgetWithText(ListTile, 'Accounts')).dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(ListTile, 'Appearance')).dy,
        ),
      );

      await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
      await h.loadSettings(tester);

      expect(find.byType(AccountsSection), findsNothing);
      expect(find.byType(AppearanceControls), findsOneWidget);
      expect(find.byType(RadioListTile<LocaleSetting?>), findsNWidgets(4));
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Appearance'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Network'))
            .selected,
        isFalse,
      );
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(
        tester.getCenter(find.widgetWithText(ListTile, 'Appearance')).dx,
        lessThan(tester.getTopLeft(find.byType(AppearanceControls)).dx),
      );

      await tester.tap(find.widgetWithText(ListTile, 'Network'));
      await h.loadSettings(tester);

      expect(find.byType(NetworkControls), findsOneWidget);
      expect(find.byType(AppearanceControls), findsNothing);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Network'))
            .selected,
        isTrue,
      );
    },
  );

  for (final width in [400.0, 700.0]) {
    testWidgets('$width wide: the list, then one group, then back', (
      tester,
    ) async {
      final h = await openSettings(tester, width);

      // 清單：沒有內容、沒有分隔線。
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.byType(AppearanceControls), findsNothing);
      expect(find.widgetWithText(ListTile, 'Appearance'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Network'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Network'));
      await h.loadSettings(tester);

      expect(find.byType(NetworkControls), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Appearance'), findsNothing);
      expect(find.text('Network'), findsOneWidget, reason: 'the heading');

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(find.byType(NetworkControls), findsNothing);
      expect(find.widgetWithText(ListTile, 'Appearance'), findsOneWidget);
    });
  }

  testWidgets(
    '400 wide: the system back key returns from a group to the list',
    (tester) async {
      final h = await openSettings(tester, 400);
      await tester.tap(find.widgetWithText(ListTile, 'Network'));
      await h.loadSettings(tester);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();

      expect(find.byType(NetworkControls), findsNothing);
      expect(find.widgetWithText(ListTile, 'Network'), findsOneWidget);
      // 回到清單之後返回鍵歸外殼：回到第一個目的地（首頁），設定頁看不到了。
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(find.byType(HomePage).hitTestable(), findsOneWidget);
    },
  );

  // 外殼以 IndexedStack 留著沒選的頁面：看不到的設定頁不能攔返回鍵。
  testWidgets('400 wide: a group left open does not hold the back key on '
      'another page', (tester) async {
    final h = await openSettings(tester, 400);
    await tester.tap(find.widgetWithText(ListTile, 'Network'));
    await h.loadSettings(tester);

    // 回到第一個目的地（首頁）：返回鍵在那裡放行，不被看不到的設定頁攔住。
    await tester.tap(ShellHarness.navigationItem(ShellDestination.home));
    await tester.pumpAndSettle();

    expect(await tester.binding.handlePopRoute(), isFalse);

    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    expect(find.byType(NetworkControls), findsOneWidget);
  });

  testWidgets('the group stays when the window crosses a breakpoint', (
    tester,
  ) async {
    final h = await openSettings(tester, 700);
    await tester.tap(find.widgetWithText(ListTile, 'Network'));
    await h.loadSettings(tester);

    tester.view.physicalSize = const Size(1400, 800);
    await tester.pump();
    await h.loadSettings(tester);

    expect(find.byType(NetworkControls), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Network'))
          .selected,
      isTrue,
    );
  });

  for (final width in [1000.0, 400.0]) {
    testWidgets('$width wide: accounts come first, library between playback '
        'and network, plugins after network, backup between plugins and about, '
        'and open the plugin page', (tester) async {
      final h = await PluginPageHarness.create(tester);
      await h.shell.pumpShell(
        tester,
        size: Size(width, 800),
        collapsePanel: true,
      );
      await tester.tap(find.text('Settings').first);
      await h.settle(tester);

      final sections = [
        for (final title in [
          'Accounts',
          'Appearance',
          'Playback',
          'Library',
          'Network',
          'Plugins',
          'Backup and restore',
          'About',
        ])
          tester.getCenter(find.widgetWithText(ListTile, title)).dy,
      ];
      expect(sections, orderedEquals([...sections]..sort()));
      expect(find.byType(PluginsPage), findsNothing);

      await tester.tap(find.widgetWithText(ListTile, 'Plugins'));
      await h.settle(tester);

      expect(find.byType(PluginsPage), findsOneWidget);
      expect(find.text('Installed'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('No plugins installed'), findsOneWidget);
      if (width < 600) {
        // 窄版：標題列是區塊名稱與返回鈕，回到清單。
        expect(find.text('Plugins'), findsOneWidget);
        await tester.tap(find.byTooltip('Back'));
        await tester.pump();
        expect(find.byType(PluginsPage), findsNothing);
      } else {
        expect(find.byType(VerticalDivider), findsOneWidget);
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, 'Plugins'))
              .selected,
          isTrue,
        );
      }
    });
  }

  testWidgets('both appearance settings can go back to following the system', (
    tester,
  ) async {
    final h = await openSettings(tester, 1000);
    await tester.tap(find.widgetWithText(ListTile, 'Appearance'));
    await h.loadSettings(tester);

    expect(find.text('System'), findsOneWidget, reason: 'theme');
    expect(find.text('System default'), findsOneWidget, reason: 'language');
  });

  /// 分組列的副標；沒有副標時是 `null`。
  String? subtitleOf(WidgetTester tester, String group) {
    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, group));
    final subtitle = tile.subtitle;
    return subtitle is Text ? subtitle.data : null;
  }

  for (final width in [400.0, 1000.0]) {
    testWidgets('$width wide: appearance and playback rows summarise their '
        'settings, the others have no subtitle', (tester) async {
      final h = await openSettings(tester, width);

      expect(subtitleOf(tester, 'Appearance'), 'Theme: System');
      expect(subtitleOf(tester, 'Playback'), 'Quality: High');
      for (final group in [
        'Accounts',
        'Library',
        'Network',
        'Plugins',
        'Backup and restore',
        'About',
      ]) {
        expect(subtitleOf(tester, group), isNull, reason: group);
      }

      // 設定一改，摘要跟著變。
      final container = h.container(tester);
      // 兩次寫入之間讓串流的重讀跑完（假時間裡開始的讀取握著 drift 的鎖）。
      await tester.runAsync(
        () => container
            .read(appearanceProvider.notifier)
            .setThemeMode(ThemeModeSetting.dark),
      );
      await h.loadSettings(tester);
      await tester.runAsync(
        () => container
            .read(playbackPreferencesProvider.notifier)
            .setAudioQuality(AudioQuality.low),
      );
      await h.loadSettings(tester);

      expect(subtitleOf(tester, 'Appearance'), 'Theme: Dark');
      expect(subtitleOf(tester, 'Playback'), 'Quality: Low');
    });
  }

  testWidgets('the appearance summary names a chosen font', (tester) async {
    final h = ShellHarness(fontChoices: const ['serif']);
    await h.pumpShell(tester, size: const Size(1000, 800), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.runAsync(
      () => h
          .container(tester)
          .read(appearanceProvider.notifier)
          .setFontFamily('serif'),
    );
    await h.loadSettings(tester);

    expect(subtitleOf(tester, 'Appearance'), 'Theme: System · Serif');
  });

  testWidgets('a stored font this platform does not offer is left out of the '
      'summary', (tester) async {
    // 例如還原了另一個平台的備份：資料庫有值，但這個平台的清單裡沒有。
    final h = ShellHarness(fontChoices: const ['serif']);
    await h.pumpShell(tester, size: const Size(1000, 800), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.runAsync(
      () => h
          .container(tester)
          .read(appearanceSettingsRepositoryProvider)
          .write(fontFamily: 'Meiryo'),
    );
    await h.loadSettings(tester);

    expect(subtitleOf(tester, 'Appearance'), 'Theme: System');
  });

  testWidgets('before the settings are read, no row has a summary', (
    tester,
  ) async {
    // 另一個 transaction 佔著資料庫：設定的第一次讀取排在它後面。
    final database = memoryDatabase();
    final release = Completer<void>();
    await tester.runAsync(() async {
      final started = Completer<void>();
      unawaited(
        database.transaction(() {
          started.complete();
          return release.future;
        }),
      );
      await started.future;
    });
    final h = ShellHarness(database: database);
    await h.pumpApp(
      tester,
      SettingsPage(visible: true, back: SettingsBack()),
      size: const Size(400, 800),
    );
    await h.loadSettings(tester);

    expect(subtitleOf(tester, 'Appearance'), isNull);
    expect(subtitleOf(tester, 'Playback'), isNull);

    release.complete();
    await h.loadSettings(tester);
    await h.loadSettings(tester);

    expect(subtitleOf(tester, 'Appearance'), 'Theme: System');
    expect(subtitleOf(tester, 'Playback'), 'Quality: High');
  });

  testWidgets('a summary is read with its row, as one tappable node', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await openSettings(tester, 400);

    final row = tester.getSemantics(
      find.widgetWithText(ListTile, 'Appearance'),
    );
    expect(row.label, 'Appearance\nTheme: System');
    expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      identical(tester.getSemantics(find.text('Theme: System')), row),
      isTrue,
      reason: 'the summary is not a node of its own',
    );
    // 沒有摘要的列只念組名。
    expect(
      tester.getSemantics(find.widgetWithText(ListTile, 'Network')).label,
      'Network',
    );
    semantics.dispose();
  });

  testWidgets('a long summary ellipsizes on one line at text scale 2.0', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const family = 'An extremely long font family name that cannot fit';
    final h = ShellHarness(fontChoices: const [family]);
    await h.pumpShell(tester, size: const Size(400, 800), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.runAsync(
      () => h
          .container(tester)
          .read(appearanceProvider.notifier)
          .setFontFamily(family),
    );
    await h.loadSettings(tester);

    expect(subtitleOf(tester, 'Appearance'), contains(family));
    final text = tester.widget<Text>(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Appearance'),
        matching: find.textContaining(family),
      ),
    );
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}
