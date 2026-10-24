import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/external_import.dart';
import 'package:fmp/ui/library/import_preview_page.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../support/shell_harness.dart';
import 'import_preview_harness.dart';

// 匯入預覽頁（M4 PR 19，design §10.9）：改選、重搜、排除、建立、取消確認、`truncated` 提示、讀取失敗。
// 環境見 import_preview_harness.dart。

void main() {
  testWidgets('before matching it shows the count, the searches per song and '
      'the targets; nothing is searched yet', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);

    expect(find.byType(ImportPreviewPage), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('From Test Source'), findsOneWidget);
    expect(find.text('3 songs · each searched on 1 source'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'video'), findsOneWidget);
    expect(find.text('Waiting'), findsNWidgets(3));
    expect(env.target.searches, isEmpty);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create playlist'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('while a song is being searched the progress names it', (
    tester,
  ) async {
    final hold = Completer<List<TrackSummary>>();
    final env = PreviewHarness(
      results: (keyword) =>
          keyword.startsWith('Green') ? hold.future : previewResults(keyword),
    );
    await env.open(tester);
    await env.start(tester, animations: false);

    expect(find.text('Matching: Green Field'), findsOneWidget);

    hold.complete(const []);
    await env.settle(tester);

    expect(find.textContaining('Matching:'), findsNothing);
  });

  testWidgets('matching shows the chosen candidates, a failed match and the '
      'progress; creating is possible once every song has a result', (
    tester,
  ) async {
    final env = PreviewHarness();
    await env.open(tester);

    await env.start(tester);

    expect(find.text('Matched 3 of 3'), findsOneWidget);
    expect(find.text('Alice · video · 3:20 · 100%'), findsOneWidget);
    expect(find.text('No match'), findsOneWidget);
    expect(find.text('1 song left out'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create playlist'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('choosing another candidate replaces the match', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);

    await expandPreviewRow(tester, 'Blue Sky');
    await tester.tap(find.text('Blue Sky (Piano)'));
    await tester.pumpAndSettle();

    // 列上的摘要換成新選的那一首。
    expect(find.text('Blue Sky (Piano)'), findsNWidgets(2));
    expect(find.textContaining('Someone · video'), findsNWidgets(2));
  });

  testWidgets('searching again with your own words finds what the first '
      'search did not', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);

    await expandPreviewRow(tester, 'Red Moon');
    expect(find.text('No candidates'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search for'),
      'red moon live',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search again'));
    await env.settle(tester);

    expect(env.target.searches.last.keyword, 'red moon live');
    expect(find.text('No match'), findsNothing);
    expect(find.text('Red Moon (Live)'), findsNWidgets(2));
    expect(find.text('1 song left out'), findsNothing);
  });

  testWidgets('excluding a song keeps it out of the playlist; including it '
      'brings back its match', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);

    await expandPreviewRow(tester, 'Green Field');
    await tester.tap(find.widgetWithText(TextButton, 'Exclude'));
    await tester.pumpAndSettle();

    expect(find.text('Excluded'), findsOneWidget);
    expect(find.text('2 songs left out'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Include'));
    await tester.pumpAndSettle();
    expect(find.text('Excluded'), findsNothing);
    expect(find.text('1 song left out'), findsOneWidget);
  });

  testWidgets('creating writes a local playlist and opens it in place of the '
      'preview', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);
    await expandPreviewRow(tester, 'Green Field');
    await tester.tap(find.widgetWithText(TextButton, 'Exclude'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create playlist'));
    await env.settle(tester);

    expect(find.byType(ImportPreviewPage), findsNothing);
    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    expect(find.text('Playlist created'), findsOneWidget);
    final [playlist] = await env.playlists(tester);
    expect(playlist.kind, PlaylistKind.local);
    expect(playlist.name, 'Road trip');
    final entries = (await tester.runAsync(
      () => env.shell
          .container(tester)
          .read(playlistRepositoryProvider)
          .entries(playlist.id),
    ))!;
    expect([for (final e in entries) e.track.sourceId], ['v1']);

    // 返回回到音樂庫，不回到預覽。
    await tester.tap(find.byTooltip('Back (Esc)'));
    await env.settle(tester);
    expect(find.byType(ImportPreviewPage), findsNothing);
    expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
  });

  testWidgets('leaving asks first; keeping going stays, stopping throws the '
      'import away and writes nothing', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);

    await tester.tap(find.byTooltip('Cancel the import'));
    await tester.pumpAndSettle();
    expect(find.text('Stop importing?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Keep going'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportPreviewPage), findsOneWidget);

    // 再點一次「音樂庫」也先問。
    await tester.tap(ShellHarness.navigationItem(ShellDestination.library));
    await tester.pumpAndSettle();
    expect(find.text('Stop importing?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await env.settle(tester);

    expect(find.byType(ImportPreviewPage), findsNothing);
    expect(find.byType(LibraryPage).hitTestable(), findsOneWidget);
    expect(await env.playlists(tester), isEmpty);
  });

  testWidgets('a truncated source says only part of the playlist came', (
    tester,
  ) async {
    final env = PreviewHarness(
      onPage: (_) => previewPage(previewSongs, truncated: true),
    );
    await env.open(tester);

    expect(
      find.text('The source only provided part of the playlist'),
      findsOneWidget,
    );
    await env.start(tester);
    expect(find.text('Matched 3 of 3'), findsOneWidget);
    expect(
      find.text('The source only provided part of the playlist'),
      findsOneWidget,
    );
  });

  testWidgets('a page that cannot be read shows why and Retry', (tester) async {
    var fail = true;
    final env = PreviewHarness(
      onPage: (query) => switch (query.cursor) {
        null => previewPage([previewSongs.first], cursor: '1'),
        _ when fail => throw NetworkError(pluginId: 'fmp-test'),
        _ => previewPage([previewSongs.last]),
      },
    );
    await env.open(tester);

    expect(find.textContaining("Couldn't read the playlist"), findsOneWidget);
    expect(find.text('Start matching'), findsNothing);

    fail = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await env.settle(tester);
    expect(find.text('2 songs · each searched on 1 source'), findsOneWidget);
  });

  testWidgets('a failed read leaves without asking', (tester) async {
    final env = PreviewHarness(
      onPage: (_) => throw NetworkError(pluginId: 'fmp-test'),
    );
    await env.open(tester);

    await tester.tap(find.byTooltip('Cancel the import'));
    await env.settle(tester);

    expect(find.text('Stop importing?'), findsNothing);
    expect(find.byType(ImportPreviewPage), findsNothing);
  });

  testWidgets('a failed search says so and can be searched again', (
    tester,
  ) async {
    var fail = true;
    final env = PreviewHarness(
      results: (keyword) => keyword.startsWith('Green') && fail
          ? throw RateLimited(pluginId: 'video')
          : previewResults(keyword),
    );
    await env.open(tester);
    await env.start(tester);

    expect(find.text('Search failed'), findsOneWidget);
    fail = false;
    await expandPreviewRow(tester, 'Green Field');
    await tester.tap(find.widgetWithText(FilledButton, 'Search again'));
    await env.settle(tester);

    expect(find.text('Search failed'), findsNothing);
    expect(find.text('Carol · video · 3:00 · 100%'), findsWidgets);
  });

  testWidgets('unchecking a target before starting leaves nothing to start '
      'with', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);

    await tester.tap(find.widgetWithText(FilterChip, 'video'));
    await tester.pumpAndSettle();

    expect(find.text('Check at least one source'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start matching'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('wide windows put the original and the match side by side', (
    tester,
  ) async {
    final env = PreviewHarness();
    await env.open(tester, size: const Size(1400, 900));
    await env.start(tester);

    final original = tester.getTopLeft(find.text('Green Field').first);
    final match = tester.getTopLeft(find.text('Green Field').last);
    expect(match.dy, original.dy);
    expect(match.dx, greaterThan(original.dx));
  });

  testWidgets('a playlist of 1,000 songs scrolls', (tester) async {
    final songs = [
      for (var i = 0; i < 1000; i++)
        previewOrigin('t$i', 'Song $i', 'Artist', 200),
    ];
    final env = PreviewHarness(onPage: (_) => previewPage(songs));
    await env.open(tester);

    expect(find.text('1000 songs · each searched on 1 source'), findsOneWidget);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -20000),
      5000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Song 0'), findsNothing);
  });

  // 審查與實機的修正（M4 PR 19）。
  testWidgets('read and not started yet: leaving asks nothing', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);

    await tester.tap(find.byTooltip('Cancel the import'));
    await env.settle(tester);

    expect(find.text('Stop importing?'), findsNothing);
    expect(find.byType(ImportPreviewPage), findsNothing);
  });

  testWidgets('excluding a song before starting counts as a change: leaving '
      'asks', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await expandPreviewRow(tester, 'Green Field');
    await tester.tap(find.widgetWithText(TextButton, 'Exclude'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel the import'));
    await tester.pumpAndSettle();

    expect(find.text('Stop importing?'), findsOneWidget);
  });

  testWidgets('the system back key asks once', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('Stop importing?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    // 確認框開著時再按返回：關掉確認框，預覽還在。
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ImportPreviewPage), findsOneWidget);
  });

  testWidgets('Esc asks once', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Stop importing?'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('while the playlist is being created, back is held without '
      'asking', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);

    // 另一個 transaction 佔著資料庫：建立的寫入排在它後面，一直在建立中。
    final release = Completer<void>();
    final database = env.shell.container(tester).read(appDatabaseProvider);
    unawaited(database.transaction(() => release.future));
    await env.settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Create playlist'));
    await env.settle(tester);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await env.settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ImportPreviewPage), findsOneWidget);

    release.complete();
    await env.settle(tester);
    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    expect(await env.playlists(tester), hasLength(1));
  });

  testWidgets('when every song uses an earlier match it is ready to create '
      'without starting, and leaving asks nothing', (tester) async {
    final env = PreviewHarness();
    await env.open(tester);
    await env.start(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create playlist'));
    await env.settle(tester);
    expect(find.byType(PlaylistDetailPage), findsOneWidget);
    // Red Moon 匹配失敗也寫進了 match_results：再匯入一次全部沿用。
    env.target.searches.clear();
    unawaited(
      openImportPreview(
        tester.element(find.byType(PlaylistDetailPage)),
        pluginId: 'fmp-test',
        playlistId: 'remote-1',
      ),
    );
    await env.settle(tester);

    expect(find.text('Start matching'), findsNothing);
    expect(find.text('Matched 3 of 3'), findsOneWidget);
    expect(find.textContaining('3 use earlier matches'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create playlist'),
          )
          .onPressed,
      isNotNull,
    );
    expect(env.target.searches, isEmpty);

    await tester.tap(find.byTooltip('Cancel the import'));
    await env.settle(tester);
    expect(find.text('Stop importing?'), findsNothing);
    expect(find.byType(ImportPreviewPage), findsNothing);
  });

  testWidgets('in a compact window the header scrolls away with the list and '
      'the progress stays at the bottom', (tester) async {
    final songs = [
      for (var i = 0; i < 30; i++)
        previewOrigin('t$i', 'Song $i', 'Artist', 200),
    ];
    final env = PreviewHarness(onPage: (_) => previewPage(songs));
    await env.open(tester);
    await env.start(tester);
    expect(find.text('Road trip'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('Road trip').hitTestable(), findsNothing);
    expect(find.text('Match against').hitTestable(), findsNothing);
    expect(find.text('Matched 30 of 30').hitTestable(), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Create playlist').hitTestable(),
      findsOneWidget,
    );
  });

  // 大量搜尋前確認（M4b 驗收後）：要搜的次數 > largeSearchThreshold 才問。
  group('a large number of searches', () {
    PreviewHarness harness(int count) => PreviewHarness(
      onPage: (_) => previewPage([
        for (var i = 0; i < count; i++)
          previewOrigin('t$i', 'Song $i', 'Artist', 200),
      ]),
    );

    Future<void> press(WidgetTester tester) async {
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Start matching'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Start matching'));
      await tester.pumpAndSettle();
    }

    testWidgets('over the threshold asks first; cancel starts nothing', (
      tester,
    ) async {
      final env = harness(largeSearchThreshold + 1);
      await env.open(tester);
      await press(tester);

      expect(find.text('About ${largeSearchThreshold + 1} searches'), findsOne);
      // 一個目標：不建議減少目標。
      expect(find.textContaining('reduce'), findsNothing);
      expect(find.text('This will take a while.'), findsOne);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        find.text('About ${largeSearchThreshold + 1} searches'),
        findsNothing,
      );
      expect(find.widgetWithText(FilledButton, 'Start matching'), findsOne);
      expect(env.target.searches, isEmpty);
    });

    testWidgets('confirming starts matching', (tester) async {
      final env = harness(largeSearchThreshold + 1);
      await env.open(tester);
      await press(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await env.settle(tester, animations: false);

      expect(find.widgetWithText(FilledButton, 'Start matching'), findsNothing);
      expect(env.target.searches, isNotEmpty);
    });

    testWidgets('at the threshold it starts without asking', (tester) async {
      final env = harness(largeSearchThreshold);
      await env.open(tester);
      await press(tester);
      await env.settle(tester, animations: false);

      expect(find.textContaining('searches'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Start matching'), findsNothing);
      expect(env.target.searches, isNotEmpty);
    });
  });
}
