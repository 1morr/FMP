import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/library/remote_playlist_writer.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../support/pump_until.dart';
import 'fake_import_plugin.dart';
import 'library_harness.dart';

// 遠端寫入（ADR 0019 §決定 4、ADR 0032 §決定 4，M4 design §7.1、§7.2、§13）：每張目標一次
// `addToPlaylist`、單張失敗不影響其他張、成功的目標若已匯入就排一次刷新（走刷新器的鎖）、
// 移除只刪 `removed`／`notPresent` 的本地項目、log 不放名稱。入口條件與畫面在 test/ui/library/。

TrackInfo _track(String id, {int? cid, String title = 'Secret song title'}) =>
    TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, cid: cid, title: title);

AddToPlaylistResponse _addResults(List<LibraryWriteStatus> statuses) =>
    AddToPlaylistResponse(
      results: [
        for (final status in statuses) LibraryWriteResult(status: status),
      ],
    );

const _added = LibraryWriteStatus.added;
const _present = LibraryWriteStatus.alreadyPresent;
const _failed = LibraryWriteStatus.failed;
const _removed = LibraryWriteStatus.removed;
const _notPresent = LibraryWriteStatus.notPresent;

/// 假的計時器：只記著，`advance` 把時間往前撥、到期的才觸發（不真的等）。
final class _FakeTimers {
  var _now = Duration.zero;
  final _timers = <_FakeTimer>[];

  Timer create(Duration delay, void Function() fire) {
    final timer = _FakeTimer(_now + delay, fire);
    _timers.add(timer);
    return timer;
  }

  /// 還沒觸發也沒取消的計時器數。
  int get pending => _timers.where((t) => t.active).length;

  void advance(Duration by) {
    _now += by;
    for (final timer in [..._timers]) {
      if (timer.active && timer.due <= _now) timer.trigger();
    }
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.due, this._fire);

  final Duration due;
  final void Function() _fire;
  var _done = false;

  @override
  bool get isActive => !_done;
  bool get active => !_done;

  void trigger() {
    _done = true;
    _fire();
  }

  @override
  void cancel() => _done = true;

  @override
  int get tick => 0;
}

void main() {
  late LibraryEnv env;
  late _FakeTimers timers;

  setUp(() async {
    timers = _FakeTimers();
    env = await LibraryEnv.open(
      plugins: [FakeImportPlugin(libraryWrite: true)],
      minimumLevel: LogLevel.debug,
      overrides: [remoteRefreshTimerProvider.overrideWithValue(timers.create)],
    );
    // 刷新讀到的頁：每次一首 `fresh`，看得出刷新有沒有發生。
    env.plugin.onPage = (query) => page(['fresh-${query.playlistId}']);
  });

  RemotePlaylistWriter writer() =>
      env.container.read(remotePlaylistWriterProvider);

  Future<int> imported(String remoteId, {bool writable = true}) async {
    final id = (await env.repository.createImported(
      pluginId: 'fmp-test',
      remoteId: remoteId,
      info: RemotePlaylistInfo(name: 'Private name $remoteId'),
    ))!;
    await env.repository.setWritable(id, writable: writable);
    return id;
  }

  Future<List<String>> ids(int id) async => [
    for (final e in await env.repository.entries(id)) e.track.sourceId,
  ];

  /// 寫入後的刷新延後 [remoteRefreshDelay]：撥過延遲，再等到刷新器讀過 [playlistId]。
  Future<void> refreshed(String playlistId) {
    timers.advance(remoteRefreshDelay);
    return pumpUntil(
      () => env.plugin.pageQueries.any((q) => q.playlistId == playlistId),
      reason: 'no refresh of $playlistId',
    );
  }

  group('createRemote', () {
    test('sends the trimmed title and returns the id', () async {
      env.plugin.onCreatePlaylist = (query) =>
          const CreatePlaylistResult(playlistId: 'new-1');

      final id = await writer().createRemote('fmp-test', '  Mine  ');

      expect(id, 'new-1');
      expect(env.plugin.createQueries.single.title, 'Mine');
    });

    test('a blank title never reaches the plugin', () async {
      await expectLater(
        writer().createRemote('fmp-test', '   '),
        throwsArgumentError,
      );
      expect(env.plugin.createQueries, isEmpty);
    });

    test('a plugin without libraryWrite is Unsupported', () async {
      final plain = await LibraryEnv.open();

      await expectLater(
        plain.container
            .read(remotePlaylistWriterProvider)
            .createRemote('fmp-test', 'Mine'),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('addToRemote', () {
    test('one addToPlaylist per playlist, with sourceId and cid', () async {
      env.plugin.onAddToPlaylist = (query) =>
          _addResults([for (final _ in query.tracks) _added]);

      final outcomes = await writer().addToRemote(
        'fmp-test',
        [_track('a'), _track('b', cid: 7)],
        ['p1', 'p2'],
      );

      expect(
        [for (final q in env.plugin.addQueries) q.playlistId],
        ['p1', 'p2'],
      );
      expect(env.plugin.addQueries.first.toJson()['tracks'], [
        {'sourceId': 'a'},
        {'sourceId': 'b', 'cid': 7},
      ]);
      expect(
        [for (final o in outcomes) (o.playlistId, o.added)],
        [('p1', 2), ('p2', 2)],
      );
    });

    test('counts added, alreadyPresent and failed per playlist', () async {
      final error = RateLimited(pluginId: 'fmp-test');
      env.plugin.onAddToPlaylist = (query) => AddToPlaylistResponse(
        results: [
          const LibraryWriteResult(status: _added),
          const LibraryWriteResult(status: _present),
          const LibraryWriteResult(status: _present),
          LibraryWriteResult(status: _failed, error: error),
        ],
      );

      final outcome = (await writer().addToRemote(
        'fmp-test',
        [_track('a'), _track('b'), _track('c'), _track('d')],
        ['p1'],
      )).single;

      expect(outcome.added, 1);
      expect(outcome.alreadyPresent, 2);
      expect(outcome.failed, 1);
      expect(outcome.error, same(error));
      expect(outcome.succeeded, isTrue);
    });

    test('a playlist that fails as a whole does not stop the others', () async {
      env.plugin.onAddToPlaylist = (query) => query.playlistId == 'p1'
          ? throw NetworkError(pluginId: 'fmp-test')
          : _addResults([_added]);

      final outcomes = await writer().addToRemote(
        'fmp-test',
        [_track('a')],
        ['p1', 'p2'],
      );

      expect(outcomes.first.error, isA<NetworkError>());
      expect(outcomes.first.failed, 1);
      expect(outcomes.first.succeeded, isFalse);
      expect(outcomes.last.added, 1);
      expect(outcomes.last.error, isNull);
    });

    test('a song selected twice is sent once', () async {
      env.plugin.onAddToPlaylist = (query) =>
          _addResults([for (final _ in query.tracks) _added]);

      final outcome = (await writer().addToRemote(
        'fmp-test',
        [_track('a'), _track('b'), _track('a'), _track('a', cid: 2)],
        ['p1'],
      )).single;

      expect(env.plugin.addQueries.single.toJson()['tracks'], [
        {'sourceId': 'a'},
        {'sourceId': 'b'},
        {'sourceId': 'a', 'cid': 2},
      ]);
      expect(outcome.added, 3);
    });

    // 錯的目標：別的音源的曲目不能送進這個插件的歌單（對照是上面同插件的照送）。
    test('a track of another plugin sends nothing', () async {
      env.plugin.onAddToPlaylist = (query) => _addResults([_added, _added]);

      await expectLater(
        writer().addToRemote(
          'fmp-test',
          [
            _track('a'),
            const TrackInfo(sourceTypeId: 'other', sourceId: 'b', title: 'B'),
          ],
          ['p1'],
        ),
        throwsArgumentError,
      );
      expect(env.plugin.addQueries, isEmpty);
    });

    test('a failure that is not an AppError is wrapped', () async {
      env.plugin.onAddToPlaylist = (query) => throw StateError('boom');

      final outcome = (await writer().addToRemote(
        'fmp-test',
        [_track('a')],
        ['p1'],
      )).single;

      expect(outcome.error, isA<AppError>());
    });
  });

  group('the refresh after a write', () {
    test('an imported target is refreshed once; a target that is not '
        'imported is not', () async {
      final local = await imported('p1');
      env.plugin.onAddToPlaylist = (query) => _addResults([_added]);

      await writer().addToRemote(
        'fmp-test',
        [_track('a')],
        ['p1', 'not-imported'],
      );
      await refreshed('p1');
      await settle();

      expect(env.plugin.pageQueries.map((q) => q.playlistId), ['p1']);
      expect(await ids(local), ['fresh-p1']);
    });

    // YouTube 寫後讀有延遲（約 40 秒）：刷新延後 60 秒。拿掉延遲，第一個 expect 就紅。
    group('the delay', () {
      test(
        'nothing is read before 60 seconds, then exactly one refresh',
        () async {
          await imported('p1');
          env.plugin.onAddToPlaylist = (query) => _addResults([_added]);

          await writer().addToRemote('fmp-test', [_track('a')], ['p1']);
          await settle();
          expect(env.plugin.pageQueries, isEmpty);
          timers.advance(const Duration(seconds: 59));
          await settle();
          expect(env.plugin.pageQueries, isEmpty);

          timers.advance(const Duration(seconds: 1));
          await pumpUntil(() => env.plugin.pageQueries.isNotEmpty);
          await settle();
          expect(env.plugin.pageQueries.map((q) => q.playlistId), ['p1']);
        },
      );

      test(
        'a removal is delayed too, and the local delete is immediate',
        () async {
          final id = await imported('p1');
          env.plugin.onPage = (query) =>
              page(['a', 'b'], remoteIds: ['ra', 'rb']);
          await env.refresher.refresh(id);
          env.plugin.pageQueries.clear();
          final entries = await env.repository.entries(id);
          env.plugin.onRemoveFromPlaylist = (query) =>
              RemoveFromPlaylistResponse(
                results: [const LibraryWriteResult(status: _removed)],
              );

          await writer().removeFromRemote(id, [entries.first]);

          expect(await ids(id), ['b']);
          timers.advance(const Duration(seconds: 59));
          await settle();
          expect(env.plugin.pageQueries, isEmpty);
          timers.advance(const Duration(seconds: 1));
          await pumpUntil(() => env.plugin.pageQueries.isNotEmpty);
        },
      );

      test(
        'a second write in the delay restarts it and refreshes once',
        () async {
          await imported('p1');
          env.plugin.onAddToPlaylist = (query) => _addResults([_added]);

          await writer().addToRemote('fmp-test', [_track('a')], ['p1']);
          timers.advance(const Duration(seconds: 40));
          await writer().addToRemote('fmp-test', [_track('b')], ['p1']);
          expect(timers.pending, 1);

          // 第一次寫入起算已 99 秒，但計時從最後一次寫入重來。
          timers.advance(const Duration(seconds: 59));
          await settle();
          expect(env.plugin.pageQueries, isEmpty);
          timers.advance(const Duration(seconds: 1));
          await pumpUntil(() => env.plugin.pageQueries.isNotEmpty);
          await settle();
          expect(env.plugin.pageQueries, hasLength(1));
        },
      );

      test('writes to two playlists keep one timer each', () async {
        await imported('p1');
        await imported('p2');
        env.plugin.onAddToPlaylist = (query) => _addResults([_added]);

        await writer().addToRemote('fmp-test', [_track('a')], ['p1', 'p2']);

        expect(timers.pending, 2);
      });

      test('disposing the provider cancels the pending refresh', () async {
        await imported('p1');
        env.plugin.onAddToPlaylist = (query) => _addResults([_added]);
        await writer().addToRemote('fmp-test', [_track('a')], ['p1']);
        expect(timers.pending, 1);

        env.container.invalidate(remotePlaylistWriterProvider);
        await settle();

        expect(timers.pending, 0);
        timers.advance(remoteRefreshDelay);
        await settle();
        expect(env.plugin.pageQueries, isEmpty);
      });
    });

    test('alreadyPresent counts as a success', () async {
      await imported('p1');
      env.plugin.onAddToPlaylist = (query) => _addResults([_present]);

      await writer().addToRemote('fmp-test', [_track('a')], ['p1']);
      await refreshed('p1');
    });

    // 變異：同一個匯入的目標，全部失敗就不刷新。
    test('a target where everything failed is not refreshed', () async {
      await imported('p1');
      env.plugin.onAddToPlaylist = (query) => _addResults([_failed]);

      await writer().addToRemote('fmp-test', [_track('a')], ['p1']);
      timers.advance(remoteRefreshDelay);
      await settle();

      expect(env.plugin.pageQueries, isEmpty);
    });

    test('a playlist of another plugin with the same remote id is not '
        'touched', () async {
      final other = await env.repository.createImported(
        pluginId: 'other-plugin',
        remoteId: 'p1',
        info: const RemotePlaylistInfo(name: 'Other'),
      );
      env.plugin.onAddToPlaylist = (query) => _addResults([_added]);

      await writer().addToRemote('fmp-test', [_track('a')], ['p1']);
      timers.advance(remoteRefreshDelay);
      await settle();

      expect(other, isNotNull);
      expect(env.plugin.pageQueries, isEmpty);
    });

    test('it waits behind a refresh that is running, through the same '
        'lock', () async {
      final busy = await imported('busy');
      await imported('p1');
      final gate = Completer<void>();
      env.plugin.onPage = (query) async {
        if (query.playlistId == 'busy') await gate.future;
        return page(['fresh-${query.playlistId}']);
      };
      env.plugin.onAddToPlaylist = (query) => _addResults([_added]);
      final manual = env.refresher.refresh(busy);
      await refreshed('busy');

      await writer().addToRemote('fmp-test', [_track('a')], ['p1']);
      timers.advance(remoteRefreshDelay);
      await settle();

      // 手動刷新還沒結束：寫入後的刷新排在它後面，沒有並行。
      expect(env.plugin.pageQueries.map((q) => q.playlistId), ['busy']);

      gate.complete();
      await manual;
      await refreshed('p1');
      expect(env.plugin.pageQueries.map((q) => q.playlistId), ['busy', 'p1']);
    });

    test(
      'a refresh that throws is reported, not thrown to the caller',
      () async {
        final local = await imported('p1');
        await env.database.customStatement(
          'CREATE TRIGGER boom BEFORE INSERT ON playlist_entries '
          "WHEN NEW.track_key = 'fmp-test:fresh-p1' "
          "BEGIN SELECT RAISE(ABORT, 'boom'); END",
        );
        env.plugin.onAddToPlaylist = (query) => _addResults([_added]);

        final outcomes = await writer().addToRemote(
          'fmp-test',
          [_track('a')],
          ['p1'],
        );
        await refreshed('p1');
        await settle();

        expect(outcomes.single.succeeded, isTrue);
        expect(await ids(local), isEmpty);
        expect(
          env.log.history.map((r) => r.message),
          contains('Failed to refresh a playlist after a remote write'),
        );
      },
    );
  });

  group('removeFromRemote', () {
    Future<(int, List<PlaylistEntry>)> seeded() async {
      final id = await imported('p1');
      env.plugin.onPage = (query) =>
          page(['a', 'b', 'c', 'd'], remoteIds: ['ra', 'rb', 'rc', 'rd']);
      await env.refresher.refresh(id);
      env.plugin.pageQueries.clear();
      return (id, await env.repository.entries(id));
    }

    test('sends sourceId, cid and remoteItemId of the local entries', () async {
      final (id, entries) = await seeded();
      env.plugin.onRemoveFromPlaylist = (query) => RemoveFromPlaylistResponse(
        results: [
          for (final _ in query.items)
            const LibraryWriteResult(status: _removed),
        ],
      );

      await writer().removeFromRemote(id, entries.take(2).toList());
      await refreshed('p1');
      await settle();

      final query = env.plugin.removeQueries.single;
      expect(query.playlistId, 'p1');
      expect(query.toJson()['items'], [
        {'sourceId': 'a', 'remoteItemId': 'ra'},
        {'sourceId': 'b', 'remoteItemId': 'rb'},
      ]);
    });

    test('deletes removed and notPresent entries locally and keeps the '
        'failed ones, which it returns', () async {
      final (id, entries) = await seeded();
      final error = NetworkError(pluginId: 'fmp-test');
      env.plugin.onRemoveFromPlaylist = (query) => RemoveFromPlaylistResponse(
        results: [
          const LibraryWriteResult(status: _removed),
          const LibraryWriteResult(status: _notPresent),
          LibraryWriteResult(status: _failed, error: error),
        ],
      );

      // 後面的刷新卡在這裡，所以下面讀到的是移除本身的結果，不是刷新的。
      final gate = Completer<void>();
      env.plugin.onPage = (query) async {
        await gate.future;
        return page(['c', 'd'], remoteIds: ['rc', 'rd']);
      };

      final outcome = await writer().removeFromRemote(
        id,
        entries.take(3).toList(),
      );

      expect(outcome.removed, 1);
      expect(outcome.notPresent, 1);
      expect(outcome.failures.single.entry.track.sourceId, 'c');
      expect(outcome.failures.single.error, same(error));
      expect(await ids(id), ['c', 'd']);
      gate.complete();
      await refreshed('p1');
      await settle();
    });

    test(
      'refreshes once in the background after something was removed',
      () async {
        final (id, entries) = await seeded();
        env.plugin.onRemoveFromPlaylist = (query) => RemoveFromPlaylistResponse(
          results: [const LibraryWriteResult(status: _removed)],
        );
        // 遠端現在只剩 b、c、d。
        env.plugin.onPage = (query) =>
            page(['b', 'c', 'd'], remoteIds: ['rb', 'rc', 'rd']);

        await writer().removeFromRemote(id, [entries.first]);
        await refreshed('p1');
        await settle();

        expect(env.plugin.pageQueries, hasLength(1));
        expect(await ids(id), ['b', 'c', 'd']);
      },
    );

    // 變異：全部失敗就沒有東西變動，不刷新。
    test('does not refresh when everything failed', () async {
      final (id, entries) = await seeded();
      env.plugin.onRemoveFromPlaylist = (query) => RemoveFromPlaylistResponse(
        results: [const LibraryWriteResult(status: _failed)],
      );

      final outcome = await writer().removeFromRemote(id, [entries.first]);
      timers.advance(remoteRefreshDelay);
      await settle();

      expect(outcome.failures, hasLength(1));
      expect(env.plugin.pageQueries, isEmpty);
      expect(await ids(id), ['a', 'b', 'c', 'd']);
    });

    test('a failed call throws and leaves the local playlist alone', () async {
      final (id, entries) = await seeded();
      env.plugin.onRemoveFromPlaylist = (query) =>
          throw AuthRequired(pluginId: 'fmp-test');

      await expectLater(
        writer().removeFromRemote(id, [entries.first]),
        throwsA(isA<AuthRequired>()),
      );
      timers.advance(remoteRefreshDelay);
      await settle();

      expect(await ids(id), ['a', 'b', 'c', 'd']);
      expect(env.plugin.pageQueries, isEmpty);
    });

    // 錯的目標：入口開著時歌單變成不可寫、項目不是這張歌單的插件的，都不呼叫插件（對照是上面的照送）。
    test('a playlist that is no longer writable sends nothing', () async {
      final (id, entries) = await seeded();
      await env.repository.setWritable(id, writable: false);

      await expectLater(
        writer().removeFromRemote(id, [entries.first]),
        throwsA(isA<Unsupported>()),
      );
      expect(env.plugin.removeQueries, isEmpty);
      expect(await ids(id), ['a', 'b', 'c', 'd']);
    });

    test('an entry of another plugin sends nothing', () async {
      final (id, entries) = await seeded();
      final stranger = PlaylistEntry(
        id: entries.first.id,
        position: 0,
        track: const TrackInfo(
          sourceTypeId: 'other',
          sourceId: 'a',
          title: 'A',
        ),
      );

      await expectLater(
        writer().removeFromRemote(id, [entries[1], stranger]),
        throwsArgumentError,
      );
      expect(env.plugin.removeQueries, isEmpty);
      expect(await ids(id), ['a', 'b', 'c', 'd']);
    });

    test('a local playlist is not an imported one', () async {
      final local = await env.repository.create(name: 'Local');

      await expectLater(
        writer().removeFromRemote(local, const []),
        throwsStateError,
      );
    });
  });

  group('the log', () {
    test('has plugin id, local playlist id and counts, and never names or '
        'titles', () async {
      final local = await imported('p1');
      env.plugin.onPage = (query) =>
          page(['a'], remoteIds: ['ra'], title: 'Secret remote title');
      await env.refresher.refresh(local);
      final entries = await env.repository.entries(local);
      env.plugin.onAddToPlaylist = (query) => _addResults([_added]);
      env.plugin.onRemoveFromPlaylist = (query) => RemoveFromPlaylistResponse(
        results: [const LibraryWriteResult(status: _removed)],
      );
      env.plugin.onCreatePlaylist = (query) =>
          const CreatePlaylistResult(playlistId: 'n');

      await writer().createRemote('fmp-test', 'Secret new name');
      await writer().addToRemote('fmp-test', [_track('x')], ['p1']);
      await writer().removeFromRemote(local, entries);
      await settle();

      final records = [
        for (final record in env.log.history)
          if (record.tag == 'library') record,
      ];
      final text = records.map((r) => r.toJsonLine()).join('\n');
      expect(text, contains('Remote add finished'));
      expect(text, contains('Remote remove finished'));
      expect(text, contains('Remote playlist created'));
      for (final secret in [
        'Secret song title',
        'Secret new name',
        'Private name',
        'Secret remote title',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      final removed = records.firstWhere(
        (r) => r.message == 'Remote remove finished',
      );
      expect(removed.toJsonLine(), contains('"playlistId":$local'));
    });
  });
}
