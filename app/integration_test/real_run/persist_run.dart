import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/platform/app_data_directory.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/playback/queue_saver.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 10 的實跑情境，前半：匿名搜一次「lofi」，前 2 首加入佇列（第 1 首開始
/// 播），播到一半（1:00 之後）就結束，App 跟著被關掉。後半是
/// `restore_run.dart`，接著這裡留下的資料重開。兩段要連著跑、中間不碰裝置：
///
///     dart run tool/device_lock.dart -- bash -c 'dart run tool/real_run.dart -d macos --out <暫存目錄>/persist integration_test/real_run/persist_run.dart && dart run tool/real_run.dart -d macos --out <暫存目錄>/restore integration_test/real_run/restore_run.dart'
///
/// 「播到一半」經播放層的 seek。後半要比對的曲名與位置寫在隔離資料目錄裡的
/// [expectFileName]。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a queue played halfway is saved when the app goes away', (
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
    Finder until(bool Function() condition) =>
        find.byWidgetPredicate((w) => w is MaterialApp && condition());

    final first = searchResultTitle(tester, 0);
    final second = searchResultTitle(tester, 1);
    for (final index in [0, 1]) {
      await tester.tap(more.at(index));
      await run.waitFor(find.text(t.queue.actions.addToQueue));
      await tester.tap(find.text(t.queue.actions.addToQueue));
      await run.waitFor(
        until(
          () =>
              container.read(queueProvider).entries.length == index + 1 &&
              find.text(t.queue.actions.addToQueue).evaluate().isEmpty,
        ),
      );
    }
    await run.waitFor(
      until(
        () =>
            playback()?.track.title == first &&
            playback()?.status == PlaybackStatus.playing,
      ),
      timeout: const Duration(seconds: 60),
    );

    await tester.runAsync(
      () => container
          .read(playbackProvider.notifier)
          .seek(const Duration(minutes: 1)),
    );
    await run.waitFor(
      until(() => playback()!.position >= const Duration(seconds: 63)),
    );
    await openDestination(tester, Destination.queue);
    await run.waitFor(find.byType(QueuePage));
    final lines = await run.step('queue-playing');
    expect(lines, containsAll([first, second]));

    // 等排著的寫入做完，記下存的位置給後半比對，然後就結束（App 被關掉）。
    await tester.runAsync(() => container.read(queueSaverProvider)!.idle);
    final saved = container.read(queueProvider);
    final position = playback()!.position;
    await tester.runAsync(() async {
      final file = File('${(await appDataDirectory()).path}/$expectFileName');
      file.writeAsStringSync(
        jsonEncode({
          'titles': [for (final e in saved.entries) e.track.title],
          'current': first,
          // 播放中每差 5 秒寫一次（`QueueSaver.positionStep`）。
          'atLeastMs': (position - QueueSaver.positionStep).inMilliseconds,
          'atMostMs': position.inMilliseconds,
        }),
      );
    });
    // ignore: avoid_print -- 留在實跑的輸出裡。
    print('[persist] quitting at $position, queue ${saved.entries.length}');
  });
}

/// 前半寫給後半的期望（隔離資料目錄裡）。
const expectFileName = 'persist_run_expect.json';
