import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

import '../playback/fake_source_plugin.dart';
import 'fake_import_plugin.dart';
import 'library_harness.dart';

// 從網址匯入（ADR 0033 §決定 2、M4 design §5.1）：問哪個插件、三種回傳、第一頁成功才建列、
// 重新匯入同一張＝刷新那一列而不動本地設定。

PlaylistRef _id(String id) => PlaylistIdRef(id);

void main() {
  late LibraryEnv env;

  Future<void> start([List<SourcePlugin>? plugins]) async {
    env = await LibraryEnv.open(plugins: plugins);
    env.plugin.onUrl = (query) => _id(Uri.parse(query.url).pathSegments.last);
  }

  setUp(() => start());

  Future<List<String>> names() async => [
    for (final p in await env.repository.watchAll().first) p.name,
  ];

  Future<List<String>> ids(int id) async => [
    for (final e in await env.repository.entries(id)) e.track.sourceId,
  ];

  group('which plugin', () {
    test('asks the enabled importPlaylist plugins in order, first answer '
        'wins', () async {
      final second = FakeImportPlugin(id: 'second', onUrl: (_) => _id('x'));
      final third = FakeImportPlugin(id: 'third', onUrl: (_) => _id('y'));
      await start([FakeImportPlugin(), second, third]);
      env.plugin.onUrl = (_) => null;
      second.onPage = (_) => page(['a'], total: 1);

      final result = await env.importer.importUrl('https://fmp.test/x');

      expect(result, isA<ImportedPlaylist>());
      expect(env.plugin.urlQueries, hasLength(1));
      expect(second.urlQueries, hasLength(1));
      expect(third.urlQueries, isEmpty);
      final remote = await env.repository.findRemote('second', 'x');
      expect(remote, isNotNull);
    });

    test('a plugin without importPlaylist is not asked', () async {
      // 問到它的 playlistFromUrl 會拋 UnimplementedError。
      final plain = FakeSourcePlugin((_) => const [], id: 'plain');
      await start([plain, FakeImportPlugin()]);
      env.plugin.onPage = (_) => page(['a']);

      final result = await env.importer.importUrl('https://fmp.test/pl');

      expect(result, isA<ImportedPlaylist>());
      expect(env.plugin.urlQueries, hasLength(1));
    });

    test('an unrecognised url is reported and nothing is written', () async {
      env.plugin.onUrl = (_) => null;

      final result = await env.importer.importUrl('https://example.com/x');

      expect(result, isA<ImportUnrecognized>());
      expect(await names(), isEmpty);
    });

    test('a blank url asks nobody', () async {
      final result = await env.importer.importUrl('   ');

      expect(result, isA<ImportUnrecognized>());
      expect(env.plugin.urlQueries, isEmpty);
    });

    test('the url is trimmed', () async {
      env.plugin.onPage = (_) => page(['a']);

      await env.importer.importUrl('  https://fmp.test/pl-basic \n');

      expect(env.plugin.urlQueries.single.url, 'https://fmp.test/pl-basic');
    });

    test('a plugin that throws stops the search', () async {
      final second = FakeImportPlugin(id: 'second', onUrl: (_) => _id('x'));
      await start([FakeImportPlugin(), second]);
      env.plugin.onUrl = (_) => throw NetworkError();

      await expectLater(
        env.importer.importUrl('https://fmp.test/x'),
        throwsA(isA<NetworkError>()),
      );
      expect(second.urlQueries, isEmpty);
    });

    test('an error that is not an AppError is wrapped', () async {
      env.plugin.onUrl = (_) => throw StateError('boom');

      await expectLater(
        env.importer.importUrl('https://fmp.test/x'),
        throwsA(isA<UnexpectedError>()),
      );
    });
  });

  group('importPlaylistId', () {
    test('imports by plugin and playlist id, without asking the url', () async {
      env.plugin.onPage = (query) => page(['a', 'b'], title: 'Mine');

      final result = await env.importer.importPlaylistId('fmp-test', 'pl-1');

      result as ImportedPlaylist;
      expect(result.created, isTrue);
      expect(env.plugin.urlQueries, isEmpty);
      expect(env.plugin.pageQueries.single.playlistId, 'pl-1');
      final remote = (await env.repository.remote(result.playlistId))!;
      expect(remote.pluginId, 'fmp-test');
      expect(remote.remoteId, 'pl-1');
      expect(await names(), ['Mine']);
      expect(await ids(result.playlistId), ['a', 'b']);
    });

    test('an imported playlist is refreshed, not created twice', () async {
      env.plugin.onPage = (_) => page(['a'], title: 'Mine');
      await env.importer.importPlaylistId('fmp-test', 'pl-1');
      env.plugin.onPage = (_) => page(['a', 'b'], title: 'Renamed remotely');

      final again = await env.importer.importPlaylistId('fmp-test', 'pl-1');

      again as ImportedPlaylist;
      expect(again.created, isFalse);
      expect(await names(), hasLength(1));
      expect(await ids(again.playlistId), ['a', 'b']);
    });

    group('the writable hint', () {
      Future<bool> writableOf(Object result) async =>
          (await env.repository.remote(
            (result as ImportedPlaylist).playlistId,
          ))!.writable;

      test('is stored when the page does not say', () async {
        env.plugin.onPage = (_) => page(['a']);

        final result = await env.importer.importPlaylistId(
          'fmp-test',
          'pl-1',
          writable: true,
        );

        expect(await writableOf(result), isTrue);
      });

      test('without a hint the page decides', () async {
        env.plugin.onPage = (_) => page(['a'], writable: true);
        final withPage = await env.importer.importPlaylistId('fmp-test', 'p1');
        env.plugin.onPage = (_) => page(['a']);
        final without = await env.importer.importPlaylistId('fmp-test', 'p2');

        expect(await writableOf(withPage), isTrue);
        expect(await writableOf(without), isFalse);
      });

      test('also sets an existing row, and a later refresh keeps it', () async {
        env.plugin.onPage = (_) => page(['a']);
        final first = await env.importer.importPlaylistId('fmp-test', 'pl-1');
        expect(await writableOf(first), isFalse);

        final again = await env.importer.importPlaylistId(
          'fmp-test',
          'pl-1',
          writable: true,
        );
        expect(again, isA<ImportedPlaylist>());
        expect((again as ImportedPlaylist).created, isFalse);
        expect(await writableOf(again), isTrue);

        await env.refresher.refresh(again.playlistId);
        expect(await writableOf(again), isTrue);
      });
    });

    test('progress is reported per page', () async {
      env.plugin.onPage = (query) => query.cursor == null
          ? page(['a', 'b'], cursor: 'p2', total: 3)
          : page(['c'], total: 3);
      final counts = <int>[];

      await env.importer.importPlaylistId(
        'fmp-test',
        'pl-1',
        onProgress: counts.add,
      );

      expect(counts, isNotEmpty);
      expect(counts.last, 3);
    });

    test('a metadata-only source is handed back', () async {
      final plugin = FakeImportPlugin(id: 'meta', resolveStream: false);
      await start([plugin]);

      final result = await env.importer.importPlaylistId('meta', 'album-1');

      expect(result, isA<ImportForMatching>());
      expect(plugin.pageQueries, isEmpty);
    });

    test('an unknown plugin is Unsupported', () async {
      await expectLater(
        env.importer.importPlaylistId('nobody', 'pl-1'),
        throwsA(isA<Unsupported>()),
      );
      expect(await names(), isEmpty);
    });

    test('a disabled plugin is Unsupported', () async {
      await env.setPlugins(const []);

      await expectLater(
        env.importer.importPlaylistId('fmp-test', 'pl-1'),
        throwsA(isA<Unsupported>()),
      );
      expect(env.plugin.pageQueries, isEmpty);
    });

    test('a plugin without importPlaylist is Unsupported', () async {
      final plain = FakeSourcePlugin((_) => const [], id: 'plain');
      env = await LibraryEnv.open(plugins: [plain]);

      await expectLater(
        env.importer.importPlaylistId('plain', 'pl-1'),
        throwsA(isA<Unsupported>()),
      );
    });

    test('a failing first page creates nothing and keeps the error', () async {
      env.plugin.onPage = (_) => throw AuthRequired();

      await expectLater(
        env.importer.importPlaylistId('fmp-test', 'pl-auth'),
        throwsA(isA<AuthRequired>()),
      );
      expect(await names(), isEmpty);
    });

    test('an error that is not an AppError is wrapped', () async {
      env.plugin.onPage = (_) => throw StateError('boom');

      await expectLater(
        env.importer.importPlaylistId('fmp-test', 'pl-1'),
        throwsA(isA<UnexpectedError>()),
      );
    });
  });

  group('what the url is', () {
    test('a mix seed is handed back and nothing is written', () async {
      final plugin = FakeImportPlugin(mix: true);
      await start([plugin]);
      plugin.onUrl = (_) =>
          PlaylistMixSeedRef(MixSeedQuery(sourceId: 'seed-1'));

      final result = await env.importer.importUrl(
        'https://fmp.test/mix/seed-1',
      );

      expect(result, isA<ImportMixSeed>());
      result as ImportMixSeed;
      expect(result.pluginId, 'fmp-test');
      expect(result.seed.sourceId, 'seed-1');
      expect(await names(), isEmpty);
      expect(plugin.pageQueries, isEmpty);
    });

    test('a metadata-only source is handed back without fetching', () async {
      final plugin = FakeImportPlugin(id: 'meta', resolveStream: false);
      await start([plugin]);
      plugin.onUrl = (_) => _id('album-1');

      final result = await env.importer.importUrl('https://fmp.test/album-1');

      expect(result, isA<ImportForMatching>());
      result as ImportForMatching;
      expect(result.pluginId, 'meta');
      expect(result.playlistId, 'album-1');
      expect(await names(), isEmpty);
      expect(plugin.pageQueries, isEmpty);
    });
  });

  // 對話框先辨識（「配對到其他音源」只給能播的插件的歌單，§17 第 19 條），再以同一個結果匯入。
  group('recognising first', () {
    test('says which plugin, what it found and whether it plays, without '
        'fetching or writing', () async {
      final meta = FakeImportPlugin(id: 'meta', resolveStream: false);
      final video = FakeImportPlugin();
      await start([meta, video]);
      meta.onUrl = (query) => query.url.contains('album') ? _id('a1') : null;
      video.onUrl = (query) => query.url.contains('mix')
          ? PlaylistMixSeedRef(MixSeedQuery(sourceId: 'seed'))
          : _id('p1');

      final playable = (await env.importer.recognize(' https://x/list '))!;
      final metadata = (await env.importer.recognize('https://x/album'))!;
      final mix = (await env.importer.recognize('https://x/mix'))!;

      expect(playable.pluginId, 'fmp-test');
      expect((playable.ref as PlaylistIdRef).playlistId, 'p1');
      expect(playable.canPair, isTrue);
      expect(metadata.pluginId, 'meta');
      expect(metadata.canPair, isFalse, reason: 'it cannot play');
      expect(mix.canPair, isFalse, reason: 'a mix seed is not a playlist');
      expect(await env.importer.recognize('  '), isNull);
      expect(video.urlQueries.first.url, 'https://x/list');
      expect(video.pageQueries, isEmpty);
      expect(meta.pageQueries, isEmpty);
      expect(await names(), isEmpty);
    });

    test('importing what was recognised does not ask the plugins '
        'again', () async {
      env.plugin.onPage = (_) => page(['a'], total: 1);
      final recognized = (await env.importer.recognize('https://fmp.test/p'))!;
      env.plugin.urlQueries.clear();

      final result = await env.importer.importRecognized(recognized);

      expect(result, isA<ImportedPlaylist>());
      expect(env.plugin.urlQueries, isEmpty);
      expect(await names(), ['Remote title']);
    });

    test('a plugin that left the list since is Unsupported', () async {
      final recognized = (await env.importer.recognize('https://fmp.test/p'))!;
      await env.setPlugins(const []);

      await expectLater(
        env.importer.importRecognized(recognized),
        throwsA(isA<Unsupported>()),
      );
    });
  });

  group('a new playlist', () {
    test(
      'is created from the first page and filled by the refresher',
      () async {
        env.plugin.onPage = (query) => switch (query.cursor) {
          null => page(
            ['a', 'b'],
            title: 'Remote title',
            description: 'About',
            writable: true,
            cursor: 'p2',
            total: 3,
          ),
          _ => page(
            ['c'],
            title: 'Remote title',
            description: 'About',
            total: 3,
          ),
        };

        final result = await env.importer.importUrl(
          'https://fmp.test/pl-basic',
        );

        result as ImportedPlaylist;
        expect(result.created, isTrue);
        expect(result.refresh, isA<RefreshFinished>());
        final playlist = (await env.repository.watchAll().first).single;
        expect(playlist.id, result.playlistId);
        expect(playlist.kind, PlaylistKind.imported);
        expect(playlist.name, 'Remote title');
        expect(playlist.description, 'About');
        final remote = (await env.repository.remote(playlist.id))!;
        expect(remote.pluginId, 'fmp-test');
        expect(remote.remoteId, 'pl-basic');
        expect(remote.refreshIntervalHours, 24);
        expect(remote.writable, isTrue);
        expect(remote.ownerName, 'Owner');
        expect(remote.lastResult, PlaylistRefreshResult.complete);
        expect(remote.refreshGeneration, 1);
        expect(await ids(playlist.id), ['a', 'b', 'c']);
        // 第一頁只取一次，之後的頁從 cursor 接。
        expect(
          [for (final q in env.plugin.pageQueries) q.cursor],
          [null, 'p2'],
        );
      },
    );

    test('a failing first page creates nothing', () async {
      env.plugin.onPage = (_) => throw NotFound();

      await expectLater(
        env.importer.importUrl('https://fmp.test/pl-gone'),
        throwsA(isA<NotFound>()),
      );

      expect(await names(), isEmpty);
    });

    test(
      'an error on the first page that is not an AppError is wrapped',
      () async {
        env.plugin.onPage = (_) => throw StateError('boom');

        await expectLater(
          env.importer.importUrl('https://fmp.test/pl'),
          throwsA(isA<UnexpectedError>()),
        );
        expect(await names(), isEmpty);
      },
    );

    test('a failing later page leaves the playlist with the first page, '
        'partial', () async {
      env.plugin.onPage = (query) => query.cursor == null
          ? page(['a', 'b'], cursor: 'p2', total: 4)
          : throw NetworkError();

      final result = await env.importer.importUrl(
        'https://fmp.test/pl-partial',
      );

      result as ImportedPlaylist;
      expect(result.created, isTrue);
      expect(
        (result.refresh as RefreshFinished).result,
        PlaylistRefreshResult.partial,
      );
      expect(await ids(result.playlistId), ['a', 'b']);
      expect(
        (await env.repository.remote(result.playlistId))!.lastResult,
        PlaylistRefreshResult.partial,
      );
    });

    test('names are not unique and are never renamed', () async {
      env.plugin.onPage = (_) => page(['a'], title: 'Same title');

      await env.importer.importUrl('https://fmp.test/one');
      await env.importer.importUrl('https://fmp.test/two');

      expect(await names(), ['Same title', 'Same title']);
    });

    test('the same url twice at once makes one playlist', () async {
      // 兩次匯入都先取到第一頁，才有一邊去建列：另一邊撞到已建好的列，改成刷新它，
      // 且照用自己取到的第一頁、不再取一次。
      final bothFetched = Completer<void>();
      env.plugin.onPage = (_) async {
        if (env.plugin.pageQueries.length == 2) bothFetched.complete();
        await bothFetched.future;
        return page(['a']);
      };

      final results = await Future.wait([
        env.importer.importUrl('https://fmp.test/pl'),
        env.importer.importUrl('https://fmp.test/pl'),
      ]);

      expect(await names(), hasLength(1));
      expect(
        results.whereType<ImportedPlaylist>().where((r) => r.created),
        hasLength(1),
      );
      expect(
        (results[0] as ImportedPlaylist).playlistId,
        (results[1] as ImportedPlaylist).playlistId,
      );
      expect(env.plugin.pageQueries, hasLength(2));
      expect(await ids((results[0] as ImportedPlaylist).playlistId), ['a']);
    });
  });

  group('progress', () {
    test(
      'reports the songs read after every page, for a new playlist',
      () async {
        env.plugin.onPage = (query) => switch (query.cursor) {
          null => page(['a', 'b'], cursor: 'c2'),
          'c2' => page(['c'], cursor: 'c3'),
          _ => page(['d', 'e']),
        };
        final counts = <int>[];

        await env.importer.importUrl(
          'https://fmp.test/pl',
          onProgress: counts.add,
        );

        expect(counts, [2, 3, 5]);
      },
    );

    test('also reports when the playlist is imported again', () async {
      env.plugin.onPage = (_) => page(['a', 'b']);
      await env.importer.importUrl('https://fmp.test/pl');
      final counts = <int>[];

      await env.importer.importUrl(
        'https://fmp.test/pl',
        onProgress: counts.add,
      );

      expect(counts, [2]);
    });

    test('a first page that fails reports nothing', () async {
      env.plugin.onPage = (_) => throw NetworkError();
      final counts = <int>[];

      await expectLater(
        env.importer.importUrl('https://fmp.test/pl', onProgress: counts.add),
        throwsA(isA<NetworkError>()),
      );

      expect(counts, isEmpty);
    });
  });

  group('an imported playlist again', () {
    test('refreshes that row and leaves the local settings alone', () async {
      env.plugin.onPage = (_) => page(['a', 'b'], title: 'Remote title');
      final first = await env.importer.importUrl(
        'https://fmp.test/pl',
      ) as ImportedPlaylist;
      // 使用者改過名稱、間隔與順序。
      await env.database.customStatement(
        "UPDATE playlists SET name = 'Mine', sort_order = 7 "
        'WHERE id = ${first.playlistId}',
      );
      await env.database.customStatement(
        'UPDATE playlist_remote SET name_overridden = 1, '
        'refresh_interval_hours = 6 WHERE playlist_id = ${first.playlistId}',
      );
      env.plugin.onPage = (_) => page(['b', 'c'], title: 'New remote title');

      final again = await env.importer.importUrl(
        'https://fmp.test/pl',
      ) as ImportedPlaylist;

      expect(again.created, isFalse);
      expect(again.playlistId, first.playlistId);
      expect(again.refresh, isA<RefreshFinished>());
      final playlists = await env.repository.watchAll().first;
      expect(playlists, hasLength(1));
      expect(playlists.single.name, 'Mine');
      expect(playlists.single.sortOrder, 7);
      final remote = (await env.repository.remote(first.playlistId))!;
      expect(remote.refreshIntervalHours, 6);
      expect(remote.nameOverridden, isTrue);
      expect(remote.refreshGeneration, 2);
      expect(await ids(first.playlistId), ['b', 'c']);
    });

    test('a re-import whose remote is gone records it on that row', () async {
      env.plugin.onPage = (_) => page(['a', 'b']);
      final first = await env.importer.importUrl(
        'https://fmp.test/pl',
      ) as ImportedPlaylist;
      env.plugin.onPage = (_) => throw NotFound();

      final again = await env.importer.importUrl(
        'https://fmp.test/pl',
      ) as ImportedPlaylist;

      expect(again.playlistId, first.playlistId);
      expect((again.refresh as RefreshFailed).error, isA<NotFound>());
      expect(
        (await env.repository.remote(first.playlistId))!.status,
        PlaylistRemoteStatus.sourceGone,
      );
      expect(await ids(first.playlistId), ['a', 'b']);
    });

    test(
      'a different url for the same remote playlist is the same row',
      () async {
        env.plugin.onUrl = (_) => _id('pl');
        env.plugin.onPage = (_) => page(['a']);

        await env.importer.importUrl('https://fmp.test/long/pl');
        final again = await env.importer.importUrl(
          'https://fmp.test/short',
        ) as ImportedPlaylist;

        expect(again.created, isFalse);
        expect(await names(), hasLength(1));
      },
    );

    test(
      'the same remote id under another plugin is another playlist',
      () async {
        final other = FakeImportPlugin(id: 'other', onUrl: (_) => _id('pl'));
        await start([FakeImportPlugin(), other]);
        env.plugin.onUrl = (_) => _id('pl');
        env.plugin.onPage = (_) => page(['a']);
        other.onPage = (_) => page(['b']);

        await env.importer.importUrl('https://fmp.test/pl');
        await env.setPlugins([other]);
        await env.importer.importUrl('https://fmp.test/pl');

        expect(await names(), hasLength(2));
      },
    );
  });

  group('a mix playlist', () {
    ImportMixSeed seed({int? cid}) => ImportMixSeed(
      pluginId: 'fmp-test',
      seed: MixSeedQuery(sourceId: 'seed-1', cid: cid),
    );

    MixBatch batch(String title) => MixBatch(
      mixId: 'm1',
      title: title,
      tracks: const [
        TrackSummary(sourceTypeId: 'fmp-test', sourceId: 'x', title: 'x'),
      ],
    );

    Future<void> startMixPlugin() async {
      final plugin = FakeImportPlugin(mix: true);
      await start([plugin]);
      plugin.onMix = (_) => batch('Radio of seed');
    }

    test('calls mix once and stores the title and the seed', () async {
      await startMixPlugin();

      final created = await env.importer.createMix(seed(cid: 7));

      expect(env.plugin.mixQueries, hasLength(1));
      final query = env.plugin.mixQueries.single as MixSeedQuery;
      expect(query.sourceId, 'seed-1');
      final playlist = (await env.repository.find(created.playlistId))!;
      expect(playlist.kind, PlaylistKind.mix);
      expect(playlist.name, 'Radio of seed');
      expect(playlist.mixPluginId, 'fmp-test');
      expect(playlist.mixSeedSourceId, 'seed-1');
      expect(playlist.mixSeedCid, 7);
      expect(await ids(created.playlistId), isEmpty);
      expect(await env.repository.remote(created.playlistId), isNull);
    });

    test('a seed without a cid stores no cid', () async {
      await startMixPlugin();

      final created = await env.importer.createMix(seed());

      expect(
        (await env.repository.find(created.playlistId))!.mixSeedCid,
        isNull,
      );
    });

    test('the same seed again is a new playlist', () async {
      await startMixPlugin();

      final first = await env.importer.createMix(seed());
      final second = await env.importer.createMix(seed());

      expect(second.playlistId, isNot(first.playlistId));
      expect(await names(), ['Radio of seed', 'Radio of seed']);
    });

    test('a mix failure is thrown and nothing is created', () async {
      await startMixPlugin();
      env.plugin.onMix = (_) => throw NotFound(pluginId: 'fmp-test');

      await expectLater(
        env.importer.createMix(seed()),
        throwsA(isA<NotFound>()),
      );

      expect(await names(), isEmpty);
    });

    test('a mix with no track is NotFound and creates nothing', () async {
      await startMixPlugin();
      env.plugin.onMix = (_) =>
          const MixBatch(mixId: 'm1', title: 'Empty', tracks: []);

      await expectLater(
        env.importer.createMix(seed()),
        throwsA(isA<NotFound>()),
      );

      expect(await names(), isEmpty);
    });

    test('a plugin that is gone or has no mix creates nothing', () async {
      await start([FakeImportPlugin()]);

      await expectLater(
        env.importer.createMix(seed()),
        throwsA(isA<Unsupported>()),
      );
      expect(env.plugin.mixQueries, isEmpty);
      expect(await names(), isEmpty);
    });
  });
}
