import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';

// U PR 15（ADR 0035 §決定 13，R2.4）：iOS 的 Dart 端慣例。用 `TargetPlatform.iOS` 驗；實機（劉海、
// 動態島、手勢）留給 iOS 平台任務。

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
const _topInset = 47.0;
const _bottomInset = 34.0;

void _asIPhone(WidgetTester tester, {bool landscape = false}) {
  final padding = landscape
      ? const FakeViewPadding(left: 59, right: 59, bottom: 21)
      : const FakeViewPadding(top: _topInset, bottom: _bottomInset);
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

void main() {
  testWidgets('iOS pages use the Cupertino transition', (tester) async {
    _asIPhone(tester);
    await ShellHarness().pumpShell(tester, at: ShellDestination.home);

    final theme = Theme.of(tester.element(find.byType(AppShell)));
    // `CupertinoPageTransitionsBuilder` 在 `cupertino_ui` 套件（App 沒有直接依賴），以型別名比對。
    expect(
      theme.pageTransitionsTheme.builders[TargetPlatform.iOS].runtimeType
          .toString(),
      'CupertinoPageTransitionsBuilder',
    );
  }, variant: _ios);

  testWidgets('swiping right from the left edge goes back from an inner page', (
    tester,
  ) async {
    _asIPhone(tester);
    final h = ShellHarness();
    await h.pumpShell(
      tester,
      size: const Size(390, 844),
      at: ShellDestination.home,
    );
    await h.openHistory(tester);
    expect(find.byType(HistoryPage), findsOneWidget);
    expect(find.byType(LibraryPage).hitTestable(), findsNothing);

    await tester.dragFrom(const Offset(2, 400), const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
  }, variant: _ios);

  // 播放頁從底部上滑開、下滑關：照 Apple Music 的「正在播放」，往下拖關閉（跟著手指），不是右滑。
  group('the player page closes with a downward drag', () {
    final barTitle = find.descendant(
      of: find.byType(PlayerBar),
      matching: find.text('Song a'),
    );

    Future<void> openPlayer(WidgetTester tester, {Size? size}) async {
      _asIPhone(tester);
      final h = ShellHarness();
      await h.pumpShell(tester, size: size ?? const Size(390, 844));
      await h.play(tester, [summary('a'), summary('b')]);
      await tester.tap(barTitle);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
    }

    testWidgets('dragging down past half the height closes it', (tester) async {
      await openPlayer(tester);

      final gesture = await tester.startGesture(const Offset(195, 300));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 100));
      }
      // 跟著手指：放開之前頁面已經往下移。
      expect(tester.getTopLeft(find.byType(PlayerPage)).dy, greaterThan(400));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(PlayerBar).hitTestable(), findsOneWidget);
    }, variant: _ios);

    testWidgets('a quick flick down closes it', (tester) async {
      await openPlayer(tester);

      await tester.flingFrom(
        const Offset(195, 300),
        const Offset(0, 150),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
    }, variant: _ios);

    testWidgets('a short slow drag springs back and keeps it open', (
      tester,
    ) async {
      await openPlayer(tester);

      final gesture = await tester.startGesture(const Offset(195, 300));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsOneWidget);
      expect(tester.getTopLeft(find.byType(PlayerPage)).dy, 0);
      // 頁面照常可用：收合鈕仍關得掉。
      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
    }, variant: _ios);

    testWidgets('dragging up does nothing', (tester) async {
      await openPlayer(tester);

      // 不會拖出超過全螢幕。
      await tester.drag(find.byType(PlayerPage), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(tester.getTopLeft(find.byType(PlayerPage)).dy, 0);
    }, variant: _ios);
  });

  testWidgets('portrait: the page bar clears the notch and the navigation '
      'bar clears the home indicator', (tester) async {
    _asIPhone(tester);
    final h = ShellHarness();
    await h.pumpShell(
      tester,
      size: const Size(390, 844),
      at: ShellDestination.queue,
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byType(PageAppBar)).dy,
      greaterThanOrEqualTo(_topInset),
    );
    final labels = ShellHarness.navigationItem(ShellDestination.home);
    expect(
      tester.getBottomLeft(labels).dy,
      lessThanOrEqualTo(844 - _bottomInset),
    );
  }, variant: _ios);

  testWidgets('landscape: the side rail and the page stay out of the notch '
      'and the corners', (tester) async {
    _asIPhone(tester, landscape: true);
    final h = ShellHarness();
    await h.pumpShell(
      tester,
      size: const Size(852, 393),
      at: ShellDestination.queue,
    );
    await tester.pumpAndSettle();

    final rail = ShellHarness.navigationItem(ShellDestination.home);
    expect(tester.getTopLeft(rail).dx, greaterThanOrEqualTo(59));
    expect(
      tester.getTopRight(find.byType(PageAppBar)).dx,
      lessThanOrEqualTo(852 - 59),
    );
  }, variant: _ios);
}
