import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/search/search_page.dart';
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
