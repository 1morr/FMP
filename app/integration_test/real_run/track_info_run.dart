import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/shell/detail_content.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 17 的實跑：啟動後不動視窗先截一張，匿名搜一次 B 站、播一首，桌面等詳情
/// 面板查到簡介（插件能力 `trackInfo`，這首查一次），按 ⌘I 打開曲目資訊；
/// 打開播放頁、點音源膠囊再打開一次（用同一份查過的結果），讀回畫面。macOS
/// 不改視窗大小。
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/track_info_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('look at the track info of one track', (tester) async {
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

    final desktop = find
        .byKey(const Key('transport-open'))
        .evaluate()
        .isNotEmpty;
    if (desktop) {
      // 詳情面板：停一秒後查曲目資訊，簡介或「沒有提供簡介」出現。
      await run.waitFor(
        find.descendant(
          of: find.byType(DetailContent),
          matching: find.text(t.shell.detail.description),
        ),
      );
      await run.waitFor(
        find.byWidgetPredicate(
          (w) =>
              w.key == const Key('detail-description') ||
              (w is Text && w.data == t.shell.detail.noDescription),
        ),
      );
      await run.step('detail', within: find.byType(DetailContent));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await run.waitFor(find.text(t.trackInfo.published));
      await run.step('shortcut-info');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(
      find.byKey(Key(desktop ? 'transport-open' : 'mini-player')),
      warnIfMissed: false,
    );
    await run.waitFor(find.byType(PlayerPage));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('player-signature')));
    await run.waitFor(find.text(t.trackInfo.published));
    await run.step('track-info');
  });
}
