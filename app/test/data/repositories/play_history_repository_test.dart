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
}
