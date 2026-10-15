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

      expect(result, isA<ImportMetadataOnly>());
      result as ImportMetadataOnly;
      expect(result.pluginId, 'meta');
      expect(result.playlistId, 'album-1');
      expect(await names(), isEmpty);
      expect(plugin.pageQueries, isEmpty);
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
}
