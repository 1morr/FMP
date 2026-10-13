import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/ui/settings/about_section.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

void main() {
  /// 開設定頁的「關於」。回傳之後每則提示的文字。
  Future<(ShellHarness, List<String>)> openAbout(
    WidgetTester tester, {
    AppFlavor flavor = AppFlavor.prod,
    double width = 1000,
  }) async {
    final h = ShellHarness(flavor: flavor);
    final toasts = <String>[];
    final subscription = h.toaster.toasts.listen(
      (toast) => toasts.add(toast.message),
    );
    addTearDown(subscription.cancel);
    await h.pumpShell(tester, size: Size(width, 800), collapsePanel: true);
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'About'));
    await h.loadSettings(tester);
    return (h, toasts);
  }

  Future<void> tapVersion(
    WidgetTester tester,
    ShellHarness h,
    int times,
  ) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text('Version'));
      await tester.pump();
    }
    await h.loadSettings(tester);
  }

  Future<DeveloperSettings> stored(WidgetTester tester, ShellHarness h) async =>
      (await tester.runAsync(
        () => h
            .container(tester)
            .read(developerSettingsRepositoryProvider)
            .read(),
      ))!;

  for (final width in [1000.0, 400.0]) {
    testWidgets('$width wide: About is the last section and shows the version '
        'and flavor', (tester) async {
      await openAbout(tester, width: width);

      expect(find.byType(AboutSection), findsOneWidget);
      expect(find.text('1.2.3 (prod)'), findsOneWidget);
    });
  }

  testWidgets('seven taps on the version turn developer mode on; from the '
      'second tap a toast says how many are left', (tester) async {
    final (h, toasts) = await openAbout(tester);
    expect(find.widgetWithText(ListTile, 'Debug'), findsNothing);

    await tapVersion(tester, h, 1);
    expect(toasts, isEmpty, reason: 'the first tap says nothing');

    await tapVersion(tester, h, 5);
    expect(toasts, [
      for (final left in [5, 4, 3, 2, 1])
        'Taps left to turn on developer mode: $left',
    ]);
    expect((await stored(tester, h)).developerMode, isNull);

    await tapVersion(tester, h, 1);
    expect(toasts.last, 'Developer mode is on');
    expect(
      await stored(tester, h),
      const DeveloperSettings(developerMode: true),
    );
    expect(find.widgetWithText(ListTile, 'Debug'), findsOneWidget);

    // 開著之後再點只說已經開啟。
    await tapVersion(tester, h, 1);
    expect(toasts.last, 'Developer mode is already on');
  });

  testWidgets('leaving the section starts the count again', (tester) async {
    final (h, toasts) = await openAbout(tester);
    await tapVersion(tester, h, 4);

    await tester.tap(find.widgetWithText(ListTile, 'Network'));
    await h.loadSettings(tester);
    await tester.tap(find.widgetWithText(ListTile, 'About'));
    await h.loadSettings(tester);
    // 同一則提示 5 秒內只顯示一次（Toaster 的去重）：過了再點。
    await tester.pump(const Duration(seconds: 6));
    toasts.clear();
    await tapVersion(tester, h, 2);

    expect(toasts, ['Taps left to turn on developer mode: 5']);
  });

  testWidgets('leaving the settings page starts the count again', (
    tester,
  ) async {
    final (h, toasts) = await openAbout(tester);
    await tapVersion(tester, h, 4);

    // 外殼以 IndexedStack 留著設定頁：State 還在，計數照樣歸零。
    await tester.tap(find.text('Search').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').first);
    await h.loadSettings(tester);
    expect(find.byType(AboutSection), findsOneWidget);
    // 同一則提示 5 秒內只顯示一次（Toaster 的去重）：過了再點。
    await tester.pump(const Duration(seconds: 6));
    toasts.clear();
    await tapVersion(tester, h, 2);

    expect(toasts, ['Taps left to turn on developer mode: 5']);
  });

  testWidgets('in a dev build developer mode is already on', (tester) async {
    final (h, toasts) = await openAbout(tester, flavor: AppFlavor.dev);
    expect(find.text('1.2.3 (dev)'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Debug'), findsOneWidget);

    await tapVersion(tester, h, 1);

    expect(toasts, ['Developer mode is already on']);
    expect(await stored(tester, h), DeveloperSettings.empty);
  });
}
