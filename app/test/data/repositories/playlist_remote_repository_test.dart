import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';

import '../../support/memory_database.dart';
import '../../support/pump_until.dart';

// 匯入歌單的寫入口（`playlist_remote`、刷新的一次寫入）。比對與套用的行為由
// `test/library/playlist_refresher_test.dart` 以假插件端到端地測；這裡只守資料層自己的
// 契約：建列、查列、代際、過期不寫、持久化格式。

final _at = DateTime.utc(2026, 10, 15, 12);

RemoteEntry entry(String id, {String? remoteItemId}) => RemoteEntry(
  track: TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: 'Song $id'),
  remoteItemId: remoteItemId,
);

void main() {
  late AppDatabase database;
  late PlaylistRepository repository;

  setUp(() {
    database = memoryDatabase();
    repository = PlaylistRepository(database);
  });

  Future<int> createImported({
    String remoteId = 'pl-basic',
    RemotePlaylistInfo info = const RemotePlaylistInfo(name: 'Remote'),
  }) async {
    final id = await repository.createImported(
      pluginId: 'fmp-test',
      remoteId: remoteId,
      info: info,
    );
    return id!;
  }

  Future<List<String>> sourceIds(int playlistId) async => [
    for (final e in await repository.entries(playlistId)) e.track.sourceId,
  ];

  group('createImported', () {
    test('writes one imported playlist and its remote row', () async {
      await repository.create(name: 'Local');
      final artwork = [TrackArtwork(url: Uri.parse('https://fmp.test/a.jpg'))];

      final id = await withClock(
        Clock.fixed(_at),
        () => createImported(
          info: RemotePlaylistInfo(
            name: 'Remote',
            description: 'About',
            artwork: artwork,
            ownerName: 'Me',
            writable: true,
          ),
        ),
      );

      final playlists = await repository.watchAll().first;
      expect([for (final p in playlists) p.name], ['Local', 'Remote']);
      final playlist = playlists.last;
      expect(playlist.id, id);
      expect(playlist.kind, PlaylistKind.imported);
      expect(playlist.description, 'About');
      expect(playlist.artwork, artwork);
      expect(playlist.sortOrder, 1);
      expect(playlist.createdAt, _at);
      final remote = (await repository.remote(id))!;
      expect(remote.pluginId, 'fmp-test');
      expect(remote.remoteId, 'pl-basic');
      expect(remote.ownerName, 'Me');
      expect(remote.writable, isTrue);
      expect(remote.refreshIntervalHours, 24);
      expect(remote.status, PlaylistRemoteStatus.active);
      expect(remote.lastResult, isNull);
      expect(remote.lastRefreshedAt, isNull);
      expect(remote.refreshGeneration, 0);
      expect([
        remote.nameOverridden,
        remote.descriptionOverridden,
        remote.artworkOverridden,
      ], everyElement(isFalse));
    });

    test('a writable of null is stored as false', () async {
      final id = await createImported();

      expect((await repository.remote(id))!.writable, isFalse);
    });

    test('the same plugin and remote id again writes nothing', () async {
      final first = await createImported();

      final second = await repository.createImported(
        pluginId: 'fmp-test',
        remoteId: 'pl-basic',
        info: const RemotePlaylistInfo(name: 'Again'),
      );

      expect(second, isNull);
      expect(
        [for (final p in await repository.watchAll().first) p.id],
        [first],
      );
      // 別的插件、別的遠端 id 照常能建，名稱不必唯一。
      expect(
        await repository.createImported(
          pluginId: 'other',
          remoteId: 'pl-basic',
          info: const RemotePlaylistInfo(name: 'Remote'),
        ),
        isNotNull,
      );
      expect(await createImported(remoteId: 'pl-grow'), isNotNull);
    });

    test('findRemote finds by plugin and remote id', () async {
      final id = await createImported();

      expect(
        (await repository.findRemote('fmp-test', 'pl-basic'))!.playlistId,
        id,
      );
      expect(await repository.findRemote('fmp-test', 'pl-grow'), isNull);
      expect(await repository.findRemote('other', 'pl-basic'), isNull);
    });

    test('a local playlist has no remote row', () async {
      final local = await repository.create(name: 'Local');

      expect(await repository.remote(local), isNull);
      expect(
        await repository.beginRefresh(local, isCurrent: () => true),
        isNull,
      );
    });
  });

  group('a refresh session', () {
    test('every begin bumps the generation', () async {
      final id = await createImported();

      final first = (await repository.beginRefresh(id, isCurrent: () => true))!;
      final second = (await repository.beginRefresh(
        id,
        isCurrent: () => true,
      ))!;

      expect(first.generation, 1);
      expect(second.generation, 2);
      expect((await repository.remote(id))!.refreshGeneration, 2);
    });

    test('a page of an older generation writes nothing', () async {
      final id = await createImported();
      final old = (await repository.beginRefresh(id, isCurrent: () => true))!;
      await repository.beginRefresh(id, isCurrent: () => true);

      expect(await old.writePage([entry('a')]), isFalse);
      expect(await old.apply(const RemotePlaylistInfo(name: 'X')), isNull);
      expect(await old.markPartial(), isFalse);
      expect(await old.markFailed(), isFalse);
      expect(await old.markStatus(PlaylistRemoteStatus.sourceGone), isFalse);

      expect(await sourceIds(id), isEmpty);
      final remote = (await repository.remote(id))!;
      expect(remote.lastResult, isNull);
      expect(remote.status, PlaylistRemoteStatus.active);
    });

    test('a trigger that is no longer current writes nothing', () async {
      final id = await createImported();
      var current = true;
      final session = (await repository.beginRefresh(
        id,
        isCurrent: () => current,
      ))!;
      expect(await session.writePage([entry('a')]), isTrue);

      current = false;

      expect(await session.writePage([entry('b')]), isFalse);
      expect(await session.apply(const RemotePlaylistInfo(name: 'X')), isNull);
      expect(await sourceIds(id), ['a']);
      expect((await repository.remote(id))!.lastResult, isNull);
    });

    test('a deleted playlist makes the session stale', () async {
      final id = await createImported();
      final session = (await repository.beginRefresh(
        id,
        isCurrent: () => true,
      ))!;

      await repository.delete(id);

      expect(await session.writePage([entry('a')]), isFalse);
    });

    test('stored format: status, result and time', () async {
      final id = await createImported();
      final session = (await repository.beginRefresh(
        id,
        isCurrent: () => true,
      ))!;
      await withClock(Clock.fixed(_at), session.markPartial);

      Future<Map<String, Object?>> row() async =>
          (await database
                  .customSelect(
                    'SELECT status, last_result, last_refreshed_at, refresh_generation '
                    'FROM playlist_remote',
                  )
                  .getSingle())
              .data;

      expect(await row(), {
        'status': 'active',
        'last_result': 'partial',
        'last_refreshed_at': _at.millisecondsSinceEpoch,
        'refresh_generation': 1,
      });

      await session.markStatus(PlaylistRemoteStatus.sourceGone);
      expect((await row())['status'], 'sourceGone');
      await session.markStatus(PlaylistRemoteStatus.authRequired);
      expect((await row())['status'], 'authRequired');
      await session.markFailed();
      expect((await row())['last_result'], 'failed');
      await session.apply(const RemotePlaylistInfo(name: 'Remote'));
      expect((await row())['last_result'], 'complete');
      expect((await row())['status'], 'active');
    });

    test('changes fires when only playlist_remote changes', () async {
      final id = await createImported();
      final session = (await repository.beginRefresh(
        id,
        isCurrent: () => true,
      ))!;
      final events = <void>[];
      final subscription = repository.changes().listen(events.add);
      addTearDown(subscription.cancel);

      await session.markFailed();
      await pumpUntil(() => events.isNotEmpty);
    });
  });
}
