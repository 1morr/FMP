import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/platform/app_data_directory.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';
import 'persist_run.dart' show expectFileName;

/// 票 10 的實跑情境，後半：接著 `persist_run.dart` 留下的資料重開 App，讀回
/// 佇列與迷你播放器停在原本那首與位置、沒有自動播放；再按一次播放，從那個
/// 位置接著播。跑法見 `persist_run.dart`。
///
/// 比 spec〈共同規則〉的「播一首」多解析一次（前半播的那首，重開後再播）。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('after a restart the queue is back, paused where it was', (
    tester,
  ) async {
    final expected = await tester.runAsync(() async {
      final file = File('${(await appDataDirectory()).path}/$expectFileName');
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });
    final run = await RealRun.launch(tester, keepData: true);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FmpApp)),
    );
    PlaybackState? playback() => container.read(playbackProvider);
    Finder until(bool Function() condition) =>
        find.byWidgetPredicate((w) => w is MaterialApp && condition());

    final current = expected!['current'] as String;
    final atLeast = Duration(milliseconds: expected['atLeastMs'] as int);
    final atMost = Duration(milliseconds: expected['atMostMs'] as int);
    expect([
      for (final e in container.read(queueProvider).entries) e.track.title,
    ], expected['titles']);
    expect(container.read(queueProvider).current?.track.title, current);
    final restored = playback()!;
    expect(restored.track.title, current);
    expect(restored.status, PlaybackStatus.paused);
    expect(restored.position, greaterThanOrEqualTo(atLeast));
    expect(restored.position, lessThanOrEqualTo(atMost));
    // ignore: avoid_print -- 留在實跑的輸出裡。
    print('[restore] back at ${restored.position} (saved $atLeast–$atMost)');

    // 不自動播放：等一下還是暫停。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump();
    expect(playback()!.status, PlaybackStatus.paused);
    expect(playback()!.position, restored.position);

    await openDestination(tester, Destination.queue);
    await run.waitFor(find.byType(QueuePage));
    final lines = await run.step('queue-restored');
    expect(lines, contains(current));

    // 按播放膠囊或迷你播放器的播放鈕：從還原的位置接著播。
    await tester.tap(find.byTooltip(t.nowPlaying.play).first);
    await run.waitFor(
      until(() => playback()?.status == PlaybackStatus.playing),
      timeout: const Duration(seconds: 60),
    );
    final resumedAt = playback()!.position;
    // ignore: avoid_print -- 留在實跑的輸出裡。
    print('[restore] playing again at $resumedAt');
    expect(
      resumedAt,
      greaterThanOrEqualTo(restored.position - const Duration(seconds: 1)),
    );
    expect(resumedAt, lessThan(restored.position + const Duration(seconds: 8)));
    await run.step('resumed');
  });
}
