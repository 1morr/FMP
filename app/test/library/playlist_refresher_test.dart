import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../support/pump_until.dart';
import 'fake_import_plugin.dart';
import 'library_harness.dart';

// 刷新器（ADR 0019 §決定 2、ADR 0033 §決定 2、M4 design §5.2）：ADR 0019 §如何確認的刷新差異
// 全部、比對鍵、完整性三條件、中途被殺後再刷新、過期不寫、`writable`、FIFO 鎖、插件停用。
// 以腳本化的假插件與記憶體資料庫跑；repository 自己的契約在
// `test/data/repositories/playlist_remote_repository_test.dart`。

final _at = DateTime.utc(2026, 10, 15, 12);

void main() {
  late LibraryEnv env;

  setUp(() async {
    env = await LibraryEnv.open();
  });

  /// 腳本：鍵是 `cursor`（第一頁是 `null`），值是 [PlaylistPage] 或要丟的錯。
  void serve(Map<String?, Object> pages) {
    env.plugin.onPage = (query) {
      final response = pages[query.cursor];
      if (response is PlaylistPage) return response;
      throw response ?? StateError('no scripted page for ${query.cursor}');
    };
  }

  Future<int> newPlaylist({
    String remoteId = 'pl',
    String name = 'Remote title',
  }) async => (await env.repository.createImported(
    pluginId: 'fmp-test',
    remoteId: remoteId,
    info: RemotePlaylistInfo(name: name),
  ))!;

  Future<RefreshOutcome> refresh(
    int id, {
    RefreshTrigger trigger = RefreshTrigger.manual,
    PlaylistPage? firstPage,
  }) => withClock(
    Clock.fixed(_at),
    () => env.refresher.refresh(id, trigger: trigger, firstPage: firstPage),
  );

  Future<List<String>> ids(int id) async => [
    for (final e in await env.repository.entries(id)) e.track.sourceId,
  ];

  Future<List<int>> entryIds(int id) async => [
    for (final e in await env.repository.entries(id)) e.id,
  ];

  Future<Map<String, Object?>> remoteRow(int id) async =>
      (await env.database
              .customSelect(
                'SELECT * FROM playlist_remote WHERE playlist_id = $id',
              )
              .getSingle())
          .data;

  Future<Map<String, Object?>> playlistRow(int id) async =>
      (await env.database
              .customSelect('SELECT * FROM playlists WHERE id = $id')
              .getSingle())
          .data;

  Future<List<Map<String, Object?>>> rawEntries(int id) async => [
    for (final row
        in await env.database
            .customSelect(
              'SELECT * FROM playlist_entries WHERE playlist_id = $id '
              'ORDER BY position, id',
            )
            .get())
      row.data,
  ];

  Future<void> sql(String statement) => env.database.customStatement(statement);

  Matcher finished(PlaylistRefreshResult result, {int? added, int? removed}) =>
      isA<RefreshFinished>()
          .having((o) => o.result, 'result', result)
          .having((o) => o.added, 'added', added ?? anything)
          .having((o) => o.removed, 'removed', removed ?? anything);

  group('differences', () {
    test('the first refresh adds everything in the remote order', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c'], total: 3),
      });

      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.complete, added: 3));
      expect(await ids(id), ['a', 'b', 'c']);
      expect([for (final r in await rawEntries(id)) r['position']], [0, 1, 2]);
      final remote = await remoteRow(id);
      expect(remote['last_result'], 'complete');
      expect(remote['status'], 'active');
      expect(remote['last_refreshed_at'], _at.millisecondsSinceEpoch);
      expect(remote['refresh_generation'], 1);
    });

    test('new tracks are added where the remote has them', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);
      final before = await entryIds(id);

      serve({
        null: page(['a', 'x', 'b', 'c', 'y']),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.complete, added: 2));
      expect(await ids(id), ['a', 'x', 'b', 'c', 'y']);
      // 比對到的項目身分不變。
      final after = await entryIds(id);
      expect([after[0], after[2], after[3]], before);
    });

    test('tracks missing from the remote are removed', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);

      serve({
        null: page(['a', 'c']),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.complete, removed: 1));
      expect(await ids(id), ['a', 'c']);
      expect([for (final r in await rawEntries(id)) r['position']], [0, 1]);
    });

    test('the order follows the remote', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);
      final before = {
        for (final e in await env.repository.entries(id))
          e.track.sourceId: e.id,
      };

      serve({
        null: page(['c', 'a', 'b']),
      });
      await refresh(id);

      expect(await ids(id), ['c', 'a', 'b']);
      final after = {
        for (final e in await env.repository.entries(id))
          e.track.sourceId: e.id,
      };
      expect(after, before);
    });

    test('track metadata, the unavailable flag and the playlist follow the '
        'remote', () async {
      final id = await newPlaylist(name: 'Old name');
      serve({
        null: page(
          ['a', 'b'],
          title: 'Old name',
          unavailable: {1},
          trackTitle: (id) => 'Old $id',
        ),
      });
      await refresh(id);
      expect([for (final r in await rawEntries(id)) r['unavailable']], [0, 1]);

      serve({
        null: page(
          ['a', 'b'],
          title: 'New name',
          description: 'New description',
          ownerName: 'New owner',
          trackTitle: (id) => 'New $id',
        ),
      });
      await refresh(id);

      final entries = await env.repository.entries(id);
      expect([for (final e in entries) e.track.title], ['New a', 'New b']);
      expect([for (final r in await rawEntries(id)) r['unavailable']], [0, 0]);
      final playlist = await playlistRow(id);
      expect(playlist['name'], 'New name');
      expect(playlist['description'], 'New description');
      expect(playlist['updated_at'], _at.millisecondsSinceEpoch);
      expect((await remoteRow(id))['owner_name'], 'New owner');
    });

    test('an unavailable entry stays in the playlist', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c'], unavailable: {1}, total: 3),
      });

      await refresh(id);

      expect(await ids(id), ['a', 'b', 'c']);
      expect(
        [for (final r in await rawEntries(id)) r['unavailable']],
        [0, 1, 0],
      );
    });

    for (final (flag, column) in [
      ('name_overridden', 'name'),
      ('description_overridden', 'description'),
      ('artwork_overridden', 'artwork_json'),
    ]) {
      test('$flag keeps the local $column and nothing else', () async {
        final id = await newPlaylist(name: 'Mine');
        await sql(
          "UPDATE playlists SET description = 'Mine', artwork_json = "
          "'[{\"url\":\"https://fmp.test/mine.jpg\"}]' WHERE id = $id",
        );
        await sql(
          'UPDATE playlist_remote SET $flag = 1 WHERE playlist_id = $id',
        );
        serve({
          null: PlaylistPage(
            playlist: RemotePlaylist(
              title: 'Remote name',
              description: 'Remote description',
              artwork: [Artwork(url: Uri.parse('https://fmp.test/remote.jpg'))],
            ),
            items: const [],
            total: 0,
          ),
        });

        await refresh(id);

        final playlist = await playlistRow(id);
        expect(playlist['name'], column == 'name' ? 'Mine' : 'Remote name');
        expect(
          playlist['description'],
          column == 'description' ? 'Mine' : 'Remote description',
        );
        expect(
          playlist['artwork_json'],
          contains(column == 'artwork_json' ? 'mine.jpg' : 'remote.jpg'),
        );
      });
    }

    test('a track that appears twice is kept twice', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'a']),
      });
      await refresh(id);
      final before = await entryIds(id);

      await refresh(id);

      expect(await ids(id), ['a', 'b', 'a']);
      expect(await entryIds(id), before);
    });
  });

  group('matching keys', () {
    test('without a remote item id the k-th occurrence of a track matches the '
        'k-th entry', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'a']),
      });
      await refresh(id);
      final byPosition = await entryIds(id); // [a1, b, a2]

      // 遠端只剩兩個 a：第 1、2 次出現各對到原來的第 1、2 個，b 被移除。
      serve({
        null: page(['a', 'a']),
      });
      await refresh(id);
      expect(await entryIds(id), [byPosition[0], byPosition[2]]);

      // 遠端又多一個：前兩個沿用，第三個是新的。
      serve({
        null: page(['a', 'a', 'a']),
      });
      await refresh(id);
      final three = await entryIds(id);
      expect(three.take(2), [byPosition[0], byPosition[2]]);
      expect(three, hasLength(3));
    });

    test(
      'the k-th entry is counted by the current position, not by id',
      () async {
        final id = await newPlaylist();
        serve({
          null: page(['a', 'a']),
        });
        await refresh(id);
        final first = await entryIds(id);
        // 把兩個項目的位置對調：id 小的排在後面。
        await sql(
          'UPDATE playlist_entries SET position = 1 - position '
          'WHERE playlist_id = $id',
        );
        expect(await entryIds(id), first.reversed.toList());

        serve({
          null: page(['a']),
        });
        await refresh(id);

        // 第 1 次出現對到目前排第一的項目（id 較大的那個）。
        expect(await entryIds(id), [first.last]);
      },
    );

    test('with a remote item id the id matches, whatever the track and '
        'position', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b'], remoteIds: ['r1', 'r2']),
      });
      await refresh(id);
      final entries = {
        for (final e in await env.repository.entries(id))
          e.track.sourceId: e.id,
      };

      // r2 換了位置，r1 的曲目被換成 z（同一個遠端項目 id）。
      serve({
        null: page(['b', 'z'], remoteIds: ['r2', 'r1']),
      });
      await refresh(id);

      expect(await ids(id), ['b', 'z']);
      expect(await entryIds(id), [entries['b'], entries['a']]);
      expect(
        [for (final r in await rawEntries(id)) r['remote_item_id']],
        ['r2', 'r1'],
      );
    });

    test('the same track under two remote item ids is two entries', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a'], remoteIds: ['r1']),
      });
      await refresh(id);

      serve({
        null: page(['a', 'a'], remoteIds: ['r1', 'r2']),
      });
      await refresh(id);
      expect(await ids(id), ['a', 'a']);

      serve({
        null: page(['a'], remoteIds: ['r2']),
      });
      await refresh(id);
      expect(await ids(id), ['a']);
      expect(
        [for (final r in await rawEntries(id)) r['remote_item_id']],
        ['r2'],
      );
    });

    test('an entry with a remote item id is only matched by that id', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b'], remoteIds: ['r1', 'r2']),
      });
      await refresh(id);
      final before = await entryIds(id);

      // 同一張改成沒有遠端項目 id 的回應，而且沒讀完：比不到，兩首接在尾端，舊的留著。
      serve({
        null: page(['a', 'b'], cursor: 'p2'),
        'p2': NetworkError(),
      });
      expect(await refresh(id), finished(PlaylistRefreshResult.partial));
      expect(await ids(id), ['a', 'b', 'a', 'b']);

      // 讀完時有 id 的舊項目被刪，留下的是新的。
      serve({
        null: page(['a', 'b']),
      });
      expect(await refresh(id), finished(PlaylistRefreshResult.complete));
      expect(await ids(id), ['a', 'b']);
      expect(await entryIds(id), isNot(contains(before.first)));
      expect(
        [for (final r in await rawEntries(id)) r['remote_item_id']],
        [null, null],
      );
    });
  });

  group('completeness', () {
    test('every page, an empty last cursor and a matching total apply the '
        'removals', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);

      serve({
        null: page(['c'], cursor: 'p2', total: 3),
        'p2': page(['b', 'a'], total: 3),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.complete));
      expect(await ids(id), ['c', 'b', 'a']);
    });

    test('a page that fails makes it partial: nothing is removed or '
        'reordered', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c', 'd']),
      });
      await refresh(id);

      serve({
        null: page(['z', 'a'], cursor: 'p2', total: 4, title: 'Renamed'),
        'p2': NetworkError(),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.partial, removed: 0));
      // 新增與更新照做，其餘原樣。
      expect(await ids(id), ['a', 'b', 'c', 'd', 'z']);
      final remote = await remoteRow(id);
      expect(remote['last_result'], 'partial');
      expect(remote['status'], 'active');
      expect(remote['last_refreshed_at'], _at.millisecondsSinceEpoch);
      // 名稱等只在完整套用時才跟遠端。
      expect((await playlistRow(id))['name'], 'Remote title');
    });

    test('fewer items than the total is partial', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);

      serve({
        null: page(['a', 'b'], total: 3),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.partial));
      expect(await ids(id), ['a', 'b', 'c']);
    });

    test('a truncated last page is partial: nothing is removed or '
        'reordered', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);

      serve({
        null: page(['c', 'a'], truncated: true, title: 'Renamed'),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.partial, removed: 0));
      expect(await ids(id), ['a', 'b', 'c']);
      expect((await playlistRow(id))['name'], isNot('Renamed'));
      expect((await remoteRow(id))['last_result'], 'partial');
    });

    test('more items than the total is partial too', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);

      serve({
        null: page(['a'], total: 3),
      });
      expect(await refresh(id), finished(PlaylistRefreshResult.partial));
      serve({
        null: page(['a', 'b', 'c', 'd'], total: 3),
      });
      expect(await refresh(id), finished(PlaylistRefreshResult.partial));
    });

    test('a cursor that never ends is cut off and partial', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b']),
      });
      await refresh(id);

      env.plugin.onPage = (_) => page(['a'], cursor: 'same');
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.partial));
      // 沒讀完所以不移除（b 還在）；同一個 cursor 取回的第二個 a 是新的項目。
      expect(await ids(id), ['a', 'b', 'a']);
      expect(env.plugin.pageQueries.length, lessThan(10));
    });

    test('no total to compare is still complete', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b']),
      });
      await refresh(id);

      serve({
        null: page(['b']),
      });

      expect(await refresh(id), finished(PlaylistRefreshResult.complete));
      expect(await ids(id), ['b']);
    });

    test('an empty remote playlist with a total of zero empties the local '
        'one', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b']),
      });
      await refresh(id);

      serve({null: page([], total: 0)});

      expect(await refresh(id), finished(PlaylistRefreshResult.complete));
      expect(await ids(id), isEmpty);
    });

    test('the first page given by the caller is not fetched again', () async {
      final id = await newPlaylist();
      serve({
        'p2': page(['c'], total: 3),
      });

      final outcome = await refresh(
        id,
        firstPage: page(['a', 'b'], cursor: 'p2', total: 3),
      );

      expect(outcome, finished(PlaylistRefreshResult.complete, added: 3));
      expect(await ids(id), ['a', 'b', 'c']);
      expect([for (final q in env.plugin.pageQueries) q.cursor], ['p2']);
    });
  });

  group('failures', () {
    Future<int> filled() async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b']),
      });
      await refresh(id);
      return id;
    }

    test('NotFound marks the source gone and keeps the content', () async {
      final id = await filled();
      serve({null: NotFound()});

      final outcome = await refresh(id);

      expect(outcome, isA<RefreshFailed>());
      expect((outcome as RefreshFailed).error, isA<NotFound>());
      expect(await ids(id), ['a', 'b']);
      final remote = await remoteRow(id);
      expect(remote['status'], 'sourceGone');
      expect(remote['last_result'], 'complete');
    });

    test('AuthRequired marks it as needing a login', () async {
      final id = await filled();
      serve({null: AuthRequired()});

      final outcome = await refresh(id);

      expect((outcome as RefreshFailed).error, isA<AuthRequired>());
      expect(await ids(id), ['a', 'b']);
      expect((await remoteRow(id))['status'], 'authRequired');
    });

    test('NotFound on a later page does not touch the entries', () async {
      final id = await filled();
      serve({
        null: page(['z'], cursor: 'p2'),
        'p2': NotFound(),
      });

      await refresh(id);

      expect((await remoteRow(id))['status'], 'sourceGone');
      // 第一頁已經寫進去的新增留著，但沒有移除與重排。
      expect(await ids(id), ['a', 'b', 'z']);
    });

    test('any other error on the first page is failed and leaves the status '
        'alone', () async {
      final id = await filled();
      await sql(
        "UPDATE playlist_remote SET status = 'sourceGone' WHERE playlist_id = $id",
      );
      serve({null: NetworkError()});

      final outcome = await refresh(id);

      expect(outcome, isA<RefreshFailed>());
      expect(await ids(id), ['a', 'b']);
      final remote = await remoteRow(id);
      expect(remote['last_result'], 'failed');
      expect(remote['status'], 'sourceGone');
    });

    test('an error that is not an AppError is failed too', () async {
      final id = await filled();
      serve({null: StateError('boom')});

      final outcome = await refresh(id);

      expect(outcome, isA<RefreshFailed>());
      expect((outcome as RefreshFailed).error, isA<UnexpectedError>());
      expect((await remoteRow(id))['last_result'], 'failed');
    });

    test('a refresh that works brings the status back to active', () async {
      final id = await filled();
      serve({null: NotFound()});
      await refresh(id);
      expect((await remoteRow(id))['status'], 'sourceGone');

      serve({
        null: page(['a']),
      });
      await refresh(id);

      final remote = await remoteRow(id);
      expect(remote['status'], 'active');
      expect(remote['last_result'], 'complete');
      expect(await ids(id), ['a']);
    });

    test('a partial refresh brings the status back to active too', () async {
      final id = await filled();
      serve({null: AuthRequired()});
      await refresh(id);
      expect((await remoteRow(id))['status'], 'authRequired');

      serve({
        null: page(['a'], cursor: 'p2'),
        'p2': NetworkError(),
      });
      expect(await refresh(id), finished(PlaylistRefreshResult.partial));

      final remote = await remoteRow(id);
      expect(remote['status'], 'active');
      expect(remote['last_result'], 'partial');
    });

    test('a failure does not move last_refreshed_at', () async {
      final id = await filled();
      serve({null: NetworkError()});
      await withClock(
        Clock.fixed(_at.add(const Duration(days: 1))),
        () => env.refresher.refresh(id),
      );

      expect(
        (await remoteRow(id))['last_refreshed_at'],
        _at.millisecondsSinceEpoch,
      );
    });
  });

  group('writable', () {
    test('null keeps the last value; a value replaces it', () async {
      final id = await newPlaylist();
      Future<Object?> writable() async => (await remoteRow(id))['writable'];

      serve({
        null: page(['a'], writable: true),
      });
      await refresh(id);
      expect(await writable(), 1);

      serve({
        null: page(['a']),
      });
      await refresh(id);
      expect(await writable(), 1);

      serve({
        null: page(['a'], writable: false),
      });
      await refresh(id);
      expect(await writable(), 0);
    });
  });

  group('interrupted refreshes', () {
    test('a refresh that stops after some pages leaves a database the next '
        'refresh repairs', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b', 'c']),
      });
      await refresh(id);
      final kept = {
        for (final e in await env.repository.entries(id))
          e.track.sourceId: e.id,
      };

      // 遠端現在是 c, d, e, f，每頁兩首；第二頁取回時觸發者失效（等於第一頁寫完後被殺）。
      var alive = true;
      env.plugin.onPage = (query) {
        if (query.cursor == null) {
          return page(['c', 'd'], cursor: 'p2', total: 4);
        }
        alive = false;
        return page(['e', 'f'], total: 4);
      };
      final killed = await refresh(
        id,
        trigger: RefreshTrigger(isCurrent: () => alive),
      );

      expect(killed, isA<RefreshDiscarded>());
      // 沒有刪、沒有重排：a、b、c 都還在，第一頁的新增（d）留在尾端。
      expect(await ids(id), ['a', 'b', 'c', 'd']);
      final remote = await remoteRow(id);
      expect(remote['last_result'], 'complete');
      expect(remote['refresh_generation'], 2);
      final afterKill = await env.repository.entries(id);
      final dId = afterKill.last.id;

      serve({
        null: page(['c', 'd'], cursor: 'p2', total: 4),
        'p2': page(['e', 'f'], total: 4),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.complete));
      expect(await ids(id), ['c', 'd', 'e', 'f']);
      final after = await entryIds(id);
      expect(after.take(2), [kept['c'], dId]);
    });

    test('an error inside a page rolls that page back; the next refresh is '
        'right', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b']),
      });
      await refresh(id);
      // 第二頁的第二首寫不進去。
      await sql(
        'CREATE TRIGGER boom BEFORE INSERT ON playlist_entries '
        "WHEN NEW.track_key = 'fmp-test:boom' "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      serve({
        null: page(['a', 'x'], cursor: 'p2'),
        'p2': page(['y', 'boom'], total: 4),
      });

      await expectLater(refresh(id), throwsA(anything));

      // 第一頁已經提交；第二頁整頁回滾（y 也沒寫，曲目表也一樣）。
      expect(await ids(id), ['a', 'b', 'x']);
      final tracks = await env.database
          .customSelect(
            "SELECT track_key FROM tracks WHERE track_key = 'fmp-test:y'",
          )
          .get();
      expect(tracks, isEmpty);
      expect((await remoteRow(id))['last_result'], 'complete');

      await sql('DROP TRIGGER boom');
      serve({
        null: page(['a', 'x'], cursor: 'p2'),
        'p2': page(['y', 'boom'], total: 4),
      });
      final outcome = await refresh(id);

      expect(outcome, finished(PlaylistRefreshResult.complete));
      expect(await ids(id), ['a', 'x', 'y', 'boom']);
    });

    test(
      'a refresh started elsewhere makes this one stop (generation)',
      () async {
        final id = await newPlaylist();
        serve({
          null: page(['a', 'b']),
        });
        await refresh(id);

        env.plugin.onPage = (query) {
          if (query.cursor == null) return page(['a', 'z'], cursor: 'p2');
          // 第二頁取回之前，另一次刷新已經開始（代際加一）。
          return env.repository
              .beginRefresh(id, isCurrent: () => true)
              .then((_) => page(['q']));
        };

        final outcome = await refresh(id);

        expect(outcome, isA<RefreshDiscarded>());
        expect(await ids(id), ['a', 'b', 'z']);
      },
    );

    test('a trigger that is no longer current writes nothing', () async {
      final id = await newPlaylist();
      serve({
        null: page(['a', 'b']),
      });
      await refresh(id);
      serve({
        null: page(['c']),
      });

      final outcome = await refresh(
        id,
        trigger: RefreshTrigger(isCurrent: () => false),
      );

      expect(outcome, isA<RefreshDiscarded>());
      expect(await ids(id), ['a', 'b']);
      final remote = await remoteRow(id);
      expect(remote['last_result'], 'complete');
      expect(remote['status'], 'active');
      // 連代際都不動：排隊期間就失效的觸發者不開始刷新。
      expect(remote['refresh_generation'], 1);
      expect(env.plugin.pageQueries, hasLength(1));
    });

    test('a failure of a stale trigger is not recorded either', () async {
      final id = await newPlaylist();
      serve({null: NotFound()});

      await refresh(id, trigger: RefreshTrigger(isCurrent: () => false));

      expect((await remoteRow(id))['status'], 'active');
    });
  });

  group('the plugin', () {
    test(
      'a disabled or removed plugin is reported and nothing is written',
      () async {
        final id = await newPlaylist();
        serve({
          null: page(['a']),
        });
        await env.setPlugins(const []);

        final outcome = await refresh(id);

        expect(outcome, isA<RefreshSourceUnavailable>());
        expect(env.plugin.pageQueries, isEmpty);
        expect(await ids(id), isEmpty);
        final remote = await remoteRow(id);
        expect(remote['refresh_generation'], 0);
        expect(remote['last_result'], isNull);
      },
    );

    test('a plugin that is disabled in the middle stops the refresh', () async {
      final id = await newPlaylist();
      env.plugin.onPage = (query) async {
        if (query.cursor == null) return page(['a'], cursor: 'p2');
        await env.setPlugins(const []);
        return page(['b']);
      };

      final outcome = await refresh(id);

      expect(outcome, isA<RefreshDiscarded>());
      expect(await ids(id), ['a']);
      expect((await remoteRow(id))['last_result'], isNull);
    });

    test(
      'a playlist that was deleted or never imported is discarded',
      () async {
        final local = await env.repository.create(name: 'Local');
        final gone = await newPlaylist();
        await env.repository.delete(gone);

        expect(await refresh(local), isA<RefreshDiscarded>());
        expect(await refresh(gone), isA<RefreshDiscarded>());
        expect(env.plugin.pageQueries, isEmpty);
      },
    );
  });

  group('a deleted playlist', () {
    test('deleting the playlist in the middle of a refresh discards it and '
        'frees the lock', () async {
      final id = await newPlaylist();
      final other = await newPlaylist(remoteId: 'other');
      env.plugin.onPage = (query) async {
        if (query.playlistId == 'other') return page(['o']);
        if (query.cursor == null) return page(['a'], cursor: 'p2');
        // 第一頁已經寫進去之後，使用者刪了這張歌單。
        await env.repository.delete(id);
        return page(['b']);
      };

      final outcomes = await Future.wait([refresh(id), refresh(other)]);

      expect(outcomes.first, isA<RefreshDiscarded>());
      expect(outcomes.last, finished(PlaylistRefreshResult.complete));
      expect(await env.repository.remote(id), isNull);
      final orphans = await env.database
          .customSelect(
            'SELECT id FROM playlist_entries WHERE playlist_id = $id',
          )
          .get();
      expect(orphans, isEmpty);
      expect(await ids(other), ['o']);
    });
  });

  group('the lock', () {
    test(
      'only one playlist is refreshed at a time, in the order asked',
      () async {
        final first = await newPlaylist(remoteId: 'one');
        final second = await newPlaylist(remoteId: 'two');
        final third = await newPlaylist(remoteId: 'three');
        final gates = <String, Completer<void>>{};
        var running = 0;
        var maxRunning = 0;
        final started = <String>[];
        env.plugin.onPage = (query) async {
          started.add(query.playlistId);
          running++;
          if (running > maxRunning) maxRunning = running;
          await (gates[query.playlistId] = Completer<void>()).future;
          running--;
          return page([query.playlistId]);
        };

        final results = [
          env.refresher.refresh(first),
          env.refresher.refresh(second),
          env.refresher.refresh(third),
        ];
        await pumpUntil(() => started.length == 1);
        await settle();

        expect(started, ['one']);

        gates['one']!.complete();
        await pumpUntil(() => started.length == 2);
        expect(started, ['one', 'two']);
        gates['two']!.complete();
        await pumpUntil(() => started.length == 3);
        gates['three']!.complete();
        final outcomes = await Future.wait(results);

        expect(started, ['one', 'two', 'three']);
        expect(maxRunning, 1);
        expect(outcomes, everyElement(isA<RefreshFinished>()));
      },
    );

    test('a refresh that throws still releases the lock', () async {
      final id = await newPlaylist();
      // 第一次的頁含寫不進去的曲目，第二次的頁正常。
      await sql(
        'CREATE TRIGGER boom BEFORE INSERT ON playlist_entries '
        "WHEN NEW.track_key = 'fmp-test:boom' "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      env.plugin.onPage = (query) =>
          env.plugin.pageQueries.length == 1 ? page(['boom']) : page(['a']);
      final failing = env.refresher.refresh(id);
      final after = env.refresher.refresh(id);

      await expectLater(failing, throwsA(anything));
      expect(await after, isA<RefreshFinished>());
      expect(await ids(id), ['a']);
    });
  });
}
