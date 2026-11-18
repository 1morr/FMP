import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 09 的實跑情境：匿名搜一次「lofi」，第 1 首加入佇列、播到一半，臨時
/// 播放第 2 首，讓它播完，回到佇列的第 1 首並倒退 10 秒，讀回位置。跑法見
/// docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/temporary_run.dart
///
/// 驗收要的就是「播一首、臨時播另一首、再回去」，比 spec〈共同規則〉的
/// 「播一首」多解析兩次（臨時那首、回去時重新解析第 1 首）。App 還沒有拖
/// 進度的畫面（播放頁的票），「播到一半」與「讓它播完」經播放層的 seek。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a temporary track goes back to the queue track, rewound', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final more = find.byTooltip(t.queue.more);
    await run.waitFor(more);
    await run.step('search');

    final container = ProviderScope.containerOf(tester.element(more.first));
    PlaybackState? playback() => container.read(playbackProvider);
    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    final tag = find.descendant(
      of: controls,
      matching: find.text(t.nowPlaying.temporaryTag),
    );

    /// 條件成立才找得到東西的 finder，給 [RealRun.waitFor] 等狀態用。
    Finder until(bool Function() condition) =>
        find.byWidgetPredicate((w) => w is MaterialApp && condition());

    final queued = searchResultTitle(tester, 0);
    final detour = searchResultTitle(tester, 1);

    // 第 1 首加入佇列：佇列是空的，加入就開始播。
    await tester.tap(more.at(0));
    await run.waitFor(find.text(t.queue.actions.addToQueue));
    await tester.tap(find.text(t.queue.actions.addToQueue));
    await run.waitFor(
      until(
        () =>
            playback()?.track.title == queued &&
            playback()?.status == PlaybackStatus.playing,
      ),
      timeout: const Duration(seconds: 60),
    );

    // 播到一半：跳到 1:00 再播幾秒。
    await tester.runAsync(
      () => container
          .read(playbackProvider.notifier)
          .seek(const Duration(minutes: 1)),
    );
    await run.waitFor(
      until(() => playback()!.position >= const Duration(seconds: 63)),
    );
    await run.step('queue-playing');

    // 臨時播放第 2 首：播放控制標著「臨時」。
    await playSearchResult(tester, searchResultAt(1));
    await run.waitFor(
      find.descendant(of: controls, matching: find.text(detour)),
    );
    await run.waitFor(tag);
    await run.waitFor(
      until(() => playback()?.status == PlaybackStatus.playing),
      timeout: const Duration(seconds: 60),
    );
    final leftAt = container.read(temporaryPlayProvider)!.leftAt;
    expect(leftAt, greaterThanOrEqualTo(const Duration(seconds: 63)));
    await run.step('temporary');

    // 佇列頁：臨時播放的卡片插在第 1 首上方，寫明回去的地方。
    await openDestination(tester, Destination.queue);
    await run.waitFor(find.byKey(const Key('queue-temporary')));
    final page = find.byType(QueuePage);
    final during = await run.step('queue-temporary', within: page);
    final resumeAt = leftAt - const Duration(seconds: 10);
    expect(during, contains(t.queue.temporary.title));
    // 回去那一列的副標是「作者 · 回來時從 1:26 繼續」，讀回時整行一起。
    final note = t.queue.temporary.returnRow(
      position: formatDuration(resumeAt),
    );
    expect(during.where((line) => line.contains(note)), isNotEmpty);

    // 讓臨時那首播完：跳到結尾前 3 秒。
    final length = playback()!.effectiveDuration!;
    await tester.runAsync(
      () => container
          .read(playbackProvider.notifier)
          .seek(length - const Duration(seconds: 3)),
    );
    await run.waitFor(
      until(
        () =>
            playback()?.track.title == queued &&
            playback()?.status == PlaybackStatus.playing,
      ),
      timeout: const Duration(seconds: 60),
    );
    final backAt = playback()!.position;
    // ignore: avoid_print -- 讀回的位置留在實跑的輸出裡。
    print(
      '[temporary] left at ${formatDuration(leftAt)}, '
      'expected back from ${formatDuration(resumeAt)}, '
      'playing again at ${formatDuration(backAt)}',
    );
    // mpv 回報的位置只到毫秒，留 100 毫秒。
    expect(
      backAt,
      greaterThanOrEqualTo(resumeAt - const Duration(milliseconds: 100)),
    );
    expect(backAt, lessThan(resumeAt + const Duration(seconds: 8)));
    expect(tag, findsNothing);
    final after = await run.step('returned', within: page);
    expect(after, isNot(contains(t.queue.temporary.title)));
    expect(after, contains(queued));
  });
}
