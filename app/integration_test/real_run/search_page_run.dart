import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/search/search.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 14 的實跑：照稿的搜尋頁。搜一次、換一次排序（spec〈共同規則〉的最少
/// 請求：兩次搜尋、播一首），點一首臨時播放，用選單（觸控是 ⋮ 的 sheet，
/// 滑鼠是右鍵）加入佇列，多選，回到搜尋紀錄，最後讀回佇列頁。macOS 另外把
/// 視窗先拉到 1280×800 走寬版，最後縮到 960×720 截中寬度的表格。
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/search_page_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search, sort, play, add from the menu, pick several, and go '
      'back to the history', (tester) async {
    final run = await RealRun.launch(tester);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    // macOS 的預設視窗是中寬度；主要流程在寬版（1280×800）走，最後再縮回
    // 960×720 截中寬度。
    if (mac) {
      await run.system('resize-wide', 'resize', ['1280x800']);
      await tester.pump(const Duration(milliseconds: 500));
    }

    await openSearch(tester);
    await run.step('search-empty');

    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    Future<void> settled({SearchSort? sort}) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      bool done() {
        final s = container.read(searchProvider);
        return s != null &&
            !s.starting &&
            s.sources.every((x) => !x.loading) &&
            (sort == null || s.sort == sort);
      }

      while (!done() && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(done(), isTrue);
      await tester.pump();
    }

    await settled();
    await run.waitFor(searchResultAt(0));
    await run.step('results');

    // 換排序：排序鈕寫著目前的排序，選單只列插件宣告的。
    await tester.tap(find.text(t.search.sort.relevance));
    await run.waitFor(find.text(t.search.sort.viewCount));
    await run.step('sort-menu');
    await tester.tap(find.text(t.search.sort.viewCount).last);
    await settled(sort: SearchSort.viewCount);
    await run.waitFor(searchResultAt(0));
    await run.step('sorted');

    final pointer =
        FormFactor.of(tester.element(find.byType(SearchPage))).density ==
        Density.pointer;
    final second = searchResultTitle(tester, 1);

    // 臨時播放第一首（觸控點一下、桌面雙擊）。
    await playSearchResult(tester, searchResultAt(0));
    await run.waitForStatus(PlaybackStatus.playing);
    await run.step('playing');

    // 第二首用選單加入佇列：觸控是 ⋮ 的 sheet，滑鼠是右鍵選單。
    if (pointer) {
      await tester.tap(
        find.text(second).first,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
    } else {
      await tester.tap(
        find.descendant(
          of: searchResultAt(1),
          matching: find.byTooltip(t.queue.more),
        ),
      );
    }
    await run.waitFor(find.text(t.queue.actions.addToQueue));
    await run.step(pointer ? 'context-menu' : 'track-sheet');
    await tester.tap(find.text(t.queue.actions.addToQueue));
    await tester.pump(const Duration(milliseconds: 400));

    // 多選：滑鼠 ⌘／Ctrl 點選，觸控長按；動作列出現，再取消。
    if (pointer) {
      await tester.tap(searchResultAt(2), kind: PointerDeviceKind.mouse);
      final command = mac
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(command);
      await tester.tap(searchResultAt(3), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(command);
    } else {
      await tester.longPress(searchResultAt(2));
      await tester.tap(searchResultAt(3));
    }
    await run.waitFor(find.text(t.search.selection.selected(count: 2)));
    await run.step('multi-select');
    if (pointer) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    } else {
      await tester.tap(find.text(t.search.selection.cancel));
    }
    await tester.pump(const Duration(milliseconds: 300));

    // macOS：中寬度（細欄＋頁面頂端的搜尋欄＋窄表格）。
    if (mac) {
      await run.system('resize-medium', 'resize', ['960x720']);
      await run.waitFor(searchResultAt(0));
      await tester.pump(const Duration(milliseconds: 500));
      await run.step('medium');
    }

    // 佇列頁：選單加入的第二首在裡面。
    await openDestination(tester, Destination.queue);
    await run.waitFor(find.byType(QueuePage));
    final queue = await run.step('queue', within: find.byType(QueuePage));
    expect(queue.join('\n'), contains(second));

    // 回搜尋頁、清掉欄位：回到搜尋紀錄，剛才的「lofi」在上面。
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), '');
    await run.waitFor(find.text(t.search.history.title));
    await run.step('history');
  });
}
