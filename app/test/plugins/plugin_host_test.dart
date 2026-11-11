import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
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
  }) => jsonEncode({
    'id': id,
    'name': 'Demo',
    'version': '1.0.0',
    'capabilities': capabilities,
    'domains': domains,
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

      final tracks = await only(h).search('中文 query');

      expect(tracks, [
        const Track(
          source: 'demo',
          id: 'a1',
          title: 'Song A / 中文 query',
          author: 'Alice',
          duration: Duration(seconds: 61),
        ),
      ]);
      expect(http.requests.single.method, 'GET');
    },
  );

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
        (await only(h).search(url)).single.title;

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
    // brief §13 的錯誤分類，對照 app/plugins/host.d.ts 的代碼。
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

  test('a call that hangs times out as NetworkError, and the next call runs '
      'on a fresh engine', () async {
    final h = host('''
      export async function search({ query }) {
        if (query === 'hang') while (true) {}
        return { tracks: [] };
      }
    ''', callTimeout: const Duration(milliseconds: 500));

    await expectLater(only(h).search('hang'), throwsA(isA<NetworkError>()));
    expect(await only(h).search('ok'), isEmpty);
    expect(
      await closeAndReadLog(),
      contains('search timed out after 500ms; restarting its engine'),
    );
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
