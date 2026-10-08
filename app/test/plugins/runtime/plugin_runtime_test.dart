import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/runtime/worker_protocol.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/plugins/source_plugin.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/pump_until.dart';
import '../plugin_harness.dart';

/// QuickJS 的標準內建（ES2020，QuickJS 的 `JS_NewContext`；沒有 BigInt）。
const _builtIns = {
  'AggregateError', 'Array', 'ArrayBuffer', 'Boolean', 'DataView', 'Date', //
  'Error', 'EvalError', 'Float32Array', 'Float64Array', 'Function',
  'Infinity', 'Int16Array', 'Int32Array', 'Int8Array', 'InternalError',
  'JSON', 'Map', 'Math', 'NaN', 'Number', 'Object', 'Promise', 'Proxy',
  'RangeError', 'ReferenceError', 'Reflect', 'RegExp', 'Set',
  'SharedArrayBuffer', 'String', 'Symbol', 'SyntaxError', 'TypeError',
  'URIError', 'Uint16Array', 'Uint32Array', 'Uint8Array',
  'Uint8ClampedArray', 'WeakMap', 'WeakSet', '__date_clock', 'decodeURI',
  'decodeURIComponent', 'encodeURI', 'encodeURIComponent', 'escape', 'eval',
  'globalThis', 'isFinite', 'isNaN', 'parseFloat', 'parseInt', 'undefined',
  'unescape',
};

void main() {
  group('engine', () {
    test('runs an ES module in QuickJS and returns JSON', () async {
      final runtime = await PluginHarness().runtime('''
export function echo(value) { return { echoed: value, sum: 1 + 2 }; }
export const notAFunction = 1;
''');

      expect(runtime.exports, {'echo'});
      expect(await runtime.invoke('echo', {'a': 'b'}), {
        'echoed': {'a': 'b'},
        'sum': 3,
      });
    });

    test('the global object has only the built-ins, fmp and console', () async {
      final runtime = await PluginHarness().runtime('''
export function globals() { return Object.getOwnPropertyNames(globalThis); }
''');

      final names = (await runtime.invoke('globals', null) as List).toSet();

      // flutter_js 自己的 setTimeout、sendMessage、fetch 都不在。
      expect(names.difference(_builtIns), {'fmp', 'console'});
    });

    test('fmp cannot be replaced or changed', () async {
      final runtime = await PluginHarness().runtime('''
export function tamper() {
  const results = [];
  for (const attempt of [
    () => { globalThis.fmp = {}; },
    () => { fmp.http = {}; },
    () => { fmp.http.request = () => 1; },
  ]) {
    try { attempt(); results.push('changed'); } catch (e) { results.push(e.name); }
  }
  return results;
}
''');

      expect(await runtime.invoke('tamper', null), [
        'TypeError',
        'TypeError',
        'TypeError',
      ]);
    });

    test('runtimes do not share globals', () async {
      final harness = PluginHarness();
      final a = await harness.runtime('''
export function set() { globalThis.secret = 'a'; return typeof secret; }
''');
      final b = await harness.runtime('''
export function get() { return typeof secret; }
''', pluginId: 'plugin-b');

      expect(await a.invoke('set', null), 'string');
      expect(await b.invoke('get', null), 'undefined');
    });

    test('a plugin cannot import other modules', () async {
      final runtime = await PluginHarness().runtime('''
export async function load(name) {
  try { await import(name); return 'loaded'; } catch (e) { return 'rejected'; }
}
''');

      expect(await runtime.invoke('load', 'fmp-host'), 'rejected');
      expect(await runtime.invoke('load', './other.js'), 'rejected');
    });

    test('invoking a function that is not exported is a bug', () async {
      final runtime = await PluginHarness().runtime('export function a() {}');

      expect(() => runtime.invoke('b', null), throwsArgumentError);
    });

    test('an argument that is not JSON leaves no call waiting', () async {
      final runtime = await PluginHarness().runtime('export function a() {}');

      await expectLater(
        runtime.invoke('a', Object()),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      // 留下等結果的呼叫的話，dispose 會讓它以沒人接的錯誤結束。
      runtime.dispose();
      await settle();
    });
  });

  group('host API', () {
    test('http.request goes through the network layer', () async {
      final harness = PluginHarness(
        handler: (options) => reply(
          200,
          body: '{"q":"${options.uri.queryParameters['q']}"}',
          headers: {'Content-Type': 'application/json'},
        ),
      );
      final runtime = await harness.runtime('''
export async function fetchIt() {
  const response = await fmp.http.request({
    url: 'https://api.example.test/search?q=tone',
    headers: { Referer: 'https://example.test/' },
  });
  return {
    status: response.status,
    body: JSON.parse(response.body),
    contentType: response.headers['content-type'],
  };
}
''');

      expect(await runtime.invoke('fetchIt', null), {
        'status': 200,
        'body': {'q': 'tone'},
        'contentType': ['application/json'],
      });
      final sent = harness.adapter.requests.single;
      expect(sent.method, 'GET');
      expect(sent.headers['Referer'], 'https://example.test/');
      final record = harness.records(networkLogTag).single;
      expect(record.fields['pluginId'], 'plugin-a');
    });

    test('http.request passes idempotent on to the retry decision', () async {
      var calls = 0;
      final harness = PluginHarness(
        handler: (options) => ++calls % 2 == 1
            ? throw DioException.connectionError(
                requestOptions: options,
                reason: 'refused',
              )
            : reply(200),
      );
      final runtime = await harness.runtime('''
export async function marked() {
  const response = await fmp.http.request({
    url: 'https://example.test/', method: 'POST', idempotent: true,
  });
  return response.status;
}
export async function unmarked() {
  try {
    await fmp.http.request({ url: 'https://example.test/', method: 'POST' });
    return 'ok';
  } catch (e) {
    return e.fmpError;
  }
}
export async function badType() {
  try {
    await fmp.http.request({ url: 'https://example.test/', idempotent: 'yes' });
    return 'ok';
  } catch (e) {
    return e.name;
  }
}
''');

      expect(await runtime.invoke('marked', null), 200);
      expect(harness.adapter.requests, hasLength(2));
      harness.adapter.requests.clear();
      calls = 0;
      expect(await runtime.invoke('unmarked', null), 'NetworkError');
      expect(harness.adapter.requests, hasLength(1));
      expect(await runtime.invoke('badType', null), 'TypeError');
    });

    test('a host outside the manifest is refused without a request', () async {
      final harness = PluginHarness();
      final runtime = await harness.runtime('''
export async function leak() {
  await fmp.http.request({ url: 'https://evil.test/' });
}
export async function caught() {
  try {
    await fmp.http.request({ url: 'https://evil.test/' });
  } catch (e) {
    return [e.fmpError, e instanceof Error];
  }
}
''');

      await expectLater(
        runtime.invoke('leak', null),
        throwsA(isA<Unsupported>()),
      );
      expect(await runtime.invoke('caught', null), ['Unsupported', true]);
      expect(harness.adapter.requests, isEmpty);
    });

    test('a host error thrown on keeps its network record', () async {
      final harness = PluginHarness(
        handler: (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'refused',
        ),
      );
      final runtime = await harness.runtime('''
export async function fetchIt() {
  await fmp.http.request({ url: 'https://example.test/' });
}
''');

      final error = await runtime
          .invoke('fetchIt', null)
          .then<AppError>(
            (_) => fail('expected an error'),
            onError: (Object error) => error as AppError,
          );

      expect(error, isA<NetworkError>());
      expect(error.pluginId, 'plugin-a');
      // 預設重試兩次；帶的是最後一次送出的紀錄 id。
      expect(
        error.networkRecordId,
        harness.records(networkLogTag).last.fields['id'],
      );
    });

    test('storage belongs to one plugin', () async {
      final harness = PluginHarness();
      const script = '''
export async function write(value) { await fmp.storage.set('k', value); }
export async function read() { return fmp.storage.get('k'); }
export async function remove() { await fmp.storage.delete('k'); }
''';
      final a = await harness.runtime(script);
      final b = await harness.runtime(script, pluginId: 'plugin-b');

      await a.invoke('write', 'from a');
      expect(await a.invoke('read', null), 'from a');
      expect(await b.invoke('read', null), isNull);
      expect(await harness.storage.read('plugin-a', 'k'), 'from a');
      expect(await harness.storage.read('plugin-b', 'k'), isNull);

      await a.invoke('remove', null);
      expect(await a.invoke('read', null), isNull);
    });

    test('crypto hashes the UTF-8 bytes to lowercase hex', () async {
      final runtime = await PluginHarness().runtime('''
export function hashes() {
  return [fmp.crypto.md5(''), fmp.crypto.md5('中文'), fmp.crypto.sha256('abc')];
}
''');

      expect(await runtime.invoke('hashes', null), [
        'd41d8cd98f00b204e9800998ecf8427e',
        'a7bac2239fcdcb3a067903d8077c4a07',
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      ]);
    });

    group('credentials', () {
      const read = '''
export async function credentials() { return fmp.credentials.get(); }
''';

      Account account(
        String id, [
        AccountStatus status = AccountStatus.active,
      ]) => Account(
        pluginId: id,
        userId: 'u',
        displayName: 'Someone',
        status: status,
        loggedInAt: DateTime.utc(2026, 10, 9),
      );

      test('are null before a login', () async {
        final runtime = await PluginHarness().runtime(read);

        expect(await runtime.invoke('credentials', null), isNull);
      });

      test(
        'are the plugin\'s own FmpLoginCredentials once logged in',
        () async {
          final harness = PluginHarness();
          await harness.install('plugin-b');
          await harness.credentials.save(
            account('plugin-a'),
            const LoginCredentials(
              cookies: {'SESSDATA': 'FAKE_SESSDATA_A'},
              extra: {'refresh_token': 'FAKE_REFRESH_A'},
            ),
          );
          await harness.credentials.save(
            account('plugin-b'),
            const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA_B'}),
          );
          final runtime = await harness.runtime(read);

          expect(await runtime.invoke('credentials', null), {
            'cookies': {'SESSDATA': 'FAKE_SESSDATA_A'},
            'extra': {'refresh_token': 'FAKE_REFRESH_A'},
          });
        },
      );

      test('are null once invalidated', () async {
        final harness = PluginHarness();
        await harness.credentials.save(
          account('plugin-a', AccountStatus.invalidated),
          const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA_A'}),
        );
        final runtime = await harness.runtime(read);

        expect(await runtime.invoke('credentials', null), isNull);
      });
    });

    group('http.request with credentials', () {
      const script = '''
export async function call(args) {
  const response = await fmp.http.request({
    url: 'https://example.test/',
    auth: args.auth,
    authHeaders: { 'X-Custom-Auth': 'FAKE_HASH_VALUE_1' },
  });
  return response.credentialsAttached;
}
''';

      Future<PluginHarness> loggedIn() async {
        final harness = PluginHarness();
        await harness.install('plugin-a');
        await harness.credentials.save(
          Account(
            pluginId: 'plugin-a',
            userId: 'u',
            displayName: 'Someone',
            status: AccountStatus.active,
            loggedInAt: DateTime.utc(2026, 10, 9),
          ),
          const LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA_A'}),
        );
        return harness;
      }

      test('authHeaders and credentials only go out when attached', () async {
        final harness = await loggedIn();
        final runtime = await harness.runtime(script, installed: false);

        expect(
          await runtime.invoke('call', {'auth': 'userPreference'}),
          isTrue,
        );
        var sent = harness.adapter.requests.last;
        expect(sent.headers['cookie'], 'SESSDATA=FAKE_SESSDATA_A');
        expect(sent.headers['X-Custom-Auth'], 'FAKE_HASH_VALUE_1');

        expect(await runtime.invoke('call', {'auth': 'never'}), isFalse);
        sent = harness.adapter.requests.last;
        expect(sent.headers['cookie'], isNull);
        expect(sent.headers['X-Custom-Auth'], isNull);
      });

      test('the authHeaders names join the redaction list', () async {
        final harness = await loggedIn();
        final runtime = await harness.runtime(script, installed: false);
        // 名稱不在內建名單裡：用過之後才遮。
        expect(
          harness.redactor.redact('x-custom-auth: FAKE_HASH_VALUE_1'),
          contains('FAKE_HASH_VALUE_1'),
        );

        await runtime.invoke('call', {'auth': 'userPreference'});

        expect(
          harness.redactor.redact('x-custom-auth: FAKE_HASH_VALUE_1'),
          isNot(contains('FAKE_HASH_VALUE_1')),
        );
      });

      test('a mistyped authHeaders is a TypeError', () async {
        final harness = PluginHarness();
        final runtime = await harness.runtime('''
export async function call() {
  try {
    await fmp.http.request({ url: 'https://example.test/', authHeaders: { a: 1 } });
    return 'ok';
  } catch (e) {
    return e.name;
  }
}
''');

        expect(await runtime.invoke('call', null), 'TypeError');
        expect(harness.adapter.requests, isEmpty);
      });
    });

    test(
      'log and console write through the facade, tagged with the id',
      () async {
        final harness = PluginHarness();
        final runtime = await harness.runtime('''
export function logIt() {
  fmp.log.info('searching', { page: 2 });
  fmp.log.warn('slow');
  console.log('value', { a: 1 }, 3);
  console.error('bad');
}
''');

        await runtime.invoke('logIt', null);

        final records = harness.records('plugin-a');
        expect(
          [for (final r in records) (r.level, r.message)],
          [
            (LogLevel.info, 'searching'),
            (LogLevel.warning, 'slow'),
            (LogLevel.debug, 'value {"a":1} 3'),
            (LogLevel.error, 'bad'),
          ],
        );
        expect(records.first.fields, {'page': 2});
      },
    );

    test('plugin logs are redacted', () async {
      final harness = PluginHarness();
      final runtime = await harness.runtime('''
export function logIt() { fmp.log.info('cookie SESSDATA=FAKE_SESSDATA_123'); }
''');

      await runtime.invoke('logIt', null);

      expect(
        harness.records('plugin-a').single.message,
        isNot(contains('FAKE_SESSDATA_123')),
      );
    });

    test('bad arguments throw a TypeError in the script', () async {
      final runtime = await PluginHarness().runtime('''
export async function misuse() {
  const results = [];
  for (const attempt of [
    () => fmp.storage.get(1),
    () => fmp.http.request({ url: 'https://example.test/', verb: 'GET' }),
    () => fmp.http.request({ url: 'https://example.test/', auth: 'always' }),
    () => fmp.crypto.md5(),
    () => fmp.http.request(function () {}),
  ]) {
    try { await attempt(); results.push('ok'); } catch (e) { results.push(e.name); }
  }
  return results;
}
''');

      expect(await runtime.invoke('misuse', null), [
        'TypeError',
        'TypeError',
        'TypeError',
        'TypeError',
        'TypeError',
      ]);
    });
  });

  group('errors', () {
    Future<AppError> thrown(String throwStatement) async {
      final runtime = await PluginHarness().runtime('''
export async function fail() { $throwStatement }
''');
      return runtime
          .invoke('fail', null)
          .then<AppError>(
            (_) => fail('expected an error'),
            onError: (Object error) => error as AppError,
          );
    }

    for (final (name, matcher) in [
      ('NetworkError', isA<NetworkError>()),
      ('RateLimited', isA<RateLimited>()),
      ('AuthRequired', isA<AuthRequired>()),
      ('CredentialInvalid', isA<CredentialInvalid>()),
      ('VerificationRequired', isA<VerificationRequired>()),
      ('NotFound', isA<NotFound>()),
      ('ParseError', isA<ParseError>()),
      ('Unsupported', isA<Unsupported>()),
      ('UnexpectedError', isA<UnexpectedError>()),
    ]) {
      test('a structured $name becomes that AppError', () async {
        final error = await thrown("throw { fmpError: '$name' };");

        expect(error, matcher);
        expect(error.pluginId, 'plugin-a');
      });
    }

    test('RateLimited carries retryAfterSeconds', () async {
      final error = await thrown(
        "throw { fmpError: 'RateLimited', retryAfterSeconds: 2.5 };",
      );

      expect(error, isA<RateLimited>());
      expect(error.retryAfter, const Duration(milliseconds: 2500));
    });

    test('a retryAfterSeconds too large for Duration is capped', () async {
      final error = await thrown(
        "throw { fmpError: 'RateLimited', retryAfterSeconds: 1e300 };",
      );

      // 不能溢位成負的等待；上限與 parseRetryAfter 相同。
      expect(error.retryAfter, const Duration(days: 36500));
    });

    test('Unavailable carries its reason', () async {
      final error = await thrown(
        "throw Object.assign(new Error('blocked'), "
        "{ fmpError: 'Unavailable', reason: 'copyright' });",
      );

      expect(
        error,
        isA<Unavailable>().having(
          (e) => e.reason,
          'reason',
          UnavailableReason.copyright,
        ),
      );
    });

    for (final (description, statement) in [
      ('an unknown fmpError', "throw { fmpError: 'Teapot' };"),
      ('Unavailable without a reason', "throw { fmpError: 'Unavailable' };"),
      ('a TypeError', 'null.x;'),
      ('a thrown string', "throw 'boom';"),
    ]) {
      test('$description becomes UnexpectedError', () async {
        expect(await thrown(statement), isA<UnexpectedError>());
      });
    }

    test('the thrown message and JS stack reach the log only', () async {
      final harness = PluginHarness();
      final runtime = await harness.runtime('''
export async function fail() { throw new RangeError('page out of range'); }
''');

      final error = await runtime
          .invoke('fail', null)
          .then<AppError>(
            (_) => fail('expected an error'),
            onError: (Object error) => error as AppError,
          );
      harness.log.report('Search failed', error, tag: 'test');

      expect(error.toString(), isNot(contains('page out of range')));
      final record = harness.records('test').single;
      expect(record.error, contains('RangeError: page out of range'));
      expect(record.error, contains('fail'));
    });

    test('a return value that is not JSON is a ParseError', () async {
      final runtime = await PluginHarness().runtime('''
export function cyclic() { const a = {}; a.self = a; return a; }
''');

      await expectLater(
        runtime.invoke('cyclic', null),
        throwsA(isA<ParseError>()),
      );
    });

    test('a script that breaks JSON fails the call, not the plugin', () async {
      final runtime = await PluginHarness().runtime('''
export function poison() {
  Object.prototype.toJSON = function () { throw new Error('poisoned'); };
  return 1;
}
''');

      await expectLater(
        runtime.invoke('poison', null),
        throwsA(isA<UnexpectedError>()),
      );
      // 回不了話是這次呼叫的錯誤，不是背景 isolate 當掉。
      await settle();
      expect(runtime.health, PluginHealth.ready);
    });

    test('a syntax error is a ParseError at load', () async {
      await expectLater(
        PluginHarness().runtime('export function (('),
        throwsA(isA<ParseError>()),
      );
    });

    test('throwing at the top level fails the load', () async {
      final harness = PluginHarness();
      await expectLater(
        harness.runtime("throw { fmpError: 'Unsupported' };"),
        throwsA(isA<Unsupported>()),
      );
      await expectLater(
        harness.runtime("throw new Error('top');", pluginId: 'plugin-b'),
        throwsA(isA<UnexpectedError>()),
      );
    });
  });

  group('timeouts and disposal', () {
    test('a call still waiting on a promise fails, the plugin stays', () async {
      final runtime =
          await PluginHarness(
            callTimeout: const Duration(milliseconds: 300),
            livenessGrace: const Duration(milliseconds: 300),
          ).runtime('''
export function hang() { return new Promise(() => {}); }
export function ok() { return 'ok'; }
''');

      final error = await runtime
          .invoke('hang', null)
          .then<AppError>(
            (_) => fail('expected an error'),
            onError: (Object error) => error as AppError,
          );

      // 背景 isolate 回應了探測：只是在等，不是卡住。
      expect(error, isA<NetworkError>());
      expect(error.pluginId, 'plugin-a');
      expect(runtime.health, PluginHealth.ready);
      expect(await runtime.invoke('ok', null), 'ok');
    });

    test(
      'a plugin stuck in a loop becomes unresponsive; others go on',
      () async {
        final harness = PluginHarness(
          callTimeout: const Duration(milliseconds: 500),
          livenessGrace: const Duration(milliseconds: 300),
        );
        final stuck = await harness.runtime('''
export function spin() { while (true) {} }
''');
        final other = await harness.runtime('''
export function ok(value) { return value; }
''', pluginId: 'plugin-b');

        final failure = stuck
            .invoke('spin', null)
            .then<Object>((_) => 'finished', onError: (Object error) => error);
        // 卡住的是背景 isolate：主 isolate 的計時器照常觸發，另一個插件照常回應。
        final tick = Completer<void>();
        Timer(const Duration(milliseconds: 50), tick.complete);
        expect(await other.invoke('ok', 'during'), 'during');
        await tick.future;
        expect(stuck.health, PluginHealth.ready);

        final error = await failure;

        expect(error, isA<UnexpectedError>());
        expect((error as AppError).pluginId, 'plugin-a');
        expect(stuck.health, PluginHealth.unresponsive);
        await stuck.whenUnresponsive;
        await expectLater(
          stuck.invoke('spin', null),
          throwsA(isA<UnexpectedError>()),
        );
        expect(
          harness.records('plugin-a').map((r) => r.message),
          contains('Plugin stopped responding'),
        );
        expect(await other.invoke('ok', 'after'), 'after');
        expect(other.health, PluginHealth.ready);
      },
    );

    test('a load stuck in a loop fails the start', () async {
      await expectLater(
        PluginHarness(
          callTimeout: const Duration(milliseconds: 500),
          livenessGrace: const Duration(milliseconds: 300),
        ).runtime('while (true) {}\nexport function a() {}'),
        throwsA(isA<UnexpectedError>()),
      );
    });

    test('a worker that dies fails the call instead of hanging', () async {
      final runtime = await PluginHarness().runtime(
        '',
        entryPoint: _crashOnCall,
      );

      await expectLater(
        runtime.invoke('boom', null),
        throwsA(isA<UnexpectedError>()),
      );
      await runtime.whenUnresponsive;
      expect(runtime.health, PluginHealth.unresponsive);
    });

    test('a worker that cannot be spawned fails the start', () async {
      // 進入點捕獲了 ReceivePort：傳不到新的 isolate，Isolate.spawn 失敗。
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);

      await expectLater(
        PluginHarness().runtime(
          '',
          entryPoint: (start) => unsendable.sendPort.send(start.pluginId),
        ),
        throwsA(isA<UnexpectedError>()),
      );
    });

    test('a worker that dies while loading fails the start', () async {
      await expectLater(
        PluginHarness().runtime('', entryPoint: _crashAtStart),
        throwsA(isA<UnexpectedError>()),
      );
    });

    test('disposing fails the calls still waiting', () async {
      final runtime = await PluginHarness().runtime(
        'export function hang() { return new Promise(() => {}); }',
      );
      Object? failure;
      unawaited(
        runtime.invoke('hang', null).catchError((Object e) => failure = e),
      );

      await settle();
      runtime.dispose();
      await pumpUntil(() => failure != null);

      expect(failure, isA<UnexpectedError>());
      await expectLater(
        runtime.invoke('hang', null),
        throwsA(isA<UnexpectedError>()),
      );
    });

    test('disposing cancels requests in flight', () async {
      final started = Completer<void>();
      final harness = PluginHarness(
        handler: (options) {
          started.complete();
          return Completer<ResponseBody>().future;
        },
      );
      final runtime = await harness.runtime('''
export async function fetchIt() { await fmp.http.request({ url: 'https://example.test/' }); }
''');
      unawaited(runtime.invoke('fetchIt', null).catchError((Object _) => null));

      await started.future;
      runtime.dispose();

      // 掛著的請求被取消，不是等到逾時。
      await pumpUntil(
        () => harness
            .records(networkLogTag)
            .any((record) => record.fields['error'] == 'Cancelled'),
      );
      expect(harness.adapter.requests, hasLength(1));
    });
  });
}

/// 背景 isolate 的替身：照協定載入，收到第一個呼叫就拋錯（isolate 隨之結束）。
void _crashOnCall(PluginWorkerStart start) {
  final commands = ReceivePort();
  start.toMain
    ..send(WorkerReady(commands.sendPort))
    ..send(const LoadResult('{"ok":true,"value":["boom"]}'));
  commands.listen((message) {
    if (message is CallRequest) throw StateError('worker crashed');
  });
}

/// 背景 isolate 的替身：一開始就拋錯。
void _crashAtStart(PluginWorkerStart start) =>
    throw StateError('worker crashed at start');
