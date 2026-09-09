import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_layout.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/layouts/responsive_scaffold.dart';

/// 收起態導覽軌在矮視窗的行為（#84）。
///
/// 橫向手機約 411dp 高，扣掉迷你播放器之後導覽軌拿到的更少；六個目的地加展開
/// 按鈕要約 540dp。以前這裡是 `Column` + `Expanded`，放不下就把最後一個目的地
/// 擠出可視區 —— 而最後一個是「設定」，六個裡唯一沒有其他入口的那個。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocale(AppLocale.en));

  Future<int?> pumpRail(
    WidgetTester tester, {
    required double height,
    bool withExpandButton = true,
  }) async {
    int? selected;
    await tester.binding.setSurfaceSize(Size(AppLayout.railCollapsed, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: AppLayout.railCollapsed,
                  child: CollapsedNavRail(
                    selectedIndex: 0,
                    onDestinationSelected: (index) => selected = index,
                    onExpand: withExpandButton ? () {} : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return selected;
  }

  testWidgets('411dp tall fits without overflowing', (tester) async {
    await pumpRail(tester, height: 411);

    // `RenderFlex overflowed` 會被 `FlutterError.onError` 收成一個 exception，
    // 測試框架在這裡就會看到它。這條在改成 scrollable 之前是紅的。
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings can be reached by scrolling the rail', (tester) async {
    await pumpRail(tester, height: 411);

    final settings = find.text(t.nav.settings);
    expect(
      settings,
      findsOneWidget,
      reason: 'the destination is built, it is only off-screen',
    );

    // 軌只有 72dp 寬，捲動手勢必須落在軌自己身上而不是被旁邊的內容區搶走。
    await tester.drag(find.byType(NavigationRail), const Offset(0, -200));
    await tester.pumpAndSettle();

    await tester.tap(settings);
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'tapping settings must not hit an off-screen widget',
    );
  });

  testWidgets('the expand button stays pinned while destinations scroll', (
    tester,
  ) async {
    await pumpRail(tester, height: 411);

    final menuButton = find.byIcon(Icons.menu);
    final before = tester.getTopLeft(menuButton);

    await tester.drag(find.byType(NavigationRail), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(menuButton), before);
  });

  testWidgets('the tablet rail has no expand button', (tester) async {
    await pumpRail(tester, height: 411, withExpandButton: false);

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tall window still shows every destination on screen', (
    tester,
  ) async {
    await pumpRail(tester, height: 900);

    final railBottom = tester.getRect(find.byType(NavigationRail)).bottom;
    expect(
      tester.getRect(find.text(t.nav.settings)).bottom,
      lessThan(railBottom),
    );
    expect(tester.takeException(), isNull);
  });
}
