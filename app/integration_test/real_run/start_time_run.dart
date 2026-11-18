import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/search/placeholder_search.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 11 的量測情境：看門狗的門檻（「開始載入到出聲」「播放中途卡住」）照
/// 四平台量到的最慢值再留餘裕。匿名搜一次「lofi 3小时」，臨時播放結果裡
/// 最長的一首（長片）與最短的一首，各記下解析、開始載入到出聲的時間，以及
/// 出聲後 20 秒內緩衝了幾次、最久多久。跑法見 docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/start_time_run.dart
///
/// 播兩首，比 spec〈共同規則〉的「播一首」多一首：要比長片與短曲。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('time from loading to sound, long and short track', (
    tester,
  ) async {
    final run = await RealRun.launch(tester);

    await openSearch(tester);
    await tester.enterText(find.byType(TextField), 'lofi 3小时');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    final more = find.byTooltip(t.queue.more);
    await run.waitFor(more);
    await run.step('search');

    final container = ProviderScope.containerOf(tester.element(more.first));
    final tracks = {
      for (final results in container.read(placeholderSearchProvider)!.value!)
        for (final track in results.tracks) track.ref: track,
    };
    // 只挑畫出來的列（列表是懶建的），[searchResultAt] 數的也是它們。
    final rows = find.byWidgetPredicate((w) => w.key is ValueKey<TrackRef>);
    final durations = <int, Duration>{};
    for (final (i, row) in rows.evaluate().indexed) {
      final ref = (row.widget.key! as ValueKey<TrackRef>).value;
      if (tracks[ref]?.duration case final d?) durations[i] = d;
    }
    expect(durations, isNotEmpty);
    final byLength = durations.keys.toList()
      ..sort((a, b) => durations[b]!.compareTo(durations[a]!));
    final picks = [('long', byLength.first), ('short', byLength.last)];

    final report = <String>[];
    addTearDown(() {
      // ignore: avoid_print -- 量到的數字留在實跑的輸出裡，寫進票的 Comments。
      print('[start time]\n  ${report.join('\n  ')}');
    });

    for (final (name, index) in picks) {
      final title = searchResultTitle(tester, index);
      final length = formatDuration(durations[index]!);
      DateTime? tapped, loading, playing, bufferingSince;
      var stalls = 0;
      var longestStall = Duration.zero;
      final sub = container.listen<PlaybackState?>(playbackProvider, (_, s) {
        if (s == null || s.track.title != title) return;
        final now = DateTime.now();
        switch (s.status) {
          case PlaybackStatus.loading:
            loading ??= now;
          case PlaybackStatus.playing:
            playing ??= now;
            if (bufferingSince case final since?) {
              final stall = now.difference(since);
              if (stall > longestStall) longestStall = stall;
              bufferingSince = null;
            }
          case PlaybackStatus.buffering when playing != null:
            if (bufferingSince == null) stalls++;
            bufferingSince ??= now;
          default:
            break;
        }
      });
      tapped = DateTime.now();
      await playSearchResult(tester, searchResultAt(index));
      await run.waitFor(
        find.text(t.placeholder.playback.playing),
        timeout: const Duration(seconds: 120),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 20)),
      );
      sub.close();
      final resolve = loading!.difference(tapped).inMilliseconds;
      final start = playing!.difference(loading!).inMilliseconds;
      report.add(
        '$name ($length): resolve $resolve ms, loading to sound $start ms, '
        'stalls in 20 s after sound: $stalls (longest '
        '${longestStall.inMilliseconds} ms)',
      );
      await run.step(name);
    }
  });
}
