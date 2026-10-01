import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_http_adapter.dart';
import '../../support/pump_until.dart';
import 'harness.dart';

/// [future] 丟出的錯誤；沒丟就讓測試失敗。
Future<Object> errorOf(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (error) {
    return error;
  }
  fail('expected an error');
}

const _noRetry = RetryPolicy(maxRetries: 0);

void main() {
  group('interceptors run in the ADR 0012 order', () {
    // dio 的 onRequest／onResponse／onError 都依加入順序執行。可以從外面觀察
    // 的前後關係逐一斷言；錯誤對應與限流之間、cookie 與錯誤對應之間的先後
    // 沒有行為差異（兩者各自只看自己的欄位），不另外斷言。
    test('auth → cookie → error mapping → throttle → network log', () async {
      final harness = Harness(
        (options) => switch (options.uri.path) {
          '/first' => reply(
            200,
            headers: {'Set-Cookie': 'buvid3=FAKE_BUVID_123; Path=/'},
          ),
          '/timeout' => throw DioException.connectionTimeout(
            requestOptions: options,
            timeout: const Duration(seconds: 10),
          ),
          _ => reply(200),
        },
        credentials: FakeCredentials(
          headers: {'Cookie': 'SESSDATA=FAKE_SESSDATA_123'},
        ),
        retryPolicy: _noRetry,
        rateLimitPolicy: const RateLimitPolicy(
          maxConcurrentRequests: 1,
          minRequestInterval: Duration(seconds: 1),
        ),
      );

      await harness.get(
        'https://example.test/first',
        auth: AuthRequirement.userPreference,
      );
      await harness.get(
        'https://example.test/second',
        auth: AuthRequirement.userPreference,
      );
      final error = await errorOf(harness.get('https://example.test/timeout'));

      // 認證在 cookie 之前：cookie 管理把 jar 的 cookie 併進認證放的 Cookie。
      expect(
        harness.adapter.requests[1].headers['cookie'],
        'SESSDATA=FAKE_SESSDATA_123; buvid3=FAKE_BUVID_123',
      );
      // 限流在網路紀錄之前：第二個請求等了 1 秒，紀錄的耗時不含這段。
      expect(harness.waits, contains(const Duration(seconds: 1)));
      final [first, second, timeout] = harness.records;
      expect(second.fields['ms'], 0);
      // 認證在網路紀錄之前：紀錄知道有沒有帶憑證。
      expect(first.fields['credentials'], isTrue);
      expect(timeout.fields['credentials'], isFalse);
      // 錯誤對應在網路紀錄之前：紀錄看到的是轉好的類型。
      expect(error, isA<NetworkError>());
      expect(timeout.fields['error'], 'NetworkError');
    });
  });

  group('allowed hosts', () {
    test('the same host and a subdomain are sent', () async {
      final harness = Harness((_) => reply(200));
      await harness.get('https://example.test/a');
      await harness.get('https://api.example.test/b');
      expect(harness.adapter.requests, hasLength(2));
    });

    test('case and a trailing dot do not matter', () async {
      final harness = Harness((_) => reply(200));
      await harness.get('https://API.Example.TEST./a');
      expect(harness.adapter.requests, hasLength(1));
    });

    for (final url in [
      'https://evil-example.test/a',
      'https://example.test.evil.net/a',
      'http://example.test/a',
      'https://example.test@evil.test/a',
      'https://evil.test#@example.test',
    ]) {
      test('$url is refused without a request', () async {
        final harness = Harness((_) => reply(200));
        final error = await errorOf(harness.get(url));
        expect(error, isA<Unsupported>());
        expect((error as Unsupported).pluginId, pluginId);
        expect(error.networkRecordId, isNull);
        expect(harness.adapter.requests, isEmpty);
        expect(harness.records, isEmpty);
      });
    }
  });

  group('redirects', () {
    /// `/r/<n>` 轉到 `/r/<n-1>`，`/r/0` 回 200。
    ResponseBody chain(RequestOptions options) {
      final remaining = int.parse(options.uri.pathSegments.last);
      return remaining == 0
          ? reply(200, body: 'done')
          : redirect('/r/${remaining - 1}');
    }

    test('up to $maxRedirects redirects are followed', () async {
      final harness = Harness(chain);
      final response = await harness.get('https://example.test/r/5');
      expect(response.statusCode, 200);
      expect(response.url, Uri.parse('https://example.test/r/0'));
      expect(utf8.decode(response.body), 'done');
      expect(harness.adapter.requests, hasLength(6));
    });

    test('the sixth redirect fails', () async {
      final harness = Harness(chain);
      final error = await errorOf(harness.get('https://example.test/r/6'));
      expect(error, isA<Unsupported>());
      expect(harness.adapter.requests, hasLength(6));
      // 帶上回了第六次轉址的那筆紀錄。
      expect(
        (error as Unsupported).networkRecordId,
        harness.records.last.fields['id'],
      );
    });

    for (final (name, target) in [
      ('outside the allowed hosts', 'https://evil-example.test/x'),
      ('to http', 'http://example.test/x'),
    ]) {
      test('a redirect $name fails before it is sent', () async {
        final harness = Harness((_) => redirect(target));
        final error = await errorOf(harness.get('https://example.test/a'));
        expect(error, isA<Unsupported>());
        expect(harness.adapter.requests, hasLength(1));
      });
    }

    test(
      'a cross-host hop drops Cookie, Authorization and credentials',
      () async {
        final harness = Harness(
          (options) => switch (options.uri.path) {
            '/a' => reply(
              302,
              headers: {
                'Location': 'https://cdn.example/file',
                'Set-Cookie': 'sid=FAKE_SID_123; Path=/',
              },
            ),
            _ => reply(200),
          },
          credentials: FakeCredentials(headers: {'X-Session': 'FAKE_SESSION'}),
        );

        await harness.get(
          'https://example.test/a',
          headers: {
            'Cookie': 'pref=FAKE_PREF_123',
            'authorization': 'Bearer FAKE_TOKEN_123',
            'Referer': 'https://example.test/',
          },
          auth: AuthRequirement.userPreference,
        );

        final [first, hop] = harness.adapter.requests;
        expect(first.headers['x-session'], 'FAKE_SESSION');
        expect(hop.uri, Uri.parse('https://cdn.example/file'));
        expect(hop.headers['cookie'], isNull);
        expect(hop.headers['authorization'], isNull);
        expect(hop.headers['x-session'], isNull);
        expect(hop.headers['referer'], 'https://example.test/');
        expect(harness.records.last.fields['credentials'], isFalse);

        // 轉址回應設的 cookie 只存給它自己的 host。
        await harness.get('https://example.test/b');
        expect(
          harness.adapter.requests.last.headers['cookie'],
          'sid=FAKE_SID_123',
        );
      },
    );

    test('a same-host hop keeps the headers', () async {
      final harness = Harness(
        (options) => options.uri.path == '/a' ? redirect('/b') : reply(200),
      );
      await harness.get(
        'https://example.test/a',
        headers: {'Cookie': 'pref=FAKE_PREF_123'},
      );
      expect(
        harness.adapter.requests.last.headers['cookie'],
        'pref=FAKE_PREF_123',
      );
    });

    test('303 turns a POST into a GET without a body', () async {
      final harness = Harness(
        (options) => options.uri.path == '/form'
            ? redirect('/done', status: 303)
            : reply(200),
      );
      await harness.client.send(
        SourceRequest(
          Uri.parse('https://example.test/form'),
          method: 'POST',
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'a=1',
        ),
      );
      final hop = harness.adapter.requests.last;
      expect(hop.method, 'GET');
      expect(hop.data, isNull);
      expect(hop.headers['content-type'], isNull);
    });

    test('307 keeps the method and the body', () async {
      final harness = Harness(
        (options) => options.uri.path == '/form'
            ? redirect('/done', status: 307)
            : reply(200),
      );
      await harness.client.send(
        SourceRequest(
          Uri.parse('https://example.test/form'),
          method: 'POST',
          body: 'a=1',
        ),
      );
      final hop = harness.adapter.requests.last;
      expect(hop.method, 'POST');
      expect(hop.data, 'a=1');
    });

    test('a protocol-relative Location is checked like any other', () async {
      final harness = Harness((_) => redirect('//evil-example.test/x'));
      final error = await errorOf(harness.get('https://example.test/a'));
      expect(error, isA<Unsupported>());
      expect(harness.adapter.requests, hasLength(1));
    });

    test('a Location that cannot be parsed is Unsupported', () async {
      final harness = Harness((_) => redirect('https://[bad'));
      final error = await errorOf(harness.get('https://example.test/a'));
      expect(error, isA<Unsupported>());
      expect(
        (error as Unsupported).networkRecordId,
        harness.records.single.fields['id'],
      );
    });

    test('a redirect status without Location is returned as is', () async {
      final harness = Harness((_) => reply(302));
      final response = await harness.get('https://example.test/a');
      expect(response.statusCode, 302);
      expect(harness.adapter.requests, hasLength(1));
    });

    test('a cross-host hop never gets credentials back', () async {
      // example.test → cdn.example → example.test：回到原本的 host 也不再帶。
      final harness = Harness(
        (options) => switch ((options.uri.host, options.uri.path)) {
          ('example.test', '/a') => redirect('https://cdn.example/b'),
          ('cdn.example', _) => redirect('https://example.test/c'),
          _ => reply(200),
        },
        credentials: FakeCredentials(headers: {'X-Session': 'FAKE_SESSION'}),
      );
      await harness.get(
        'https://example.test/a',
        auth: AuthRequirement.required,
      );
      expect(harness.adapter.requests.map((r) => r.headers['x-session']), [
        'FAKE_SESSION',
        null,
        null,
      ]);
      expect(harness.records.map((r) => r.fields['credentials']), [
        true,
        false,
        false,
      ]);
    });

    test('a same-host hop keeps the credentials', () async {
      final harness = Harness(
        (options) => options.uri.path == '/a' ? redirect('/b') : reply(200),
        credentials: FakeCredentials(headers: {'X-Session': 'FAKE_SESSION'}),
      );
      await harness.get(
        'https://example.test/a',
        auth: AuthRequirement.userPreference,
      );
      expect(
        harness.adapter.requests.last.headers['x-session'],
        'FAKE_SESSION',
      );
    });

    for (final (status, method, expectedMethod) in [
      (301, 'POST', 'GET'),
      (302, 'POST', 'GET'),
      (302, 'PUT', 'PUT'),
      (303, 'PUT', 'GET'),
      (303, 'HEAD', 'HEAD'),
      (308, 'POST', 'POST'),
    ]) {
      test('$status turns $method into $expectedMethod', () async {
        final harness = Harness(
          (options) => options.uri.path == '/form'
              ? redirect('/done', status: status)
              : reply(200),
        );
        await harness.client.send(
          SourceRequest(
            Uri.parse('https://example.test/form'),
            method: method,
            body: method == 'HEAD' ? null : 'a=1',
          ),
        );
        final hop = harness.adapter.requests.last;
        expect(hop.method, expectedMethod);
        expect(
          hop.data,
          expectedMethod == method && method != 'HEAD' ? 'a=1' : isNull,
        );
      });
    }

    group('Set-Cookie Domain', () {
      /// api.example.test 的回應設 [setCookie]，再各打一次 example.test、
      /// api.example.test 與 cdn.example，回傳三者帶的 Cookie。
      Future<List<Object?>> cookiesAfter(String setCookie) async {
        final harness = Harness(
          (options) => options.uri.path == '/set'
              ? reply(200, headers: {'Set-Cookie': setCookie})
              : reply(200),
        );
        await harness.get('https://api.example.test/set');
        for (final url in [
          'https://example.test/x',
          'https://api.example.test/x',
          'https://cdn.example/x',
        ]) {
          await harness.get(url);
        }
        return [
          for (final request in harness.adapter.requests.skip(1))
            request.headers['cookie'],
        ];
      }

      test('a parent domain inside the allowed hosts is shared', () async {
        expect(await cookiesAfter('a=FAKE_1; Domain=example.test; Path=/'), [
          'a=FAKE_1',
          'a=FAKE_1',
          null,
        ]);
      });

      test('no Domain stays with the host that set it', () async {
        expect(await cookiesAfter('a=FAKE_1; Path=/'), [
          null,
          'a=FAKE_1',
          null,
        ]);
      });

      for (final domain in ['cdn.example', 'example', 'test', 'other.test']) {
        test('Domain=$domain is not stored', () async {
          expect(await cookiesAfter('a=FAKE_1; Domain=$domain; Path=/'), [
            null,
            null,
            null,
          ]);
        });
      }
    });

    test('300 and 304 are returned as they are', () async {
      final harness = Harness((_) => redirect('/elsewhere', status: 304));
      final response = await harness.get('https://example.test/a');
      expect(response.statusCode, 304);
      expect(harness.adapter.requests, hasLength(1));
    });
  });

  group('error mapping', () {
    Future<Object> failWith(
      DioException Function(RequestOptions options) failure,
    ) {
      final harness = Harness(
        (options) => throw failure(options),
        retryPolicy: _noRetry,
      );
      return errorOf(harness.get('https://example.test/a'));
    }

    test('timeouts and connection failures become NetworkError', () async {
      for (final failure in <DioException Function(RequestOptions)>[
        (o) => DioException.connectionTimeout(
          requestOptions: o,
          timeout: const Duration(seconds: 10),
        ),
        (o) => DioException.receiveTimeout(
          requestOptions: o,
          timeout: const Duration(seconds: 30),
        ),
        (o) => DioException.connectionError(
          requestOptions: o,
          reason: 'refused',
          error: const SocketException('refused'),
        ),
        // TLS 握手失敗：dio 歸為 unknown，error 是 HandshakeException。
        (o) => DioException(
          requestOptions: o,
          error: const HandshakeException('handshake failed'),
        ),
      ]) {
        final error = await failWith(failure);
        expect(error, isA<NetworkError>());
        expect((error as NetworkError).retryable, isTrue);
        expect(error.pluginId, pluginId);
        expect(error.networkRecordId, isNotNull);
      }
    });

    test(
      'a rejected certificate is a NetworkError that is not retried',
      () async {
        final error = await failWith(
          (o) => DioException.badCertificate(requestOptions: o),
        );
        expect(error, isA<NetworkError>());
        expect((error as NetworkError).retryable, isFalse);
      },
    );

    test('anything else is an UnexpectedError', () async {
      final error = await failWith(
        (o) => DioException(requestOptions: o, error: StateError('bug')),
      );
      expect(error, isA<UnexpectedError>());
    });

    test('429 with Retry-After in seconds', () async {
      final harness = Harness(
        (_) => reply(429, headers: {'Retry-After': '120'}),
        retryPolicy: _noRetry,
      );
      final error = await errorOf(harness.get('https://example.test/a'));
      expect(error, isA<RateLimited>());
      expect((error as RateLimited).retryAfter, const Duration(seconds: 120));
    });

    test('429 with Retry-After as a date (fake clock)', () async {
      final harness = Harness(
        (_) => reply(
          429,
          headers: {'Retry-After': 'Tue, 29 Sep 2026 12:00:45 GMT'},
        ),
        retryPolicy: _noRetry,
      );
      final error = await errorOf(harness.get('https://example.test/a'));
      expect((error as RateLimited).retryAfter, const Duration(seconds: 45));
    });

    test('429 without Retry-After', () async {
      final harness = Harness((_) => reply(429), retryPolicy: _noRetry);
      final error = await errorOf(harness.get('https://example.test/a'));
      expect((error as RateLimited).retryAfter, isNull);
    });

    test('503 with Retry-After is rate limiting', () async {
      final harness = Harness(
        (_) => reply(503, headers: {'Retry-After': '5'}),
        retryPolicy: _noRetry,
      );
      final error = await errorOf(harness.get('https://example.test/a'));
      expect((error as RateLimited).retryAfter, const Duration(seconds: 5));
    });

    test('503 with an unparseable Retry-After goes to the plugin', () async {
      final harness = Harness(
        (_) => reply(503, headers: {'Retry-After': 'soon'}),
      );
      final response = await harness.get('https://example.test/a');
      expect(response.statusCode, 503);
      expect(harness.adapter.requests, hasLength(1));
    });

    test(
      '503 without Retry-After and other statuses go to the plugin',
      () async {
        for (final status in [503, 500, 404, 412]) {
          final harness = Harness((_) => reply(status, body: 'x'));
          final response = await harness.get('https://example.test/a');
          expect(response.statusCode, status);
          expect(harness.adapter.requests, hasLength(1), reason: '$status');
        }
      },
    );
  });

  group('retry', () {
    DioException refused(RequestOptions options) =>
        DioException.connectionError(
          requestOptions: options,
          reason: 'refused',
        );

    test(
      'an idempotent request is retried with backoff until it works',
      () async {
        var calls = 0;
        final harness = Harness(
          (options) => ++calls < 3 ? throw refused(options) : reply(200),
        );
        final response = await harness.get('https://example.test/a');
        expect(response.statusCode, 200);
        expect(harness.adapter.requests, hasLength(3));
        // 全抖動：第 n 次重試的等待在 [0, 500ms × 2^n) 之內。
        final [firstWait, secondWait] = harness.waits;
        expect(firstWait, lessThan(const Duration(milliseconds: 500)));
        expect(secondWait, lessThan(const Duration(milliseconds: 1000)));
        expect(harness.records.map((r) => r.fields['retry']), [0, 1, 2]);
      },
    );

    test('stops at the retry limit', () async {
      final harness = Harness(
        (options) => throw refused(options),
        retryPolicy: const RetryPolicy(maxRetries: 2),
      );
      final error = await errorOf(harness.get('https://example.test/a'));
      expect(error, isA<NetworkError>());
      expect(harness.adapter.requests, hasLength(3));
      // 丟出的錯誤帶最後一次送出的紀錄 id。
      expect(
        (error as NetworkError).networkRecordId,
        harness.records.last.fields['id'],
      );
    });

    test('a non-idempotent request is not retried', () async {
      final harness = Harness((options) => throw refused(options));
      final error = await errorOf(
        harness.client.send(
          SourceRequest(Uri.parse('https://example.test/a'), method: 'POST'),
        ),
      );
      expect(error, isA<NetworkError>());
      expect(harness.adapter.requests, hasLength(1));
      expect(harness.waits, isEmpty);
    });

    test('Retry-After is respected (fake clock)', () async {
      var calls = 0;
      final harness = Harness(
        (_) => ++calls == 1
            ? reply(429, headers: {'Retry-After': '3'})
            : reply(200),
      );
      final response = await harness.get('https://example.test/a');
      expect(response.statusCode, 200);
      expect(harness.waits, [const Duration(seconds: 3)]);
    });

    test('a Retry-After beyond the policy limit is not waited for', () async {
      final harness = Harness(
        (_) => reply(429, headers: {'Retry-After': '120'}),
        retryPolicy: const RetryPolicy(maxRetryAfter: Duration(seconds: 60)),
      );
      final error = await errorOf(harness.get('https://example.test/a'));
      expect(error, isA<RateLimited>());
      expect(harness.adapter.requests, hasLength(1));
      expect(harness.waits, isEmpty);
    });

    test('a cancelled request is not retried', () async {
      final pending = Completer<ResponseBody>();
      final abort = Completer<void>();
      final harness = Harness((_) => pending.future);

      final send = errorOf(
        harness.get('https://example.test/a', abortTrigger: abort.future),
      );
      await pumpUntil(() => harness.adapter.requests.isNotEmpty);
      abort.complete();

      expect(await send, isA<RequestCancelled>());
      expect(harness.adapter.requests, hasLength(1));
      expect(harness.waits, isEmpty);
      final record = harness.records.single;
      expect(record.fields['error'], 'Cancelled');
      // 取消是呼叫端要的，不算失敗。
      expect(record.level, LogLevel.debug);
    });
  });

  group('rate limit', () {
    test('never more requests in flight than the limit', () async {
      final pending = <Completer<ResponseBody>>[];
      final harness = Harness(
        (_) {
          final completer = Completer<ResponseBody>();
          pending.add(completer);
          return completer.future;
        },
        rateLimitPolicy: const RateLimitPolicy(
          maxConcurrentRequests: 2,
          minRequestInterval: Duration.zero,
        ),
      );

      final sends = [
        for (var i = 0; i < 3; i++) harness.get('https://example.test/$i'),
      ];
      await pumpUntil(() => pending.length == 2);
      await settle();
      expect(harness.adapter.requests, hasLength(2));

      pending.first.complete(reply(200));
      await pumpUntil(() => pending.length == 3);
      for (final completer in pending.skip(1)) {
        completer.complete(reply(200));
      }
      await Future.wait(sends);
    });

    test('a failed request gives its place back', () async {
      // 傳輸錯誤（dio 在送出時 reject）、429（錯誤對應在 onResponse reject）、
      // 未登入（認證在拿位置之前 reject）三種失敗之後，位置都要還在；沒讓出
      // 的話下一個請求會永遠排隊，pumpUntil 會失敗。
      final harness = Harness(
        (options) => switch (options.uri.path) {
          '/refused' => throw DioException.connectionError(
            requestOptions: options,
            reason: 'refused',
          ),
          '/limited' => reply(429),
          _ => reply(200),
        },
        retryPolicy: _noRetry,
        rateLimitPolicy: const RateLimitPolicy(
          maxConcurrentRequests: 1,
          minRequestInterval: Duration.zero,
        ),
      );
      for (final (path, auth) in [
        ('/refused', AuthRequirement.never),
        ('/limited', AuthRequirement.never),
        ('/private', AuthRequirement.required),
      ]) {
        await errorOf(harness.get('https://example.test$path', auth: auth));
        var done = false;
        unawaited(
          harness.get('https://example.test/ok').then((_) => done = true),
        );
        await pumpUntil(() => done, reason: 'blocked after $path');
      }
      expect(harness.adapter.requests, hasLength(5));
    });

    test('a cancelled request gives its place back', () async {
      // 一個在送出中、一個在排隊時被取消；兩者都要讓出位置。
      final pending = <Completer<ResponseBody>>[];
      final harness = Harness(
        (_) {
          final completer = Completer<ResponseBody>();
          pending.add(completer);
          return completer.future;
        },
        rateLimitPolicy: const RateLimitPolicy(
          maxConcurrentRequests: 1,
          minRequestInterval: Duration.zero,
        ),
      );
      final abortInFlight = Completer<void>();
      final abortQueued = Completer<void>();

      final inFlight = errorOf(
        harness.get(
          'https://example.test/1',
          abortTrigger: abortInFlight.future,
        ),
      );
      await pumpUntil(() => pending.length == 1);
      final queued = errorOf(
        harness.get('https://example.test/2', abortTrigger: abortQueued.future),
      );
      await settle();
      abortQueued.complete();
      expect(await queued, isA<RequestCancelled>());
      abortInFlight.complete();
      expect(await inFlight, isA<RequestCancelled>());

      final last = harness.get('https://example.test/3');
      await pumpUntil(() => pending.length == 2);
      pending.last.complete(reply(200));
      expect((await last).statusCode, 200);
      expect(harness.adapter.requests.map((r) => r.uri.path), ['/1', '/3']);
    });

    test('the minimum interval spaces the starts (fake clock)', () async {
      final harness = Harness(
        (_) => reply(200),
        rateLimitPolicy: const RateLimitPolicy(
          maxConcurrentRequests: 4,
          minRequestInterval: Duration(milliseconds: 250),
        ),
      );
      await Future.wait([
        for (var i = 0; i < 3; i++) harness.get('https://example.test/$i'),
      ]);
      expect(harness.waits, [
        const Duration(milliseconds: 250),
        const Duration(milliseconds: 250),
      ]);
    });
  });

  group('network log', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('fmp_network_test');
      addTearDown(() => temp.delete(recursive: true));
    });

    test('one record per request with every field', () async {
      final harness = Harness(
        (_) => reply(200, body: 'FAKE_RESPONSE_BODY'),
        credentials: FakeCredentials(headers: {'X-Session': 'FAKE_SESSION'}),
      );
      await harness.get(
        'https://api.example.test/x/search?keyword=a&page=2',
        auth: AuthRequirement.userPreference,
      );

      final record = harness.records.single;
      expect(record.level, LogLevel.debug);
      expect(record.message, 'HTTP request');
      expect(record.fields, {
        'id': 1,
        'pluginId': pluginId,
        'method': 'GET',
        'host': 'api.example.test',
        'path': '/x/search',
        'query': 'keyword=a&page=2',
        'status': 200,
        'ms': 0,
        'bytes': 'FAKE_RESPONSE_BODY'.length,
        'credentials': true,
        'retry': 0,
      });
    });

    test('a failure is a warning and the AppError carries its id', () async {
      final harness = Harness((_) => reply(429), retryPolicy: _noRetry);
      await errorOf(harness.get('https://example.test/before'));
      final error = await errorOf(harness.get('https://example.test/a'));

      final record = harness.records.last;
      expect(record.level, LogLevel.warning);
      expect(record.message, 'HTTP request failed');
      expect(record.fields['status'], 429);
      expect(record.fields['error'], 'RateLimited');
      expect(record.fields['id'], 2);
      expect((error as RateLimited).networkRecordId, 2);
    });

    test(
      'a status of 400 or more is a warning, the response still returns',
      () async {
        final harness = Harness((_) => reply(404));
        final response = await harness.get('https://example.test/a');
        expect(response.statusCode, 404);
        expect(harness.records.single.level, LogLevel.warning);
        expect(harness.records.single.fields.containsKey('error'), isFalse);
      },
    );

    test(
      'fake secrets in the query are redacted and bodies are not logged',
      () async {
        final logFile = LogFile(Directory(p.join(temp.path, logDirectoryName)));
        final harness = Harness(
          (_) => reply(200, body: 'FAKE_RESPONSE_BODY_123'),
          logFile: logFile,
        );
        await harness.client.send(
          SourceRequest(
            Uri.parse(
              'https://example.test/a?access_key=FAKE_ACCESS_KEY_123'
              '&csrf=FAKE_CSRF_123&keyword=ok',
            ),
            method: 'POST',
            body: 'FAKE_REQUEST_BODY_123',
          ),
        );

        final query = harness.records.single.fields['query']! as String;
        expect(query, contains('keyword=ok'));
        await logFile.flush();
        final stored = await logFile.currentFile.readAsString();
        final history = jsonEncode([
          for (final record in harness.log.history) record.toJsonLine(),
        ]);
        for (final output in [history, stored]) {
          expect(output, contains('keyword=ok'));
          for (final secret in [
            'FAKE_ACCESS_KEY_123',
            'FAKE_CSRF_123',
            'FAKE_RESPONSE_BODY_123',
            'FAKE_REQUEST_BODY_123',
          ]) {
            expect(output, isNot(contains(secret)));
          }
        }
      },
    );

    test('every request gets the next id', () async {
      final harness = Harness((_) => reply(200));
      await harness.get('https://example.test/a');
      await harness.get('https://example.test/b');
      expect(harness.records.map((r) => r.fields['id']), [1, 2]);
    });
  });

  // ADR 0016 §決定 6：每次送出的結果進網路狀態。拿到回應（不論狀態碼）＝連得
  // 上；NetworkError＝連不上；沒送出或取消的不算。
  group('network status', () {
    DioException refused(RequestOptions options) =>
        DioException.connectionError(
          requestOptions: options,
          reason: 'refused',
        );

    test('any status code is a response', () async {
      for (final status in [200, 404, 500]) {
        final harness = Harness((_) => reply(status), retryPolicy: _noRetry);
        await harness.get('https://example.test/a');
        expect(harness.outcomes, [RequestOutcome.responded], reason: '$status');
      }
    });

    test('429 is a response even though it fails as RateLimited', () async {
      final harness = Harness((_) => reply(429), retryPolicy: _noRetry);
      expect(
        await errorOf(harness.get('https://example.test/a')),
        isA<RateLimited>(),
      );
      expect(harness.outcomes, [RequestOutcome.responded]);
    });

    test('every attempt and every hop reports once', () async {
      var calls = 0;
      final harness = Harness(
        (options) => switch (options.uri.path) {
          '/a' => redirect('/b'),
          _ => ++calls < 3 ? throw refused(options) : reply(200),
        },
      );
      await harness.get('https://example.test/a');
      expect(harness.outcomes, [
        RequestOutcome.responded,
        RequestOutcome.networkError,
        RequestOutcome.networkError,
        RequestOutcome.responded,
      ]);
    });

    test('a rejected certificate is a network error', () async {
      final harness = Harness(
        (o) => throw DioException.badCertificate(requestOptions: o),
        retryPolicy: _noRetry,
      );
      await errorOf(harness.get('https://example.test/a'));
      expect(harness.outcomes, [RequestOutcome.networkError]);
    });

    test(
      'requests that were not sent or were cancelled report nothing',
      () async {
        final harness = Harness(
          (o) =>
              throw DioException(requestOptions: o, error: StateError('bug')),
          retryPolicy: _noRetry,
        );
        // 網域不符：沒送出。
        await errorOf(harness.get('https://elsewhere.test/a'));
        // 未登入的 required：沒送出。
        await errorOf(
          harness.get('https://example.test/a', auth: AuthRequirement.required),
        );
        // 不是傳輸錯誤的失敗（UnexpectedError）。
        await errorOf(harness.get('https://example.test/a'));
        expect(harness.outcomes, isEmpty);

        final pending = Completer<ResponseBody>();
        final abort = Completer<void>();
        final hanging = Harness((_) => pending.future);
        final send = errorOf(
          hanging.get('https://example.test/a', abortTrigger: abort.future),
        );
        await pumpUntil(() => hanging.adapter.requests.isNotEmpty);
        abort.complete();
        expect(await send, isA<RequestCancelled>());
        expect(hanging.outcomes, isEmpty);
      },
    );
  });
}
