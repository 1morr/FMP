import 'package:flutter/gestures.dart';
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
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/search/search_rows.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/shell.dart';
import 'driver.dart';

/// 票 15 的實跑：B 站分 P。匿名搜一次「陈楚生 高品质音乐合集」，找第一個帶
/// 分 P 數小標的結果，展開、整組臨時播放、按一次下一首換到第 2 個分 P，
/// 最後讀回佇列頁的臨時播放卡片。請求：search 一次、infos 一次、展開時的
/// pagelist、P1 的 pagelist 與 playurl、預載 P2 的 pagelist 與 playurl
/// （按下一首用預載的）。
///
///     dart run tool/real_run.dart -d macos integration_test/real_run/parts_run.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('expand the parts of a video, play the group, skip to part 2', (
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
    var read = await run.step('results');
    expect(read.any((line) => RegExp(r'^\d+P$').hasMatch(line)), isTrue);

    // 第一個帶分 P 數的列：它的列、曲目與分 P。
    final row = find
        .ancestor(
          of: toggle.first,
          matching: find.byWidgetPredicate((w) => w.key is ValueKey<TrackRef>),
        )
        .first;
    final video = switch (tester.widget(row)) {
      SearchTouchRow(:final track) || SearchTableRow(:final track) => track,
      final other => throw StateError('not a search result: $other'),
    };
    final key = ValueKey<TrackRef>(video.ref);
    // ignore: avoid_print -- 找到的影片留在實跑的輸出裡。
    print('[parts] ${video.title} (${video.partCount}P)');

    // 佇列頁要有一首佇列裡的歌，臨時播放的卡片才有地方插（佇列空著時頁面
    // 只顯示空狀態）：用選單把另一個結果加入佇列，它開始播。多一次 playurl。
    final other = find
        .byWidgetPredicate((w) => w.key is ValueKey<TrackRef> && w.key != key)
        .first;
    final pointer =
        FormFactor.of(tester.element(other)).density == Density.pointer;
    if (pointer) {
      await tester.tap(
        other,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
    } else {
      await tester.tap(
        find.descendant(of: other, matching: find.byTooltip(t.queue.more)),
      );
    }
    await run.waitFor(find.text(t.queue.actions.addToQueue));
    await tester.tap(find.text(t.queue.actions.addToQueue));
    await run.waitForStatus(
      PlaybackStatus.playing,
      timeout: const Duration(seconds: 60),
    );
    final queued = container.read(playbackProvider)!.track;
    await run.step('queued-one');

    // 展開：箭頭換成收起，分 P 列出來。
    await tester.tap(
      find.descendant(
        of: find.byKey(key),
        matching: find.byTooltip(t.search.parts.expand),
      ),
    );
    final parts = await tester.runAsync(
      () => container.read(partsProvider(video).future),
    );
    expect(parts!.length, video.partCount);
    await run.waitFor(find.text(t.search.parts.number(n: 2)));
    read = await run.step('expanded');
    expect(read, contains(parts[1].title));

    // 點父列：整組臨時播放，從 P1 開始。
    PlaybackState? playback() => container.read(playbackProvider);
    final controls = find.byWidgetPredicate(
      (w) => w is MiniPlayer || w is TransportBar,
    );
    final tag = find.descendant(
      of: controls,
      matching: find.text(t.nowPlaying.temporaryTag),
    );
    Finder until(bool Function() condition) =>
        find.byWidgetPredicate((w) => w is MaterialApp && condition());
    await playSearchResult(tester, find.byKey(key));
    await run.waitForStatus(
      PlaybackStatus.playing,
      timeout: const Duration(seconds: 60),
    );
    await run.waitFor(tag);
    expect(playback()!.track.ref, parts.first.ref);
    final playing1 = await run.step('playing-part-1', within: controls);
    expect(playing1, contains(parts.first.title));
    expect(playing1, contains(t.nowPlaying.temporaryTag));

    // 下一首：換到第 2 個分 P（預載好的）。
    await tester.tap(
      find
          .descendant(of: controls, matching: find.byTooltip(t.nowPlaying.next))
          .first,
    );
    await run.waitFor(
      until(
        () =>
            playback()?.track.ref == parts[1].ref &&
            playback()?.status == PlaybackStatus.playing,
      ),
      timeout: const Duration(seconds: 60),
    );
    final playing2 = await run.step('playing-part-2', within: controls);
    expect(playing2, contains(parts[1].title));
    expect(playing2, contains(t.nowPlaying.temporaryTag));
    expect(container.read(temporaryPlayProvider), isNotNull);

    // 佇列頁：臨時播放的卡片。
    await openDestination(tester, Destination.queue);
    await run.waitFor(find.byKey(const Key('queue-temporary')));
    final queue = await run.step('queue', within: find.byType(QueuePage));
    expect(queue, contains(t.queue.temporary.title));
    expect(queue, contains(queued.title));
  });
}
