import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';

import '../../support/credentials.dart';
import '../../support/fake_http_adapter.dart';
import 'harness.dart';

/// ADR 0012 §如何確認：三種標記在「未登入／已登入且開關開／已登入且開關關」
/// 下的注入結果。
enum _State { loggedOut, loggedInOn, loggedInOff }

const _expected = {
  (_State.loggedOut, AuthRequirement.required): AuthDecision.refuse,
  (_State.loggedOut, AuthRequirement.userPreference): AuthDecision.omit,
  (_State.loggedOut, AuthRequirement.never): AuthDecision.omit,
  (_State.loggedInOn, AuthRequirement.required): AuthDecision.attach,
  (_State.loggedInOn, AuthRequirement.userPreference): AuthDecision.attach,
  (_State.loggedInOn, AuthRequirement.never): AuthDecision.omit,
  // 開關只管 userPreference；required 已登入就一定帶。
  (_State.loggedInOff, AuthRequirement.required): AuthDecision.attach,
  (_State.loggedInOff, AuthRequirement.userPreference): AuthDecision.omit,
  (_State.loggedInOff, AuthRequirement.never): AuthDecision.omit,
};

const _sessdata = 'FAKE_SESSDATA_123';
const _headers = {'X-Session': 'FAKE_SESSION'};

String? _cookie(Harness harness) =>
    harness.adapter.requests.last.headers['cookie'] as String?;

/// 一個 jar 裡已經有 [seeded] 這些 cookie 的 harness：先對 `/seed/<名稱>` 各打
/// 一次，回應設 cookie。回傳時 `adapter.requests` 已清空。
Future<Harness> _harnessWithJar(
  Map<String, String> seeded, {
  CredentialSource? credentials,
}) async {
  final harness = Harness(
    (options) => options.uri.path.startsWith('/seed/')
        ? reply(
            200,
            headers: {
              'Set-Cookie':
                  '${options.uri.pathSegments.last}='
                  '${seeded[options.uri.pathSegments.last]}; Path=/',
            },
          )
        : reply(200),
    credentials: credentials ?? const NoCredentials(),
  );
  for (final name in seeded.keys) {
    await harness.get('https://example.test/seed/$name');
  }
  harness.adapter.requests.clear();
  return harness;
}

void main() {
  test('the table covers every state and requirement', () {
    expect(_expected, hasLength(_State.values.length * 3));
  });

  group('decideAuth', () {
    for (final MapEntry(key: (state, requirement), value: decision)
        in _expected.entries) {
      test('${requirement.name} when ${state.name} → ${decision.name}', () {
        expect(
          decideAuth(
            requirement,
            loggedIn: state != _State.loggedOut,
            browseAsLoggedIn: state != _State.loggedInOff,
          ),
          decision,
        );
      });
    }
  });

  group('the auth interceptor injects only by the decision', () {
    for (final MapEntry(key: (state, requirement), value: decision)
        in _expected.entries) {
      test('${requirement.name} when ${state.name}', () async {
        final harness = Harness(
          (_) => reply(200),
          credentials: FakeCredentials(
            cookies: state == _State.loggedOut ? null : {'SESSDATA': _sessdata},
            headers: _headers,
            browseAsLoggedInValue: state != _State.loggedInOff,
          ),
        );
        final send = harness.get(
          'https://example.test/a',
          auth: requirement,
          authHeaders: {'Authorization': 'FAKE_AUTH_HASH'},
        );

        switch (decision) {
          case AuthDecision.refuse:
            final error = await send.then<Object?>(
              (_) => null,
              onError: (Object error) => error,
            );
            expect(error, isA<AuthRequired>());
            expect((error! as AuthRequired).pluginId, pluginId);
            // 不發請求。
            expect(harness.adapter.requests, isEmpty);
          case AuthDecision.attach:
            final response = await send;
            final request = harness.adapter.requests.single;
            expect(request.headers['cookie'], 'SESSDATA=$_sessdata');
            expect(request.headers['x-session'], 'FAKE_SESSION');
            expect(request.headers['authorization'], 'FAKE_AUTH_HASH');
            expect(response.credentialsAttached, isTrue);
          case AuthDecision.omit:
            final response = await send;
            final request = harness.adapter.requests.single;
            expect(request.headers['cookie'], isNull);
            expect(request.headers['x-session'], isNull);
            // authHeaders 只在帶憑證時才出現。
            expect(request.headers['authorization'], isNull);
            expect(response.credentialsAttached, isFalse);
        }
        final record = harness.records.single;
        expect(record.fields['credentials'], decision == AuthDecision.attach);
      });
    }
  });

  test('nothing is attached without a credential', () async {
    final harness = Harness((_) => reply(200));
    final response = await harness.get(
      'https://example.test/a',
      auth: AuthRequirement.userPreference,
    );
    expect(harness.adapter.requests.single.headers['cookie'], isNull);
    expect(response.credentialsAttached, isFalse);
    await expectLater(
      harness.get('https://example.test/a', auth: AuthRequirement.required),
      throwsA(isA<AuthRequired>()),
    );
  });

  group('Cookie merging (ADR 0029 §決定 4)', () {
    test('the credential wins over the plugin header and the jar', () async {
      final harness = await _harnessWithJar({
        'sid': 'FAKE_JAR_SID',
        'buvid3': 'FAKE_JAR_BUVID',
      }, credentials: FakeCredentials(cookies: {'sid': _sessdata}));

      await harness.get(
        'https://example.test/a',
        headers: {'Cookie': 'sid=FAKE_PLUGIN_SID; pref=FAKE_PREF'},
        auth: AuthRequirement.userPreference,
      );

      // 同名：憑證 > 插件 header > jar；不同名的各自保留。
      expect(
        _cookie(harness),
        'sid=$_sessdata; pref=FAKE_PREF; buvid3=FAKE_JAR_BUVID',
      );
    });

    test(
      'the plugin header wins over the jar when nothing is attached',
      () async {
        final harness = await _harnessWithJar({
          'sid': 'FAKE_JAR_SID',
          'buvid3': 'FAKE_JAR_BUVID',
        });

        await harness.get(
          'https://example.test/a',
          headers: {'Cookie': 'sid=FAKE_PLUGIN_SID'},
        );

        expect(_cookie(harness), 'sid=FAKE_PLUGIN_SID; buvid3=FAKE_JAR_BUVID');
      },
    );

    test('with only the jar, the jar is sent', () async {
      final harness = await _harnessWithJar({'buvid3': 'FAKE_JAR_BUVID'});

      await harness.get('https://example.test/a');

      expect(_cookie(harness), 'buvid3=FAKE_JAR_BUVID');
    });

    test('with only the plugin header, it is sent as it is', () async {
      final harness = Harness((_) => reply(200));

      await harness.get(
        'https://example.test/a',
        headers: {'Cookie': 'pref=FAKE_PREF'},
      );

      expect(_cookie(harness), 'pref=FAKE_PREF');
    });

    test('credential cookies are added to the plugin header', () async {
      final harness = Harness(
        (_) => reply(200),
        credentials: FakeCredentials(cookies: {'SESSDATA': _sessdata}),
      );

      await harness.get(
        'https://example.test/a',
        headers: {'Cookie': 'buvid3=FAKE_PLUGIN_BUVID'},
        auth: AuthRequirement.required,
      );

      expect(_cookie(harness), 'buvid3=FAKE_PLUGIN_BUVID; SESSDATA=$_sessdata');
    });
  });

  // 登入回應設的 cookie 是憑證，不能落進 jar（ADR 0029 §決定 2，design §6.3）。插件
  // 呼叫層的版本在 script_source_plugin_test.dart 的 `login`。
  group('a login does not store its cookies', () {
    Harness loginHarness() => Harness(
      (options) => switch (options.uri.path) {
        '/login' => reply(
          200,
          headers: {'Set-Cookie': 'SESSDATA=$_sessdata; Path=/'},
        ),
        '/later' => reply(
          200,
          headers: {'Set-Cookie': 'later=FAKE_LATER_COOKIE; Path=/'},
        ),
        _ => reply(200),
      },
      credentials: const NoCredentials(),
    );

    test('a response during the login is not stored, a later one is', () async {
      final harness = loginHarness();

      final response = await harness.client.withoutSavingCookies(
        () => harness.get('https://example.test/login'),
      );
      // 呼叫端照樣讀得到 header（QR 的 done 從這裡取憑證）。
      expect(response.headers['set-cookie'], [contains(_sessdata)]);
      await harness.get('https://example.test/check');
      expect(_cookie(harness), isNull);

      await harness.get('https://example.test/later');
      await harness.get('https://example.test/check');
      expect(_cookie(harness), 'later=FAKE_LATER_COOKIE');
    });

    test('overlapping logins hold until the last one ends', () async {
      final harness = loginHarness();
      final first = Completer<void>();

      final outer = harness.client.withoutSavingCookies(() => first.future);
      await harness.client.withoutSavingCookies(
        () => harness.get('https://example.test/later'),
      );
      await harness.get('https://example.test/login');
      await harness.get('https://example.test/check');
      expect(_cookie(harness), isNull, reason: 'the outer login still runs');

      first.complete();
      await outer;
      await harness.get('https://example.test/later');
      await harness.get('https://example.test/check');
      expect(_cookie(harness), 'later=FAKE_LATER_COOKIE');
    });

    // 計數是每個 client 一個：一個插件在登入，別的插件的回應照存。
    test('a login holds only its own client', () async {
      final adapter = FakeHttpAdapter(
        (options) => switch (options.uri.path) {
          '/later' => reply(
            200,
            headers: {'Set-Cookie': 'later=FAKE_LATER_COOKIE; Path=/'},
          ),
          _ => reply(200),
        },
      );
      final factory = SourceHttpClientFactory(
        log: Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
        credentials: const NoCredentials(),
        createAdapter: () => adapter,
      );
      SourceHttpClient client(String id) =>
          factory.create(pluginId: id, allowedHosts: allowedHosts);
      final a = client('plugin-a');
      final b = client('plugin-b');
      addTearDown(a.close);
      addTearDown(b.close);
      Future<String?> send(SourceHttpClient client, String path) async {
        await client.send(
          SourceRequest(Uri.parse('https://example.test$path')),
        );
        return adapter.requests.last.headers['cookie'] as String?;
      }

      final login = Completer<void>();
      final held = a.withoutSavingCookies(() => login.future);
      await send(a, '/later');
      await send(b, '/later');

      expect(await send(a, '/check'), isNull);
      expect(await send(b, '/check'), 'later=FAKE_LATER_COOKIE');
      login.complete();
      await held;
    });

    test('a failed login gives the jar back', () async {
      final harness = loginHarness();

      await expectLater(
        harness.client.withoutSavingCookies<void>(
          () => Future.error(StateError('login failed')),
        ),
        throwsStateError,
      );
      await harness.get('https://example.test/later');
      await harness.get('https://example.test/check');

      expect(_cookie(harness), 'later=FAKE_LATER_COOKIE');
    });
  });

  group('credential cookies never come from the jar', () {
    // jar 裡先放一個與憑證同名的 cookie（例如非登入請求的回應設的）。
    const jarValue = 'FAKE_JAR_SESSDATA';
    const seeded = {'SESSDATA': jarValue, 'buvid3': 'FAKE_JAR_BUVID'};

    for (final (name, requirement, credentials, expected) in [
      (
        'attached',
        AuthRequirement.userPreference,
        FakeCredentials(cookies: {'SESSDATA': _sessdata}),
        'SESSDATA=$_sessdata; buvid3=FAKE_JAR_BUVID',
      ),
      (
        'omitted by the switch',
        AuthRequirement.userPreference,
        FakeCredentials(
          cookies: {'SESSDATA': _sessdata},
          browseAsLoggedInValue: false,
        ),
        'buvid3=FAKE_JAR_BUVID',
      ),
      (
        'omitted by auth never after a login',
        AuthRequirement.never,
        FakeCredentials(cookies: {'SESSDATA': _sessdata}),
        'buvid3=FAKE_JAR_BUVID',
      ),
      (
        'invalidated',
        AuthRequirement.userPreference,
        FakeCredentials(invalidatedCookies: {'SESSDATA': _sessdata}),
        'buvid3=FAKE_JAR_BUVID',
      ),
    ]) {
      test(name, () async {
        final harness = await _harnessWithJar(seeded, credentials: credentials);

        await harness.get('https://example.test/a', auth: requirement);

        expect(_cookie(harness), expected);
        expect(_cookie(harness), isNot(contains(jarValue)));
      });
    }

    test('logged out, the jar is sent as it was', () async {
      final harness = await _harnessWithJar(seeded);

      await harness.get('https://example.test/a');

      expect(_cookie(harness), 'SESSDATA=$jarValue; buvid3=FAKE_JAR_BUVID');
    });
  });

  group('authHeaders', () {
    test('are dropped when the hop leaves the host', () async {
      final harness = Harness(
        (options) => options.uri.path == '/a'
            ? redirect('https://cdn.example/b')
            : reply(200),
        credentials: FakeCredentials(cookies: {'SESSDATA': _sessdata}),
      );

      await harness.get(
        'https://example.test/a',
        auth: AuthRequirement.userPreference,
        authHeaders: {'X-Hash': 'FAKE_HASH'},
      );

      final [first, hop] = harness.adapter.requests;
      expect(first.headers['x-hash'], 'FAKE_HASH');
      expect(hop.headers['x-hash'], isNull);
    });

    test('stay on a same-host hop', () async {
      final harness = Harness(
        (options) => options.uri.path == '/a' ? redirect('/b') : reply(200),
        credentials: FakeCredentials(cookies: {'SESSDATA': _sessdata}),
      );

      await harness.get(
        'https://example.test/a',
        auth: AuthRequirement.userPreference,
        authHeaders: {'X-Hash': 'FAKE_HASH'},
      );

      expect(harness.adapter.requests.last.headers['x-hash'], 'FAKE_HASH');
    });

    test('are not sent for an invalidated credential', () async {
      final harness = Harness(
        (_) => reply(200),
        credentials: FakeCredentials(
          invalidatedCookies: {'SESSDATA': _sessdata},
        ),
      );

      final response = await harness.get(
        'https://example.test/a',
        auth: AuthRequirement.userPreference,
        authHeaders: {'X-Hash': 'FAKE_HASH'},
      );

      expect(harness.adapter.requests.single.headers['x-hash'], isNull);
      expect(response.credentialsAttached, isFalse);
    });
  });
}
