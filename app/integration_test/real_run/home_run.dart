import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/home/chart_rows.dart';
import 'package:fmp/ui/now_playing/mini_player.dart';
import 'package:fmp/ui/now_playing/transport_bar.dart';
import 'package:integration_test/integration_test.dart';

import 'driver.dart';

/// 票 18 的實跑：開 App 後首頁抓一次 B 站排行榜（匿名，spec〈共同規則〉的
/// 聯網規則），截到榜（macOS 先把視窗拉到寬版 1280×800，只有一個音源時 10 名
/// 排成兩欄，票 18b）；點第 1 名臨時播放（觸控點一下、桌面雙擊），讀回播放
/// 控制與播放狀態。跑法見 docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/home_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the home page shows the Bilibili chart and plays the top '
      'track', (tester) async {
    final run = await RealRun.launch(tester);

    final rows = find.byWidgetPredicate(
      (w) => w is HomeTouchRow || w is ChartDeskRow,
    );
    await run.waitFor(rows, timeout: const Duration(seconds: 30));
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await run.system('resize-wide', 'resize', ['1280x800']);
    }
    final home = await run.step('chart');
    expect(home, contains(t.home.charts));

    final top = switch (tester.widget(rows.first)) {
      HomeTouchRow(:final track) || ChartDeskRow(:final track) => track,
      _ => throw StateError('not a chart row'),
    };
    await tester.tap(rows.first);
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(rows.first);
    }
    await tester.pump();
    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    await run.waitFor(
      find.descendant(of: controls, matching: find.text(top.title)),
    );
    await run.waitForStatus(PlaybackStatus.playing);
    await run.step('playing');
  });
}
