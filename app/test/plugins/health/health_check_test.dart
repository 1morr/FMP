import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/plugins/health/health_check.dart';
import 'package:fmp/plugins/plugin_registry.dart';

import '../../playback/fake_source_plugin.dart';
import '../../support/fake_http_adapter.dart';
import '../../support/pump_until.dart';
import '../dev/dev_support.dart';
import '../plugin_harness.dart';

// 健康檢查（M3 PR 16a，ADR 0025 §決定 6）。不連網：插件跑在真的 QuickJS，HTTP 是假 adapter。

/// search 打 `/s`；loginVerify 以傳進來的憑證組 Cookie 打 `/me`。
const _script = '''
export async function search({ keyword }) {
  const response = await fmp.http.request({
    url: 'https://example.test/s',
    auth: 'userPreference',
  });
  if (response.status !== 200) throw { fmpError: 'ParseError' };
  return { items: [{ sourceId: 'a', title: 'Song' }], hasMore: false };
}
''';

const _loginScript = '''
export async function loginVerify(credentials) {
  await fmp.http.request({
    url: 'https://example.test/me',
    headers: { Cookie: 'SESSDATA=' + credentials.cookies.SESSDATA },
    auth: 'never',
  });
  return { userId: '42', displayName: 'Tester' };
}
''';

/// liveStatus 打 `/room`：200 是開播中，其他狀態碼一律拋錯（不回未開播）。
const _liveScript = '''
export function liveSearch() { return { items: [], hasMore: false }; }
export function liveRoomFromUrl() { return null; }
export function resolveLive() { return { candidates: [{ url: 'https://example.test/a' }] }; }
export async function liveStatus({ roomId }) {
  const response = await fmp.http.request({ url: 'https://example.test/room', auth: 'userPreference' });
  if (response.status !== 200) throw { fmpError: 'NetworkError', message: 'HTTP ' + response.status };
  return { roomId, title: 'Room', hostName: 'Host', status: 'live' };
}
''';

/// mix 打 `/mix`：200 回五首，其他狀態碼一律拋錯。
const _mixScript = '''
export async function mix({ seed }) {
  const response = await fmp.http.request({ url: 'https://example.test/mix', auth: 'userPreference' });
  if (response.status !== 200) throw { fmpError: 'NetworkError', message: 'HTTP ' + response.status };
  return { mixId: 'm', title: 'Mix', tracks: [1, 2].map((n) => ({ sourceId: seed.sourceId + n, title: 'T' + n })) };
}
''';

const _mixCheck =
    '"mix": {"input": {"seed": {"sourceId": "s"}}, '
    '"expect": {"minItems": 2, "nonEmpty": ["sourceId", "title"]}}';

const _liveCheck =
    '"live": {"input": {"roomId": "r1"}, '
    '"expect": {"minItems": 1, "nonEmpty": ["roomId", "hostName"]}}';

const _searchCheck =
    '"search": {"input": {"keyword": "k", "page": 1}, '
    '"expect": {"minItems": 1, "nonEmpty": ["title"]}}';
const _loginCheck =
    '"login": {"input": {"cookies": {"SESSDATA": "***"}}, '
    '"expect": {"minItems": 1, "nonEmpty": ["userId"]}, "requiresLogin": true}';

const _stored = LoginCredentials(cookies: {'SESSDATA': 'FAKE_STORED_SESSION'});

/// 一個要裝進 `installed_plugins` 的插件。
final class _Spec {
  const _Spec(
    this.id, {
    this.checks = '{$_searchCheck}',
    this.enabled = true,
    this.login = false,
    this.live = false,
    this.mix = false,
  });

  final String id;
  final String? checks;
  final bool enabled;
  final bool login;
  final bool live;
  final bool mix;
}

Future<
  ({PluginHarness harness, ProviderContainer container, List<String> requests})
>
_setup(
  List<_Spec> specs, {
  FutureOr<ResponseBody> Function(RequestOptions options)? handler,
}) async {
  final requests = <String>[];
  final harness = PluginHarness(
    handler: (options) async {
      requests.add('${options.uri.path} ${options.headers['cookie'] ?? ''}');
      return handler == null ? reply(200) : await handler(options);
    },
  );
  for (final spec in specs) {
    await harness.plugins.install(
      InstalledPlugin(
        id: spec.id,
        version: '1.0.0',
        manifestJson: jsonEncode({'id': spec.id, 'name': 'Plugin ${spec.id}'}),
        script: pluginSource(
          '$_script${spec.login ? _loginScript : ''}'
          '${spec.live ? _liveScript : ''}${spec.mix ? _mixScript : ''}',
          id: spec.id,
          capabilities: [
            'search',
            if (spec.live) 'live',
            if (spec.mix) 'mix',
            if (spec.login) 'login',
          ],
          login: spec.login ? '{"methods": ["cookie"]}' : null,
        ),
        installedAt: DateTime.utc(2026, 10, 14),
        checksJson: spec.checks,
      ),
    );
    if (!spec.enabled) {
      await harness.plugins.setEnabled(spec.id, enabled: false);
    }
  }
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      pluginRepositoryProvider.overrideWithValue(harness.plugins),
      scriptPluginLoaderProvider.overrideWithValue(harness.loader),
      mediaHttpClientFactoryProvider.overrideWithValue(
        harness.mediaHttpClients,
      ),
      credentialStoreProvider.overrideWithValue(harness.credentials),
      logProvider.overrideWithValue(harness.log),
      redactorProvider.overrideWithValue(harness.redactor),
    ],
  );
  addTearDown(container.dispose);
  await container.read(pluginRegistryProvider.future);
  return (harness: harness, container: container, requests: requests);
}

Future<void> _login(PluginHarness harness, String pluginId) async {
  await harness.credentials.ready;
  await harness.credentials.save(
    Account(
      pluginId: pluginId,
      userId: '42',
      displayName: 'Tester',
      status: AccountStatus.active,
      loggedInAt: DateTime.utc(2026, 10, 14),
    ),
    _stored,
  );
}

void main() {
  group('requiresLogin cases', () {
    final both = _Spec(
      'plugin-a',
      checks: '{$_searchCheck, $_loginCheck}',
      login: true,
    );

    test('are skipped when the source is not logged in', () async {
      final s = await _setup([both]);
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final cases = s.container
          .read(healthCheckProvider)
          .results['plugin-a']!
          .cases;
      expect(cases.map((c) => c.outcome), [
        HealthOutcome.passed,
        HealthOutcome.skipped,
      ]);
      expect(s.requests.where((r) => r.startsWith('/me')), isEmpty);
    });

    test('run with the stored credentials when logged in', () async {
      final s = await _setup([both]);
      await _login(s.harness, 'plugin-a');
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final cases = s.container
          .read(healthCheckProvider)
          .results['plugin-a']!
          .cases;
      expect(cases.map((c) => c.outcome), [
        HealthOutcome.passed,
        HealthOutcome.passed,
      ]);
      // 送出的是已存的憑證，不是案例檔裡的假值 `***`。
      expect(s.requests, contains('/me SESSDATA=FAKE_STORED_SESSION'));
      // loginVerify 回的帳號與憑證值都不進結果與 log（擁有者不准記帳號名稱）。
      final shown = [
        for (final c in cases) ...[c.errorType ?? '', ...c.problems],
        for (final r in s.harness.log.history) r.toJsonLine(),
      ].join(' | ');
      expect(shown, isNot(contains('FAKE_STORED_SESSION')));
      expect(shown, isNot(contains('Tester')));
    });
  });

  group('a live case', () {
    final live = _Spec(
      'plugin-a',
      checks: '{$_searchCheck, $_liveCheck}',
      live: true,
    );

    test('runs liveStatus and passes on a live room', () async {
      final s = await _setup([live]);
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final cases = s.container
          .read(healthCheckProvider)
          .results['plugin-a']!
          .cases;

      expect(cases.map((c) => c.outcome), [
        HealthOutcome.passed,
        HealthOutcome.passed,
      ]);
      expect(s.requests.where((r) => r.startsWith('/room')), hasLength(1));
    });

    test('fails, not offline, when the status request fails', () async {
      final s = await _setup(
        [live],
        handler: (options) =>
            reply(options.uri.path == '/room' ? 500 : 200, body: '{}'),
      );
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final cases = s.container
          .read(healthCheckProvider)
          .results['plugin-a']!
          .cases;

      expect(cases.last.outcome, HealthOutcome.failed);
    });
  });

  group('a mix case', () {
    final mix = _Spec(
      'plugin-a',
      checks: '{$_searchCheck, $_mixCheck}',
      mix: true,
    );

    test('starts a mix by seed and passes', () async {
      final s = await _setup([mix]);
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final cases = s.container
          .read(healthCheckProvider)
          .results['plugin-a']!
          .cases;

      expect(cases.map((c) => c.outcome), [
        HealthOutcome.passed,
        HealthOutcome.passed,
      ]);
      expect(s.requests.where((r) => r.startsWith('/mix')), hasLength(1));
    });

    test('fails when the mix request fails', () async {
      final s = await _setup(
        [mix],
        handler: (options) =>
            reply(options.uri.path == '/mix' ? 500 : 200, body: '{}'),
      );
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final cases = s.container
          .read(healthCheckProvider)
          .results['plugin-a']!
          .cases;

      expect(cases.last.outcome, HealthOutcome.failed);
    });
  });

  group('one plugin at a time', () {
    test('"all" runs the plugins in order and never two at once', () async {
      var active = 0;
      var maxActive = 0;
      final order = <String>[];
      final s = await _setup(
        [_Spec('plugin-a'), _Spec('plugin-b')],
        handler: (options) async {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
          return reply(200);
        },
      );
      final notifier = s.container.read(healthCheckProvider.notifier);
      s.container.listen(healthCheckProvider, (_, next) {
        final running = next.running;
        if (running != null && (order.isEmpty || order.last != running)) {
          order.add(running);
        }
      });
      await notifier.runAll();
      expect(order, ['plugin-a', 'plugin-b']);
      expect(maxActive, 1);
      expect(s.container.read(healthCheckProvider).busy, isFalse);
      expect(s.container.read(healthCheckProvider).running, isNull);
    });

    test('pressing again while a round runs does not start another', () async {
      final gate = Completer<void>();
      final s = await _setup(
        [_Spec('plugin-a')],
        handler: (options) async {
          await gate.future;
          return reply(200);
        },
      );
      final notifier = s.container.read(healthCheckProvider.notifier);
      final first = notifier.runAll();
      await pumpUntil(() => s.requests.isNotEmpty);
      expect(s.container.read(healthCheckProvider).busy, isTrue);
      await notifier.runAll();
      await notifier.runOne('plugin-a');
      gate.complete();
      await first;
      // 只有第一輪的那一個請求。
      expect(s.requests, hasLength(1));
    });
  });

  test('a plugin disabled while an earlier one runs is not run', () async {
    final gate = Completer<void>();
    final s = await _setup(
      [_Spec('plugin-a'), _Spec('plugin-b')],
      handler: (options) async {
        await gate.future;
        return reply(200);
      },
    );
    final round = s.container.read(healthCheckProvider.notifier).runAll();
    await pumpUntil(() => s.requests.isNotEmpty);
    await s.harness.plugins.setEnabled('plugin-b', enabled: false);
    gate.complete();
    await round;
    final results = s.container.read(healthCheckProvider).results;
    expect(results.keys, ['plugin-a']);
    expect(s.requests, hasLength(1));
  });

  test('an enabled plugin that did not load is marked not loaded', () async {
    final s = await _setup([_Spec('plugin-a')]);
    // 啟用、有案例，但清單上沒有它（例如載入失敗）。
    await s.container
        .read(pluginRegistryProvider.notifier)
        .unregister('plugin-a');
    await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
    final result = s.container.read(healthCheckProvider).results['plugin-a']!;
    expect(result.notLoaded, isTrue);
    expect(result.cases, isEmpty);
    expect(s.requests, isEmpty);
  });

  test('disabled plugins and plugins without checks are not run', () async {
    final s = await _setup([
      _Spec('plugin-a', enabled: false),
      _Spec('plugin-b', checks: null),
    ]);
    final notifier = s.container.read(healthCheckProvider.notifier);
    await notifier.runAll();
    await notifier.runOne('plugin-a');
    await notifier.runOne('plugin-b');
    expect(s.container.read(healthCheckProvider).results, isEmpty);
    expect(s.requests, isEmpty);
    expect(s.harness.records('health'), isEmpty);
  });

  test('every case writes one log record tagged health', () async {
    final s = await _setup([
      _Spec('plugin-a', checks: '{$_searchCheck, $_loginCheck}', login: true),
    ], handler: (options) => reply(options.uri.path == '/s' ? 429 : 200));
    await s.container.read(healthCheckProvider.notifier).runAll();
    final records = s.harness.records('health');
    expect(records, hasLength(2));
    expect(records[0].fields, {
      'pluginId': 'plugin-a',
      'capability': 'search',
      'result': 'failed',
      'durationMs': isA<int>(),
      'errorType': 'RateLimited',
    });
    expect(records[1].fields, containsPair('result', 'skipped'));
    expect(records[1].fields, isNot(contains('errorType')));
  });

  group('failures', () {
    test('a mismatch is a failure with the problem and error type', () async {
      final s = await _setup([
        _Spec('plugin-a'),
      ], handler: (options) => reply(429));
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final result = s.container
          .read(healthCheckProvider)
          .results['plugin-a']!
          .cases
          .single;
      expect(result.outcome, HealthOutcome.failed);
      expect(result.errorType, 'RateLimited');
      expect(result.problems.single, startsWith('expected success, got'));
    });

    test('a non-AppError fails the case without stopping the round', () async {
      final s = await _setup([_Spec('plugin-a'), _Spec('plugin-b')]);
      final fake = FakeSourcePlugin(
        (_) => const [],
        id: 'plugin-a',
        onSearch: (_) => throw StateError('boom FAKE_SECRET'),
      );
      await s.container.read(pluginRegistryProvider.notifier).register(fake);
      await s.container.read(healthCheckProvider.notifier).runAll();
      final results = s.container.read(healthCheckProvider).results;
      expect(results['plugin-a']!.cases.single.outcome, HealthOutcome.failed);
      expect(
        results['plugin-a']!.cases.single.problems.single,
        'threw StateError, not an AppError',
      );
      expect(results['plugin-b']!.cases.single.outcome, HealthOutcome.passed);
    });

    test('unreadable checks.json is a plugin-level problem', () async {
      final s = await _setup([_Spec('plugin-a', checks: '{"search": 1}')]);
      await s.container.read(healthCheckProvider.notifier).runOne('plugin-a');
      final result = s.container.read(healthCheckProvider).results['plugin-a']!;
      expect(result.cases, isEmpty);
      expect(result.problem, isNotNull);
    });
  });

  test('does not add a table (the database has no health table)', () async {
    final s = await _setup([_Spec('plugin-a')]);
    final before = s.harness.database.allTables.map((t) => t.actualTableName);
    expect(before, isNot(contains(contains('health'))));
  });

  test('a plugin in development runs the checks.json of its folder, not the '
      'installed row', () async {
    final harness = PluginHarness(handler: (_) => reply(200));
    // 已安裝的列沒有案例；資料夾的 checks.json 有 search。
    await storeInstalled(harness, pluginSource(_script, id: 'plugin-a'));
    final folder = tempFolder();
    final directory = Directory('${folder.path}/plugin-a')..createSync();
    File('${directory.path}/plugin-a.js')
        .writeAsStringSync(pluginSource(_script, id: 'plugin-a'));
    File('${directory.path}/checks.json').writeAsStringSync('{$_searchCheck}');
    await selectFolder(harness, folder);
    final container = devContainer(
      harness,
      overrides: [
        credentialStoreProvider.overrideWithValue(harness.credentials),
      ],
    );
    container.listen(pluginDevelopmentProvider, (_, _) {});
    await pumpUntil(
      () => container.read(pluginDevelopmentProvider)?.busy == false,
      maxRounds: 1000,
    );

    await container.read(healthCheckProvider.notifier).runOne('plugin-a');

    final result = container.read(healthCheckProvider).results['plugin-a']!;
    expect(result.cases.single.outcome, HealthOutcome.passed);
    // 卸載之後回到已安裝的列：它沒有案例，不跑。
    await selectFolder(harness, null);
    await pumpUntil(
      () => container.read(pluginDevelopmentProvider) == null,
      maxRounds: 1000,
    );
    container.invalidate(healthCheckProvider);
    await container.read(healthCheckProvider.notifier).runOne('plugin-a');
    expect(container.read(healthCheckProvider).results, isEmpty);
  });
}
