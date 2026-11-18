import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 實跑的範例情境（票 08b）：啟動後不動視窗先截一張，匿名搜一次 B 站、播
/// 一首（spec〈共同規則〉的聯網規則；點一首是臨時播放），進佇列頁讀回。
/// 之後的票照這個寫自己的情境。跑法見 docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/search_and_play_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search Bilibili once, play the first result, read the queue', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);

    // 搜尋：外殼依視窗寬度換入口（test/support/shell.dart）。
    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final more = find.byTooltip(t.queue.more);
    await run.waitFor(more);
    await run.step('search');

    // 點第一首（臨時播放，桌面雙擊）：曲名出現在迷你播放器或播放膠囊，
    // 狀態到播放中。
    final title = searchResultTitle(tester, 0);
    await playSearchResult(tester, searchResultAt(0));
    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    await run.waitFor(
      find.descendant(of: controls, matching: find.text(title)),
    );
    await run.waitFor(find.text(t.placeholder.playback.playing));
    await run.step('playing');

    // 佇列頁：點導覽的「佇列」。臨時播放的曲目不在佇列裡，佇列還是空的。
    await openDestination(tester, Destination.queue);
    await run.waitFor(find.byType(QueuePage));
    final queue = await run.step('queue', within: find.byType(QueuePage));
    expect(queue, contains(t.queue.empty.title));
  });
}
