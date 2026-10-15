import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/tracks_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/memory_database.dart';
import '../../support/pump_until.dart';

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

final _at = DateTime.utc(2026, 10, 15, 12);

/// 被某種約束擋下（不是別的錯，例如欄位名寫錯）。比對 SQLite 的訊息：`RESTRICT`
/// 以 trigger 實作，擴充碼是 `SQLITE_CONSTRAINT_TRIGGER` 而不是 `_FOREIGNKEY`。
Matcher _violates(String constraint) => throwsA(
  isA<SqliteException>().having(
    (e) => e.message,
    'message',
    contains('$constraint constraint failed'),
  ),
);

final _check = _violates('CHECK');

void main() {
  late AppDatabase database;
  late PlaylistRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = PlaylistRepository(database);
  });

  Future<List<String>> names() async => [
    for (final p in await repository.watchAll().first) p.name,
  ];

  Future<List<String>> ids(int playlistId) async => [
    for (final e in await repository.entries(playlistId)) e.track.sourceId,
  ];

  group('playlists', () {
    test('create appends in order and watchAll follows sort_order', () async {
      await withClock(Clock.fixed(_at), () async {
        await repository.create(name: 'A', description: 'first');
        await repository.create(name: 'B');
      });

      final all = await repository.watchAll().first;

      expect([for (final p in all) p.name], ['A', 'B']);
      expect([for (final p in all) p.sortOrder], [0, 1]);
      expect(all.first.kind, PlaylistKind.local);
      expect(all.first.description, 'first');
      expect(all.first.createdAt, _at);
      expect(all.first.updatedAt, _at);
    });

    test('update overwrites name, description and artwork', () async {
      final id = await withClock(
        Clock.fixed(_at),
        () => repository.create(name: 'A', description: 'old'),
      );
      final artwork = [TrackArtwork(url: Uri.parse('https://fmp.test/a.jpg'))];
      final later = _at.add(const Duration(hours: 1));

      await withClock(
        Clock.fixed(later),
        () => repository.update(id, name: 'A2', artwork: artwork),
      );

      final playlist = (await repository.watchAll().first).single;
      expect(playlist.name, 'A2');
      expect(playlist.description, isNull, reason: 'null clears it');
      expect(playlist.artwork, artwork);
      expect(playlist.createdAt, _at);
      expect(playlist.updatedAt, later);
    });

    test('adding, removing and moving entries bump updated_at', () async {
      final id = await withClock(
        Clock.fixed(_at),
        () => repository.create(name: 'A'),
      );
      final other = await withClock(
        Clock.fixed(_at),
        () => repository.create(name: 'B'),
      );
      Future<DateTime> updatedAt(int playlistId) async =>
          (await repository.watchAll().first)
              .singleWhere((p) => p.id == playlistId)
              .updatedAt;

      final added = _at.add(const Duration(hours: 1));
      await withClock(
        Clock.fixed(added),
        () => repository.addTracks(id, [track('a'), track('b')]),
      );
      expect(await updatedAt(id), added);

      final entries = await repository.entries(id);
      final moved = _at.add(const Duration(hours: 2));
      await withClock(
        Clock.fixed(moved),
        () => repository.moveEntries(id, [entries[1].id, entries[0].id]),
      );
      expect(await updatedAt(id), moved);

      final removed = _at.add(const Duration(hours: 3));
      await withClock(
        Clock.fixed(removed),
        () => repository.removeEntries([entries[0].id]),
      );
      expect(await updatedAt(id), removed);
      expect(await updatedAt(other), _at, reason: 'other playlists untouched');
    });

    test('reorder rewrites sort_order in the given order', () async {
      final a = await repository.create(name: 'A');
      final b = await repository.create(name: 'B');
      final c = await repository.create(name: 'C');

      await repository.reorder([c, a, b]);

      expect(await names(), ['C', 'A', 'B']);
      expect(
        [for (final p in await repository.watchAll().first) p.sortOrder],
        [0, 1, 2],
      );
    });

    test('deleting a playlist deletes its entries', () async {
      final id = await repository.create(name: 'A');
      await repository.addTracks(id, [track('a'), track('b')]);

      await repository.delete(id);

      expect(await names(), isEmpty);
      final left = await database
          .customSelect('SELECT COUNT(*) AS n FROM playlist_entries')
          .getSingle();
      expect(left.read<int>('n'), 0);
      expect(
        await TracksRepository(database).countOrphans(),
        2,
        reason: 'the track rows are left to the orphan cleanup',
      );
    });
  });

  group('entries', () {
    test('addTracks appends after the last entry with display data', () async {
      final id = await repository.create(name: 'A');
      final other = await repository.create(name: 'B');
      await repository.addTracks(id, [track('a'), track('b')]);
      await repository.addTracks(other, [track('z')]);

      await repository.addTracks(id, [track('c'), track('a')]);

      expect(await ids(id), ['a', 'b', 'c', 'a']);
      expect(
        [for (final e in await repository.entries(id)) e.position],
        [0, 1, 2, 3],
      );
      expect((await repository.entries(id)).first.track, track('a'));
      expect(await ids(other), ['z']);
    });

    test('addTracks writes the tracks with upsert', () async {
      final id = await repository.create(name: 'A');
      await repository.addTracks(id, [track('a', title: 'Old')]);

      await repository.addTracks(id, [track('a', title: 'New')]);

      expect(
        [for (final e in await repository.entries(id)) e.track.title],
        ['New', 'New'],
      );
    });

    test('removeEntries deletes only the given entries', () async {
      final id = await repository.create(name: 'A');
      await repository.addTracks(id, [track('a'), track('b'), track('c')]);
      final entries = await repository.entries(id);

      await repository.removeEntries([entries[0].id, entries[2].id]);

      expect(await ids(id), ['b']);
    });

    test('moveEntries rewrites positions in the given order', () async {
      final id = await repository.create(name: 'A');
      await repository.addTracks(id, [track('a'), track('b'), track('c')]);
      final e = await repository.entries(id);

      await repository.moveEntries(id, [e[2].id, e[0].id, e[1].id]);

      expect(await ids(id), ['c', 'a', 'b']);
      expect(
        [for (final x in await repository.entries(id)) x.position],
        [0, 1, 2],
      );
    });

    test('moveEntries does not touch another playlist', () async {
      final id = await repository.create(name: 'A');
      final other = await repository.create(name: 'B');
      await repository.addTracks(id, [track('a'), track('b')]);
      await repository.addTracks(other, [track('x'), track('y')]);
      final foreign = await repository.entries(other);

      await repository.moveEntries(id, [foreign[1].id, foreign[0].id]);

      expect(await ids(other), ['x', 'y']);
    });

    test(
      'moveEntries with a stale list keeps later entries at the end',
      () async {
        final id = await repository.create(name: 'A');
        await repository.addTracks(id, [track('a'), track('b'), track('c')]);
        final stale = await repository.entries(id);
        await repository.removeEntries([stale[1].id]);
        await repository.addTracks(id, [track('d')]);

        await repository.moveEntries(id, [
          for (final e in stale.reversed) e.id,
        ]);

        expect(await ids(id), ['c', 'a', 'd']);
      },
    );

    test('a track in a playlist cannot be deleted (RESTRICT)', () async {
      final id = await repository.create(name: 'A');
      await repository.addTracks(id, [track('a')]);

      await expectLater(
        database.customStatement('DELETE FROM tracks'),
        _violates('FOREIGN KEY'),
      );
      expect(await ids(id), ['a']);
    });
  });

  test('changes fires when a playlist or an entry changes', () async {
    final events = <void>[];
    final subscription = repository.changes().listen(events.add);
    addTearDown(subscription.cancel);

    final id = await repository.create(name: 'A');
    await settle();
    final afterCreate = events.length;
    await repository.addTracks(id, [track('a')]);
    await settle();

    expect(afterCreate, greaterThan(0));
    expect(events.length, greaterThan(afterCreate));
  });

  group('stored format and constraints', () {
    test('stored format: fixed kind strings and epoch milliseconds', () async {
      await withClock(Clock.fixed(_at), () => repository.create(name: 'L'));
      // 匯入與 Mix 歌單的寫入口在之後的 PR；這裡直接經 drift 寫，釘住轉換的寫入方向。
      for (final (kind, plugin, seed) in [
        (PlaylistKind.imported, null, null),
        (PlaylistKind.mix, 'youtube', 'abc'),
      ]) {
        await database
            .into(database.playlistsTable)
            .insert(
              PlaylistsTableCompanion.insert(
                kind: kind,
                name: '$kind',
                sortOrder: 1,
                createdAt: _at,
                updatedAt: _at,
                mixPluginId: Value(plugin),
                mixSeedSourceId: Value(seed),
              ),
            );
      }

      final rows = await database
          .customSelect(
            'SELECT kind, created_at, updated_at, artwork_json '
            'FROM playlists ORDER BY id',
          )
          .get();

      expect(
        [for (final r in rows) r.read<String>('kind')],
        ['local', 'imported', 'mix'],
      );
      expect(rows.first.data, {
        'kind': 'local',
        'created_at': _at.millisecondsSinceEpoch,
        'updated_at': _at.millisecondsSinceEpoch,
        'artwork_json': null,
      });
    });

    test('fixed kind strings read back as their kinds', () async {
      await database.customStatement(
        'INSERT INTO playlists (kind, name, sort_order, created_at, updated_at, '
        "mix_plugin_id, mix_seed_source_id) VALUES ('local', 'L', 0, 1, 1, "
        "NULL, NULL), ('imported', 'I', 1, 1, 1, NULL, NULL), "
        "('mix', 'M', 2, 1, 1, 'youtube', 'abc')",
      );

      expect(
        [for (final p in await repository.watchAll().first) p.kind],
        [PlaylistKind.local, PlaylistKind.imported, PlaylistKind.mix],
      );
    });

    Future<void> insert(String kind, String mix) => database.customStatement(
      'INSERT INTO playlists (kind, name, sort_order, created_at, updated_at, '
      "mix_plugin_id, mix_seed_source_id, mix_seed_cid) VALUES ('$kind', 'n', "
      '0, 1, 1, $mix)',
    );

    test('a mix needs its plugin and seed source', () async {
      await insert('mix', "'youtube', 'abc', NULL");
      await insert('mix', "'youtube', 'abc', 5");

      await expectLater(insert('mix', 'NULL, NULL, NULL'), _check);
      await expectLater(insert('mix', "'youtube', NULL, NULL"), _check);
      await expectLater(insert('mix', "NULL, 'abc', NULL"), _check);
    });

    test('a non-mix playlist carries no mix columns', () async {
      await insert('local', 'NULL, NULL, NULL');

      await insert('imported', 'NULL, NULL, NULL');

      await expectLater(insert('local', "'youtube', NULL, NULL"), _check);
      await expectLater(insert('local', "NULL, 'abc', NULL"), _check);
      await expectLater(insert('imported', 'NULL, NULL, 1'), _check);
      await expectLater(insert('imported', "'youtube', 'abc', NULL"), _check);
    });

    test('an unknown kind in the database is a FormatException', () async {
      await database.customStatement(
        'INSERT INTO playlists (kind, name, sort_order, created_at, '
        "updated_at) VALUES ('weird', 'n', 0, 1, 1)",
      );

      await expectLater(
        repository.watchAll().first,
        throwsA(isA<FormatException>()),
      );
    });
  });
}
