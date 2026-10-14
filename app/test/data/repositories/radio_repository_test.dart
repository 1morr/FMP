import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/domain/track_info.dart';

import '../../support/memory_database.dart';

final _at = DateTime.utc(2026, 10, 14, 12);

Future<bool> _add(
  RadioRepository repository,
  String room, {
  String plugin = 'bilibili',
  String title = 'Title',
  List<TrackArtwork> artwork = const [],
}) => repository.add(
  pluginId: plugin,
  roomId: room,
  title: title,
  artwork: artwork,
  addedAt: _at,
);

void main() {
  test('adds to the end of the list in order', () async {
    final repository = RadioRepository(memoryDatabase());

    expect(await _add(repository, 'a'), isTrue);
    expect(await _add(repository, 'b'), isTrue);
    expect(await _add(repository, 'c', plugin: 'other'), isTrue);

    final list = await repository.list();
    expect(
      [for (final s in list) '${s.pluginId}:${s.roomId}'],
      ['bilibili:a', 'bilibili:b', 'other:c'],
    );
    expect([for (final s in list) s.sortOrder], [0, 1, 2]);
  });

  test('the same plugin and room is added once; another plugin may use the '
      'same room id', () async {
    final repository = RadioRepository(memoryDatabase());
    await _add(repository, '5440', title: 'First');

    expect(await _add(repository, '5440', title: 'Second'), isFalse);
    expect(await _add(repository, '5440', plugin: 'other'), isTrue);

    final list = await repository.list();
    expect(list, hasLength(2));
    expect(list.first.title, 'First', reason: 'the existing row is untouched');
  });

  test('keeps the details that were given, and a status that was never '
      'checked stays empty', () async {
    final repository = RadioRepository(memoryDatabase());

    await repository.add(
      pluginId: 'bilibili',
      roomId: '1',
      title: 'Room',
      hostName: 'Host',
      artwork: [
        TrackArtwork(url: Uri.parse('https://example.test/a.jpg'), width: 300),
        TrackArtwork(url: Uri.parse('https://example.test/b.jpg')),
      ],
      addedAt: _at,
    );

    final station = (await repository.list()).single;
    expect(station.hostName, 'Host');
    expect(station.artwork, [
      TrackArtwork(url: Uri.parse('https://example.test/a.jpg'), width: 300),
      TrackArtwork(url: Uri.parse('https://example.test/b.jpg')),
    ]);
    expect(station.addedAt, _at);
    expect(station.liveStatus, isNull);
    expect(station.liveTitle, isNull);
    expect(station.statusCheckedAt, isNull);
  });

  test('reorder rewrites sort_order for the whole list', () async {
    final repository = RadioRepository(memoryDatabase());
    for (final room in ['a', 'b', 'c', 'd']) {
      await _add(repository, room);
    }
    final ids = {for (final s in await repository.list()) s.roomId: s.id};

    await repository.reorder([ids['c']!, ids['a']!, ids['d']!, ids['b']!]);

    final list = await repository.list();
    expect([for (final s in list) s.roomId], ['c', 'a', 'd', 'b']);
    expect([for (final s in list) s.sortOrder], [0, 1, 2, 3]);
    // 重排之後新加的排在最後。
    await _add(repository, 'e');
    expect((await repository.list()).last.roomId, 'e');
  });

  test(
    'remove deletes one row and tolerates a row that is already gone',
    () async {
      final repository = RadioRepository(memoryDatabase());
      await _add(repository, 'a');
      await _add(repository, 'b');
      final a = (await repository.list()).first;

      await repository.remove(a.id);
      await repository.remove(a.id);

      expect([for (final s in await repository.list()) s.roomId], ['b']);
      // 刪掉的位置之後新加的，排序仍在最後。
      await _add(repository, 'c');
      expect([for (final s in await repository.list()) s.roomId], ['b', 'c']);
    },
  );

  test('updateStatus writes only the status fields', () async {
    final repository = RadioRepository(memoryDatabase());
    await repository.add(
      pluginId: 'bilibili',
      roomId: 'a',
      title: 'Original title',
      hostName: 'Host',
      addedAt: _at,
    );
    final station = (await repository.list()).single;

    await repository.updateStatus(
      station.id,
      status: RadioLiveStatus.live,
      liveTitle: 'On air now',
      checkedAt: _at.add(const Duration(minutes: 5)),
    );

    final after = (await repository.list()).single;
    expect(after.liveStatus, RadioLiveStatus.live);
    expect(after.liveTitle, 'On air now');
    expect(after.statusCheckedAt, _at.add(const Duration(minutes: 5)));
    expect(after.title, 'Original title');
    expect(after.hostName, 'Host');
    expect(after.sortOrder, station.sortOrder);
  });

  test(
    'updateStatus on a row that was deleted meanwhile does nothing',
    () async {
      final repository = RadioRepository(memoryDatabase());
      await _add(repository, 'a');
      final station = (await repository.list()).single;
      await repository.remove(station.id);

      await repository.updateStatus(
        station.id,
        status: RadioLiveStatus.offline,
        liveTitle: 'x',
        checkedAt: _at,
      );

      expect(await repository.list(), isEmpty);
    },
  );

  test('watch emits the list and every change in it', () async {
    final repository = RadioRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current, isEmpty);

    await _add(repository, 'a');
    expect(await events.moveNext(), isTrue);
    expect(events.current.map((s) => s.roomId), ['a']);

    await repository.updateStatus(
      events.current.single.id,
      status: RadioLiveStatus.live,
      liveTitle: 'On air',
      checkedAt: _at,
    );
    expect(await events.moveNext(), isTrue);
    expect(events.current.single.liveStatus, RadioLiveStatus.live);
  });

  test('stored format: status strings and epoch milliseconds', () async {
    final database = memoryDatabase();
    final repository = RadioRepository(database);
    await _add(repository, 'a');
    await repository.updateStatus(
      (await repository.list()).single.id,
      status: RadioLiveStatus.offline,
      liveTitle: 'Gone',
      checkedAt: _at,
    );

    final row = await database
        .customSelect(
          'SELECT live_status, live_title, status_checked_at, added_at '
          'FROM radio_stations',
        )
        .getSingle();
    expect(row.data, {
      'live_status': 'offline',
      'live_title': 'Gone',
      'status_checked_at': _at.millisecondsSinceEpoch,
      'added_at': _at.millisecondsSinceEpoch,
    });
  });
}
