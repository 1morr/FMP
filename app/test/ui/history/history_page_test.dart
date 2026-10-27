import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/history/history_state.dart';
import 'package:fmp/ui/search/search_page.dart' as search_ui;
import 'package:fmp/ui/tracks/now_playing_overlay.dart';
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

/// 一天的標頭（可點的那一列）；統計卡也有「Today」，所以限定在 [InkWell] 裡找。
Finder dayHeader(String label) =>
    find.descendant(of: find.byType(InkWell), matching: find.text(label));

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
    Size size = const Size(1000, 1200),
    bool registered = false,
  }) async {
    final h = ShellHarness(registryOfSources: registered);
    await h.pumpApp(tester, const HistoryPage(), size: size);
    return h;
  }

  /// 讓資料庫的變動送到頁面（變動的串流與重讀都是真的非同步）。
  Future<void> reload(WidgetTester tester, ShellHarness h) async {
    // 篩選一變：先一幀讓頁面重建、provider 才開始查，再等查詢回來。
    for (var i = 0; i < 3; i++) {
      await h.loadSettings(tester);
    }
  }

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
          dayHeader('Today'),
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

    testWidgets('a song of a source that is not installed shows why in place '
        'of the artist', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = ShellHarness(
          sourceUnavailable: (ref, id) => 'Source not installed',
        );
        await h.pumpApp(tester, const HistoryPage());
        await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
        await reload(tester, h);

        expect(find.text('Source not installed · 14:05'), findsOneWidget);
        expect(find.textContaining('Artist'), findsNothing);
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

    // 選單是 overlay：以滑鼠或點按打開的也要能以 Esc 關掉（design §9.5）。
    testWidgets('Esc closes the menu opened from "⋯"', (tester) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await reload(tester, h);

      await tester.tap(find.byTooltip('More options').first);
      await tester.pump();
      expect(find.text('Remove from history'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Remove from history'), findsNothing);
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

    // 長按是多選（見 `selecting`），選單在右鍵與「⋯」。
    testWidgets('right click and "⋯" open the same menu', (tester) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await record(tester, h, 'b', DateTime(2026, 10, 7, 14, 6));
      await reload(tester, h);

      await tester.tap(find.text('Song a'), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Remove from history'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      await tester.tap(find.text('Play next'));
      await tester.pump();
      expect(
        [for (final e in h.controller.queue.entries) e.track.sourceId],
        ['a'],
      );

      // 最新的 b 在最上面。
      await tester.tap(find.byTooltip('More options').first);
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
    /// 標題列的「⋯」→「清除全部歷史」。
    Future<void> chooseClearAll(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all history'));
      await tester.pumpAndSettle();
    }

    Future<ShellHarness> withTwoEntries(WidgetTester tester) async {
      final h = await openHistory(tester);
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await record(tester, h, 'b', DateTime(2026, 10, 7, 14, 6));
      await reload(tester, h);
      return h;
    }

    testWidgets('asks first; cancelling keeps everything', (tester) async {
      final h = await withTwoEntries(tester);

      await chooseClearAll(tester);
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

      await chooseClearAll(tester);
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

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<void>>(
        find.widgetWithText(PopupMenuItem<void>, 'Clear all history'),
      );
      expect(item.enabled, isFalse);
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
    await h.openHistory(tester);
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

    test(
      'a filter change while a page is in flight never mixes pages',
      () async {
        final database = await seeded(120);
        await database.customStatement(
          'INSERT INTO tracks (track_key, source_type_id, source_id, title, '
          "updated_at) VALUES ('other:b', 'other', 'b', 'B', 0)",
        );
        await database.customStatement(
          'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
          'WHERE i < 120) INSERT INTO play_history (track_key, played_at) '
          "SELECT 'other:b', 1000 + i FROM n",
        );
        final container = containerWith(database);
        container.listen(historyProvider, (_, _) {});
        await container.read(historyProvider.future);
        final notifier = container.read(historyProvider.notifier);

        // 下一頁在路上時換篩選。
        final pending = notifier.loadMore();
        container.read(historyFilterProvider.notifier).setSource('fmp-test');
        await pending;
        await container.read(historyProvider.future);

        final state = container.read(historyProvider).value!;
        expect(state.entries, hasLength(historyPageSize));
        expect(
          state.entries.every((e) => e.track.sourceTypeId == 'fmp-test'),
          isTrue,
        );
        final ids = [for (final e in state.entries) e.id];
        expect(ids.toSet(), hasLength(ids.length));
      },
    );

    test(
      'loadMore is ignored while the first page of a new filter loads',
      () async {
        final database = await seeded(120);
        final container = containerWith(database);
        container.listen(historyProvider, (_, _) {});
        await container.read(historyProvider.future);
        final notifier = container.read(historyProvider.notifier);

        container
            .read(historyFilterProvider.notifier)
            .setSort(HistorySort.oldest);
        // 讀一下讓重建開始、還沒讀完：`state.value` 是舊排序的清單。
        expect(container.read(historyProvider).isLoading, isTrue);
        await notifier.loadMore();
        final state = await container.read(historyProvider.future);

        expect(state.entries, hasLength(historyPageSize));
        expect(
          state.entries.first.playedAt.millisecondsSinceEpoch,
          1,
          reason: 'oldest first, nothing from the newest-first list',
        );
      },
    );

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

  group('the Mix items of the menu', () {
    Future<ShellHarness> openWith(
      WidgetTester tester, {
      bool mix = true,
    }) async {
      final h = ShellHarness(mix: mix, registryOfSources: true);
      h.plugin.onMix = (query) => MixBatch(
        mixId: 'm1',
        title: 'Mix',
        tracks: [
          for (final id in ['m1', 'm2'])
            TrackSummary(sourceTypeId: 'fmp-test', sourceId: id, title: id),
        ],
      );
      await h.pumpApp(tester, const HistoryPage());
      await record(tester, h, 'a', DateTime(2026, 10, 7, 14, 5));
      await reload(tester, h);
      return h;
    }

    Finder item(String label) => find.widgetWithText(MenuItemButton, label);

    testWidgets('Start Mix is there when the source has mix', (tester) async {
      await withClock(Clock.fixed(now), () async {
        await openWith(tester);
        await tester.tap(find.byTooltip('More options').first);
        await tester.pumpAndSettle();

        expect(item('Start Mix'), findsOneWidget);
      });
    });

    testWidgets('Start Mix is not there when the source has no mix', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        await openWith(tester, mix: false);
        await tester.tap(find.byTooltip('More options').first);
        await tester.pumpAndSettle();

        expect(item('Start Mix'), findsNothing);
        expect(item('Play'), findsOneWidget);
      });
    });

    testWidgets('starting a mix replaces the queue', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openWith(tester);
        await tester.tap(find.byTooltip('More options').first);
        await tester.pumpAndSettle();

        await tester.tap(item('Start Mix'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(h.controller.queue.mode, QueueMode.mix);
        expect((h.plugin.mixQueries.first as MixSeedQuery).sourceId, 'a');
      });
    });

    testWidgets('play next and add to queue are disabled inside a mix', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openWith(tester);
        unawaited(h.controller.startMix(track('seed')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byTooltip('More options').first);
        await tester.pumpAndSettle();

        for (final label in [
          'Play next (unavailable in a Mix)',
          'Add to queue (unavailable in a Mix)',
        ]) {
          expect(item(label), findsOneWidget);
          expect(
            tester.widget<MenuItemButton>(item(label)).onPressed,
            isNull,
            reason: label,
          );
        }
        expect(h.controller.queue.entries, hasLength(2));
      });
    });
  });

  // 多選（M4 PR 5，design §10.7）：在外殼裡開（Esc 與返回鍵由外殼處理）。紀錄 a、b、c 依時間，
  // 畫面上由新到舊是 c、b、a。
  group('selecting', () {
    Future<ShellHarness> openThree(
      WidgetTester tester, {
      ShellHarness? harness,
    }) async {
      final h = harness ?? ShellHarness();
      await h.pumpShell(tester);
      await h.openHistory(tester);
      for (final (id, minute) in [('a', 5), ('b', 6), ('c', 7)]) {
        await record(tester, h, id, DateTime(2026, 10, 7, 14, minute));
      }
      await reload(tester, h);
      await tester.pumpAndSettle();
      expect(find.text('Song a'), findsOneWidget);
      return h;
    }

    List<String> queued(ShellHarness h) => [
      for (final entry in h.controller.queue.entries) entry.track.sourceId,
    ];

    IconButton button(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          ),
        );

    testWidgets('a long press enters; the bar replaces the title; Esc and '
        'the back key leave selection mode before the page', (tester) async {
      await openThree(tester);

      await tester.longPress(find.text('Song b'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Play history'), findsNothing);
      expect(find.byType(Checkbox), findsNWidgets(3));
      expect(find.byTooltip('More options'), findsNothing);

      // 選取模式裡點一下是勾選，不是播放。
      await tester.tap(find.text('Song a'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Play history'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(HistoryPage), findsOneWidget);

      await tester.longPress(find.text('Song b'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Play history'), findsOneWidget);
      expect(find.byType(HistoryPage), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HistoryPage), findsNothing);
    });

    testWidgets('"Select" in the menu enters with that entry', (tester) async {
      await openThree(tester);

      await tester.tap(find.text('Song a'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Select'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(
                of: find.widgetWithText(ListTile, 'Song a'),
                matching: find.byType(Checkbox),
              ),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('"Add to queue" adds the selected songs in screen order and '
        'ends selection mode', (tester) async {
      final h = await openThree(tester);

      await tester.longPress(find.text('Song a'));
      await tester.tap(find.text('Song c'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pump();
      await tester.pump();

      expect(queued(h), ['c', 'a']);
      expect(h.controller.state, isA<Idle>(), reason: 'adding does not play');
      expect(find.text('Added to the queue'), findsOneWidget);
      expect(find.text('Play history'), findsOneWidget);
    });

    testWidgets('"Add to playlist…" adds the selected songs', (tester) async {
      final h = await openThree(tester);
      final id = (await tester.runAsync(
        () => h
            .container(tester)
            .read(playlistRepositoryProvider)
            .create(name: 'Road'),
      ))!;
      await reload(tester, h);

      await tester.longPress(find.text('Song c'));
      await tester.tap(find.text('Song b'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add to playlist…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Road'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      for (var i = 0; i < 3; i++) {
        await reload(tester, h);
      }
      await tester.pumpAndSettle();

      final stored = await tester.runAsync(
        () => h.container(tester).read(playlistRepositoryProvider).entries(id),
      );
      expect([for (final entry in stored!) entry.track.sourceId], ['c', 'b']);
      expect(find.text('Added to "Road"'), findsOneWidget);
      expect(find.text('Play history'), findsOneWidget);
    });

    testWidgets('past the queue limit nothing is added and the selection '
        'stays', (tester) async {
      final h = await openThree(tester);
      expect(
        h.controller.addToQueue([
          for (var i = 0; i < QueueModel.maxLength - 1; i++) track('q$i'),
        ]),
        isTrue,
      );
      await tester.pump();

      await tester.longPress(find.text('Song a'));
      await tester.tap(find.text('Song b'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add to queue'));
      await tester.pump();
      await tester.pump();

      expect(h.controller.queue.entries, hasLength(QueueModel.maxLength - 1));
      expect(
        find.text(
          'The queue is full (10,000 songs at most); nothing was added',
        ),
        findsOneWidget,
      );
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('inside a Mix "Add to queue" is disabled; "Add to playlist…" '
        'is not', (tester) async {
      final h = ShellHarness(mix: true, registryOfSources: true);
      h.plugin.onMix = (query) => MixBatch(
        mixId: 'm1',
        title: 'Mix',
        tracks: [
          for (final id in ['m1', 'm2'])
            TrackSummary(sourceTypeId: 'fmp-test', sourceId: id, title: id),
        ],
      );
      await openThree(tester, harness: h);
      unawaited(h.controller.startMix(track('seed')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(h.controller.queue.mode, QueueMode.mix);

      await tester.longPress(find.text('Song a'));
      await tester.pumpAndSettle();

      expect(
        button(tester, 'Add to queue (unavailable in a Mix)').onPressed,
        isNull,
      );
      expect(button(tester, 'Add to playlist…').onPressed, isNotNull);
      expect(h.controller.queue.entries, hasLength(2));
    });

    testWidgets('Shift+click selects a range; Ctrl+A selects every entry', (
      tester,
    ) async {
      await openThree(tester);
      await tester.longPress(find.text('Song c'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Song a'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.text('Song b'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);
    });
  });

  // 舊版的完整頁首（ADR 0035，R5.1–R5.5）。
  group('the legacy header', () {
    Future<void> recordTrack(
      WidgetTester tester,
      ShellHarness h,
      TrackInfo info,
      DateTime at,
    ) => tester.runAsync(
      () => h
          .container(tester)
          .read(playHistoryRepositoryProvider)
          .record(info, playedAt: at, limit: 100000),
    );

    TrackInfo timed(
      String id, {
      String source = 'fmp-test',
      Duration duration = const Duration(minutes: 3, seconds: 5),
    }) => TrackInfo(
      sourceTypeId: source,
      sourceId: id,
      title: 'Song $id',
      uploader: 'Artist',
      duration: duration,
    );

    testWidgets('the app bar has the date, search and more actions', (
      tester,
    ) async {
      await openHistory(tester);

      expect(find.byTooltip('Pick a date'), findsOneWidget);
      expect(find.byTooltip('Search history'), findsOneWidget);
      expect(find.byTooltip('More actions'), findsOneWidget);
    });

    testWidgets('the stats card counts today, this week and all time', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        // now 是 2026-10-07（週三），本週從 10-05 起。
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 10));
        await recordTrack(tester, h, timed('c'), DateTime(2026, 10, 5, 8));
        await recordTrack(
          tester,
          h,
          timed('d', duration: const Duration(hours: 1, minutes: 30)),
          DateTime(2026, 9, 1, 8),
        );
        await reload(tester, h);

        // 今天 2 首 6 分、本週 3 首 9 分、全部 4 首 1 小時 39 分。
        expect(find.text('2 plays'), findsOneWidget);
        expect(find.text('6m'), findsOneWidget);
        expect(find.text('3 plays'), findsOneWidget);
        expect(find.text('9m'), findsOneWidget);
        expect(find.text('4 plays'), findsOneWidget);
        expect(find.text('1h 39m'), findsOneWidget);
        expect(find.text('This week'), findsOneWidget);
      });
    });

    testWidgets('a source chip filters, and All brings everything back', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester, registered: true);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(
          tester,
          h,
          timed('x', source: 'other'),
          DateTime(2026, 10, 7, 10),
        );
        await reload(tester, h);
        expect(find.text('Song x'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Test Source'));
        await reload(tester, h);
        expect(find.text('Song a'), findsOneWidget);
        expect(find.text('Song x'), findsNothing);

        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await reload(tester, h);
        expect(find.text('Song x'), findsOneWidget);
      });
    });

    testWidgets('a picked date filters; its chip removes the filter', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 6, 9));
        await reload(tester, h);

        await tester.tap(find.byTooltip('Pick a date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('6'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await reload(tester, h);

        expect(find.byType(InputChip), findsOneWidget);
        expect(find.text('Song b'), findsOneWidget);
        expect(find.text('Song a'), findsNothing);

        await tester.tap(find.byTooltip('Clear the date filter'));
        await reload(tester, h);
        expect(find.byType(InputChip), findsNothing);
        expect(find.text('Song a'), findsOneWidget);
      });
    });

    testWidgets('search narrows by title or artist and closing restores', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 10));
        await reload(tester, h);

        await tester.tap(find.byTooltip('Search history'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'song a');
        await tester.pump(const Duration(milliseconds: 300));
        await reload(tester, h);
        expect(find.text('Song a'), findsOneWidget);
        expect(find.text('Song b'), findsNothing);

        await tester.enterText(find.byType(TextField), 'zzz');
        await tester.pump(const Duration(milliseconds: 300));
        await reload(tester, h);
        expect(find.text('No matching records'), findsOneWidget);
        // 有篩選時的空結果不是「還沒有紀錄」，也沒有「去搜尋」。
        expect(find.text('No play history yet'), findsNothing);
        expect(find.text('Go to Search'), findsNothing);

        await tester.tap(find.byTooltip('Close search'));
        await tester.pump();
        await reload(tester, h);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Song a'), findsOneWidget);
        expect(find.text('Song b'), findsOneWidget);
      });
    });

    testWidgets('sorting: oldest first reverses the rows; most played is a '
        'flat list with the count', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 10));
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 11));
        await reload(tester, h);
        expect(find.byType(ListTile), findsNWidgets(3));

        Future<void> choose(String current, String label) async {
          await tester.tap(find.widgetWithText(ActionChip, current));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(RadioMenuButton<HistorySort>, label),
          );
          await tester.pumpAndSettle();
          await reload(tester, h);
        }

        await choose('Newest first', 'Oldest first');
        expect(
          tester.getTopLeft(find.text('Artist · 09:00')).dy,
          lessThan(tester.getTopLeft(find.text('Artist · 11:00')).dy),
        );

        await choose('Oldest first', 'Most played');
        expect(find.byType(ListTile), findsNWidgets(2));
        expect(dayHeader('Today'), findsNothing);
        expect(find.text('Artist · 2 plays'), findsOneWidget);
        expect(find.text('Artist · 1 play'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Song a')).dy,
          lessThan(tester.getTopLeft(find.text('Song b')).dy),
        );
      });
    });

    testWidgets('a day header shows the count and collapses its rows only', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 10));
        await recordTrack(tester, h, timed('c'), DateTime(2026, 10, 6, 10));
        await reload(tester, h);
        expect(find.byIcon(Icons.expand_less), findsNWidgets(2));

        await tester.tap(dayHeader('Today'));
        await tester.pump();
        expect(find.text('Song a'), findsNothing);
        expect(find.text('Song b'), findsNothing);
        expect(find.text('Song c'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);

        await tester.tap(dayHeader('Today'));
        await tester.pump();
        expect(find.text('Song a'), findsOneWidget);
      });
    });

    testWidgets('a row shows its duration and the source badge', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await reload(tester, h);

        expect(find.text('3:05'), findsOneWidget);
        // 插件沒有圖示時是名稱的縮寫（`SourceIcon`；「Test Source」是 TS）。
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, 'Song a'),
            matching: find.text('TS'),
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('the playing track has the overlay and a bold title', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 10));
        await reload(tester, h);
        expect(find.byKey(NowPlayingOverlay.overlayKey), findsNothing);

        await h.controller.playTemporary(timed('a'));
        await tester.pump();
        await tester.pump();

        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, 'Song a'),
            matching: find.byKey(NowPlayingOverlay.overlayKey),
          ),
          findsOneWidget,
        );
        expect(find.byKey(NowPlayingOverlay.overlayKey), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('Song a')).style?.fontWeight,
          FontWeight.bold,
        );
        expect(tester.widget<Text>(find.text('Song b')).style, isNull);
      });
    });

    testWidgets('delete all plays of a track asks, deletes and says how many', (
      tester,
    ) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 10));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 11));
        await reload(tester, h);

        // 最上面是 b；第二列是 a 的第二次。
        await tester.tap(find.byTooltip('More options').at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete all plays of this song'));
        await tester.pumpAndSettle();
        expect(find.text('Delete every play of this song?'), findsOneWidget);

        // 取消：什麼都不刪。
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsNWidgets(3));

        await tester.tap(find.byTooltip('More options').at(1));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete all plays of this song'));
        await tester.pumpAndSettle();
        final confirm = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Delete'),
        );
        final scheme = Theme.of(tester.element(find.byType(AlertDialog)))
            .colorScheme;
        expect(
          confirm.style?.backgroundColor?.resolve({}),
          scheme.error,
          reason: 'the confirm button is red',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pump();
        await reload(tester, h);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Deleted 2 records'), findsOneWidget);
        expect(find.byType(ListTile), findsNWidgets(1));
        expect(find.text('Song a'), findsNothing);
      });
    });

    testWidgets('selecting then Delete asks, deletes and says how many', (
      tester,
    ) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.openHistory(tester);
      for (final (id, minute) in [('a', 5), ('b', 6), ('c', 7)]) {
        await record(tester, h, id, DateTime(2026, 10, 7, 14, minute));
      }
      await reload(tester, h);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Song c'));
      await tester.tap(find.text('Song a'));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 records?'), findsOneWidget);

      // 取消：選取留著。
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await reload(tester, h);
      await tester.pumpAndSettle();

      expect(find.text('Deleted 2 records'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
      expect(find.text('Song a'), findsNothing);
      expect(find.text('Song c'), findsNothing);
      expect(find.text('Play history'), findsOneWidget);
    });

    testWidgets('the source chips come from the history: a source with no '
        'plugin shows its id and filters', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester, registered: true);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(
          tester,
          h,
          timed('x', source: 'gone-plugin'),
          DateTime(2026, 10, 7, 10),
        );
        await reload(tester, h);

        expect(find.widgetWithText(ChoiceChip, 'Test Source'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, 'gone-plugin'), findsOneWidget);

        await tester.tap(find.widgetWithText(ChoiceChip, 'gone-plugin'));
        await reload(tester, h);
        expect(find.text('Song x'), findsOneWidget);
        expect(find.text('Song a'), findsNothing);
      });
    });

    testWidgets('a source nobody has played is not a chip', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester, registered: true);
        await recordTrack(
          tester,
          h,
          timed('x', source: 'gone-plugin'),
          DateTime(2026, 10, 7, 10),
        );
        await reload(tester, h);

        expect(find.widgetWithText(ChoiceChip, 'Test Source'), findsNothing);
        expect(find.widgetWithText(ChoiceChip, 'gone-plugin'), findsOneWidget);
      });
    });

    testWidgets('the filter goes back to All when its source leaves the '
        'history', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester, registered: true);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(
          tester,
          h,
          timed('x', source: 'gone-plugin'),
          DateTime(2026, 10, 7, 10),
        );
        await reload(tester, h);
        await tester.tap(find.widgetWithText(ChoiceChip, 'gone-plugin'));
        await reload(tester, h);
        expect(
          h.container(tester).read(historyFilterProvider).source,
          isNotNull,
        );

        await tester.runAsync(
          () => h
              .container(tester)
              .read(playHistoryRepositoryProvider)
              .deleteAllForTrack('gone-plugin:x'),
        );
        await reload(tester, h);
        await reload(tester, h);

        expect(h.container(tester).read(historyFilterProvider).source, isNull);
        expect(find.widgetWithText(ChoiceChip, 'gone-plugin'), findsNothing);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All'))
              .selected,
          isTrue,
        );
        expect(find.text('Song a'), findsOneWidget);
      });
    });

    group('deleting under the most-played sort', () {
      Future<ShellHarness> mostPlayed(WidgetTester tester) async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 10));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 11));
        await recordTrack(tester, h, timed('b'), DateTime(2026, 10, 7, 12));
        await recordTrack(tester, h, timed('c'), DateTime(2026, 10, 7, 13));
        await reload(tester, h);
        await tester.tap(find.widgetWithText(ActionChip, 'Newest first'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(RadioMenuButton<HistorySort>, 'Most played'),
        );
        await tester.pumpAndSettle();
        await reload(tester, h);
        return h;
      }

      testWidgets('the row menu only has the delete-every-play item', (
        tester,
      ) async {
        await withClock(Clock.fixed(now), () async {
          final h = await mostPlayed(tester);
          // b 次數最多（2），其次 a（2、較舊），最後 c。
          await tester.tap(find.byTooltip('More options').first);
          await tester.pumpAndSettle();
          expect(find.text('Remove from history'), findsNothing);
          await tester.tap(find.text('Delete all plays of this song'));
          await tester.pumpAndSettle();
          expect(find.text('Delete every play of this song?'), findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
          await tester.pump();
          await reload(tester, h);
          await tester.pumpAndSettle();

          expect(find.text('Deleted 2 records'), findsOneWidget);
          expect(find.text('Song b'), findsNothing);
          expect(find.text('Song a'), findsOneWidget);
          expect(find.text('Song c'), findsOneWidget);
        });
      });

      testWidgets('multi-select Delete removes every play of the tracks', (
        tester,
      ) async {
        await withClock(Clock.fixed(now), () async {
          final h = await mostPlayed(tester);
          await tester.longPress(find.text('Song b'));
          await tester.tap(find.text('Song c'));
          await tester.pump();
          await tester.tap(find.byTooltip('Delete'));
          await tester.pumpAndSettle();
          expect(find.text('Delete every play of 2 songs?'), findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
          await tester.pump();
          await reload(tester, h);
          await tester.pumpAndSettle();

          // b 兩次加 c 一次。
          expect(find.text('Deleted 3 records'), findsOneWidget);
          expect(find.text('Song a'), findsOneWidget);
          expect(find.text('Song b'), findsNothing);
          expect(find.text('Song c'), findsNothing);
        });
      });
    });

    testWidgets('under the time sorts the menu removes one record and '
        'multi-select deletes the selected records', (tester) async {
      await withClock(Clock.fixed(now), () async {
        final h = await openHistory(tester);
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 9));
        await recordTrack(tester, h, timed('a'), DateTime(2026, 10, 7, 10));
        await reload(tester, h);

        await tester.tap(find.byTooltip('More options').first);
        await tester.pumpAndSettle();
        expect(find.text('Remove from history'), findsOneWidget);
        await tester.tap(find.text('Remove from history'));
        await tester.pump();
        await reload(tester, h);
        await tester.pumpAndSettle();

        expect(find.byType(ListTile), findsNWidgets(1));
        expect(find.text('Artist · 09:00'), findsOneWidget);
      });
    });

    testWidgets('loading shows a spinner', (tester) async {
      // 資料庫被一個 transaction 佔著，讀取排在它後面（同 import_preview_test）。
      final database = memoryDatabase();
      final gate = Completer<void>();
      await tester.runAsync(() async {
        unawaited(database.transaction(() => gate.future));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      final h = ShellHarness(database: database);
      await h.pumpApp(tester, const HistoryPage());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await reload(tester, h);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No play history yet'), findsOneWidget);
    });

    testWidgets('the empty state has Go to Search which opens the search '
        'destination', (tester) async {
      final h = ShellHarness();
      await h.pumpShell(tester);
      await h.openHistory(tester);
      await reload(tester, h);
      await tester.pumpAndSettle();
      expect(find.text('No play history yet'), findsOneWidget);
      await tester.tap(find.text('Go to Search'));
      await tester.pumpAndSettle();
      expect(find.byType(search_ui.SearchPage), findsOneWidget);
    });

    testWidgets('a failed load has a Retry that reads again', (tester) async {
      final h = await openHistory(tester);
      await reload(tester, h);
      final database = h.container(tester).read(appDatabaseProvider);
      await tester.runAsync(() async {
        await database.customStatement(
          'ALTER TABLE play_history RENAME TO play_history_gone',
        );
        database.markTablesUpdated({database.playHistoryTable});
      });
      await reload(tester, h);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Retry'), findsOneWidget);

      await tester.runAsync(
        () => database.customStatement(
          'ALTER TABLE play_history_gone RENAME TO play_history',
        ),
      );
      await tester.tap(find.text('Retry'));
      await reload(tester, h);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Retry'), findsNothing);
      expect(find.text('No play history yet'), findsOneWidget);
    });
  });
}
