import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/queue/queue_view.dart';
import 'package:material_ui/material_ui.dart';

import '../../playback/fake_source_plugin.dart';
import '../support/shell_harness.dart';

// 分 P 曲目的顯示（M3 PR 20，design §11.1）：播放列、播放頁、佇列與播放歷史都顯示
// 「影片標題 · P2 分 P 標題」；不是分 P 的曲目照舊只有曲名。

TrackInfo _part(int index) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: 'v',
  cid: 10 + index,
  title: 'Part $index',
  uploader: 'Uploader',
  partIndex: index,
  parentTitle: 'The video',
);

const _composed = 'The video · P2 Part 2';

Finder get _barTitle => find.descendant(
  of: find.byKey(PlayerBar.titleKey),
  matching: find.text(_composed),
);

void main() {
  Future<ShellHarness> playParts(WidgetTester tester, Size size) async {
    final h = ShellHarness();
    await h.pumpShell(tester, size: size);
    expect(
      h.controller.addToQueue([for (var i = 1; i <= 3; i++) _part(i)]),
      isTrue,
    );
    unawaited(h.controller.jumpTo(1));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return h;
  }

  testWidgets('the player bar shows the composed title', (tester) async {
    await playParts(tester, const Size(400, 800));

    expect(_barTitle, findsOneWidget);
  });

  for (final size in const [Size(400, 800), Size(1000, 800)]) {
    testWidgets('the player page and the queue show the composed title at '
        '${size.width}', (tester) async {
      final h = await playParts(tester, size);

      await tester.tap(_barTitle);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.text(_composed), findsWidgets);

      await tester.tap(find.byKey(PlayerPage.closeKey));
      await tester.pumpAndSettle();
      await h.openQueue(tester);

      expect(find.byType(QueueView), findsOneWidget);
      for (final index in [1, 2, 3]) {
        expect(
          find.descendant(
            of: find.byType(QueueView),
            matching: find.text('The video · P$index Part $index'),
          ),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('the play history shows the composed title', (tester) async {
    final h = ShellHarness();
    await h.pumpApp(tester, const HistoryPage());
    await tester.runAsync(
      () => h
          .container(tester)
          .read(playHistoryRepositoryProvider)
          .record(_part(2), playedAt: DateTime.now(), limit: 100),
    );
    await h.loadSettings(tester);

    expect(find.text(_composed), findsOneWidget);
  });

  testWidgets('a skipped part is named with the composed title', (
    tester,
  ) async {
    final h = ShellHarness();
    h.plugin.respond = (request) => request.cid == 12
        ? throw Unavailable(
            reason: UnavailableReason.copyright,
            pluginId: 'fmp-test',
          )
        : [candidate('${request.sourceId}-${request.cid}.m4a')];
    await h.pumpShell(tester, size: const Size(400, 800));
    expect(
      h.controller.addToQueue([for (var i = 1; i <= 3; i++) _part(i)]),
      isTrue,
    );
    unawaited(h.controller.jumpTo(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(h.controller.queue.current?.cid, 13);
    expect(
      find.text('Skipped "$_composed": Not available: copyright restriction'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a track that is not a part shows only its title', (
    tester,
  ) async {
    final h = ShellHarness();
    await h.pumpShell(tester, size: const Size(400, 800));
    await h.play(tester, [summary('a')]);

    expect(
      find.descendant(
        of: find.byKey(PlayerBar.titleKey),
        matching: find.text('Song a'),
      ),
      findsOneWidget,
    );
  });
}
