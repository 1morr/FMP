import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/widgets/feedback/error_display.dart';

/// 空狀態與錯誤狀態在矮視窗的版面。
///
/// 橫向手機約 411dp 高，扣掉狀態列、工具列與迷你播放器後內容區約 267dp；完整
/// 版面以前固定約 300dp，實機在 Library、Radio、Queue 三頁都溢出 41px，錯誤
/// 狀態被裁掉的是「重試」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocale(AppLocale.en));

  Future<void> pumpIn(WidgetTester tester, Size size, Widget body) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(home: Scaffold(body: body)),
      ),
    );
  }

  final retry = find.text('Retry');
  final retryButton = find.ancestor(
    of: retry,
    matching: find.byWidgetPredicate((widget) => widget is FilledButton),
  );

  testWidgets('the retry button fits in a landscape phone content area', (
    tester,
  ) async {
    await pumpIn(
      tester,
      const Size(840, 267),
      ErrorDisplay.network(onRetry: () {}),
    );

    expect(tester.takeException(), isNull);
    // 整顆按鈕都在畫面內，不必捲動就按得到。
    expect(tester.getRect(retryButton).bottom, lessThanOrEqualTo(267));
  });

  testWidgets('large text scrolls to the retry button instead of clipping', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var retried = false;

    await pumpIn(
      tester,
      const Size(840, 267),
      ErrorDisplay.network(onRetry: () => retried = true),
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(retry, 50);
    await tester.tap(retry);
    expect(retried, isTrue);
  });

  testWidgets('a tall area keeps the full-size layout, centred', (
    tester,
  ) async {
    await pumpIn(
      tester,
      const Size(400, 800),
      ErrorDisplay.network(onRetry: () {}),
    );

    final icon = find.byIcon(Icons.wifi_off_rounded);
    expect(tester.getSize(icon).height, 80);
    // 內容比 800dp 矮很多，應該上下都有留白，而不是貼在頂端。
    expect(tester.getRect(icon).top, greaterThan(200));
  });

  testWidgets('inside an unbounded scroll view it lays out as is', (
    tester,
  ) async {
    await pumpIn(
      tester,
      const Size(400, 800),
      ListView(children: [ErrorDisplay.network(onRetry: () {})]),
    );

    expect(tester.takeException(), isNull);
    expect(retry, findsOneWidget);
  });
}
