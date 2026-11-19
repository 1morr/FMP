import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 16 的實跑：啟動後不動視窗先截一張，匿名搜一次 B 站、播一首（點一首是
/// 臨時播放），從迷你播放器（桌面是播放膠囊左邊）打開播放頁，拖進度到一半，
/// 手機滑到佇列畫面、桌面關掉再打開右欄的佇列，讀回畫面。macOS 不改視窗大小，
/// 截到的紅綠燈就是啟動後的位置（票 05d）。
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/player_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open the player, seek, and swipe to the queue', (tester) async {
    final run = await RealRun.launch(tester);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await run.waitFor(find.byTooltip(t.queue.more));
    final title = searchResultTitle(tester, 0);
    await playSearchResult(tester, searchResultAt(0));
    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    await run.waitFor(
      find.descendant(of: controls, matching: find.text(title)),
    );
    await run.waitForStatus(PlaybackStatus.playing);
    await run.step('playing');

    // 打開播放頁：手機點迷你播放器，桌面點播放膠囊左邊的封面與曲名。
    final desktop = find.byKey(const Key('transport-open'));
    await tester.tap(
      desktop.evaluate().isNotEmpty
          ? desktop
          : find.byKey(const Key('mini-player')),
      warnIfMissed: false,
    );
    await run.waitFor(find.byType(PlayerPage));
    await run.step('player', within: find.byType(PlayerPage));

    // 拖進度到一半：放開後播放位置跳到那附近。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
    );
    final duration = container.read(playbackProvider)!.effectiveDuration!;
    final bar = find.byKey(const Key('player-progress'));
    final box = tester.getRect(bar);
    final gesture = await tester.startGesture(
      Offset(box.left + box.width * .2, box.top + 12),
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveTo(Offset(box.left + box.width * .5, box.top + 12));
    await gesture.up();
    await run.step('seeked', within: find.byType(PlayerPage));
    await run.waitForStatus(PlaybackStatus.playing);
    final position = container.read(playbackProvider)!.position;
    expect(
      (position - duration * .5).abs() < const Duration(seconds: 15),
      isTrue,
      reason: 'seeked to $position of $duration',
    );

    final pages = find.byKey(const Key('player-pages'));
    if (pages.evaluate().isNotEmpty) {
      // 手機：往右滑到佇列畫面。
      await tester.fling(pages, const Offset(300, 0), 1000);
      await run.waitFor(find.text(t.queue.upNext));
      await run.step('queue', within: find.byType(PlayerPage));
    } else {
      // 桌面：右欄的佇列關掉再打開。
      final toggle = find.byKey(const Key('player-queue-toggle'));
      await tester.tap(toggle);
      await run.step('queue-off', within: find.byType(PlayerPage));
      await tester.tap(toggle);
      await run.waitFor(find.text(t.player.queue));
      await run.step('queue-on', within: find.byType(PlayerPage));
    }
  });
}
