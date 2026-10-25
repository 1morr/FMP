import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';

import '../../support/memory_database.dart';

TrackInfo track(String id, {String? title}) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  title: title ?? 'Song $id',
  uploader: 'Artist',
  duration: const Duration(minutes: 3),
  artwork: [
    TrackArtwork(url: Uri.parse('https://fmp.test/$id.jpg'), width: 300),
  ],
);

DateTime at(int minute) => DateTime.utc(2026, 10, 7, 12, minute);

void main() {
  late AppDatabase database;
  late PlayHistoryRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = PlayHistoryRepository(database);
  });

  Future<void> record(String id, int minute, {int limit = 10000}) =>
      repository.record(track(id), playedAt: at(minute), limit: limit);

  Future<List<String>> titles({int limit = 100, int offset = 0}) async => [
    for (final entry in await repository.page(limit: limit, offset: offset))
      entry.track.title,
  ];

  group('record and read', () {
    test('reads newest first with the display data of the track', () async {
      await record('a', 1);
      await record('b', 3);
      await record('c', 2);

      final entries = await repository.page(limit: 10);

      expect([for (final e in entries) e.track.sourceId], ['b', 'c', 'a']);
      expect(entries.first.playedAt, at(3));
      expect(entries.first.track, track('b'));
    });

    test('a part keeps its index and the video title', () async {
      const part = TrackInfo(
        sourceTypeId: 'fmp-test',
        sourceId: 'v',
        cid: 5,
        title: 'Second',
        partIndex: 2,
        parentTitle: 'The video',
      );
      await repository.record(part, playedAt: at(1), limit: 10);

      final entries = await repository.page(limit: 10);

      expect(entries.single.track, part);
      expect(entries.single.track.displayTitle, 'The video · P2 Second');
    });

    test('the same song twice is two entries with the latest title', () async {
      await repository.record(
        track('a', title: 'Old'),
        playedAt: at(1),
        limit: 100,
      );
      await repository.record(
        track('a', title: 'New'),
        playedAt: at(2),
        limit: 100,
      );

      expect(await titles(), ['New', 'New']);
    });

    test('entries at the same instant keep the later write first', () async {
      await record('a', 1);
      await record('b', 1);

      expect(await titles(), ['Song b', 'Song a']);
    });

    test('pages do not overlap and cover everything', () async {
      for (var i = 0; i < 7; i++) {
        await record('$i', i);
      }

      expect(await titles(limit: 3), ['Song 6', 'Song 5', 'Song 4']);
      expect(await titles(limit: 3, offset: 3), ['Song 3', 'Song 2', 'Song 1']);
      expect(await titles(limit: 3, offset: 6), ['Song 0']);
    });
  });

  group('removing', () {
    test('delete removes only that entry, not the other plays', () async {
      await record('a', 1);
      await record('a', 2);
      await record('b', 3);
      final entries = await repository.page(limit: 10);

      await repository.delete(entries[1].id);

      expect(
        [for (final e in await repository.page(limit: 10)) e.id],
        [entries[0].id, entries[2].id],
      );
    });

    test('clear removes everything', () async {
      await record('a', 1);
      await record('b', 2);

      await repository.clear();

      expect(await titles(), isEmpty);
    });
  });

  group('the retention limit', () {
    test('a write trims the oldest beyond the limit', () async {
      for (var i = 0; i < 3; i++) {
        await record('$i', i, limit: 3);
      }
      expect(await titles(), ['Song 2', 'Song 1', 'Song 0']);

      await record('3', 3, limit: 3);

      expect(await titles(), ['Song 3', 'Song 2', 'Song 1']);
    });

    test('exactly the limit keeps everything', () async {
      await record('0', 0, limit: 2);
      await record('1', 1, limit: 2);

      expect(await titles(), hasLength(2));
    });

    test('a limit of one keeps only the latest', () async {
      await record('0', 0, limit: 1);
      await record('1', 1, limit: 1);

      expect(await titles(), ['Song 1']);
    });

    test('trimTo drops the oldest down to the new limit', () async {
      for (var i = 0; i < 5; i++) {
        await record('$i', i);
      }

      await repository.trimTo(2);

      expect(await titles(), ['Song 4', 'Song 3']);
    });

    test('trimTo above the count changes nothing', () async {
      await record('a', 1);

      await repository.trimTo(5);

      expect(await titles(), hasLength(1));
    });
  });

  test('changes fires after a record, a delete and a clear', () async {
    final events = <void>[];
    final subscription = repository.changes().listen(events.add);
    addTearDown(subscription.cancel);

    await record('a', 1);
    await record('b', 2);
    await Future<void>.delayed(Duration.zero);
    final afterRecord = events.length;
    await repository.delete((await repository.page(limit: 1)).single.id);
    await Future<void>.delayed(Duration.zero);
    final afterDelete = events.length;
    await repository.clear();
    await Future<void>.delayed(Duration.zero);

    expect(afterRecord, greaterThan(0));
    expect(afterDelete, greaterThan(afterRecord));
    expect(events.length, greaterThan(afterDelete));
  });

  group('references', () {
    test('a track in the history cannot be deleted (RESTRICT)', () async {
      await record('a', 1);

      await expectLater(
        database.customStatement(
          "DELETE FROM tracks WHERE track_key = 'fmp-test:a'",
        ),
        throwsA(anything),
      );
    });

    test('a history row cannot point at a track that does not exist', () async {
      await expectLater(
        database.customStatement(
          'INSERT INTO play_history (track_key, played_at) '
          "VALUES ('fmp-test:missing', 1)",
        ),
        throwsA(anything),
      );
    });

    test('orphan cleanup keeps tracks the history refers to', () async {
      await record('history', 1);
      await QueueRepository(database).write(
        edit: QueueRangeEdit(from: 0, removed: 0, inserted: [track('queue')]),
        player: const PlayerState(
          currentPosition: 0,
          position: Duration.zero,
          loopMode: LoopMode.off,
          shuffleEnabled: false,
          volume: 1,
          muted: false,
        ),
      );
      await TracksRepository(database).upsert([track('orphan')]);

      final deleted = await TracksRepository(database).deleteOrphans();

      expect(deleted, 1, reason: 'only the track nobody refers to');
      expect(
        [
          for (final row
              in await database
                  .customSelect('SELECT track_key FROM tracks ORDER BY 1')
                  .get())
            row.read<String>('track_key'),
        ],
        ['fmp-test:history', 'fmp-test:queue'],
      );
    });

    test('after clearing the history its tracks become orphans', () async {
      await record('a', 1);
      await repository.clear();

      expect(await TracksRepository(database).deleteOrphans(), 1);
    });
  });

  test('stored format', () async {
    await record('a', 1);

    final rows = await database
        .customSelect('SELECT track_key, played_at FROM play_history')
        .get();
    expect(rows.single.read<String>('track_key'), 'fmp-test:a');
    expect(rows.single.read<int>('played_at'), at(1).millisecondsSinceEpoch);
  });

  test('the first page of ten thousand entries is read with a limit', () async {
    await database.customStatement(
      'INSERT INTO tracks (track_key, source_type_id, source_id, title, '
      "updated_at) VALUES ('fmp-test:a', 'fmp-test', 'a', 'T', 0)",
    );
    await database.customStatement(
      'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
      'WHERE i < 10000) INSERT INTO play_history (track_key, played_at) '
      "SELECT 'fmp-test:a', i FROM n",
    );

    final watch = Stopwatch()..start();
    final first = await repository.page(limit: 50);
    final firstMs = watch.elapsedMilliseconds;
    watch
      ..reset()
      ..start();
    final deep = await repository.page(limit: 50, offset: 9950);
    // 量測結果印在測試輸出，超過 500 毫秒要在 PR 說明。
    // ignore: avoid_print
    print(
      'play history: first page of 50 in ${firstMs}ms, '
      'last page in ${watch.elapsedMilliseconds}ms (10000 rows)',
    );

    expect(first, hasLength(50));
    expect(deep, hasLength(50));
    expect(first.first.playedAt.millisecondsSinceEpoch, 10000);
    expect(deep.last.playedAt.millisecondsSinceEpoch, 1);
    expect(firstMs, lessThan(500));
  });

  group('filters, sorts and stats', () {
    TrackInfo other(
      String id, {
      String source = 'fmp-test',
      String title = 'Song',
      String? uploader = 'Artist',
      Duration? duration = const Duration(minutes: 3),
    }) => TrackInfo(
      sourceTypeId: source,
      sourceId: id,
      title: title,
      uploader: uploader,
      duration: duration,
    );

    Future<void> play(TrackInfo t, DateTime local) =>
        repository.record(t, playedAt: local, limit: 10000);

    Future<List<String>> ids(Future<List<PlayHistoryEntry>> entries) async => [
      for (final e in await entries) e.track.sourceId,
    ];

    test('stats split today, this week (Monday start) and all', () async {
      // 2026-10-07 是週三，本週從 10-05（週一）起。
      final now = DateTime(2026, 10, 7, 15, 30);
      await play(other('a'), DateTime(2026, 10, 7, 0, 0)); // 今天，正好午夜
      await play(other('b'), DateTime(2026, 10, 6, 23, 59, 59)); // 本週
      await play(other('c'), DateTime(2026, 10, 5, 0, 0)); // 本週，正好週一午夜
      await play(other('d'), DateTime(2026, 10, 4, 23, 59)); // 上週日
      await play(
        other('e', duration: null),
        DateTime(2026, 10, 7, 9, 0),
      ); // 今天、沒有時長

      final stats = await repository.stats(now);

      expect(stats.today.count, 2);
      expect(stats.today.duration, const Duration(minutes: 3));
      expect(stats.week.count, 4);
      expect(stats.week.duration, const Duration(minutes: 9));
      expect(stats.all.count, 5);
      expect(stats.all.duration, const Duration(minutes: 12));
    });

    test('stats of an empty history are zero', () async {
      final stats = await repository.stats(DateTime(2026, 10, 7));
      expect(
        stats.all,
        const HistoryPeriodStats(count: 0, duration: Duration.zero),
      );
      expect(stats.today.count, 0);
    });

    test('stats on a Sunday still count back to that week Monday', () async {
      await play(other('a'), DateTime(2026, 10, 5, 8)); // 週一
      await play(other('b'), DateTime(2026, 10, 4, 8)); // 上週日
      final stats = await repository.stats(DateTime(2026, 10, 11, 20));
      expect(stats.week.count, 1);
    });

    test(
      'filters by source, by day and by search, and combines them',
      () async {
        await play(other('a', title: 'Alpha'), DateTime(2026, 10, 7, 10));
        await play(
          other('b', source: 'other', title: 'Beta', uploader: 'Zed'),
          DateTime(2026, 10, 7, 11),
        );
        await play(other('c', title: 'Gamma'), DateTime(2026, 10, 6, 23, 59));
        await play(other('d', title: 'Delta'), DateTime(2026, 10, 8, 0, 0));

        expect(await ids(repository.page(limit: 10, source: 'other')), ['b']);
        expect(
          await ids(repository.page(limit: 10, day: DateTime(2026, 10, 7, 13))),
          ['b', 'a'],
        );
        expect(
          await ids(repository.page(limit: 10, day: DateTime(2026, 10, 6))),
          ['c'],
        );
        // 曲名與作者都算，英文不分大小寫。
        expect(await ids(repository.page(limit: 10, query: 'ALPH')), ['a']);
        expect(await ids(repository.page(limit: 10, query: 'zed')), ['b']);
        expect(
          await ids(
            repository.page(
              limit: 10,
              day: DateTime(2026, 10, 7),
              query: 'artist',
            ),
          ),
          ['a'],
        );
        expect(
          await ids(repository.page(limit: 10, query: '  ')),
          hasLength(4),
        );
        expect(await ids(repository.page(limit: 10, query: 'nope')), isEmpty);
      },
    );

    test('a search treats % and _ as plain characters', () async {
      await play(other('a', title: '100% sure'), DateTime(2026, 10, 7, 10));
      await play(other('b', title: 'a_b'), DateTime(2026, 10, 7, 11));
      await play(other('c', title: 'axb'), DateTime(2026, 10, 7, 12));

      expect(await ids(repository.page(limit: 10, query: '%')), ['a']);
      expect(await ids(repository.page(limit: 10, query: 'a_b')), ['b']);
    });

    test('a search also matches the title of the video of a part', () async {
      await play(
        const TrackInfo(
          sourceTypeId: 'fmp-test',
          sourceId: 'v',
          cid: 2,
          title: 'P2',
          partIndex: 2,
          parentTitle: 'Concert',
        ),
        DateTime(2026, 10, 7, 10),
      );
      expect(await ids(repository.page(limit: 10, query: 'concert')), ['v']);
    });

    test('oldest first reverses newest first', () async {
      await play(other('a'), DateTime(2026, 10, 7, 10));
      await play(other('b'), DateTime(2026, 10, 7, 12));
      await play(other('c'), DateTime(2026, 10, 7, 11));

      expect(await ids(repository.page(limit: 10, sort: HistorySort.oldest)), [
        'a',
        'c',
        'b',
      ]);
      expect(await ids(repository.page(limit: 10)), ['b', 'c', 'a']);
    });

    test(
      'most played groups by track, last play and count, ties by recency',
      () async {
        await play(other('a'), DateTime(2026, 10, 7, 10));
        await play(other('a'), DateTime(2026, 10, 7, 12));
        await play(other('a'), DateTime(2026, 10, 7, 11));
        await play(other('b'), DateTime(2026, 10, 7, 13));
        await play(other('c'), DateTime(2026, 10, 7, 9));
        await play(other('c'), DateTime(2026, 10, 7, 14));

        final entries = await repository.page(
          limit: 10,
          sort: HistorySort.mostPlayed,
        );

        expect([for (final e in entries) e.track.sourceId], ['a', 'c', 'b']);
        expect([for (final e in entries) e.playCount], [3, 2, 1]);
        expect(entries.first.playedAt, DateTime(2026, 10, 7, 12).toUtc());
        // 每首的 id 是它最後一次播放那一列。
        expect(entries.first.id, 2);
      },
    );

    test('most played counts only the plays that pass the filter', () async {
      await play(other('a'), DateTime(2026, 10, 6, 10));
      await play(other('a'), DateTime(2026, 10, 7, 10));
      await play(other('a'), DateTime(2026, 10, 7, 11));

      final entries = await repository.page(
        limit: 10,
        sort: HistorySort.mostPlayed,
        day: DateTime(2026, 10, 7),
      );

      expect(entries.single.playCount, 2);
    });

    test(
      'paging across a filter and a sort neither repeats nor skips',
      () async {
        for (var i = 0; i < 7; i++) {
          await play(
            other('s$i', source: 'other'),
            DateTime(2026, 10, 7, 10, i),
          );
          await play(other('t$i'), DateTime(2026, 10, 7, 11, i));
        }

        for (final sort in HistorySort.values) {
          final seen = <String>[];
          for (var offset = 0; ; offset += 3) {
            final page = await repository.page(
              limit: 3,
              offset: offset,
              source: 'other',
              sort: sort,
            );
            seen.addAll([for (final e in page) e.track.sourceId]);
            if (page.length < 3) break;
          }
          expect(seen.toSet(), hasLength(7), reason: '$sort');
          expect(seen, hasLength(7), reason: '$sort');
          expect(seen.every((id) => id.startsWith('s')), isTrue);
        }
      },
    );

    test('deleteAllForTrack removes every play of one track only', () async {
      await play(other('a'), DateTime(2026, 10, 7, 10));
      await play(other('a'), DateTime(2026, 10, 7, 11));
      await play(other('b'), DateTime(2026, 10, 7, 12));

      expect(await repository.deleteAllForTrack('fmp-test:a'), 2);
      expect(await repository.deleteAllForTrack('fmp-test:a'), 0);
      expect(await ids(repository.page(limit: 10)), ['b']);
    });

    test('deleteMany removes the given entries, in batches', () async {
      await play(other('a'), DateTime(2026, 10, 7, 10));
      await play(other('b'), DateTime(2026, 10, 7, 11));
      await play(other('c'), DateTime(2026, 10, 7, 12));
      final all = await repository.page(limit: 10);

      expect(await repository.deleteMany([all[0].id, all[2].id, 9999]), 2);
      expect(await ids(repository.page(limit: 10)), ['b']);
      expect(await repository.deleteMany(const []), 0);

      // 超過一批（500）的 id。
      expect(
        await repository.deleteMany(List.generate(1200, (i) => i + 100)),
        0,
      );
    });

    test('the filtered queries use the played_at index', () async {
      Future<String> plan(String sql) async => [
        for (final row
            in await database.customSelect('EXPLAIN QUERY PLAN $sql').get())
          row.read<String>('detail'),
      ].join('\n');

      final newest = await plan(
        'SELECT h.id FROM play_history h JOIN tracks t '
        'ON t.track_key = h.track_key '
        "WHERE t.source_type_id = 'x' ORDER BY h.played_at DESC, h.id DESC "
        'LIMIT 50',
      );
      expect(newest, contains('play_history_played_at'));
      expect(newest, isNot(contains('USE TEMP B-TREE FOR ORDER BY')));
    });
  });
}
