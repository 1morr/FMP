import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';

import '../../support/memory_database.dart';

TrackInfo track(
  String id, {
  String title = 'Song',
  int? cid,
  String? uploader,
  Duration? duration,
  List<TrackArtwork> artwork = const [],
}) => TrackInfo(
  sourceTypeId: 'fmp-test',
  sourceId: id,
  cid: cid,
  title: '$title $id',
  uploader: uploader,
  duration: duration,
  artwork: artwork,
);

const _player = PlayerState(
  currentPosition: 0,
  position: Duration.zero,
  loopMode: LoopMode.off,
  shuffleEnabled: false,
  volume: 1,
  muted: false,
);

void main() {
  late AppDatabase database;
  late QueueRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = QueueRepository(database);
  });

  /// 把 [tracks] 整份寫成佇列（取代資料庫裡原有的）。
  Future<void> writeAll(
    List<TrackInfo> tracks, {
    int existing = 0,
    PlayerState player = _player,
  }) => repository.write(
    edit: QueueRangeEdit(from: 0, removed: existing, inserted: tracks),
    player: player,
  );

  Future<List<String>> keysInOrder() async => [
    for (final row
        in await database
            .customSelect(
              'SELECT track_key FROM queue_entries ORDER BY position',
            )
            .get())
      row.read<String>('track_key'),
  ];

  test('nothing is stored before the first write', () async {
    expect((await repository.readQueue()).entries, isEmpty);
    expect(await repository.readPlayerState(), isNull);
  });

  test(
    'reads back the queue, the shuffle ranks and the player state',
    () async {
      final tracks = [
        track(
          'a',
          cid: 7,
          uploader: 'Up',
          duration: const Duration(seconds: 213),
          artwork: [
            TrackArtwork(
              url: Uri.parse('https://cdn.example/a.jpg'),
              width: 300,
            ),
            TrackArtwork(url: Uri.parse('https://cdn.example/a2.jpg')),
          ],
        ),
        track('b'),
      ];
      // 同一首可以出現在兩個位置。
      tracks.add(tracks[0]);
      const player = PlayerState(
        currentPosition: 1,
        position: Duration(milliseconds: 83500),
        loopMode: LoopMode.all,
        shuffleEnabled: true,
        volume: 0.35,
        muted: true,
      );
      await writeAll(tracks, player: player);
      await repository.write(shuffleRanks: {0: 2, 1: 0, 2: 1}, player: player);

      final stored = await repository.readQueue();
      expect(stored.entries, [tracks[0], tracks[1], tracks[2]]);
      expect(stored.shuffleRanks, [2, 0, 1]);
      expect(await repository.readPlayerState(), player);
    },
  );

  group('editing a range', () {
    final a = track('a');
    final b = track('b');
    final c = track('c');
    final d = track('d');
    final e = track('e');

    test('inserting in the middle shifts the rows after it', () async {
      await writeAll([a, b, c]);

      await repository.write(
        edit: QueueRangeEdit(from: 1, removed: 0, inserted: [d, e]),
        player: _player,
      );

      expect((await repository.readQueue()).entries, [a, d, e, b, c]);
    });

    test('removing shifts the rows after it back', () async {
      await writeAll([a, b, c, d, e]);

      await repository.write(
        edit: const QueueRangeEdit(from: 1, removed: 2, inserted: []),
        player: _player,
      );

      expect((await repository.readQueue()).entries, [a, d, e]);
    });

    test('replacing a range with one of another length', () async {
      await writeAll([a, b, c, d]);

      await repository.write(
        edit: QueueRangeEdit(from: 1, removed: 2, inserted: [e, a, e]),
        player: _player,
      );

      expect((await repository.readQueue()).entries, [a, e, a, e, d]);
    });

    test('replacing the whole queue', () async {
      await writeAll([a, b, c]);

      await writeAll([d, e], existing: 3);

      expect((await repository.readQueue()).entries, [d, e]);
    });

    test(
      'new rows have no shuffle rank and shifted rows keep theirs',
      () async {
        await writeAll([a, b]);
        await repository.write(shuffleRanks: {0: 1, 1: 0}, player: _player);

        await repository.write(
          edit: QueueRangeEdit(from: 1, removed: 0, inserted: [c]),
          player: _player,
        );

        expect((await repository.readQueue()).shuffleRanks, [1, null, 0]);
      },
    );

    test(
      'a seeded run of random edits always reads back as the model',
      () async {
        final random = Random(14);
        final model = <TrackInfo>[];
        var next = 0;
        for (var step = 0; step < 300; step++) {
          final from = random.nextInt(model.length + 1);
          final removed = random.nextInt(model.length - from + 1);
          final inserted = [
            for (var i = random.nextInt(4); i > 0; i--)
              track('t${next++ % 12}'),
          ];
          await repository.write(
            edit: QueueRangeEdit(
              from: from,
              removed: removed,
              inserted: inserted,
            ),
            player: _player,
          );
          model.replaceRange(from, from + removed, inserted);

          expect(
            (await repository.readQueue()).entries,
            model,
            reason:
                'step $step: replace $removed at $from with '
                '${inserted.length}',
          );
        }
      },
    );
  });

  group('tracks', () {
    test(
      'a track already stored takes the new values and stays referenced',
      () async {
        await writeAll([track('a', title: 'Old')]);

        // REPLACE 會先刪列、被 RESTRICT 擋下；upsert 不會。
        await repository.write(
          edit: QueueRangeEdit(
            from: 1,
            removed: 0,
            inserted: [track('a', title: 'New')],
          ),
          player: _player,
        );

        expect((await repository.readQueue()).entries.map((t) => t.title), [
          'New a',
          'New a',
        ]);
      },
    );

    test('a track in the queue cannot be deleted (RESTRICT)', () async {
      await writeAll([track('a'), track('b')]);

      await expectLater(
        database.customStatement(
          "DELETE FROM tracks WHERE track_key = 'fmp-test:a'",
        ),
        throwsA(anything),
      );
      expect(await keysInOrder(), ['fmp-test:a', 'fmp-test:b']);
    });

    test('a queue row cannot point at a track that does not exist', () async {
      await expectLater(
        database.customStatement(
          "INSERT INTO queue_entries (position, track_key) "
          "VALUES (0, 'fmp-test:missing')",
        ),
        throwsA(anything),
      );
    });

    test('only unreferenced tracks are orphans', () async {
      await writeAll([track('a'), track('b'), track('c')]);
      await repository.write(
        edit: const QueueRangeEdit(from: 0, removed: 2, inserted: []),
        player: _player,
      );

      final deleted = await TracksRepository(database).deleteOrphans();

      expect(deleted, 2, reason: 'a and b are no longer in the queue');
      expect(
        [
          for (final row
              in await database
                  .customSelect('SELECT track_key FROM tracks')
                  .get())
            row.read<String>('track_key'),
        ],
        ['fmp-test:c'],
      );
    });

    test('no orphans means nothing is deleted', () async {
      await writeAll([track('a')]);

      expect(await TracksRepository(database).deleteOrphans(), 0);
      expect(await keysInOrder(), ['fmp-test:a']);
    });
  });

  test('a write is one transaction', () async {
    await writeAll([track('a')]);

    // 音量是 NaN：SQLite 存成 NULL，NOT NULL 讓最後一步失敗。
    await expectLater(
      repository.write(
        edit: QueueRangeEdit(from: 1, removed: 0, inserted: [track('b')]),
        player: const PlayerState(
          currentPosition: 0,
          position: Duration.zero,
          loopMode: LoopMode.off,
          shuffleEnabled: false,
          volume: double.nan,
          muted: false,
        ),
      ),
      throwsA(anything),
    );

    expect(await keysInOrder(), ['fmp-test:a']);
    expect(
      await database.customSelect('SELECT 1 FROM tracks').get(),
      hasLength(1),
      reason: 'the upsert of the new track was rolled back too',
    );
  });

  test(
    'reset clears the queue and the player state but keeps the tracks',
    () async {
      await writeAll([track('a')]);

      await repository.reset();

      expect((await repository.readQueue()).entries, isEmpty);
      expect(await repository.readPlayerState(), isNull);
      expect(
        await database.customSelect('SELECT 1 FROM tracks').get(),
        hasLength(1),
      );
    },
  );

  test('a queue with a gap in its positions is refused', () async {
    await writeAll([track('a'), track('b')]);
    await database.customStatement(
      'UPDATE queue_entries SET position = 5 WHERE position = 1',
    );

    await expectLater(repository.readQueue(), throwsFormatException);
  });

  group('stored format', () {
    test('tracks, queue rows and the player state', () async {
      await withClock(Clock.fixed(DateTime.utc(2026, 10, 7, 12)), () async {
        await writeAll(
          [
            track(
              'a',
              cid: 9,
              uploader: 'Up',
              duration: const Duration(seconds: 2),
              artwork: [
                TrackArtwork(
                  url: Uri.parse('https://cdn.example/a.jpg'),
                  width: 64,
                ),
                TrackArtwork(url: Uri.parse('https://cdn.example/b.jpg')),
              ],
            ),
            track('b'),
          ],
          player: const PlayerState(
            currentPosition: 1,
            position: Duration(milliseconds: 1500),
            loopMode: LoopMode.one,
            shuffleEnabled: true,
            volume: 0.5,
            muted: true,
          ),
        );
        await repository.write(
          shuffleRanks: {0: 1, 1: 0},
          player: const PlayerState(
            currentPosition: 1,
            position: Duration(milliseconds: 1500),
            loopMode: LoopMode.one,
            shuffleEnabled: true,
            volume: 0.5,
            muted: true,
          ),
        );
      });

      final tracks = await database
          .customSelect('SELECT * FROM tracks ORDER BY track_key')
          .get();
      expect(tracks.map((row) => row.data).toList(), [
        {
          'track_key': 'fmp-test:a:9',
          'source_type_id': 'fmp-test',
          'source_id': 'a',
          'cid': 9,
          'title': 'Song a',
          'uploader': 'Up',
          'duration_ms': 2000,
          'artwork_json':
              '[{"url":"https://cdn.example/a.jpg","width":64},'
              '{"url":"https://cdn.example/b.jpg"}]',
          'updated_at': DateTime.utc(2026, 10, 7, 12).millisecondsSinceEpoch,
        },
        {
          'track_key': 'fmp-test:b',
          'source_type_id': 'fmp-test',
          'source_id': 'b',
          'cid': null,
          'title': 'Song b',
          'uploader': null,
          'duration_ms': null,
          'artwork_json': null,
          'updated_at': DateTime.utc(2026, 10, 7, 12).millisecondsSinceEpoch,
        },
      ]);
      final entries = await database
          .customSelect('SELECT * FROM queue_entries ORDER BY position')
          .get();
      expect(entries.map((row) => row.data).toList(), [
        {'position': 0, 'track_key': 'fmp-test:a:9', 'shuffle_rank': 1},
        {'position': 1, 'track_key': 'fmp-test:b', 'shuffle_rank': 0},
      ]);
      final player = await database
          .customSelect('SELECT * FROM player_state')
          .getSingle();
      expect(player.data, {
        'id': 1,
        'current_position': 1,
        'position_ms': 1500,
        'loop_mode': 'one',
        'shuffle_enabled': 1,
        'volume': 0.5,
        'muted': 1,
        'updated_at': DateTime.utc(2026, 10, 7, 12).millisecondsSinceEpoch,
      });
    });

    test('the loop modes are written as fixed strings', () async {
      for (final (mode, text) in [
        (LoopMode.off, 'off'),
        (LoopMode.all, 'all'),
        (LoopMode.one, 'one'),
      ]) {
        await repository.write(
          player: PlayerState(
            currentPosition: null,
            position: Duration.zero,
            loopMode: mode,
            shuffleEnabled: false,
            volume: 1,
            muted: false,
          ),
        );
        final row = await database
            .customSelect('SELECT loop_mode FROM player_state')
            .getSingle();
        expect(row.read<String>('loop_mode'), text);
      }
    });

    test('an unknown loop mode is refused when reading', () async {
      await repository.write(player: _player);
      await database.customStatement("UPDATE player_state SET loop_mode = 'x'");

      await expectLater(repository.readPlayerState(), throwsFormatException);
    });

    test('a second player-state row cannot be inserted', () async {
      await repository.write(player: _player);

      await expectLater(
        database.customStatement(
          "INSERT INTO player_state (id, position_ms, loop_mode, "
          "shuffle_enabled, volume, muted, updated_at) "
          "VALUES (2, 0, 'off', 0, 1, 0, 0)",
        ),
        throwsA(anything),
      );
    });
  });

  test('replacing a queue of 10,000 songs', () async {
    final tracks = [for (var i = 0; i < 10000; i++) track('t$i')];
    final replacement = [for (var i = 0; i < 10000; i++) track('u$i')];

    final first = Stopwatch()..start();
    await writeAll(tracks);
    first.stop();
    final replace = Stopwatch()..start();
    await writeAll(replacement, existing: 10000);
    replace.stop();
    final read = Stopwatch()..start();
    final stored = await repository.readQueue();
    read.stop();

    // 數字記在 PR 描述：超過 500 ms 要說明。
    // ignore: avoid_print
    print(
      'queue of 10,000: first write ${first.elapsedMilliseconds} ms, '
      'whole replace ${replace.elapsedMilliseconds} ms, '
      'read ${read.elapsedMilliseconds} ms',
    );
    expect(stored.entries, replacement);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
