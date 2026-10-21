import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/library/external_import.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:yaml/yaml.dart';

import '../library/library_harness.dart';
import '../support/pump_until.dart';
import 'plugin_harness.dart';

// 內附測試插件（`fmp-test`）是 dev 實機驗證的離線音源：以 `--fmp-dev-plugin`
// 安裝後可以搜尋、播放，不連網（ADR 0027 §決定 1）。它的串流指向 dev flavor
// 打包的音檔，prod 不打包（app/AGENTS.md § 插件）。

void main() {
  test('every search result plays a bundled asset', () async {
    final plugin = await PluginHarness().load(
      testPluginFile.readAsStringSync(),
    );
    final ids = <String>[];
    for (var page = 1; ; page++) {
      final result = await plugin.search(SearchQuery(keyword: 'x', page: page));
      ids.addAll([for (final item in result.items) item.sourceId]);
      if (!result.hasMore) break;
    }
    expect(ids, hasLength(greaterThanOrEqualTo(2)));

    for (final id in ids) {
      final result = await plugin.resolveStream(
        StreamRequest(
          sourceId: id,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );
      final candidates = result.candidates;
      expect(candidates.first.url.scheme, 'asset');
      expect(
        candidates.first.url.path,
        startsWith('/test/fixtures/plugins/test_plugin/'),
      );
    }
  });

  test(
    'searching "fail" fails as rate limited, for an offline toast',
    () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      await expectLater(
        plugin.search(SearchQuery(keyword: 'fail')),
        throwsA(isA<RateLimited>()),
      );
      // 只有剛好是它才失敗。
      expect(
        (await plugin.search(SearchQuery(keyword: 'failure'))).items,
        isNotEmpty,
      );
    },
  );

  test('searching "missing" makes the second song stream an asset that does '
      'not exist, for an unopenable look-ahead', () async {
    final plugin = await PluginHarness().load(
      testPluginFile.readAsStringSync(),
    );
    Future<Uri> streamOf(String sourceId) async => (await plugin.resolveStream(
      StreamRequest(
        sourceId: sourceId,
        formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
      ),
    )).candidates.first.url;

    final items = (await plugin.search(SearchQuery(keyword: 'missing'))).items;
    expect(items, hasLength(2));
    final first = await streamOf(items[0].sourceId);
    final second = await streamOf(items[1].sourceId);
    // asset 鍵就是 app/ 底下的相對路徑：第一首的在，第二首的不在。
    expect(File(first.path.substring(1)).existsSync(), isTrue);
    expect(second.scheme, 'asset');
    expect(File(second.path.substring(1)).existsSync(), isFalse);
    // 只有剛好是它才改第二首；第二頁不受影響。
    final other = (await plugin.search(SearchQuery(keyword: 'missing2'))).items;
    expect(await streamOf(other[1].sourceId), first);
    final page2 = await plugin.search(SearchQuery(keyword: 'missing', page: 2));
    expect(await streamOf(page2.items.single.sourceId), first);
  });

  // 播放恢復的實機驗證（ADR 0018 §決定 7），不連網。
  group('recovery keywords', () {
    late Future<StreamResult> Function(String sourceId) resolve;
    late Future<List<String>> Function(String keyword) search;

    setUp(() async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );
      resolve = (sourceId) => plugin.resolveStream(
        StreamRequest(
          sourceId: sourceId,
          formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
        ),
      );
      search = (keyword) async => [
        for (final item in (await plugin.search(
          SearchQuery(keyword: keyword),
        )).items)
          item.sourceId,
      ];
    });

    test('"preview" songs are preview clips of the bundled tone', () async {
      final ids = await search('preview');
      expect(ids, hasLength(2));
      for (final id in ids) {
        final result = await resolve(id);
        expect(result.previewOnly, isTrue);
        expect(result.candidates.single.url.scheme, 'asset');
      }
      // 其他關鍵字的歌不是試聽。
      expect(
        (await resolve((await search('previews')).first)).previewOnly,
        isFalse,
      );
    });

    test('"flaky" songs fail with NetworkError every other time, starting '
        'with the first', () async {
      final [first, second] = await search('flaky');
      await expectLater(resolve(first), throwsA(isA<NetworkError>()));
      expect((await resolve(first)).candidates, hasLength(1));
      await expectLater(resolve(first), throwsA(isA<NetworkError>()));
      // 每一首各自算。
      await expectLater(resolve(second), throwsA(isA<NetworkError>()));
    });

    test(
      '"unavailable" makes only the first song unavailable for copyright',
      () async {
        final [first, second] = await search('unavailable');
        await expectLater(
          resolve(first),
          throwsA(
            isA<Unavailable>().having(
              (e) => e.reason,
              'reason',
              UnavailableReason.copyright,
            ),
          ),
        );
        expect((await resolve(second)).candidates, hasLength(1));
      },
    );
  });

  // 電台的實機驗證（ADR 0028 §決定 3）：五個固定的直播間，不連網。
  group('live rooms', () {
    late ScriptSourcePlugin plugin;
    final formats = [StreamFormat(container: 'wav', codec: 'pcm_s16le')];

    setUp(() async {
      plugin = await PluginHarness().load(testPluginFile.readAsStringSync());
    });

    Future<LiveRoom> status(String roomId) =>
        plugin.liveStatus(LiveRoomQuery(roomId: roomId));
    Future<Uri> stream(String roomId) async => (await plugin.resolveLive(
      LiveStreamRequest(roomId: roomId, formats: formats),
    )).candidates.first.url;
    Future<List<String>> search([LiveRoomStatus? status]) async => [
      for (final room in (await plugin.liveSearch(
        LiveSearchQuery(keyword: 'any', status: status),
      )).items)
        room.roomId,
    ];

    test('search returns the five rooms and filters by status', () async {
      const all = [
        'live-ok',
        'live-offline',
        'live-drop',
        'live-ended',
        'live-broken',
      ];
      final page = await plugin.liveSearch(LiveSearchQuery(keyword: 'x'));

      expect(page.hasMore, isFalse);
      expect(await search(), all);
      expect(await search(LiveRoomStatus.offline), ['live-offline']);
      expect(
        await search(LiveRoomStatus.live),
        all.where((id) => id != 'live-offline'),
      );
    });

    test('searching "fail" is rate limited, other keywords are not', () async {
      await expectLater(
        plugin.liveSearch(LiveSearchQuery(keyword: 'fail')),
        throwsA(isA<RateLimited>()),
      );
      expect(
        (await plugin.liveSearch(LiveSearchQuery(keyword: 'failure'))).items,
        isNotEmpty,
      );
    });

    test('only https://fmp.test/live/<known room> is a room url', () async {
      Future<String?> room(String url) async =>
          (await plugin.liveRoomFromUrl(LiveUrlQuery(url: url)))?.roomId;

      expect(await room('https://fmp.test/live/live-ok'), 'live-ok');
      expect(await room('https://fmp.test/live/live-broken'), 'live-broken');
      expect(await room('https://fmp.test/live/unknown'), isNull);
      expect(await room('https://fmp.test/live/live-ok/extra'), isNull);
      expect(await room('https://other.test/live/live-ok'), isNull);
    });

    test(
      'live-ok is live with a fixed audience and plays the 60 s file',
      () async {
        final room = await status('live-ok');
        final url = await stream('live-ok');

        expect(room.status, LiveRoomStatus.live);
        expect(room.online, 42);
        expect(url.scheme, 'asset');
        expect(url.path, '/test/fixtures/plugins/test_plugin/live.wav');
        final bytes = File(url.path.substring(1)).lengthSync();
        // 8 kHz 單聲道 16-bit、60 秒，加 44 bytes 的標頭。
        expect(bytes, 8000 * 2 * 60 + 44);
      },
    );

    test('live-offline is offline and cannot be resolved', () async {
      expect((await status('live-offline')).status, LiveRoomStatus.offline);
      await expectLater(stream('live-offline'), throwsA(isA<NotFound>()));
    });

    test(
      'live-drop is always live and streams the 2 s tone each time',
      () async {
        for (var i = 0; i < 3; i++) {
          expect((await status('live-drop')).status, LiveRoomStatus.live);
          expect(
            (await stream('live-drop')).path,
            '/test/fixtures/plugins/test_plugin/tone.wav',
          );
        }
      },
    );

    test('live-ended is live on the first check and offline after', () async {
      expect((await status('live-ended')).status, LiveRoomStatus.live);
      expect((await status('live-ended')).status, LiveRoomStatus.offline);
      expect((await status('live-ended')).status, LiveRoomStatus.offline);
      // 每個 isolate 各自算：換一個插件從頭開始。
      final fresh = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );
      expect(
        (await fresh.liveStatus(LiveRoomQuery(roomId: 'live-ended'))).status,
        LiveRoomStatus.live,
      );
    });

    test('live-broken fails with NetworkError, never offline', () async {
      await expectLater(status('live-broken'), throwsA(isA<NetworkError>()));
      await expectLater(stream('live-broken'), throwsA(isA<NetworkError>()));
      expect(await search(LiveRoomStatus.live), contains('live-broken'));
    });

    test('an unknown room is NotFound', () async {
      await expectLater(status('nope'), throwsA(isA<NotFound>()));
      await expectLater(stream('nope'), throwsA(isA<NotFound>()));
    });
  });

  group('playlists', () {
    Future<ScriptSourcePlugin> load() =>
        PluginHarness().load(testPluginFile.readAsStringSync());

    Future<PlaylistPage> page(
      ScriptSourcePlugin plugin,
      String id, [
      String? cursor,
    ]) => plugin.importPlaylist(
      PlaylistPageQuery(playlistId: id, cursor: cursor),
    );

    List<String> titles(PlaylistPage page) => [
      for (final item in page.items) item.track.title,
    ];

    test('only fmp.test playlist and mix urls are recognised', () async {
      final plugin = await load();
      Future<PlaylistRef?> from(String url) =>
          plugin.playlistFromUrl(PlaylistUrlQuery(url: url));

      final playlist = await from('https://fmp.test/playlist/pl-basic');
      final mix = await from('https://fmp.test/mix/tone-440');

      expect((playlist! as PlaylistIdRef).playlistId, 'pl-basic');
      expect((mix! as PlaylistMixSeedRef).seed.sourceId, 'tone-440');
      expect(await from('https://fmp.test/live/live-ok'), isNull);
      expect(await from('https://fmp.test/playlist/'), isNull);
      expect(await from('https://other.test/playlist/pl-basic'), isNull);
    });

    test(
      'pl-basic has five songs over two pages, the 1st and 4th alike',
      () async {
        final plugin = await load();

        final first = await page(plugin, 'pl-basic');
        final second = await page(plugin, 'pl-basic', first.cursor);

        expect(first.items, hasLength(3));
        expect(second.items, hasLength(2));
        expect(first.cursor, isNotNull);
        expect(second.cursor, isNull);
        expect(first.total, 5);
        final all = [...first.items, ...second.items];
        final ids = [for (final item in all) item.track.sourceId];
        expect(ids[0], ids[3]);
        expect(ids.toSet(), hasLength(4));
        // 同一首的資料也相同：宿主依曲目鍵只存一份，兩個位置顯示同一個標題。
        expect(all[0].track.title, all[3].track.title);
        expect(all[0].track.toTrackInfo(), all[3].track.toTrackInfo());
        expect(all.map((item) => item.remoteItemId), everyElement(isNull));
      },
    );

    test(
      'pl-grow adds, removes, then reverses, one step per refresh',
      () async {
        final plugin = await load();
        List<String?> ids(PlaylistPage page) => [
          for (final item in page.items) item.remoteItemId,
        ];

        final first = await page(plugin, 'pl-grow');
        final second = await page(plugin, 'pl-grow');
        final third = await page(plugin, 'pl-grow');

        expect(ids(first), ['grow-1', 'grow-2', 'grow-3', 'grow-4', 'grow-5']);
        expect(ids(second), ['grow-2', 'grow-3', 'grow-4', 'grow-5']);
        expect(ids(third), ['grow-5', 'grow-4', 'grow-3', 'grow-2']);
        // 每項是不同的曲目：新增、移除與倒序在歌單裡看得出來。
        expect(
          [for (final item in third.items) item.track.sourceId],
          ['grow-5', 'grow-4', 'grow-3', 'grow-2'],
        );
        expect(
          [first, second, third].map((page) => (page.cursor, page.total)),
          [(null, 5), (null, 4), (null, 4)],
        );
      },
    );

    test('pl-partial fails on the second page', () async {
      final plugin = await load();

      final first = await page(plugin, 'pl-partial');

      expect(first.cursor, isNotNull);
      await expectLater(
        page(plugin, 'pl-partial', first.cursor),
        throwsA(isA<NetworkError>()),
      );
    });

    test('pl-gone is NotFound, and so is an unknown playlist', () async {
      final plugin = await load();

      await expectLater(page(plugin, 'pl-gone'), throwsA(isA<NotFound>()));
      await expectLater(page(plugin, 'pl-nope'), throwsA(isA<NotFound>()));
    });

    test('pl-auth needs a login, then it is three writable songs', () async {
      final harness = PluginHarness();
      final plugin = await harness.load(testPluginFile.readAsStringSync());

      await expectLater(page(plugin, 'pl-auth'), throwsA(isA<AuthRequired>()));

      await harness.credentials.save(
        Account(
          pluginId: 'fmp-test',
          userId: 'fmp-test-user',
          displayName: 'FMP Test User',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026, 10, 15),
        ),
        const LoginCredentials(cookies: {'fmp_test_session': 'fake-session'}),
      );
      final result = await page(plugin, 'pl-auth');

      expect(result.items, hasLength(3));
      expect(result.playlist.writable, isTrue);
    });

    test('the other playlists do not know whether they are writable', () async {
      final plugin = await load();

      for (final id in ['pl-basic', 'pl-grow', 'pl-unavailable', 'pl-parts']) {
        expect((await page(plugin, id)).playlist.writable, isNull, reason: id);
      }
    });

    test('pl-unavailable marks only its second song', () async {
      final plugin = await load();

      final result = await page(plugin, 'pl-unavailable');

      expect(result.items.map((item) => item.unavailable), [
        false,
        true,
        false,
      ]);
    });

    test('pl-parts expands one video into three parts', () async {
      final plugin = await load();

      final result = await page(plugin, 'pl-parts');

      expect(result.total, isNull);
      expect(result.cursor, isNull);
      expect(titles(result), ['Part one', 'Part two', 'Part three']);
      final tracks = [for (final item in result.items) item.track];
      expect(tracks.map((track) => track.partIndex), [1, 2, 3]);
      expect(tracks.map((track) => track.cid), [22001, 22002, 22003]);
      expect(tracks.map((track) => track.parentTitle).toSet(), {
        'Test multi-part video',
      });
      expect({for (final track in tracks) track.sourceId}, {'parts-220'});
      // 和 multiPart 的 parts-220 同一組 cid。
      final parts = await plugin.multiPart(
        MultiPartQuery(sourceId: 'parts-220'),
      );
      expect(parts.parts.map((part) => part.cid), tracks.map((t) => t.cid));
    });

    test('every playlist song plays a bundled asset', () async {
      final plugin = await load();

      for (final id in ['pl-basic', 'pl-grow', 'pl-unavailable', 'pl-parts']) {
        for (final item in (await page(plugin, id)).items) {
          final stream = await plugin.resolveStream(
            StreamRequest(
              sourceId: item.track.sourceId,
              formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
            ),
          );
          expect(stream.candidates.first.url.scheme, 'asset', reason: id);
        }
      }
    });
  });

  group('charts', () {
    Future<ScriptSourcePlugin> load() =>
        PluginHarness().load(testPluginFile.readAsStringSync());

    test('the list is hot, new and broken, in that order', () async {
      final list = await (await load()).chartList();

      expect(
        [for (final chart in list.charts) chart.chartId],
        ['hot', 'new', 'broken'],
      );
      expect(
        [for (final chart in list.charts) chart.title],
        ['Hot', 'New', 'Broken'],
      );
    });

    test('hot has five songs and new has three', () async {
      final plugin = await load();

      final hot = await plugin.chart(ChartQuery(chartId: 'hot'));
      final fresh = await plugin.chart(ChartQuery(chartId: 'new'));

      expect(hot.tracks, hasLength(5));
      expect(fresh.tracks, hasLength(3));
      expect(
        {
          ...hot.tracks.map((t) => t.sourceId),
          ...fresh.tracks.map((t) => t.sourceId),
        },
        hasLength(8),
        reason: 'no song is in both charts',
      );
    });

    test(
      'broken fails with NetworkError and an unknown chart is NotFound',
      () async {
        final plugin = await load();

        await expectLater(
          plugin.chart(ChartQuery(chartId: 'broken')),
          throwsA(isA<NetworkError>()),
        );
        await expectLater(
          plugin.chart(ChartQuery(chartId: 'nope')),
          throwsA(isA<NotFound>()),
        );
      },
    );

    test('every chart song plays the bundled asset', () async {
      final plugin = await load();

      for (final id in ['hot', 'new']) {
        for (final track in (await plugin.chart(
          ChartQuery(chartId: id),
        )).tracks) {
          final stream = await plugin.resolveStream(
            StreamRequest(
              sourceId: track.sourceId,
              formats: [StreamFormat(container: 'wav', codec: 'pcm_s16le')],
            ),
          );
          expect(stream.candidates.first.url.scheme, 'asset', reason: id);
        }
      }
    });
  });

  group('libraryRead', () {
    Future<void> logIn(PluginHarness harness) => harness.credentials.save(
      Account(
        pluginId: 'fmp-test',
        userId: 'fmp-test-user',
        displayName: 'FMP Test User',
        status: AccountStatus.active,
        loggedInAt: DateTime.utc(2026, 10, 20),
      ),
      const LoginCredentials(cookies: {'fmp_test_session': 'fake-session'}),
    );

    test('needs a login', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      await expectLater(
        plugin.libraryPlaylists(LibraryPlaylistsQuery()),
        throwsA(isA<AuthRequired>()),
      );
    });

    test('lists pl-auth (writable) and pl-basic (read-only) after a login, '
        'with the titles and counts importPlaylist returns', () async {
      final harness = PluginHarness();
      final plugin = await harness.load(testPluginFile.readAsStringSync());
      await logIn(harness);

      final page = await plugin.libraryPlaylists(LibraryPlaylistsQuery());

      expect(page.cursor, isNull);
      expect(
        [
          for (final p in page.playlists)
            (p.playlistId, p.writable, p.trackCount),
        ],
        [('pl-auth', true, 3), ('pl-basic', false, 5)],
      );
      for (final entry in page.playlists) {
        final imported = await plugin.importPlaylist(
          PlaylistPageQuery(playlistId: entry.playlistId),
        );
        expect(imported.playlist.title, entry.title);
        expect(imported.total ?? imported.items.length, entry.trackCount);
      }
    });
  });

  group('libraryLiveRooms', () {
    test('needs a login', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      expect(plugin.exportsLibraryLiveRooms, isTrue);
      await expectLater(
        plugin.libraryLiveRooms(),
        throwsA(isA<AuthRequired>()),
      );
    });

    test('lists the five live rooms of liveSearch after a login', () async {
      final harness = PluginHarness();
      final plugin = await harness.load(testPluginFile.readAsStringSync());
      await harness.credentials.save(
        Account(
          pluginId: 'fmp-test',
          userId: 'fmp-test-user',
          displayName: 'FMP Test User',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026, 10, 20),
        ),
        const LoginCredentials(cookies: {'fmp_test_session': 'fake-session'}),
      );

      final rooms = (await plugin.libraryLiveRooms()).rooms;
      final searched = (await plugin.liveSearch(LiveSearchQuery(keyword: 'x')))
          .items;

      expect(rooms, hasLength(5));
      expect({for (final r in rooms) r.roomId}, hasLength(5));
      expect(
        [for (final r in rooms) (r.roomId, r.title, r.status)],
        [for (final r in searched) (r.roomId, r.title, r.status)],
      );
    });

    test('the README documents libraryLiveRooms', () {
      final readme = File('test/fixtures/plugins/test_plugin/README.md')
          .readAsStringSync();

      expect(readme, contains('libraryLiveRooms'));
      expect(readme, contains('從帳號匯入電台'));
    });
  });

  // 遠端寫入的假實作（design §4.9）：狀態在插件 isolate 的記憶體，每個測試載入自己的一份。
  group('libraryWrite', () {
    Future<(ScriptSourcePlugin, PluginHarness)> loggedIn() async {
      final harness = PluginHarness();
      final plugin = await harness.load(testPluginFile.readAsStringSync());
      await harness.credentials.save(
        Account(
          pluginId: 'fmp-test',
          userId: 'fmp-test-user',
          displayName: 'FMP Test User',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026, 10, 20),
        ),
        const LoginCredentials(cookies: {'fmp_test_session': 'fake-session'}),
      );
      return (plugin, harness);
    }

    AddToPlaylistQuery add(String playlistId, List<String> ids, {int? cid}) =>
        AddToPlaylistQuery(
          playlistId: playlistId,
          tracks: [for (final id in ids) AddTrackRef(sourceId: id, cid: cid)],
        );

    Future<List<RemotePlaylistItem>> items(
      ScriptSourcePlugin plugin,
      String id,
    ) async =>
        (await plugin.importPlaylist(PlaylistPageQuery(playlistId: id))).items;

    test(
      'declares the capability, so the exports are checked on load',
      () async {
        final plugin = await PluginHarness().load(
          testPluginFile.readAsStringSync(),
        );

        expect(
          plugin.manifest.capabilities,
          contains(PluginCapability.libraryWrite),
        );
        expect(
          plugin.manifest.requiredExports,
          containsAll(LibraryWriteExports.all),
        );
      },
    );

    test('every write needs a login', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      await expectLater(
        plugin.addToPlaylist(add('pl-auth', ['tone-330'])),
        throwsA(isA<AuthRequired>()),
      );
      await expectLater(
        plugin.removeFromPlaylist(
          RemoveFromPlaylistQuery(
            playlistId: 'pl-auth',
            items: [RemoveItemRef(sourceId: 'tone-440')],
          ),
        ),
        throwsA(isA<AuthRequired>()),
      );
      await expectLater(
        plugin.createPlaylist(CreatePlaylistQuery(title: 'x')),
        throwsA(isA<AuthRequired>()),
      );
    });

    test('adding a song is added once, then alreadyPresent', () async {
      final (plugin, _) = await loggedIn();

      final first = await plugin.addToPlaylist(add('pl-auth', ['tone-330']));
      final second = await plugin.addToPlaylist(add('pl-auth', ['tone-330']));

      expect(first.results.single.status, LibraryWriteStatus.added);
      expect(second.results.single.status, LibraryWriteStatus.alreadyPresent);
      // 初始內容裡就有的也是 alreadyPresent。
      final initial = await plugin.addToPlaylist(add('pl-auth', ['tone-440']));
      expect(initial.results.single.status, LibraryWriteStatus.alreadyPresent);
    });

    test('a cid makes it another song', () async {
      final (plugin, _) = await loggedIn();

      await plugin.addToPlaylist(add('pl-auth', ['parts-220'], cid: 22001));
      final other = await plugin.addToPlaylist(
        add('pl-auth', ['parts-220'], cid: 22002),
      );

      expect(other.results.single.status, LibraryWriteStatus.added);
    });

    test('the song with sourceId "fail" fails with a structured error, the '
        'others in the same call are unaffected', () async {
      final (plugin, _) = await loggedIn();

      final response = await plugin.addToPlaylist(
        add('pl-auth', ['tone-330', 'fail', 'tone-550']),
      );

      expect(
        [for (final r in response.results) r.status],
        [
          LibraryWriteStatus.added,
          LibraryWriteStatus.failed,
          LibraryWriteStatus.added,
        ],
      );
      expect(response.results[1].error, isA<RateLimited>());
      expect(response.results[0].error, isNull);
    });

    test('importPlaylist of pl-auth and libraryPlaylists reflect the '
        'writes, so a refresh after a write can be observed', () async {
      final (plugin, _) = await loggedIn();
      expect(await items(plugin, 'pl-auth'), hasLength(3));

      await plugin.addToPlaylist(add('pl-auth', ['tone-330', 'tone-550']));

      final after = await items(plugin, 'pl-auth');
      expect(
        [for (final i in after) i.track.sourceId],
        ['tone-440', 'tone-220', 'tone-880', 'tone-330', 'tone-550'],
      );
      // 每項都有 remoteItemId，移除可以用它。
      expect(after.every((item) => item.remoteItemId != null), isTrue);
      expect({for (final i in after) i.remoteItemId}, hasLength(5));
      final listed = await plugin.libraryPlaylists(LibraryPlaylistsQuery());
      expect(listed.playlists.first.trackCount, 5);
    });

    test('removing finds a song by remoteItemId, or by sourceId and cid; '
        'a missing one is notPresent', () async {
      final (plugin, _) = await loggedIn();
      final current = await items(plugin, 'pl-auth');

      final response = await plugin.removeFromPlaylist(
        RemoveFromPlaylistQuery(
          playlistId: 'pl-auth',
          items: [
            RemoveItemRef(
              sourceId: 'tone-440',
              remoteItemId: current[0].remoteItemId,
            ),
            RemoveItemRef(sourceId: 'tone-220'),
            RemoveItemRef(sourceId: 'tone-220'),
            RemoveItemRef(sourceId: 'tone-880', cid: 5),
          ],
        ),
      );

      expect(
        [for (final r in response.results) r.status],
        [
          LibraryWriteStatus.removed,
          LibraryWriteStatus.removed,
          LibraryWriteStatus.notPresent,
          LibraryWriteStatus.notPresent,
        ],
      );
      expect(
        [for (final i in await items(plugin, 'pl-auth')) i.track.sourceId],
        ['tone-880'],
      );
    });

    test('removing "fail" fails', () async {
      final (plugin, _) = await loggedIn();

      final response = await plugin.removeFromPlaylist(
        RemoveFromPlaylistQuery(
          playlistId: 'pl-auth',
          items: [RemoveItemRef(sourceId: 'fail')],
        ),
      );

      expect(response.results.single.status, LibraryWriteStatus.failed);
      expect(response.results.single.error, isNotNull);
    });

    test(
      'a playlist that is not the account\'s writable one is NotFound',
      () async {
        final (plugin, _) = await loggedIn();

        await expectLater(
          plugin.addToPlaylist(add('pl-basic', ['tone-330'])),
          throwsA(isA<NotFound>()),
        );
      },
    );

    test('createPlaylist makes pl-new-<n>: empty, listed as writable, '
        'importable and writable afterwards', () async {
      final (plugin, _) = await loggedIn();

      final first = await plugin.createPlaylist(
        CreatePlaylistQuery(title: 'Mine'),
      );
      final second = await plugin.createPlaylist(
        CreatePlaylistQuery(title: 'Other'),
      );

      expect([first.playlistId, second.playlistId], ['pl-new-1', 'pl-new-2']);
      final listed = await plugin.libraryPlaylists(LibraryPlaylistsQuery());
      expect(
        [for (final p in listed.playlists) (p.playlistId, p.writable)],
        [
          ('pl-auth', true),
          ('pl-basic', false),
          ('pl-new-1', true),
          ('pl-new-2', true),
        ],
      );
      final page = await plugin.importPlaylist(
        PlaylistPageQuery(playlistId: 'pl-new-1'),
      );
      expect(page.items, isEmpty);
      expect(page.playlist.title, 'Mine');
      expect(page.playlist.writable, isTrue);
      await plugin.addToPlaylist(add('pl-new-1', ['tone-330']));
      expect(await items(plugin, 'pl-new-1'), hasLength(1));
    });

    test('searching "write-fail" puts the failing song first, only for '
        'that keyword', () async {
      final plugin = await PluginHarness().load(
        testPluginFile.readAsStringSync(),
      );

      final failing = await plugin.search(SearchQuery(keyword: 'write-fail'));
      final other = await plugin.search(SearchQuery(keyword: 'write-fail2'));

      expect(failing.items.first.sourceId, 'fail');
      expect([
        for (final i in failing.items.skip(1)) i.sourceId,
      ], everyElement(startsWith('tone-')));
      expect(
        other.items.map((i) => i.sourceId),
        everyElement(startsWith('tone-')),
      );
    });

    test('the README documents the keywords and ids', () {
      final readme = File('test/fixtures/plugins/test_plugin/README.md')
          .readAsStringSync();

      for (final keyword in [
        'libraryWrite',
        'write-fail',
        'pl-new-',
        'alreadyPresent',
        'createPlaylist',
      ]) {
        expect(readme, contains(keyword), reason: keyword);
      }
    });
  });

  test('the test plugin is bundled only in the dev flavor', () {
    final assets =
        (loadYaml(File('pubspec.yaml').readAsStringSync())
                as YamlMap)['flutter']['assets']
            as YamlList;
    expect(
      assets,
      contains(
        allOf(
          containsPair('path', 'test/fixtures/plugins/test_plugin/'),
          containsPair('flavors', ['dev']),
        ),
      ),
    );
  });

  // 僅元資料來源的測試插件（M4 design §4.9）：外部匯入的實機重播。標題、歌手、時長照 fmp-test 的
  // 搜尋結果寫，以真的 ExternalImport 對真的 fmp-test 匹配，守「重播時匹配得到」。
  group('the metadata test plugin (fmp-test-meta)', () {
    Future<SourcePlugin> load(PluginHarness harness) =>
        harness.load(testMetaPluginFile.readAsStringSync());

    test('declares only importPlaylist and knows its links', () async {
      final plugin = await load(PluginHarness());

      expect(plugin.manifest.id, 'fmp-test-meta');
      expect(plugin.manifest.capabilities, {PluginCapability.importPlaylist});
      final found = await plugin.playlistFromUrl(
        PlaylistUrlQuery(url: 'https://fmp.test/meta/meta-basic'),
      );
      expect((found! as PlaylistIdRef).playlistId, 'meta-basic');
      expect(
        await plugin.playlistFromUrl(
          PlaylistUrlQuery(url: 'https://fmp.test/playlist/pl-basic'),
        ),
        isNull,
        reason: 'the links of fmp-test are not its own',
      );
    });

    Future<List<RemotePlaylistItem>> readAll(
      SourcePlugin plugin,
      String id,
    ) async {
      final items = <RemotePlaylistItem>[];
      String? cursor;
      do {
        final page = await plugin.importPlaylist(
          PlaylistPageQuery(playlistId: id, cursor: cursor),
        );
        items.addAll(page.items);
        cursor = page.cursor;
      } while (cursor != null);
      return items;
    }

    test('meta-truncated says so on its last page; meta-broken fails on its '
        'second page', () async {
      final plugin = await load(PluginHarness());

      final first = await plugin.importPlaylist(
        PlaylistPageQuery(playlistId: 'meta-truncated'),
      );
      expect(first.truncated, isFalse);
      final last = await plugin.importPlaylist(
        PlaylistPageQuery(playlistId: 'meta-truncated', cursor: first.cursor),
      );
      expect(last.cursor, isNull);
      expect(last.truncated, isTrue);

      final broken = await plugin.importPlaylist(
        PlaylistPageQuery(playlistId: 'meta-broken'),
      );
      expect(broken.items, hasLength(2));
      await expectLater(
        plugin.importPlaylist(
          PlaylistPageQuery(playlistId: 'meta-broken', cursor: broken.cursor),
        ),
        throwsA(isA<NetworkError>()),
      );
      await expectLater(
        plugin.importPlaylist(PlaylistPageQuery(playlistId: 'nope')),
        throwsA(isA<NotFound>()),
      );
    });

    test('meta-basic matches fmp-test where it should and nowhere '
        'else', () async {
      // 插件的 harness 與音樂庫各開一個記憶體資料庫。
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false,
      );
      final harness = PluginHarness();
      final meta = await load(harness);
      final tones = await harness.load(testPluginFile.readAsStringSync());
      expect(await readAll(meta, 'meta-basic'), hasLength(6));
      final env = await LibraryEnv.open(plugins: [meta, tones]);
      final job = await env.container
          .read(externalImportsProvider)
          .open('fmp-test-meta', 'meta-basic');
      addTearDown(job.dispose);

      await job.read();
      expect(job.targets, ['fmp-test']);
      expect(job.pairing, isFalse);
      job.start();
      await pumpUntil(
        () => job.phase == ExternalImportPhase.done,
        maxRounds: 200,
      );

      expect(
        [for (final row in job.rows) row.chosen?.sourceTypeId],
        ['fmp-test', null, 'fmp-test', 'fmp-test', null, 'fmp-test'],
      );
      expect(job.rows.first, same(job.rows.last), reason: 'the same song');
      expect(job.songs, hasLength(5));
    });

    test('the README documents the playlists', () {
      final readme = File('test/fixtures/plugins/test_meta_plugin/README.md')
          .readAsStringSync();

      for (final id in ['meta-basic', 'meta-truncated', 'meta-broken']) {
        expect(readme, contains(id), reason: id);
      }
    });

    test('it is bundled only in the dev flavor', () {
      final assets =
          (loadYaml(File('pubspec.yaml').readAsStringSync())
                  as YamlMap)['flutter']['assets']
              as YamlList;
      expect(
        assets,
        contains(
          allOf(
            containsPair('path', 'test/fixtures/plugins/test_meta_plugin/'),
            containsPair('flavors', ['dev']),
          ),
        ),
      );
    });
  });
}
