import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/detail_panel.dart';
import 'package:fmp/ui/shell/nav_rail.dart';
import 'package:fmp/ui/shell/phone_dock.dart';
import 'package:fmp/ui/shell/side_bar.dart';
import 'package:material_ui/material_ui.dart';

/// App 外殼的路由與導覽（`docs/design/DESIGN.md`〈外殼〉）：打開在首頁，四個
/// 分頁與搜尋都到得了，返回行為照手機的分頁慣例。三種寬度各用一個視窗大小。
void main() {
  const phone = Size(390, 844);
  const tablet = Size(820, 1180);
  const desktop = Size(1280, 800);

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.zhTw));
  tearDown(
    () => LocaleSettings.setLocaleSync(AppLocaleUtils.instance.baseLocale),
  );

  Future<void> start(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildRoot());
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<bool> systemBack(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    return handled;
  }

  Finder inDock(String text) =>
      find.descendant(of: find.byType(PhoneDock), matching: find.text(text));

  group('phone', () {
    testWidgets('opens on home with the four tabs and the search orb', (
      tester,
    ) async {
      await start(tester, phone);

      expect(find.byType(HomePage), findsOneWidget);
      for (final label in ['首頁', '音樂庫', '佇列', '設定']) {
        expect(inDock(label), findsOneWidget);
      }
      expect(find.byTooltip('搜尋'), findsOneWidget);
      expect(find.byType(NavRail), findsNothing);
      expect(find.byType(SideBar), findsNothing);
    });

    testWidgets('each tab opens its page', (tester) async {
      await start(tester, phone);

      await tap(tester, inDock('音樂庫'));
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.text('還沒有歌單'), findsOneWidget);
      await tap(tester, inDock('佇列'));
      expect(find.byType(QueuePage), findsOneWidget);
      await tap(tester, inDock('設定'));
      expect(find.byType(SettingsPage), findsOneWidget);
      await tap(tester, inDock('首頁'));
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('search turns the tabs into an orb back to the tab it came '
        'from, and keeps the query', (tester) async {
      await start(tester, phone);
      await tap(tester, inDock('音樂庫'));

      await tap(tester, find.byTooltip('搜尋'));
      expect(find.byType(SearchPage), findsOneWidget);
      expect(inDock('音樂庫'), findsNothing);
      await tester.enterText(find.byType(TextField), '晴天');

      await tap(tester, find.byTooltip('回到音樂庫'));
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tap(tester, find.byTooltip('搜尋'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '晴天',
      );
    });

    testWidgets('system back leaves search for the tab underneath, goes '
        'from another tab to home, and leaves the app from home', (
      tester,
    ) async {
      await start(tester, phone);
      await tap(tester, inDock('佇列'));
      await tap(tester, find.byTooltip('搜尋'));

      expect(await systemBack(tester), isTrue);
      expect(find.byType(QueuePage), findsOneWidget);

      expect(await systemBack(tester), isTrue);
      expect(find.byType(HomePage), findsOneWidget);

      expect(await systemBack(tester), isFalse);
    });
  });

  group('medium', () {
    testWidgets('the rail reaches search, the four tabs, and floats the '
        'detail panel', (tester) async {
      await start(tester, tablet);
      expect(find.byType(NavRail), findsOneWidget);
      expect(find.byType(PhoneDock), findsNothing);
      expect(find.byType(DetailPanel), findsNothing);

      Finder inRail(String text) =>
          find.descendant(of: find.byType(NavRail), matching: find.text(text));
      for (final (label, page) in [
        ('音樂庫', LibraryPage),
        ('佇列', QueuePage),
        ('設定', SettingsPage),
        ('首頁', HomePage),
      ]) {
        await tap(tester, inRail(label));
        expect(find.byType(page), findsOneWidget);
      }

      // 細欄的搜尋是項目，欄位在搜尋頁頂端。
      await tap(tester, inRail('搜尋'));
      expect(find.byType(SearchPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SearchPage),
          matching: find.byType(TextField),
        ),
        findsOneWidget,
      );
      expect(await systemBack(tester), isTrue);
      expect(find.byType(HomePage), findsOneWidget);

      await tap(tester, find.byTooltip('顯示詳情面板'));
      expect(find.byType(DetailPanel), findsOneWidget);
      expect(find.text('正在播放'), findsOneWidget);
      await tap(tester, find.byTooltip('收起面板'));
      expect(find.byType(DetailPanel), findsNothing);
    });
  });

  group('wide', () {
    testWidgets('the sidebar reaches the four tabs, its field opens search, '
        'and the detail panel collapses', (tester) async {
      await start(tester, desktop);
      expect(find.byType(SideBar), findsOneWidget);
      expect(find.byType(DetailPanel), findsOneWidget);

      Finder inSide(String text) =>
          find.descendant(of: find.byType(SideBar), matching: find.text(text));
      for (final (label, page) in [
        ('音樂庫', LibraryPage),
        ('佇列', QueuePage),
        ('首頁', HomePage),
      ]) {
        await tap(tester, inSide(label));
        expect(find.byType(page), findsOneWidget);
      }

      await tap(tester, find.byType(TextField));
      expect(find.byType(SearchPage), findsOneWidget);
      await tap(tester, inSide('首頁'));
      expect(find.byType(HomePage), findsOneWidget);

      await tap(tester, find.byTooltip('收起面板'));
      expect(find.byType(DetailPanel), findsNothing);
      await tap(tester, find.byTooltip('顯示詳情面板'));
      expect(find.byType(DetailPanel), findsOneWidget);
    });

    testWidgets('settings opens with the detail panel collapsed', (
      tester,
    ) async {
      await start(tester, desktop);
      await tap(
        tester,
        find.descendant(of: find.byType(SideBar), matching: find.text('設定')),
      );
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byType(DetailPanel), findsNothing);

      await tap(
        tester,
        find.descendant(of: find.byType(SideBar), matching: find.text('首頁')),
      );
      expect(find.byType(DetailPanel), findsOneWidget);
    });

    testWidgets('the search field shows the shortcut of the platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await start(tester, desktop);
      expect(find.text('⌘K'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
