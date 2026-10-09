import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';

/// 最小的合法 manifest；[changes] 覆蓋或加欄位，值為 `#remove` 就拿掉。
String manifest([Map<String, Object?> changes = const {}]) {
  final json = <String, Object?>{
    'id': 'plugin-a',
    'name': 'Plugin A',
    'version': '1.0.0',
    'author': 'FMP tests',
    'apiVersion': 1,
    'capabilities': ['search'],
    'allowedHosts': ['example.test'],
  };
  for (final MapEntry(:key, :value) in changes.entries) {
    if (value == '#remove') {
      json.remove(key);
    } else {
      json[key] = value;
    }
  }
  return jsonEncode(json);
}

Matcher _rejectedAs<T extends AppError>() => throwsA(isA<T>());

void main() {
  test('parses the required fields', () {
    final parsed = PluginManifest.parse(manifest());

    expect(parsed.id, 'plugin-a');
    expect(parsed.name, 'Plugin A');
    expect(parsed.version, '1.0.0');
    expect(parsed.author, 'FMP tests');
    expect(parsed.capabilities, {PluginCapability.search});
    expect(parsed.allowedHosts, ['example.test']);
    expect(parsed.retryPolicy, isNull);
    expect(parsed.rateLimitPolicy, isNull);
    expect(parsed.defaults, isEmpty);
    expect(parsed.icon, isNull);
    expect(parsed.description, isEmpty);
  });

  test('parses the optional fields', () {
    final parsed = PluginManifest.parse(
      manifest({
        'capabilities': ['search', 'resolveStream'],
        'allowedHosts': ['example.test', 'cdn.example'],
        'login': null,
        'retry': {'maxRetries': 1, 'baseDelayMs': 250},
        'rateLimit': {'maxConcurrentRequests': 2, 'minRequestIntervalMs': 300},
        'redaction': {
          'keyNames': ['sid'],
          'mediaCdns': [
            {
              'host': 'cdn.example',
              'signedQueryParameters': ['sig'],
            },
          ],
        },
        'defaults': {'quality': 'high'},
        'icon': 'https://cdn.example/icon.png',
      }),
    );

    expect(parsed.capabilities, {
      PluginCapability.search,
      PluginCapability.resolveStream,
    });
    expect(parsed.retryPolicy!.maxRetries, 1);
    expect(parsed.retryPolicy!.baseDelay, const Duration(milliseconds: 250));
    expect(parsed.retryPolicy!.maxDelay, const RetryPolicy().maxDelay);
    expect(parsed.rateLimitPolicy!.maxConcurrentRequests, 2);
    expect(
      parsed.rateLimitPolicy!.minRequestInterval,
      const Duration(milliseconds: 300),
    );
    expect(parsed.redaction.keyNames, ['sid']);
    expect(parsed.redaction.mediaCdns.single.host, 'cdn.example');
    expect(parsed.redaction.mediaCdns.single.signedQueryParameters, {'sig'});
    expect(parsed.defaults, {'quality': 'high'});
    expect(parsed.icon, Uri.parse('https://cdn.example/icon.png'));
  });

  test('knows the twelve capabilities of ADR 0014', () {
    final names = [for (final c in PluginCapability.values) c.wireName];

    expect(names, [
      'search',
      'resolveStream',
      'trackDetail',
      'multiPart',
      'importPlaylist',
      'libraryRead',
      'libraryWrite',
      'charts',
      'live',
      'mix',
      'lyrics',
      'login',
    ]);
    expect(
      PluginManifest.parse(
        manifest({
          'capabilities': names,
          'login': {
            'methods': ['qr'],
          },
        }),
      ).capabilities,
      PluginCapability.values.toSet(),
    );
  });

  test('accepts a data icon', () {
    final icon = 'data:image/png;base64,${base64.encode([1, 2, 3])}';

    expect(
      PluginManifest.parse(manifest({'icon': icon})).icon.toString(),
      icon,
    );
  });

  group('description', () {
    test('is read, and null or absent is empty', () {
      expect(
        PluginManifest.parse(manifest({'description': 'A source'})).description,
        'A source',
      );
      expect(
        PluginManifest.parse(manifest({'description': null})).description,
        isEmpty,
      );
    });

    test('accepts the limit and rejects one more character', () {
      final max = PluginManifest.maxDescriptionLength;
      expect(
        PluginManifest.parse(manifest({'description': '音' * max}))
            .description
            .runes,
        hasLength(max),
      );
      expect(
        () => PluginManifest.parse(manifest({'description': '音' * (max + 1)})),
        _rejectedAs<ParseError>(),
      );
    });

    test('must be a string', () {
      expect(
        () => PluginManifest.parse(manifest({'description': 3})),
        _rejectedAs<ParseError>(),
      );
    });
  });

  group('apiVersion', () {
    test('another version is Unsupported, whatever its other fields', () {
      expect(
        () => PluginManifest.parse(
          jsonEncode({'id': 'plugin-a', 'apiVersion': 2, 'newField': true}),
        ),
        throwsA(
          isA<Unsupported>().having((e) => e.pluginId, 'pluginId', 'plugin-a'),
        ),
      );
      expect(
        () => PluginManifest.parse(manifest({'apiVersion': 0})),
        _rejectedAs<Unsupported>(),
      );
    });

    test('a missing or non-integer version is a ParseError', () {
      expect(
        () => PluginManifest.parse(manifest({'apiVersion': '#remove'})),
        _rejectedAs<ParseError>(),
      );
      expect(
        () => PluginManifest.parse(manifest({'apiVersion': '1'})),
        _rejectedAs<ParseError>(),
      );
    });
  });

  group('rejects as Unsupported', () {
    for (final (description, changes) in [
      (
        'an unknown capability',
        {
          'capabilities': ['search', 'teleport'],
        },
      ),
      (
        'an unknown login method',
        {
          'capabilities': ['search', 'login'],
          'login': {
            'methods': ['qr', 'passkey'],
          },
        },
      ),
      (
        'an unknown refresh timing',
        {
          'capabilities': ['search', 'login'],
          'login': {
            'methods': ['qr'],
            'refresh': 'hourly',
          },
        },
      ),
    ]) {
      test(description, () {
        expect(
          () => PluginManifest.parse(manifest(changes)),
          _rejectedAs<Unsupported>(),
        );
      });
    }
  });

  group('login', () {
    const webView = {
      'url': 'https://accounts.example.test/signin',
      'cookieHosts': ['https://example.test'],
      'doneCookies': ['SID', 'HSID'],
    };
    Map<String, Object?> withLogin(Map<String, Object?> login) => {
      'capabilities': ['search', 'login'],
      'allowedHosts': ['example.test'],
      'login': login,
    };

    test('reads every field', () {
      final parsed = PluginManifest.parse(
        manifest(
          withLogin({
            'methods': ['webView', 'cookie'],
            'webView': webView,
            'refresh': 'onStartup',
            'browseAsLoggedInDefault': false,
            'automationRisk': true,
          }),
        ),
      );

      final login = parsed.login!;
      expect(login.methods, {LoginMethod.webView, LoginMethod.cookie});
      expect(
        login.webView!.url,
        Uri.parse('https://accounts.example.test/signin'),
      );
      expect(login.webView!.cookieHosts, [Uri.parse('https://example.test')]);
      expect(login.webView!.doneCookies, ['SID', 'HSID']);
      expect(login.refresh, LoginRefresh.onStartup);
      expect(login.browseAsLoggedInDefault, isFalse);
      expect(login.automationRisk, isTrue);
    });

    test('the optional fields have their defaults', () {
      final login = PluginManifest.parse(
        manifest(
          withLogin({
            'methods': ['qr'],
            'webView': null,
            'refresh': null,
          }),
        ),
      ).login!;

      expect(login.methods, {LoginMethod.qr});
      expect(login.webView, isNull);
      expect(login.refresh, isNull);
      expect(login.browseAsLoggedInDefault, isTrue);
      expect(login.automationRisk, isFalse);
    });

    test('no login capability means no login', () {
      expect(PluginManifest.parse(manifest()).login, isNull);
      expect(PluginManifest.parse(manifest({'login': null})).login, isNull);
    });

    test('the required exports follow the methods and the refresh', () {
      PluginManifest parse(Map<String, Object?> login) =>
          PluginManifest.parse(manifest(withLogin(login)));

      expect(
        parse({
          'methods': ['qr'],
        }).requiredExports,
        {'search', 'loginVerify', 'loginQrStart', 'loginQrPoll'},
      );
      expect(
        parse({
          'methods': ['cookie'],
          'refresh': 'onStartup',
        }).requiredExports,
        {'search', 'loginVerify', 'loginRefresh'},
      );
      expect(PluginManifest.parse(manifest()).requiredExports, {'search'});
    });

    for (final (description, changes) in <(String, Map<String, Object?>)>[
      (
        'a login without the login capability',
        {
          'login': {
            'methods': ['qr'],
          },
        },
      ),
      (
        'the login capability without a login',
        {
          'capabilities': ['search', 'login'],
        },
      ),
      ('a login that is not an object', withLogin({})..['login'] = 'cookie'),
      ('no methods', withLogin({'methods': <String>[]})),
      (
        'a method listed twice',
        withLogin({
          'methods': ['qr', 'qr'],
        }),
      ),
      (
        'the webView method without a webView',
        withLogin({
          'methods': ['webView'],
        }),
      ),
      (
        'a webView without the webView method',
        withLogin({
          'methods': ['qr'],
          'webView': webView,
        }),
      ),
      (
        'a login page on another host',
        withLogin({
          'methods': ['webView'],
          'webView': {...webView, 'url': 'https://evil.test/signin'},
        }),
      ),
      (
        'an http login page',
        withLogin({
          'methods': ['webView'],
          'webView': {...webView, 'url': 'http://example.test/signin'},
        }),
      ),
      (
        'a cookie host on another host',
        withLogin({
          'methods': ['webView'],
          'webView': {
            ...webView,
            'cookieHosts': ['https://evil.test'],
          },
        }),
      ),
      (
        'no cookie hosts',
        withLogin({
          'methods': ['webView'],
          'webView': {...webView, 'cookieHosts': <String>[]},
        }),
      ),
      (
        'no done cookies',
        withLogin({
          'methods': ['webView'],
          'webView': {...webView, 'doneCookies': <String>[]},
        }),
      ),
      (
        'an unknown login field',
        withLogin({
          'methods': ['qr'],
          'userAgent': 'Chrome',
        }),
      ),
      (
        'an unknown webView field',
        withLogin({
          'methods': ['webView'],
          'webView': {...webView, 'userAgent': 'Chrome'},
        }),
      ),
    ]) {
      test('rejects $description as ParseError', () {
        expect(
          () => PluginManifest.parse(manifest(changes)),
          _rejectedAs<ParseError>(),
        );
      });
    }
  });

  group('rejects as ParseError', () {
    test('text that is not JSON or not an object', () {
      expect(() => PluginManifest.parse('{'), _rejectedAs<ParseError>());
      expect(() => PluginManifest.parse('[]'), _rejectedAs<ParseError>());
    });

    for (final field in [
      'id',
      'name',
      'version',
      'author',
      'capabilities',
      'allowedHosts',
    ]) {
      test('a missing $field', () {
        expect(
          () => PluginManifest.parse(manifest({field: '#remove'})),
          _rejectedAs<ParseError>(),
        );
      });
    }

    for (final (description, changes) in <(String, Map<String, Object?>)>[
      ('an unknown field', {'homepage': 'x'}),
      ('a wrong type', {'name': 1}),
      ('an empty name', {'name': ' '}),
      ('no capabilities', {'capabilities': <String>[]}),
      (
        'a capability listed twice',
        {
          'capabilities': ['search', 'search'],
        },
      ),
      ('an id with upper case', {'id': 'Plugin-A'}),
      ('an id with a colon', {'id': 'plugin:a'}),
      ('an id ending with -', {'id': 'plugin-'}),
      ('an id longer than 32', {'id': 'a' * 33}),
      (
        'a host with a scheme',
        {
          'allowedHosts': ['https://example.test'],
        },
      ),
      (
        'a host with a path',
        {
          'allowedHosts': ['example.test/api'],
        },
      ),
      (
        'a host with a port',
        {
          'allowedHosts': ['example.test:443'],
        },
      ),
      (
        'a wildcard host',
        {
          'allowedHosts': ['*.example.test'],
        },
      ),
      (
        'a bare top-level domain',
        {
          'allowedHosts': ['com'],
        },
      ),
      (
        'an IP address',
        {
          'allowedHosts': ['10.0.0.1'],
        },
      ),
      (
        'an upper-case host',
        {
          'allowedHosts': ['Example.test'],
        },
      ),
      (
        'too many retries',
        {
          'retry': {'maxRetries': 6},
        },
      ),
      (
        'a negative delay',
        {
          'retry': {'baseDelayMs': -1},
        },
      ),
      (
        'a fractional delay',
        {
          'retry': {'baseDelayMs': 1.5},
        },
      ),
      (
        'an unknown retry field',
        {
          'retry': {'jitter': true},
        },
      ),
      (
        'a rate limit without its interval',
        {
          'rateLimit': {'maxConcurrentRequests': 1},
        },
      ),
      (
        'a rate limit of zero requests',
        {
          'rateLimit': {'maxConcurrentRequests': 0, 'minRequestIntervalMs': 0},
        },
      ),
      ('an icon on another host', {'icon': 'https://evil.test/icon.png'}),
      ('an http icon', {'icon': 'http://example.test/icon.png'}),
      (
        'a data icon that is not an image',
        {'icon': 'data:text/html;base64,PGI+'},
      ),
      ('defaults that are not an object', {'defaults': 'x'}),
    ]) {
      test(description, () {
        expect(
          () => PluginManifest.parse(manifest(changes)),
          _rejectedAs<ParseError>(),
        );
      });
    }
  });
}
