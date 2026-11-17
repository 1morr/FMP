import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:material_ui/material_ui.dart';

/// 從外殼進搜尋頁，不管現在是哪種寬度：手機點搜尋圓鈕，中寬度點細欄的
/// 搜尋項目，桌面點側欄的搜尋欄。integration_test 在各平台的視窗大小不同，
/// 也用這個。
Future<void> openSearch(WidgetTester tester) async {
  final label = t.shell.nav.search;
  final orb = find.byTooltip(label);
  final railItem = find.text(label);
  await tester.tap(
    orb.evaluate().isNotEmpty
        ? orb
        : railItem.evaluate().isNotEmpty
        ? railItem.first
        : find.byType(TextField),
  );
  // 不用 pumpAndSettle：頁面上可能有不停的動畫（載入中的轉圈）。
  for (var i = 0; i < 20 && find.byType(SearchPage).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(SearchPage), findsOneWidget);
}

/// 從外殼切到導覽的 [destination]，不管現在是哪種寬度：側欄、細欄、手機的
/// 分頁列都點它的名稱；手機在搜尋頁時分頁列收成返回圓鈕（「回到<進搜尋前的
/// 分頁>」），先點它回到分頁列。
Future<void> openDestination(
  WidgetTester tester,
  Destination destination,
) async {
  final tab = find.text(destination.label(t));
  if (tab.evaluate().isEmpty) {
    final backTo = {
      for (final tab in Destination.tabs) t.shell.nav.backTo(tab: tab.label(t)),
    };
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tooltip && backTo.contains(w.message)),
    );
    // 等分頁列從圓鈕變回來；變形中的分頁點不到。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  await tester.tap(tab.first);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
