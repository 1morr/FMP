import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/core/redaction/redact.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';

import 'fake_http.dart';
import 'fjs.dart';
import 'plugin_fixtures.dart';

/// 契約測試的工具（`plugin_fixtures.dart`）自己的測試：小插件的 JS 寫在
/// 這裡，跑在真的 fjs 引擎裡。
void main() {
  late Directory logDir;
  late Log log;

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_plugin_fixtures_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
  });
  tearDown(() async {
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  final manifest = jsonEncode({
    'id': 'demo',
    'name': 'Demo',
    'version': '1.0.0',
    'capabilities': ['search'],
    'domains': ['api.example.com'],
  });

  /// 搜尋時依序 GET [urls]，把最後一個回應的 JSON 當結果。
  PluginBundle searching(List<String> urls) => PluginBundle(
    manifest: manifest,
    code:
        '''
export async function search({ query }) {
  let res;
  for (const url of ${jsonEncode(urls)}) {
    res = await host.http.request({ url: url + encodeURIComponent(query) });
  }
  return JSON.parse(res.body);
}
''',
  );

  String tracks(List<Map<String, Object?>> tracks) =>
      jsonEncode({'tracks': tracks});

  final oneTrack = tracks([
    {'id': 'a1', 'title': 'Lemon', 'author': 'Someone', 'durationMs': 1000},
  ]);

  PluginFixture fixture(List<(String url, String body)> responses) =>
      PluginFixture(
        input: {'query': 'lemon'},
        interactions: [
          for (final (url, body) in responses)
            Interaction(
              method: 'GET',
              url: url,
              status: 200,
              headers: const {'content-type': 'application/json'},
              body: body,
            ),
        ],
      );

  group('runContractCase', () {
    test('a plugin that keeps the contract has no problems', () async {
      final problems = await runContractCase(
        searching(['https://api.example.com/s?q=']),
        PluginCapability.search,
        fixture([('https://api.example.com/s?q=lemon', oneTrack)]),
        log: log,
      );
      expect(problems, isEmpty);
    });

    test('names the request that has no fixture', () async {
      final problems = await runContractCase(
        searching(['https://api.example.com/other?q=']),
        PluginCapability.search,
        fixture([('https://api.example.com/s?q=lemon', oneTrack)]),
        log: log,
      );
      // 插件因此丟的錯是同一個原因，不重複回報。
      expect(problems, [
        'no fixture for GET https://api.example.com/other?q=lemon',
        'unused fixture request GET https://api.example.com/s?q=lemon',
      ]);
    });

    test(
      'a recorded request the plugin no longer makes is a problem',
      () async {
        final problems = await runContractCase(
          searching(['https://api.example.com/s?q=']),
          PluginCapability.search,
          fixture([
            ('https://api.example.com/s?q=lemon', oneTrack),
            ('https://api.example.com/extra?q=lemon', oneTrack),
          ]),
          log: log,
        );
        expect(problems, [
          'unused fixture request GET https://api.example.com/extra?q=lemon',
        ]);
      },
    );

    test('each recorded request answers only once', () async {
      final problems = await runContractCase(
        searching([
          'https://api.example.com/s?q=',
          'https://api.example.com/s?q=',
        ]),
        PluginCapability.search,
        fixture([('https://api.example.com/s?q=lemon', oneTrack)]),
        log: log,
      );
      expect(
        problems,
        contains('no fixture for GET https://api.example.com/s?q=lemon'),
      );
    });

    test('a plugin error is a problem', () async {
      final problems = await runContractCase(
        PluginBundle(
          manifest: manifest,
          code:
              "export async function search() "
              "{ throw new PluginError('rate_limited'); }",
        ),
        PluginCapability.search,
        fixture([]),
        log: log,
      );
      expect(problems, [contains('search threw')]);
    });

    test('a result that breaks the contract is a problem', () async {
      final problems = await runContractCase(
        searching(['https://api.example.com/s?q=']),
        PluginCapability.search,
        fixture([('https://api.example.com/s?q=lemon', tracks([]))]),
        log: log,
      );
      expect(problems, ['search returned no tracks']);
    });

    test('an input of the wrong shape is a problem', () async {
      final problems = await runContractCase(
        searching(['https://api.example.com/s?q=']),
        PluginCapability.search,
        PluginFixture(input: {'q': 'lemon'}, interactions: const []),
        log: log,
      );
      expect(problems, [contains('"query"')]);
    });
  });

  group('searchContractViolations', () {
    Track track({
      String source = 'demo',
      String id = 'a1',
      String title = 'Lemon',
      Duration? duration,
    }) => Track(
      source: source,
      id: id,
      title: title,
      author: '',
      duration: duration,
    );

    test('accepts tracks without an author or a duration', () {
      expect(searchContractViolations('demo', [track()]), isEmpty);
      expect(
        searchContractViolations('demo', [
          track(duration: const Duration(milliseconds: 1)),
        ]),
        isEmpty,
      );
    });

    test('flags each broken field', () {
      expect(searchContractViolations('demo', []), [
        'search returned no tracks',
      ]);
      expect(
        searchContractViolations('demo', [
          track(),
          track(source: 'other', id: '', title: ' ', duration: Duration.zero),
        ]),
        [
          'track 1: source is "other"',
          'track 1: empty id',
          'track 1: empty title',
          'track 1: duration 0:00:00.000000 is not positive',
        ],
      );
    });
  });

  group('resolveStreamContractViolations', () {
    final url = Uri.parse('https://cdn.example.com/a.m4a');

    test('accepts a stream with only a url, or with every field', () {
      expect(resolveStreamContractViolations(AudioStream(url: url)), isEmpty);
      expect(
        resolveStreamContractViolations(
          AudioStream(
            url: url,
            headers: const {'Referer': 'https://example.com'},
            expiresAt: DateTime.utc(2026),
            codec: 'mp4a.40.2',
            bitrate: 1,
          ),
        ),
        isEmpty,
      );
    });

    test('flags each broken field', () {
      expect(
        resolveStreamContractViolations(
          AudioStream(
            url: url,
            headers: const {'': 'x'},
            expiresAt: DateTime.utc(1970),
            codec: ' ',
            bitrate: 0,
          ),
        ),
        [
          'empty header name',
          'expiresAt 1970-01-01 00:00:00.000Z is not after the epoch',
          'empty codec',
          'bitrate 0 is not positive',
        ],
      );
    });
  });

  group('RecordingHttp', () {
    test('keeps only redacted values and the headers the host reads', () async {
      final recording = RecordingHttp(
        FakeHttp(
          (_) => const FakeResponse(200, '{"access_token":"tok123","n":1}', {
            'content-type': ['application/json'],
            'set-cookie': ['SESSDATA=abc123'],
            'x-trace-ip': ['203.0.113.7'],
          }),
        ),
      );
      final problems = await runContract(
        searching(['https://api.example.com/s?sign=abc&q=']),
        PluginCapability.search,
        const {'query': 'lemon'},
        log: log,
        httpAdapter: recording,
      );
      // 回應不是曲目清單，契約不過；這裡只看錄下了什麼。
      expect(problems, isNotEmpty);

      final written = PluginFixture(
        input: const {'query': 'lemon'},
        interactions: recording.recorded,
      ).encode();
      expect(written, isNot(contains('tok123')));
      expect(written, isNot(contains('abc123')));
      expect(written, isNot(contains('203.0.113.7')));
      final interaction = PluginFixture.parse(written).interactions.single;
      expect(interaction.url, 'https://api.example.com/s?sign=***&q=***');
      expect(interaction.headers, {'content-type': 'application/json'});
      expect(interaction.body, '{"access_token":"***","n":1}');
      expect(unredactedValues(written), isEmpty);
    });

    test('hands the plugin the unredacted response', () async {
      final recording = RecordingHttp(
        FakeHttp((_) => FakeResponse(200, oneTrack)),
      );
      final problems = await runContract(
        searching(['https://api.example.com/s?q=']),
        PluginCapability.search,
        const {'query': 'lemon'},
        log: log,
        httpAdapter: recording,
      );
      expect(problems, isEmpty);
      expect(recording.recorded.single.body, oneTrack);
    });
  });

  group('unredactedValues', () {
    String fixtureJson({
      String url = 'https://api.example.com/s?q=lemon',
      Map<String, String> headers = const {'content-type': 'application/json'},
      String body = '{"code":0,"data":{"title":"Lemon"}}',
      Map<String, Object?> input = const {'query': 'lemon'},
    }) => PluginFixture(
      input: input,
      interactions: [
        Interaction(
          method: 'GET',
          url: url,
          status: 200,
          headers: headers,
          body: body,
        ),
      ],
    ).encode();

    test('a fixture with masked values stays green', () {
      expect(unredactedValues(fixtureJson()), isEmpty);
      expect(
        unredactedValues(
          fixtureJson(
            url: 'https://api.example.com/s?sign=***&q=***',
            headers: {'set-cookie': '***'},
            body: '{"access_token":"***","n":1}',
          ),
        ),
        isEmpty,
      );
    });

    test('formatting and unrelated names do not matter', () {
      final compact = jsonEncode(jsonDecode(fixtureJson()));
      expect(unredactedValues(compact), isEmpty);
      expect(
        unredactedValues(
          fixtureJson(
            input: {'keyword': 'design token'},
            body: '{"designer":"x","assign":"y","tokens_left":3}',
          ),
        ),
        isEmpty,
      );
    });

    test('turns red on a cookie value', () {
      expect(
        unredactedValues(fixtureJson(headers: {'set-cookie': 'SESSDATA=abc'})),
        [matches(RegExp(r'^line \d+$'))],
      );
    });

    test('turns red on a token in the body', () {
      expect(
        unredactedValues(fixtureJson(body: '{"data":{"access_token":"x1"}}')),
        ['interactions[0].response.body'],
      );
    });

    test('turns red on a signed URL', () {
      expect(
        unredactedValues(
          fixtureJson(url: 'https://cdn.example.com/a.m4s?e=1&sign=abc123'),
        ),
        contains('interactions[0].request.url'),
      );
    });

    test('turns red on a credential in the input', () {
      expect(
        unredactedValues(fixtureJson(input: {'query': 'x', 'token': 42})),
        isNotEmpty,
      );
    });
  });

  group('keepFields', () {
    const body = {
      'code': 0,
      'ttl': 1,
      'data': {
        'seid': '42',
        'result': [
          {'bvid': 'BV1', 'title': 'A', 'mid': 7, 'pic': '//x/1.jpg'},
          {'bvid': 'BV2', 'title': 'B', 'mid': 8},
        ],
      },
    };

    test('keeps only the listed paths, through lists, in order', () {
      expect(
        keepFields(body, ['code', 'data.result.bvid', 'data.result.title']),
        {
          'code': 0,
          'data': {
            'result': [
              {'bvid': 'BV1', 'title': 'A'},
              {'bvid': 'BV2', 'title': 'B'},
            ],
          },
        },
      );
    });

    test('a path to an object keeps all of it; missing paths are skipped', () {
      expect(keepFields(body, ['data.result', 'nope.x']), {
        'data': {'result': (body['data']! as Map)['result']},
      });
    });
  });

  group('untrimmedResponses', () {
    PluginFixture withBody(String body) => PluginFixture(
      input: const {'query': 'q'},
      interactions: [
        Interaction(
          method: 'GET',
          url: 'https://api.example.com/s',
          status: 200,
          headers: const {},
          body: body,
        ),
      ],
    );
    const keep = ['code', 'data.result.bvid'];

    test('a body with only the kept fields stays green, however formatted', () {
      expect(
        untrimmedResponses(
          withBody('{"code":0,"data":{"result":[{"bvid":"BV1"}]}}'),
          keep,
        ),
        isEmpty,
      );
      expect(
        untrimmedResponses(
          withBody(
            '{\n  "code": 0,\n  "data": {"result": [{"bvid": "BV1"}]}\n}',
          ),
          keep,
        ),
        isEmpty,
      );
    });

    test('turns red on a field the plugin does not read', () {
      expect(
        untrimmedResponses(
          withBody('{"code":0,"data":{"result":[{"bvid":"BV1","mid":7}]}}'),
          keep,
        ),
        ['interactions[0] keeps fields outside keep.json'],
      );
    });

    test('turns red on a body that is not JSON', () {
      expect(untrimmedResponses(withBody('<html>'), keep), [
        'interactions[0] body is not JSON, so it cannot be trimmed',
      ]);
    });

    test('trimmed() leaves a fixture that passes', () {
      final fixture = withBody(
        '{"code":0,"ttl":1,"data":{"result":[{"bvid":"BV1","mid":7}]}}',
      ).trimmed(keep);
      expect(
        fixture.interactions.single.body,
        '{"code":0,"data":{"result":[{"bvid":"BV1"}]}}',
      );
      expect(untrimmedResponses(fixture, keep), isEmpty);
    });

    test('a recorded signed URL in a body passes the secret check', () {
      // 票 10：B 站的 playurl 回應裡是簽名網址，`&` 寫成 JSON 跳脫；遮過、
      // 裁過、寫成檔之後，整份文字仍要是遮蔽函式的不動點。
      final body = redact(
        r'{"code":0,"data":{"dash":{"audio":[{"baseUrl":'
        r'"https://cdn.example.com/a.m4s?deadline=1&upsig=FAKE"}]}}}',
      );
      final written = PluginFixture(
        input: const {'trackId': 'BV1'},
        interactions: [
          Interaction(
            method: 'GET',
            url: 'https://api.example.com/play',
            status: 200,
            headers: const {},
            body: body,
          ),
        ],
      ).trimmed(['code', 'data.dash.audio.baseUrl']).encode();
      expect(written, isNot(contains('FAKE')));
      expect(unredactedValues(written), isEmpty);
    });
  });

  group('fixture discovery', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('fmp_plugins_'));
    tearDown(() => root.deleteSync(recursive: true));

    void write(String path, [String content = '{}']) =>
        File('${root.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(content);

    PluginDirectory onlyPlugin() => pluginDirectories(root).single;

    setUp(() {
      write('demo/manifest.json', manifest);
      write('demo/dist/plugin.js', '// code');
      write('demo/fixtures/keep.json', '{"search": ["code"]}');
      write('node_modules/x/index.js');
    });

    test('finds directories with a manifest and their bundles', () {
      final plugin = onlyPlugin();
      expect(plugin.id, 'demo');
      expect(plugin.manifest.capabilities, {PluginCapability.search});
      expect(plugin.bundle.code, '// code');
    });

    test('a declared capability without a fixture is a problem', () {
      expect(fixtureProblems(onlyPlugin()), [
        'demo declares search but has no fixtures/search/*.json',
      ]);
    });

    test(
      'a fixture directory that is not a declared capability is a problem',
      () {
        write('demo/fixtures/search/lemon.json');
        write('demo/fixtures/serch/lemon.json');
        expect(fixtureProblems(onlyPlugin()), [
          'demo has fixtures/serch but does not declare that capability',
        ]);
      },
    );

    test('reads the kept fields per capability from fixtures/keep.json', () {
      write('demo/fixtures/keep.json', '{"search": ["code", "data.x"]}');
      write('demo/fixtures/search/lemon.json');
      expect(keptFields(onlyPlugin()), {
        PluginCapability.search: ['code', 'data.x'],
      });
      expect(fixtureProblems(onlyPlugin()), isEmpty);
    });

    test('a declared capability without kept fields is a problem', () {
      write('demo/fixtures/search/lemon.json');
      write('demo/fixtures/keep.json', '{}');
      expect(fixtureProblems(onlyPlugin()), [
        'demo declares search but fixtures/keep.json does not list its fields',
      ]);
    });

    test('lists each declared capability with its cases, sorted', () {
      write('demo/fixtures/search/b.json');
      write('demo/fixtures/search/a.json');
      write('demo/fixtures/search/notes.md');
      final plugin = onlyPlugin();
      expect(fixtureProblems(plugin), isEmpty);
      expect(
        {
          for (final MapEntry(:key, :value) in fixtureFiles(plugin).entries)
            key: [for (final f in value) f.uri.pathSegments.last],
        },
        {
          PluginCapability.search: ['a.json', 'b.json'],
        },
      );
    });
  });
}
