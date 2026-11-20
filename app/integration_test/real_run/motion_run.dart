import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/search/parts.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/search/search_rows.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 19d 的實跑：換歌、搜尋多選、展開分 P、佇列移除各截一張動畫中途（放慢
/// 30 倍，`RealRun.slowly`）與結束。整段只匿名搜一次「陈楚生 高品质音乐合集」（結果裡有
/// 多 P 影片），用選單把兩首單 P 的結果加入佇列（第一首開始播），按下一首換到
/// 第二首：共兩次 playurl、展開時一次 pagelist，另有開 App 時照常抓一次榜。
///
///     dart run tool/real_run.dart -d macos --out build/real_run-motion integration_test/real_run/motion_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('song change, multi-select, parts and queue removal animate', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), '陈楚生 高品质音乐合集');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    final toggle = find.byType(PartsToggle);
    // 結果與分 P 數都到齊；只等，不再搜。
    await run.waitFor(toggle, timeout: const Duration(seconds: 60));
    await run.step('results');

    final results = find.byWidgetPredicate((w) => w.key is ValueKey<TrackRef>);
    Track trackOf(Finder row) => switch (tester.widget(row)) {
      SearchTouchRow(:final track) || SearchTableRow(:final track) => track,
      final other => throw StateError('not a search result: $other'),
    };
    final pointer =
        FormFactor.of(tester.element(results.first)).density == Density.pointer;

    // 兩首單 P 的結果（沒有分 P 箭頭的列）。
    final singles = <Finder>[];
    for (var i = 0; singles.length < 2; i++) {
      final row = results.at(i);
      final hasParts = find
          .descendant(of: row, matching: toggle)
          .evaluate()
          .isNotEmpty;
      if (!hasParts) singles.add(find.byKey(ValueKey(trackOf(row).ref)));
    }

    Future<void> addToQueue(Finder row) async {
      if (pointer) {
        await tester.tap(
          row,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
        );
      } else {
        await tester.tap(
          find.descendant(of: row, matching: find.byTooltip(t.queue.more)),
        );
      }
      await run.waitFor(find.text(t.queue.actions.addToQueue));
      // 手機的 sheet 升起要 520ms：升好才點，不然點到的是還在畫面外的位置。
      await run.wait(const Duration(milliseconds: 800));
      await tester.tap(find.text(t.queue.actions.addToQueue));
      await run.wait(const Duration(seconds: 1));
    }

    await addToQueue(singles[0]);
    await run.waitForStatus(
      PlaybackStatus.playing,
      timeout: const Duration(seconds: 60),
    );
    await addToQueue(singles[1]);
    expect(container.read(queueProvider).entries, hasLength(2));
    // 等封面載好，換歌時才看得到交叉淡出。
    await run.wait(const Duration(seconds: 3));

    // 換歌：迷你播放器或播放膠囊（與桌面的詳情面板）的封面交叉淡出。
    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    await run.slowly(
      'song-change',
      () => tester.tap(
        find
            .descendant(
              of: controls,
              matching: find.byTooltip(t.nowPlaying.next),
            )
            .first,
      ),
      after: const Duration(milliseconds: 500),
    );
    await run.waitForStatus(
      PlaybackStatus.playing,
      timeout: const Duration(seconds: 60),
    );

    // 搜尋多選：動作列從底部滑入（手機的 dock 同時往下離開）。
    if (pointer) {
      await tester.tap(singles[0], kind: PointerDeviceKind.mouse);
      await run.wait(const Duration(milliseconds: 600));
      await run.slowly('multi-select', () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.tap(singles[1], kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    } else {
      await run.slowly('multi-select', () async {
        final press = await tester.startGesture(tester.getCenter(singles[0]));
        await run.wait(kLongPressTimeout + const Duration(milliseconds: 100));
        await press.up();
      });
      await tester.tap(find.text(t.search.selection.cancel));
    }
    await run.wait(const Duration(seconds: 1));

    // 展開分 P：高度跟著長出來。
    final video = trackOf(
      find.ancestor(of: toggle.first, matching: results).first,
    );
    final videoRow = find.byKey(ValueKey(video.ref));
    // 捲回頂端（結果的第一個多 P 影片在那裡）；別用 ensureVisible，它會把列
    // 捲到頂列底下，點擊被頂列吃掉。
    await tester.drag(find.byType(SearchPage), const Offset(0, 3000));
    await run.wait(const Duration(seconds: 1));
    await run.slowly('parts-expand', () async {
      await tester.tap(
        find.descendant(
          of: videoRow,
          matching: find.byTooltip(t.search.parts.expand),
        ),
      );
      await tester.runAsync(() => container.read(partsProvider(video).future));
    }, after: const Duration(milliseconds: 500));

    // 佇列移除：不是正在播的那首（第一首）收起並淡出，資料馬上就沒有它。
    await openDestination(tester, Destination.queue);
    await run.wait(const Duration(seconds: 1));
    final first = container.read(queueProvider).entries.first.track;
    final firstRow = find
        .ancestor(
          of: find.text(first.title).last,
          matching: find.byWidgetPredicate(
            (w) =>
                w.runtimeType.toString().startsWith('Queue') &&
                w.runtimeType.toString().endsWith('Row'),
          ),
        )
        .first;
    await run.step('queue-before');
    await run.slowly('queue-remove', () async {
      if (pointer) {
        await tester.tap(firstRow, kind: PointerDeviceKind.mouse);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      } else {
        await tester.tap(
          find.descendant(
            of: firstRow,
            matching: find.byKey(const Key('queue-remove')),
          ),
        );
      }
      expect(container.read(queueProvider).entries, hasLength(1));
    }, after: const Duration(milliseconds: 300));
  });
}
