import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fake_http.dart';
import '../support/fjs.dart';

/// 插件宿主（`plugins/`）經它的公開介面測：測試用的小插件（JS 寫在這裡）
/// 跑在真的 fjs 引擎裡，網路換成 [FakeHttp]。
void main() {
  late Directory logDir;
  late Log log;
  final hosts = <PluginHost>[];

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_plugin_host_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
  });
  tearDown(() async {
    for (final host in hosts) {
      await host.close();
    }
    hosts.clear();
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  String manifest({
    String id = 'demo',
    List<String> capabilities = const ['search'],
    List<String> domains = const ['api.example.com'],
    Object? mark,
    Object? searchSorts,
  }) => jsonEncode({
    'id': id,
    'name': 'Demo',
    'version': '1.0.0',
    'capabilities': capabilities,
    'domains': domains,
    'mark': ?mark,
    'searchSorts': ?searchSorts,
  });

  PluginHost host(
    String code, {
    String? manifestJson,
    FakeHttp? http,
    Duration callTimeout = const Duration(seconds: 10),
  }) {
    final h = PluginHost(
      bundles: [PluginBundle(manifest: manifestJson ?? manifest(), code: code)],
      log: log,
      httpAdapter: http ?? FakeHttp((_) => const FakeResponse(404)),
      callTimeout: callTimeout,
    );
    hosts.add(h);
    return h;
  }

  Plugin only(PluginHost h) => h.plugins.single;

  /// 寫完 log 再讀；之後的 tearDown 照常關（關兩次無妨）。
  Future<String> closeAndReadLog() async {
    await log.close();
    return File('${logDir.path}/${Log.fileName}').readAsStringSync();
  }

  test(
    'search returns the tracks the plugin builds from the host network',
    () async {
      final http = FakeHttp(
        (request) => FakeResponse.json({
          'items': [
            {'id': 'a1', 'name': 'Song A', 'by': 'Alice', 'seconds': 61},
          ],
          'echo': request.uri.queryParameters['q'],
        }),
      );
      final h = host('''
      export async function search({ query }) {
        const res = await host.http.request({
          url: 'https://api.example.com/find?q=' + encodeURIComponent(query),
        });
        const json = JSON.parse(res.body);
        return {
          tracks: json.items.map((i) => ({
            id: i.id,
            title: i.name + ' / ' + json.echo,
            author: i.by,
            durationMs: i.seconds * 1000,
          })),
        };
      }
    ''', http: http);

      final tracks = (await only(h).search('中文 query')).tracks;

      expect(tracks, [
        const Track(
          ref: TrackRef(pluginId: 'demo', trackId: 'a1'),
          title: 'Song A / 中文 query',
          author: 'Alice',
          duration: Duration(seconds: 61),
        ),
      ]);
      expect(http.requests.single.method, 'GET');
    },
  );

  group('a track cover', () {
    String searching(String cover) =>
        '''
      export async function search() {
        return { tracks: [{ id: 'a1', title: 'A', author: 'B', coverUrl: $cover }] };
      }
    ''';

    test('is the https or http URL the plugin gives', () async {
      final tracks = (await only(
        host(searching("'https://img.example.com/a.jpg'")),
      ).search('q')).tracks;
      expect(tracks.single.coverUrl, 'https://img.example.com/a.jpg');
    });

    test('is optional', () async {
      final tracks = (await only(host(searching('undefined'))).search('q'))
          .tracks;
      expect(tracks.single.coverUrl, isNull);
    });

    for (final cover in ["'//img.example.com/a.jpg'", "'file:///a.jpg'", '1']) {
      test('$cover is a ParseFailure', () async {
        await expectLater(
          only(host(searching(cover))).search('q'),
          throwsA(isA<ParseFailure>()),
        );
      });
    }
  });

  group('a track large cover', () {
    String searching(String cover) =>
        '''
      export async function search() {
        return { tracks: [{ id: 'a1', title: 'A', author: 'B', coverLargeUrl: $cover }] };
      }
    ''';

    test('is the https or http URL the plugin gives', () async {
      final tracks = (await only(
        host(searching("'https://img.example.com/a-large.jpg'")),
      ).search('q')).tracks;
      expect(
        tracks.single.coverLargeUrl,
        'https://img.example.com/a-large.jpg',
      );
    });

    test('is optional', () async {
      final tracks = (await only(host(searching('undefined'))).search('q'))
          .tracks;
      expect(tracks.single.coverLargeUrl, isNull);
    });

    for (final cover in ["'//img.example.com/a.jpg'", "'file:///a.jpg'", '1']) {
      test('$cover is a ParseFailure', () async {
        await expectLater(
          only(host(searching(cover))).search('q'),
          throwsA(isA<ParseFailure>()),
        );
      });
    }
  });

  group('search sorting and paging', () {
    /// 把收到的參數原樣回成一首曲目的標題。
    const echo = '''
      export async function search(req) {
        return { tracks: [{ id: 'a', title: JSON.stringify(req), author: 'x' }] };
      }
    ''';

    Future<Map<String, Object?>> received(
      PluginHost h, {
      SearchSort? sort,
      int page = 1,
    }) async {
      final results = await only(h).search('q', sort: sort, page: page);
      return jsonDecode(results.tracks.single.title) as Map<String, Object?>;
    }

    PluginHost sortable([Object? sorts = const ['viewCount', 'relevance']]) =>
        host(echo, manifestJson: manifest(searchSorts: sorts));

    test('a declared sort goes to the plugin by name', () async {
      expect(await received(sortable(), sort: SearchSort.viewCount), {
        'query': 'q',
        'sort': 'viewCount',
        'page': 1,
      });
    });

    test('a sort the manifest does not declare is not passed on', () async {
      expect(
        (await received(sortable(), sort: SearchSort.date)).keys,
        unorderedEquals(['query', 'page']),
      );
      final plain = host(echo);
      expect(
        (await received(plain, sort: SearchSort.viewCount)).keys,
        unorderedEquals(['query', 'page']),
      );
    });

    test('the page number goes to the plugin', () async {
      expect((await received(sortable(), page: 4))['page'], 4);
    });

    test('a page below 1 is an ArgumentError', () {
      expect(
        () => only(sortable()).search('q', page: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'the manifest keeps its order, drops duplicates and unknown names',
      () {
        final m = only(sortable(['date', 'bogus', 'relevance', 'date']))
            .manifest;
        expect(m.searchSorts, [SearchSort.date, SearchSort.relevance]);
      },
    );

    test('a manifest without searchSorts declares none', () {
      expect(only(host(echo)).manifest.searchSorts, isEmpty);
    });

    for (final bad in [
      'viewCount',
      [1],
      {'a': 1},
    ]) {
      test('searchSorts $bad skips the plugin', () {
        final h = host(echo, manifestJson: manifest(searchSorts: bad));
        expect(h.plugins, isEmpty);
      });
    }
  });

  group('search results', () {
    String returning(String result) =>
        '''
      export async function search() { return $result; }
    ''';

    Future<SearchResults> searchWith(String result) =>
        only(host(returning(result))).search('q');

    test('isEnd is what the plugin says', () async {
      expect((await searchWith('{ tracks: [], isEnd: false }')).isEnd, isFalse);
      expect((await searchWith('{ tracks: [], isEnd: true }')).isEnd, isTrue);
    });

    test('a plugin that does not say has no next page', () async {
      expect((await searchWith('{ tracks: [] }')).isEnd, isTrue);
    });

    for (final bad in ["'no'", '0', '[]']) {
      test('isEnd $bad is a ParseFailure', () async {
        await expectLater(
          searchWith('{ tracks: [], isEnd: $bad }'),
          throwsA(isA<ParseFailure>()),
        );
      });
    }

    String withTrack(String fields) =>
        "{ tracks: [{ id: 'a', title: 'A', author: 'B', $fields }] }";

    test('a track keeps the play count and the page it is given', () async {
      final track = (await searchWith(
        withTrack("playCount: 1200, url: 'https://www.example.com/v/a'"),
      )).tracks.single;
      expect(track.playCount, 1200);
      expect(track.url, 'https://www.example.com/v/a');
    });

    test('play count and url are optional', () async {
      final track = (await searchWith(withTrack('x: 1'))).tracks.single;
      expect(track.playCount, isNull);
      expect(track.url, isNull);
    });

    for (final bad in ['-1', '1.5', "'12'", 'NaN', 'Infinity', 'true']) {
      test('play count $bad is a ParseFailure', () async {
        await expectLater(
          searchWith(withTrack('playCount: $bad')),
          throwsA(isA<ParseFailure>()),
        );
      });
    }

    for (final bad in [
      "'//www.example.com/a'",
      "'ftp://a.example.com/a'",
      '1',
    ]) {
      test('url $bad is a ParseFailure', () async {
        await expectLater(
          searchWith(withTrack('url: $bad')),
          throwsA(isA<ParseFailure>()),
        );
      });
    }
  });

  group('search part counts', () {
    Future<SearchResults> searchWith(String fields) => only(
      host('''
      export async function search() {
        return { tracks: [{ id: 'a', title: 'A', author: 'B', $fields }] };
      }
    '''),
    ).search('q');

    test('a track keeps the part count it is given', () async {
      final track = (await searchWith('partCount: 51')).tracks.single;
      expect(track.partCount, 51);
    });

    test('part count is optional', () async {
      expect((await searchWith('x: 1')).tracks.single.partCount, isNull);
    });

    for (final bad in ['0', '-1', '1.5', "'2'", 'NaN', 'Infinity', 'true']) {
      test('part count $bad is a ParseFailure', () async {
        await expectLater(
          searchWith('partCount: $bad'),
          throwsA(isA<ParseFailure>()),
        );
      });
    }
  });

  group('listParts', () {
    final partsManifest = manifest(capabilities: ['listParts']);
    const parent = Track(
      ref: TrackRef(pluginId: 'demo', trackId: 'v1'),
      title: 'Whole video',
      author: 'Uploader',
      duration: Duration(minutes: 90),
      coverUrl: 'https://img.example.com/v1.jpg',
      coverLargeUrl: 'https://img.example.com/v1-large.jpg',
      playCount: 500,
      partCount: 2,
      url: 'https://www.example.com/v/v1',
    );

    Plugin listing(String result) => only(
      host('''
      export async function listParts({ trackId }) {
        return $result;
      }
    ''', manifestJson: partsManifest),
    );

    const twoParts = '''{ parts: [
      { id: 'v1', title: 'One', durationMs: 60000, url: 'https://www.example.com/v/v1' },
      { id: 'v1?p=2', title: 'Two', durationMs: 120000.4, url: 'https://www.example.com/v/v1?p=2' },
    ] }''';

    test('turns each part into a track of the same plugin, in order', () async {
      final parts = await listing(twoParts).listParts(parent);

      expect([for (final p in parts) p.ref.trackId], ['v1', 'v1?p=2']);
      expect([for (final p in parts) p.ref.pluginId], ['demo', 'demo']);
      expect([for (final p in parts) p.title], ['One', 'Two']);
      expect(
        [for (final p in parts) p.duration],
        [const Duration(minutes: 1), const Duration(minutes: 2)],
      );
      expect(
        [for (final p in parts) p.url],
        ['https://www.example.com/v/v1', 'https://www.example.com/v/v1?p=2'],
      );
    });

    test('a part keeps its own title, duration and url, but the '
        "parent's author and covers", () async {
      final part = (await listing(twoParts).listParts(parent)).last;

      expect(part.author, 'Uploader');
      expect(part.coverUrl, 'https://img.example.com/v1.jpg');
      expect(part.coverLargeUrl, 'https://img.example.com/v1-large.jpg');
      expect(part.playCount, isNull);
      expect(part.partCount, isNull);
    });

    test('duration and url are optional for a part', () async {
      final part = (await listing(
        "{ parts: [{ id: 'v1', title: 'One' }] }",
      ).listParts(parent)).single;

      expect(part.duration, isNull);
      expect(part.url, isNull);
    });

    test('gets the id of the track it lists the parts of', () async {
      final h = host('''
      export async function listParts({ trackId }) {
        return { parts: [{ id: trackId, title: 'T' }] };
      }
    ''', manifestJson: partsManifest);

      final parts = await only(h).listParts(parent);

      expect(parts.single.ref.trackId, 'v1');
    });

    test('a track of another plugin is an ArgumentError', () async {
      const other = Track(
        ref: TrackRef(pluginId: 'other', trackId: 'v1'),
        title: 'T',
        author: 'A',
      );
      await expectLater(
        listing(twoParts).listParts(other),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a plugin that does not declare it is Unsupported', () async {
      final h = host('', manifestJson: manifest());
      await expectLater(only(h).listParts(parent), throwsA(isA<Unsupported>()));
    });

    final bad = {
      'no parts': '{ parts: [] }',
      'duplicate ids':
          "{ parts: [{ id: 'a', title: 'A' }, { id: 'a', title: 'B' }] }",
      'a relative url': "{ parts: [{ id: 'a', title: 'A', url: '/v/a' }] }",
      'a non-web url':
          "{ parts: [{ id: 'a', title: 'A', url: 'ftp://x.example.com/a' }] }",
      'a url that is not a string':
          "{ parts: [{ id: 'a', title: 'A', url: 1 }] }",
      'a title that is not a string': '{ parts: [{ id: \'a\', title: 1 }] }',
      'an id that is not a string': "{ parts: [{ id: 1, title: 'A' }] }",
      'a duration that is not a number':
          "{ parts: [{ id: 'a', title: 'A', durationMs: 'x' }] }",
      'parts that is not a list': "{ parts: 'x' }",
    };
    for (final MapEntry(:key, :value) in bad.entries) {
      test('$key is a ParseFailure', () async {
        await expectLater(
          listing(value).listParts(parent),
          throwsA(isA<ParseFailure>()),
        );
      });
    }
  });

  group('trackInfo', () {
    final infoManifest = manifest(capabilities: ['trackInfo']);
    const ref = TrackRef(pluginId: 'demo', trackId: 'v1');

    Plugin describing(String result) => only(
      host('''
      export async function trackInfo({ trackId }) {
        return $result;
      }
    ''', manifestJson: infoManifest),
    );

    test('returns every field the plugin gives', () async {
      final info = await describing('''{
        album: 'Night Train',
        publishedAtMs: 1698939176000,
        playCount: 376272,
        likeCount: 3122,
        commentCount: 110,
        description: 'Line one\\nLine two',
      }''').trackInfo(ref);

      expect(info.album, 'Night Train');
      expect(
        info.publishedAt,
        DateTime.fromMillisecondsSinceEpoch(1698939176000, isUtc: true),
      );
      expect(info.playCount, 376272);
      expect(info.likeCount, 3122);
      expect(info.commentCount, 110);
      expect(info.description, 'Line one\nLine two');
    });

    test('every field is optional', () async {
      final info = await describing('{}').trackInfo(ref);

      expect(info.album, isNull);
      expect(info.publishedAt, isNull);
      expect(info.playCount, isNull);
      expect(info.likeCount, isNull);
      expect(info.commentCount, isNull);
      expect(info.description, isNull);
    });

    test('blank text counts as not given and text is trimmed', () async {
      final info = await describing(
        r"{ album: '  ', description: '\n About this track \n' }",
      ).trackInfo(ref);

      expect(info.album, isNull);
      expect(info.description, 'About this track');
    });

    test('gets the id of the track it describes', () async {
      final info = await describing('{ album: trackId }').trackInfo(ref);

      expect(info.album, 'v1');
    });

    test('a track of another plugin is an ArgumentError', () async {
      await expectLater(
        describing('{}')
            .trackInfo(const TrackRef(pluginId: 'other', trackId: 'v1')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a plugin that does not declare it is Unsupported', () async {
      final h = host('', manifestJson: manifest());
      await expectLater(only(h).trackInfo(ref), throwsA(isA<Unsupported>()));
    });

    final bad = {
      'a negative play count': '{ playCount: -1 }',
      'a fractional like count': '{ likeCount: 1.5 }',
      'a comment count that is not a number': "{ commentCount: '3' }",
      'an infinite play count': '{ playCount: Infinity }',
      'a publish time that is not a number': "{ publishedAtMs: '2026' }",
      'a fractional publish time': '{ publishedAtMs: 1.5 }',
      'an album that is not a string': '{ album: 1 }',
      'a description that is not a string': '{ description: [] }',
      'a result that is not an object': "'x'",
    };
    for (final MapEntry(:key, :value) in bad.entries) {
      test('$key is a ParseFailure', () async {
        await expectLater(
          describing(value).trackInfo(ref),
          throwsA(isA<ParseFailure>()),
        );
      });
    }
  });

  test('pluginFor finds the plugin that provides a track', () {
    final h = PluginHost(
      bundles: [
        PluginBundle(
          manifest: manifest(id: 'one'),
          code: '',
        ),
        PluginBundle(
          manifest: manifest(id: 'two'),
          code: '',
        ),
      ],
      log: log,
    );
    hosts.add(h);

    TrackRef from(String pluginId) =>
        TrackRef(pluginId: pluginId, trackId: 'x');
    expect(h.pluginFor(from('two'))?.manifest.id, 'two');
    expect(h.pluginFor(from('three')), isNull);
  });

  group('resolveStream', () {
    String resolving(String result) =>
        '''
      export async function resolveStream({ trackId }) {
        return $result;
      }
    ''';
    final resolveManifest = manifest(capabilities: ['resolveStream']);
    const a1 = TrackRef(pluginId: 'demo', trackId: 'a1');

    test('returns the stream the plugin resolves for the track id', () async {
      final h = host(
        resolving('''{
          url: 'https://cdn.example.com/a.m4a?track=' + trackId,
          headers: { Referer: 'https://example.com' },
          expiresAtMs: 1767225600000,
          codec: 'mp4a.40.2',
          bitrate: 132000,
        }'''),
        manifestJson: resolveManifest,
      );

      expect(
        await only(h).resolveStream(a1),
        AudioStream(
          url: Uri.parse('https://cdn.example.com/a.m4a?track=a1'),
          headers: const {'Referer': 'https://example.com'},
          expiresAt: DateTime.utc(2026),
          codec: 'mp4a.40.2',
          bitrate: 132000,
        ),
      );
    });

    test('a single-file fragmented MP4 says where its index is', () async {
      final h = host(
        resolving('''{
          url: 'https://cdn.example.com/a.m4s',
          segmentBase: { initialization: '0-836', indexRange: '837-9432' },
        }'''),
        manifestJson: resolveManifest,
      );

      expect(
        (await only(h).resolveStream(a1)).segmentBase,
        const SegmentBase(
          initialization: ByteRange(0, 836),
          index: ByteRange(837, 9432),
        ),
      );
    });

    test('headers, expiry, codec and bitrate are optional', () async {
      final h = host(
        resolving("{ url: 'https://cdn.example.com/a.m4a' }"),
        manifestJson: resolveManifest,
      );

      expect(
        await only(h).resolveStream(a1),
        AudioStream(url: Uri.parse('https://cdn.example.com/a.m4a')),
      );
    });

    for (final (name, result) in [
      ('no url', '{}'),
      ('a relative url', "{ url: '/a.m4a' }"),
      ('a non-http url', "{ url: 'file:///etc/passwd' }"),
      (
        'an expiry that is not a number',
        "{ url: 'https://a.example/x', expiresAtMs: NaN }",
      ),
      (
        'an expiry out of range',
        "{ url: 'https://a.example/x', expiresAtMs: 1e300 }",
      ),
      (
        'a bitrate that is not finite',
        "{ url: 'https://a.example/x', bitrate: Infinity }",
      ),
      (
        'a segment base without an index range',
        "{ url: 'https://a.example/x', "
            "segmentBase: { initialization: '0-836' } }",
      ),
      (
        'a segment base range that is not first-last',
        "{ url: 'https://a.example/x', "
            "segmentBase: { initialization: '0-836', indexRange: '9432-837' } }",
      ),
      (
        'a header that is not a string',
        "{ url: 'https://a.example/x', "
            'headers: { Referer: 1 } }',
      ),
    ]) {
      test('$name is a ParseFailure', () async {
        final h = host(resolving(result), manifestJson: resolveManifest);
        await expectLater(
          only(h).resolveStream(a1),
          throwsA(isA<ParseFailure>()),
        );
      });
    }

    test('a plugin that does not declare it is Unsupported', () async {
      final h = host(resolving("{ url: 'https://a.example/x' }"));
      await expectLater(only(h).resolveStream(a1), throwsA(isA<Unsupported>()));
    });

    test('a track of another plugin is a program error', () async {
      final h = host(
        resolving("{ url: 'https://a.example/x' }"),
        manifestJson: resolveManifest,
      );
      await expectLater(
        only(h).resolveStream(const TrackRef(pluginId: 'other', trackId: 'a1')),
        throwsArgumentError,
      );
    });
  });

  group('host network', () {
    // 插件抓 query 給的網址，把狀態碼與內文、或錯誤代碼放進標題回傳，
    // 看得到宿主交回什麼。
    const probe = '''
      export async function search({ query }) {
        let title;
        try {
          const res = await host.http.request({ url: query, headers: { 'X-Test': '1' } });
          title = res.status + ' ' + res.body;
        } catch (e) {
          title = 'error ' + e.code;
        }
        return { tracks: [{ id: '1', title, author: '' }] };
      }
    ''';

    Future<String> fetch(PluginHost h, String url) async =>
        (await only(h).search(url)).tracks.single.title;

    test('passes any status code and body back to the plugin', () async {
      final http = FakeHttp((_) => const FakeResponse(412, 'banned'));
      final h = host(probe, http: http);

      expect(await fetch(h, 'https://api.example.com/x'), '412 banned');
      expect(http.requests.single.headers['X-Test'], '1');
    });

    test(
      'rejects hosts the manifest does not declare, without connecting',
      () async {
        final http = FakeHttp((_) => const FakeResponse(200, 'ok'));
        final h = host(probe, http: http);

        expect(
          await fetch(h, 'https://evil.example.org/x'),
          'error domain_not_allowed',
        );
        expect(
          await fetch(h, 'https://example.com/x'),
          'error domain_not_allowed',
        );
        expect(await fetch(h, 'not a url'), 'error domain_not_allowed');
        expect(http.requests, isEmpty);
      },
    );

    test('rejects other ports on a declared host', () async {
      final http = FakeHttp((_) => const FakeResponse(200, 'ok'));
      final h = host(probe, http: http);

      expect(
        await fetch(h, 'https://api.example.com:8443/x'),
        'error domain_not_allowed',
      );
      expect(await fetch(h, 'https://api.example.com:443/x'), '200 ok');
      expect(http.requests, hasLength(1));
    });

    test('rejects plain http even on a declared host', () async {
      final http = FakeHttp((_) => const FakeResponse(200, 'ok'));
      final h = host(probe, http: http);

      expect(
        await fetch(h, 'http://api.example.com/x'),
        'error domain_not_allowed',
      );
      expect(http.requests, isEmpty);
    });

    test('a *. domain covers subdomains but not the bare domain', () async {
      final http = FakeHttp((_) => const FakeResponse(200, 'ok'));
      final h = host(
        probe,
        manifestJson: manifest(domains: ['*.cdn.example.com']),
        http: http,
      );

      expect(await fetch(h, 'https://a.b.CDN.example.com/x'), '200 ok');
      expect(
        await fetch(h, 'https://cdn.example.com/x'),
        'error domain_not_allowed',
      );
      expect(
        await fetch(h, 'https://evilcdn.example.com/x'),
        'error domain_not_allowed',
      );
    });

    test('follows redirects only to declared hosts', () async {
      final http = FakeHttp(
        (request) => switch (request.uri.path) {
          '/start' => const FakeResponse(302, '', {
            'location': ['/next'],
          }),
          '/next' => const FakeResponse(301, '', {
            'location': ['https://evil.example.org/steal'],
          }),
          _ => const FakeResponse(200, 'should not get here'),
        },
      );
      final h = host(probe, http: http);

      expect(
        await fetch(h, 'https://api.example.com/start'),
        'error domain_not_allowed',
      );
      expect(http.requests.map((r) => r.uri.toString()), [
        'https://api.example.com/start',
        'https://api.example.com/next',
      ]);
    });

    test('a connection failure reaches the plugin as network, and the caller '
        'as NetworkError when the plugin lets it through', () async {
      final http = FakeHttp(
        (request) => throw DioException.connectionError(
          requestOptions: request,
          reason: 'offline',
        ),
      );
      final h = host(probe, http: http);
      expect(await fetch(h, 'https://api.example.com/x'), 'error network');

      final passthrough = host(
        '''
        export async function search() {
          await host.http.request({ url: 'https://api.example.com/x' });
        }
      ''',
        manifestJson: manifest(id: 'other'),
        http: http,
      );
      await expectLater(
        only(passthrough).search('q'),
        throwsA(isA<NetworkError>()),
      );
    });

    test('logs requests and failures through the redacting log', () async {
      final http = FakeHttp(
        (request) => request.uri.path == '/down'
            ? throw DioException.connectionTimeout(
                requestOptions: request,
                timeout: const Duration(seconds: 1),
              )
            : const FakeResponse(200, 'ok'),
      );
      final h = host(probe, http: http);
      await fetch(h, 'https://api.example.com/ok?q=hi&access_token=s3cret');
      await fetch(h, 'https://api.example.com/down');
      await fetch(h, 'https://evil.example.org/x');

      final text = await closeAndReadLog();
      expect(text, isNot(contains('s3cret')));
      expect(
        text,
        allOf(
          contains(
            'DEBUG plugin demo: GET '
            'https://api.example.com/ok?q=hi&access_token=*** -> 200',
          ),
          contains(
            'WARNING plugin demo: GET https://api.example.com/down '
            'failed: connectionTimeout',
          ),
          contains(
            'WARNING plugin demo: blocked a request to '
            'https://evil.example.org',
          ),
        ),
      );
    });
  });

  group('plugin errors', () {
    // brief〈錯誤、log 與診斷〉 的錯誤分類，對照 app/plugins/host.d.ts 的代碼。
    Matcher unavailable(UnavailableReason reason) =>
        isA<Unavailable>().having((e) => e.reason, 'reason', reason);
    final expected = <String, Matcher>{
      'network': isA<NetworkError>(),
      'rate_limited': isA<RateLimited>(),
      'login_required': isA<LoginRequired>(),
      'credential_invalid': isA<CredentialInvalid>(),
      'verification_required': isA<VerificationRequired>(),
      'unavailable_region': unavailable(UnavailableReason.region),
      'unavailable_copyright': unavailable(UnavailableReason.copyright),
      'unavailable_membership_required': unavailable(
        UnavailableReason.membershipRequired,
      ),
      'unavailable_trial_only': unavailable(UnavailableReason.trialOnly),
      'not_found': isA<NotFound>(),
      'parse_failure': isA<ParseFailure>(),
      'unsupported': isA<Unsupported>(),
      'domain_not_allowed': isA<Unsupported>(),
      'no_such_code': isA<ParseFailure>(),
    };

    for (final MapEntry(key: code, value: matcher) in expected.entries) {
      test('PluginError("$code") becomes the matching error class', () async {
        final h = host('''
          export async function search() {
            throw new PluginError('$code', 'details');
          }
        ''');
        await expectLater(only(h).search('q'), throwsA(matcher));
      });
    }

    test('the failure is logged with its code', () async {
      final h = host('''
        export async function search() {
          throw new PluginError('rate_limited', 'code -352');
        }
      ''');
      await expectLater(only(h).search('q'), throwsA(isA<RateLimited>()));

      expect(
        await closeAndReadLog(),
        contains(
          'WARNING plugin demo: search failed with rate_limited: code -352',
        ),
      );
    });

    test('an exception without a code becomes ParseFailure', () async {
      final h = host('''
        export async function search() { return null.tracks; }
      ''');
      await expectLater(only(h).search('q'), throwsA(isA<ParseFailure>()));
    });

    test('a result of the wrong shape becomes ParseFailure', () async {
      final h = host('''
        export async function search() { return { tracks: [{ id: 1 }] }; }
      ''');
      await expectLater(only(h).search('q'), throwsA(isA<ParseFailure>()));
    });

    test('a capability the manifest does not declare is Unsupported, even if '
        'the code exports it', () async {
      final h = host('''
        export async function search() { return { tracks: [] }; }
      ''', manifestJson: manifest(capabilities: ['lyrics-someday']));

      expect(only(h).manifest.capabilities, isEmpty);
      await expectLater(only(h).search('q'), throwsA(isA<Unsupported>()));
    });

    test(
      'a declared capability the code does not export is Unsupported',
      () async {
        final h = host('export const nothing = 1;');
        await expectLater(only(h).search('q'), throwsA(isA<Unsupported>()));
      },
    );
  });

  test('a call that hangs times out as ParseFailure, and the next call runs '
      'on a fresh engine', () async {
    final h = host('''
      export async function search({ query }) {
        if (query === 'hang') while (true) {}
        return { tracks: [] };
      }
    ''', callTimeout: const Duration(milliseconds: 500));

    await expectLater(only(h).search('hang'), throwsA(isA<ParseFailure>()));
    expect((await only(h).search('ok')).tracks, isEmpty);
    expect(
      await closeAndReadLog(),
      contains('search timed out after 500ms; restarting its engine'),
    );
  });

  test('a call cancelled by a timeout does not close the engine a newer call '
      'has started', () async {
    // A 卡住逾時、關掉引擎（引擎先清掉，再等 close()）。同一個引擎上排著
    // 的 B 接著也失敗：被 close() 取消，或自己的逾時先到。B 寫完 log、還沒
    // 去關引擎的那一刻 C 進來建了新引擎：B 不能把 C 的新引擎關掉。C 在 B
    // 寫 log 的同步段裡發出，時序是固定的。
    final hooked = _HookedLog(log);
    late final Plugin plugin;
    var failures = 0;
    Future<SearchResults>? c;
    hooked.onWarningOrError = (message) {
      final failed =
          message.contains('search timed out') ||
          message.contains('search failed in the engine');
      // 第一筆是 A 的逾時：B 只會在 A 關引擎之後失敗。
      if (failed && ++failures == 2) c = plugin.search('ok');
    };
    final h = PluginHost(
      bundles: [
        PluginBundle(
          manifest: manifest(),
          code: '''
            export async function search({ query }) {
              if (query === 'hang') while (true) {}
              return { tracks: [] };
            }
          ''',
        ),
      ],
      log: hooked,
      callTimeout: const Duration(milliseconds: 500),
    );
    hosts.add(h);
    plugin = only(h);

    final a = only(h).search('hang');
    final b = only(h).search('hang');
    await Future.wait([
      expectLater(a, throwsA(isA<ParseFailure>())),
      expectLater(b, throwsA(isA<ParseFailure>())),
    ]);

    expect(c, isNotNull, reason: 'B failed after A closed the engine');
    expect((await c)!.tracks, isEmpty);
  });

  group('source mark', () {
    Map<String, Object?> mark({Object? paths}) => {
      'short': 'Dm',
      'color': '#FB7299',
      'paths':
          paths ??
          [
            {
              'pathData': 'M5 1.8 6.6 3.9',
              'strokeColor': '#FB7299',
              'strokeWidth': 1.5,
            },
            {'pathData': 'M1 1h14v14H1z', 'fillColor': '#ffffff'},
          ],
    };

    PluginManifest? parsed(Object? markJson) {
      final h = PluginHost(
        bundles: [
          PluginBundle(
            manifest: manifest(mark: markJson),
            code: '',
          ),
        ],
        log: log,
      );
      hosts.add(h);
      return h.plugins.firstOrNull?.manifest;
    }

    test('the manifest gives the short name, colour and the paths to draw', () {
      final m = parsed(mark())!.mark!;

      expect(m.short, 'Dm');
      expect(m.color, 0xFFFB7299);
      expect(m.paths, hasLength(2));
      expect(m.paths[0].pathData, 'M5 1.8 6.6 3.9');
      expect(m.paths[0].strokeColor, 0xFFFB7299);
      expect(m.paths[0].strokeWidth, 1.5);
      expect(m.paths[0].fillColor, isNull);
      expect(m.paths[1].fillColor, 0xFFFFFFFF);
      expect(m.paths[1].strokeColor, isNull);
    });

    test('a plugin without a mark has none', () {
      expect(parsed(null)!.mark, isNull);
    });

    for (final (name, bad) in [
      ('a colour that is not #RRGGBB', {...mark(), 'color': 'pink'}),
      ('a missing short name', {...mark()}..remove('short')),
      (
        'path data that does not parse',
        mark(
          paths: [
            {'pathData': 'M5 Q', 'fillColor': '#000000'},
          ],
        ),
      ),
      (
        'a path with neither fill nor stroke',
        mark(
          paths: [
            {'pathData': 'M1 1h2'},
          ],
        ),
      ),
      (
        'a stroke without a width',
        mark(
          paths: [
            {'pathData': 'M1 1h2', 'strokeColor': '#000000'},
          ],
        ),
      ),
      ('no paths', mark(paths: <Object>[])),
    ]) {
      test('a mark with $name skips the plugin', () {
        expect(parsed(bad), isNull);
      });
    }
  });

  test(
    'plugins with a bad or duplicate manifest are skipped and logged',
    () async {
      final h = PluginHost(
        bundles: [
          PluginBundle(
            manifest: manifest(id: 'good'),
            code: '',
          ),
          const PluginBundle(manifest: '{"id": "no-domains"}', code: ''),
          PluginBundle(
            manifest: manifest(id: 'Bad Id'),
            code: '',
          ),
          PluginBundle(
            manifest: manifest(domains: ['https://x.com']),
            code: '',
          ),
          PluginBundle(
            manifest: manifest(id: 'good'),
            code: '',
          ),
          const PluginBundle(manifest: 'not json', code: ''),
        ],
        log: log,
      );
      hosts.add(h);

      expect(h.plugins.map((p) => p.manifest.id), ['good']);
      expect(
        'Skipped a plugin with a bad manifest'.allMatches(
          await closeAndReadLog(),
        ),
        hasLength(5),
      );
    },
  );
}

/// 照原樣轉給 [inner]；[onWarningOrError] 讓測試在宿主寫 warning 或 error log 的
/// 同步段裡插進別的呼叫。
class _HookedLog implements Log {
  _HookedLog(this.inner);

  final Log inner;
  void Function(String message)? onWarningOrError;

  @override
  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      inner.debug(message, error: error, stackTrace: stackTrace);

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      inner.info(message, error: error, stackTrace: stackTrace);

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    inner.warning(message, error: error, stackTrace: stackTrace);
    onWarningOrError?.call(message);
  }

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    inner.error(message, error: error, stackTrace: stackTrace);
    onWarningOrError?.call(message);
  }

  @override
  Future<void> close() => inner.close();
}
