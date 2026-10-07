import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/history/history_state.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/memory_database.dart';
import '../support/shell_harness.dart';

TrackInfo track(String id, {String? uploader = 'Artist'}) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: 'Song $id',
  uploader: uploader,
);

/// 測試裡的「現在」：本地時間 2026-10-07 15:30。日界依裝置的本地時間，所以測試也用
/// 本地時間造資料，不依賴執行的機器在哪個時區。
final now = DateTime(2026, 10, 7, 15, 30);

void main() {
  /// 寫一筆播放歷史（本地時間 [at]）；資料庫在 drift 的 isolate，要在真的事件迴圈裡跑。
  Future<void> record(
    WidgetTester tester,
    ShellHarness h,
    String id,
    DateTime at, {
    String? uploader = 'Artist',
  }) => tester.runAsync(
    () => h
        .container(tester)
        .read(playHistoryRepositoryProvider)
        .record(track(id, uploader: uploader), playedAt: at, limit: 100000),
  );

  Future<ShellHarness> openHistory(
    WidgetTester tester, {
    Size size = const Size(1000, 700),
  }) async {
    final h = ShellHarness();
    await h.pumpApp(tester, const HistoryPage(), size: size);
    return h;
  }

  /// 讓資料庫的變動送到頁面（變動的串流與重讀都是真的非同步）。
  Future<void> reload(WidgetTester tester, ShellHarness h) =>
      h.loadSettings(tester);

  group('grouping by day', () {
    testWidgets('today, yesterday, earlier this year and another year', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
        await record(tester, h, 'b', DateTime(2026, 10, 7, 0, 1));
        await record(tester, h, 'c', DateTime(2026, 10, 6, 23, 59));
        await record(tester, h, 'd', DateTime(2026, 3, 3, 8, 0));
        await record(tester, h, 'e', DateTime(2025, 12, 31, 23, 30));
        await reload(tester, h);

        double top(Finder finder) => tester.getTopLeft(finder).dy;
        final order = [
          find.text('Today'),
          find.text('Song a'),
          find.text('Song b'),
          find.text('Yesterday'),
          find.text('Song c'),
          // 同一年不帶年份。
          find.textContaining('Mar 3'),
          find.text('Song d'),
          // 跨年才帶年份。
          find.text('Dec 31, 2025'),
          find.text('Song e'),
        ];
        for (final finder in order) {
          expect(finder, findsOneWidget);
        }
        final tops = [for (final finder in order) top(finder)];
        expect(tops, orderedEquals([...tops]..sort()));
        expect(find.textContaining('2026'), findsNothing);
      });
    });

    testWidgets('a row shows the artist and the time as HH:mm', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
        await record(tester, h, 'b', DateTime(2026, 10, 7, 9, 7));
        await reload(tester, h);

        expect(find.text('Artist · 14:05'), findsOneWidget);
        expect(find.text('Artist · 09:07'), findsOneWidget);
      });
    });

    testWidgets('a song without an artist shows only the time', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await record(
          tester,
          h,
          'a',
          DateTime(2026, 10, 7, 14, 5),
          uploader: null,
        );
        await reload(tester, h);

        expect(find.text('14:05'), findsOneWidget);
      });
    });

    test('groupByDay starts a group at each local day change', () {
      PlayHistoryEntry entry(int id, DateTime local) => PlayHistoryEntry(
        id: id,
        playedAt: local.toUtc(),
        track: track('$id'),
      );
      final rows = groupByDay([
        entry(3, DateTime(2026, 10, 7, 12)),
        entry(2, DateTime(2026, 10, 7, 1)),
        entry(1, DateTime(2026, 10, 6, 23, 59)),
      ]);

      expect(
        [
          for (final row in rows)
            switch (row) {
              HistoryDay(:final day) => day.day,
              HistoryItem(:final entry) => -entry.id,
            },
        ],
        [7, -3, -2, 6, -1],
      );
    });
  });

  group('playing from the history', () {
    testWidgets('tapping a row plays it on its own (temporary play)', (
      tester,
    ) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await reload(tester, h);

      await tester.tap(find.text('Song a'));
      await tester.pump();
      await tester.pump();

      expect(h.controller.queue.mode, QueueMode.temporary);
      expect(h.controller.queue.current?.sourceId, 'a');
      expect(h.controller.queue.entries, isEmpty);
    });

    testWidgets('the menu has four items and plays, plays next and queues', (
      tester,
    ) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await record(tester, h, 'b', DateTime(2026, 10, 7, 14, 6));
      await reload(tester, h);

      await tester.tap(find.byTooltip('More options').first);
      await tester.pump();
      for (final label in [
        'Play',
        'Play next',
        'Add to queue',
        'Remove from history',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['b'],
        reason: 'the first row is the newest, b',
      );

      await tester.tap(find.byTooltip('More options').last);
      await tester.pump();
      await tester.tap(find.text('Play next'));
      await tester.pump();
      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['b', 'a'],
      );

      await tester.tap(find.byTooltip('More options').last);
      await tester.pump();
      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump();
      expect(h.controller.queue.mode, QueueMode.temporary);
      expect(h.controller.queue.current?.sourceId, 'a');
    });

    testWidgets('right click and long press open the same menu', (
      tester,
    ) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await record(tester, h, 'b', DateTime(2026, 10, 7, 14, 6));
      await reload(tester, h);

      await tester.tap(find.text('Song a'), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Remove from history'), findsOneWidget);
      await tester.tap(find.text('Play next'));
      await tester.pump();
      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['a'],
      );

      await tester.longPress(find.text('Song b'));
      await tester.pump();
      await tester.tap(find.text('Add to queue'));
      await tester.pump();
      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['a', 'b'],
      );
    });
  });

  group('removing', () {
    testWidgets('removes only that entry, without a toast', (tester) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 6));
      await record(tester, h, 'b', DateTime(2026, 10, 7, 14, 7));
      await reload(tester, h);
      expect(find.byType(ListTile), findsNWidgets(3));

      // 最新的是 b，其次是 a 的第二次、第一次：移除中間那一筆。
      await tester.tap(find.byTooltip('More options').at(1));
      await tester.pump();
      await tester.tap(find.text('Remove from history'));
      await tester.pump();
      await reload(tester, h);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Artist · 14:07'), findsOneWidget);
      expect(find.text('Artist · 14:05'), findsOneWidget);
      expect(find.text('Artist · 14:06'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('clearing everything', () {
    Future<ShellHarness> withTwoEntries(WidgetTester tester) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await record(tester, h, 'b', DateTime(2026, 10, 7, 14, 6));
      await reload(tester, h);
      return h;
    }

    testWidgets('asks first; cancelling keeps everything', (tester) async {
      final h = await withTwoEntries(tester);

      await tester.tap(find.byTooltip('Clear all history'));
      await tester.pumpAndSettle();
      expect(find.text('Clear all play history?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await reload(tester, h);

      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Play history cleared'), findsNothing);
    });

    testWidgets('confirming clears, says so once and shows the empty state', (
      tester,
    ) async {
      final h = await withTwoEntries(tester);

      await tester.tap(find.byTooltip('Clear all history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pump();
      await reload(tester, h);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Play history cleared'), findsOneWidget);
      expect(find.text('No play history yet'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('is disabled when there is nothing to clear', (tester) async {
      await openHistory(tester);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined),
      );
      expect(button.onPressed, isNull);
    });
  });

  testWidgets('with no records it shows the empty state', (tester) async {
    final h = await openHistory(tester);
    await reload(tester, h);

    expect(find.text('No play history yet'), findsOneWidget);
  });

  testWidgets('a failed load shows the error, not the empty state, and is '
      'reported once', (tester) async {
    final h = await openHistory(tester);
    await reload(tester, h);
    expect(find.text('No play history yet'), findsOneWidget);

    // 表不見了：下一次重讀失敗。
    final database = h.container(tester).read(appDatabaseProvider);
    await tester.runAsync(() async {
      await database.customStatement('DROP TABLE play_history');
      database.markTablesUpdated({database.playHistoryTable});
    });
    await reload(tester, h);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('No play history yet'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect([
      for (final record in h.log.history)
        if (record.message == 'Failed to load play history') record,
    ], hasLength(1));
  });

  testWidgets('it works offline; the cover is a placeholder', (tester) async {
    final h = ShellHarness();
    await h.pumpShell(tester);
    await tester.tap(find.text('History'));
    await tester.pump();
    await h.setNetwork(tester, NetworkStatus.noInterface);
    await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
    await reload(tester, h);

    expect(find.text('No network connection'), findsOneWidget);
    expect(find.text('Song a'), findsOneWidget);
    await tester.tap(find.text('Song a'));
    await tester.pump();
    expect(h.controller.queue.current?.sourceId, 'a');
  });

  group('paging', () {
    ProviderContainer containerWith(AppDatabase database) =>
        ProviderContainer.test(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
        );

    Future<AppDatabase> seeded(int count) async {
      final database = memoryDatabase();
      await database.customStatement(
        'INSERT INTO tracks (track_key, source_type_id, source_id, title, '
        "updated_at) VALUES ('fmp-test:a', 'fmp-test', 'a', 'T', 0)",
      );
      await database.customStatement(
        'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
        'WHERE i < $count) INSERT INTO play_history (track_key, played_at) '
        "SELECT 'fmp-test:a', i FROM n",
      );
      return database;
    }

    test('only the first page is read; the next one on loadMore', () async {
      final container = containerWith(await seeded(120));
      container.listen(historyProvider, (_, _) {});

      final first = await container.read(historyProvider.future);
      expect(first.entries, hasLength(historyPageSize));
      expect(first.hasMore, isTrue);
      expect(
        first.entries.first.playedAt.millisecondsSinceEpoch,
        120,
        reason: 'newest first',
      );

      final notifier = container.read(historyProvider.notifier);
      await notifier.loadMore();
      expect(
        container.read(historyProvider).value!.entries,
        hasLength(historyPageSize * 2),
      );
      await notifier.loadMore();
      final all = container.read(historyProvider).value!;
      expect(all.entries, hasLength(120));
      expect(all.hasMore, isFalse);
      expect(all.entries.last.playedAt.millisecondsSinceEpoch, 1);

      await notifier.loadMore();
      expect(container.read(historyProvider).value!.entries, hasLength(120));
    });

    test('a change reloads what is loaded, not just the first page', () async {
      final database = await seeded(120);
      final container = containerWith(database);
      container.listen(historyProvider, (_, _) {});
      await container.read(historyProvider.future);
      await container.read(historyProvider.notifier).loadMore();

      await PlayHistoryRepository(database).delete(
        (await PlayHistoryRepository(database).page(limit: 1)).single.id,
      );
      for (var round = 0; round < 50; round++) {
        if (container
                .read(historyProvider)
                .value!
                .entries
                .first
                .playedAt
                .millisecondsSinceEpoch ==
            119) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final state = container.read(historyProvider).value!;
      expect(state.entries.first.playedAt.millisecondsSinceEpoch, 119);
      expect(state.entries, hasLength(historyPageSize * 2));
    });

    test('a page read while a reload is in flight is dropped, not merged '
        'into the reloaded list', () async {
      final database = await seeded(120);
      final container = containerWith(database);
      container.listen(historyProvider, (_, _) {});
      await container.read(historyProvider.future);
      final notifier = container.read(historyProvider.notifier);
      final repository = PlayHistoryRepository(database);
      // 在 notifier 之後訂閱：它的監聽（重讀）先跑到第一個 await，這裡才開始讀下一頁，
      // 所以下一頁以重讀之前的清單算位移、在重讀之後回來（捲到底時剛好記了一筆）。
      final pageStarted = Completer<void>();
      final changes = repository.changes().listen((_) {
        if (pageStarted.isCompleted) return;
        pageStarted.complete();
        unawaited(notifier.loadMore());
      });
      addTearDown(changes.cancel);

      await repository.record(
        track('new'),
        playedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        limit: 100000,
      );
      await pageStarted.future;
      for (var round = 0; round < 20; round++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final entries = container.read(historyProvider).value!.entries;
      final ids = [for (final entry in entries) entry.id];
      expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicate rows');
      expect(entries.first.track.sourceId, 'new', reason: 'the new play shows');
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      final h = await openHistory(tester, size: const Size(400, 700));
      final database = h.container(tester).read(appDatabaseProvider);
      await tester.runAsync(() async {
        await database.customStatement(
          'INSERT INTO tracks (track_key, source_type_id, source_id, title, '
          "updated_at) VALUES ('fmp-test:a', 'fmp-test', 'a', 'T', 0)",
        );
        await database.customStatement(
          'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
          'WHERE i < 120) INSERT INTO play_history (track_key, played_at) '
          "SELECT 'fmp-test:a', i * 60000 FROM n",
        );
        // customStatement 不通知 drift 的串流。
        database.markTablesUpdated({database.playHistoryTable});
      });
      await reload(tester, h);
      expect(
        h.container(tester).read(historyProvider).value!.entries,
        hasLength(historyPageSize),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -100000));
      await tester.pump();
      await tester.pump();
      await reload(tester, h);

      expect(
        h.container(tester).read(historyProvider).value!.entries.length,
        greaterThan(historyPageSize),
      );
    });
  });
}
