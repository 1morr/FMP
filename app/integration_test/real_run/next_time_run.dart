import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/search/placeholder_search.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 12 的量測情境：「按下一首到出聲」與「播完接下一首」。匿名搜一次
/// 「lofi」，把畫出來的結果都加進佇列，第一首播 [_listen] 後按迷你播放器
/// （或播放膠囊）的下一首，連按 [_presses] 次，各記下按下到開始載入
/// （解析）、開始載入到出聲、按下到出聲；最後那首跳到結尾前 5 秒，記播完
/// 到下一首出聲隔了多久。播不了的那首（CDN 拒絕）佇列會跳過，記成跳過、
/// 不算樣本。跑法見 docs/development.md〈實跑驅動〉：
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/next_time_run.dart
///
/// 解析 [_presses] + 2 首以上，比 spec〈共同規則〉的「播一首」多：要多個
/// 樣本，也要量播完接下一首。每首先播 [_listen]，預載（票 12）才有時間做完。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('time from next to sound, pressed and at the end', (
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
    final tracks = {
      for (final results in container.read(placeholderSearchProvider)!.value!)
        for (final track in results.tracks) track.ref: track,
    };
    // 只挑畫出來的列（列表是懶建的）。
    final rows = find.byWidgetPredicate((w) => w.key is ValueKey<TrackRef>);
    final picks = [
      for (final row in rows.evaluate())
        tracks[(row.widget.key! as ValueKey<TrackRef>).value]!,
    ];
    expect(picks.length, greaterThanOrEqualTo(_presses + 2));

    final report = <String>[];
    addTearDown(() {
      // ignore: avoid_print -- 量到的數字留在實跑的輸出裡，整理進 docs/research/。
      print('[next time]\n  ${report.join('\n  ')}');
    });

    Track? playingTrack() => switch (container.read(playbackProvider)) {
      PlaybackState(status: PlaybackStatus.playing, :final track) => track,
      _ => null,
    };

    // 等到 [test] 對正在出聲的那首成立：條件成立時這個 finder 找得到所有
    // 元件，否則找不到。播不了的那首佇列會跳過（票 11），等的是下一首出聲。
    Future<Track> waitPlaying(bool Function(Track track) test) async {
      await run.waitFor(
        find.byWidgetPredicate(
          (_) => switch (playingTrack()) {
            final track? => test(track),
            null => false,
          },
        ),
        timeout: const Duration(seconds: 120),
      );
      return playingTrack()!;
    }

    Future<void> listen() =>
        tester.runAsync(() => Future<void>.delayed(_listen));

    Track upcoming() => container.read(queueProvider).upcoming!.track;

    // 加入佇列：佇列是空的，開始播第一首。
    await container.read(queueProvider.notifier).add(picks);
    var current = await waitPlaying((_) => true);
    await listen();
    await run.step('first');

    final next = find.byTooltip(t.nowPlaying.next);
    for (var i = 1; i <= _presses; i++) {
      final track = upcoming();
      final times = _Times.watch(container, track);
      times.tapped = DateTime.now();
      await tester.tap(next.first);
      final previous = current;
      current = await waitPlaying((t) => t != previous);
      times.close();
      report.add(
        current != track
            ? 'press $i: ${track.ref.logId} could not play, skipped'
            : 'press $i (${formatDuration(track.duration ?? Duration.zero)}): '
                  'resolve ${times.resolve} ms, loading to sound '
                  '${times.start} ms, next to sound ${times.total} ms',
      );
      await listen();
      await run.step('next-$i');
    }

    // 播完接下一首：跳到結尾前 5 秒，記播完（或換曲）到下一首出聲。
    final following = upcoming();
    final length = container.read(playbackProvider)!.effectiveDuration!;
    final times = _Times.watch(container, following, endOf: current);
    await container
        .read(playbackProvider.notifier)
        .seek(length - const Duration(seconds: 5));
    final previous = current;
    current = await waitPlaying((t) => t != previous);
    times.close();
    report.add(
      current != following
          ? 'at the end: ${following.ref.logId} could not play, skipped'
          : 'at the end: end of the previous to sound ${times.gap} ms '
                '(resolve ${times.resolve} ms, loading to sound '
                '${times.start} ms)',
    );
    await run.step('at-the-end');
  });
}

/// 按幾次下一首；之後再量一次播完接下一首。
const _presses = 3;

/// 每首先播多久再按下一首。
const _listen = Duration(seconds: 15);

/// 一次換曲的時間點，從 [playbackProvider] 的狀態變化記。
class _Times {
  _Times.watch(ProviderContainer container, Track track, {Track? endOf}) {
    _subscription = container.listen<PlaybackState?>(playbackProvider, (
      previous,
      s,
    ) {
      final now = DateTime.now();
      if (endOf != null &&
          ended == null &&
          previous?.track == endOf &&
          (s?.track != endOf || s?.status == PlaybackStatus.completed)) {
        ended = now;
      }
      if (s == null || s.track != track) return;
      switch (s.status) {
        case PlaybackStatus.resolving:
          resolving ??= now;
        case PlaybackStatus.loading:
          resolving ??= now;
          loading ??= now;
        case PlaybackStatus.playing:
          resolving ??= now;
          loading ??= now;
          playing ??= now;
        default:
          break;
      }
    });
  }

  late final ProviderSubscription<PlaybackState?> _subscription;
  DateTime? tapped, ended, resolving, loading, playing;

  void close() => _subscription.close();

  int get resolve => loading!.difference(tapped ?? ended!).inMilliseconds;
  int get start => playing!.difference(loading!).inMilliseconds;
  int get total => playing!.difference(tapped!).inMilliseconds;
  int get gap => playing!.difference(ended!).inMilliseconds;
}
