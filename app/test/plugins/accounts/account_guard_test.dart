import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/plugins/accounts/account_guard.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/fake_network_interfaces.dart';
import '../../support/pump_until.dart';
import '../plugin_harness.dart';

// 假憑證。刷新的結果由舊憑證的值決定（見 [_script] 的 loginRefresh）。
const _old = LoginCredentials(cookies: {'SESSDATA': 'FAKE_OLD_SESSION'});
const _new = LoginCredentials(cookies: {'SESSDATA': 'FAKE_NEW_SESSION'});
const _nothingNew = LoginCredentials(
  cookies: {'SESSDATA': 'FAKE_NULL_SESSION'},
);
const _refused = LoginCredentials(cookies: {'SESSDATA': 'FAKE_HARD_SESSION'});
const _offline = LoginCredentials(cookies: {'SESSDATA': 'FAKE_NET_SESSION'});

/// 搜尋 `https://example.test/s`（`userPreference`）：帶了憑證的 401 是憑證失效。
/// 關鍵字 `rate`、`net` 直接丟限流與網路錯誤。`loginRefresh`（宣告 refresh 時才匯出）
/// 先打一次 `/refresh` 讓測試數得到次數。
String _script({required bool refresh}) =>
    '''
export async function search({ keyword }) {
  if (keyword === 'rate') throw { fmpError: 'RateLimited' };
  if (keyword === 'net') throw { fmpError: 'NetworkError' };
  const response = await fmp.http.request({
    url: 'https://example.test/s',
    auth: 'userPreference',
  });
  if (response.credentialsAttached && response.status === 401) {
    throw { fmpError: 'CredentialInvalid' };
  }
  return { items: [], hasMore: false };
}
export function loginVerify() { return { userId: '42', displayName: 'Tester' }; }
${refresh ? '''
export async function loginRefresh(credentials) {
  await fmp.http.request({ url: 'https://example.test/refresh', auth: 'never' });
  switch (credentials.cookies.SESSDATA) {
    case 'FAKE_OLD_SESSION': return { cookies: { SESSDATA: 'FAKE_NEW_SESSION' } };
    case 'FAKE_HARD_SESSION': throw { fmpError: 'CredentialInvalid' };
    case 'FAKE_NET_SESSION': throw { fmpError: 'NetworkError' };
    default: return null;
  }
}
''' : ''}
''';

/// `/s` 只認新憑證；`/refresh` 永遠成功。
ResponseBody _server(RequestOptions options) {
  if (options.uri.path == '/s') {
    return options.headers['cookie'] == 'SESSDATA=FAKE_NEW_SESSION'
        ? reply(200)
        : reply(401);
  }
  return reply(200);
}

Account _account() => Account(
  pluginId: 'plugin-a',
  userId: '42',
  displayName: 'Tester',
  status: AccountStatus.active,
  loggedInAt: DateTime.utc(2026, 10, 9),
);

final class _Fixture {
  _Fixture._(this.harness, this.plugin) {
    final subscription = harness.guard.invalidations.listen(invalidations.add);
    addTearDown(subscription.cancel);
  }

  final PluginHarness harness;
  final ScriptSourcePlugin plugin;
  final invalidations = <AccountInvalidated>[];

  static Future<_Fixture> create({
    bool refresh = true,
    LoginCredentials? credentials = _old,
    FutureOr<ResponseBody> Function(RequestOptions options) handler = _server,
  }) async {
    final harness = PluginHarness(handler: handler);
    final plugin = await harness.load(
      pluginSource(
        _script(refresh: refresh),
        capabilities: ['search', 'login'],
        login:
            '{"methods": ["cookie"]'
            '${refresh ? ', "refresh": "onStartup"' : ''}}',
      ),
    );
    await harness.credentials.ready;
    if (credentials != null) {
      await harness.credentials.save(_account(), credentials);
    }
    return _Fixture._(harness, plugin);
  }

  Future<SearchPage> search([String keyword = 'x']) =>
      plugin.search(SearchQuery(keyword: keyword, page: 1));

  List<String> get paths => [
    for (final request in harness.adapter.requests) request.uri.path,
  ];

  int get refreshes => paths.where((path) => path == '/refresh').length;

  Future<Account> account() async =>
      (await AccountRepository(harness.database).list()).single;

  AccountService get service => AccountService(
    credentials: harness.credentials,
    accounts: AccountRepository(harness.database),
    settings: SourceSettingsRepository(harness.database),
    clearCookies: (_) async {},
    plugins: harness.plugins,
    loginWebView: null,
    guard: harness.guard,
  );
}

void main() {
  group('a rejected credential', () {
    test('is refreshed, and the rerun carries the new credentials', () async {
      final f = await _Fixture.create();

      await f.search();

      // 第一次帶舊的被拒，刷新之後重跑的那次帶新的。
      expect(f.paths, ['/s', '/refresh', '/s']);
      final requests = f.harness.adapter.requests;
      expect(requests.first.headers['cookie'], 'SESSDATA=FAKE_OLD_SESSION');
      expect(requests.last.headers['cookie'], 'SESSDATA=FAKE_NEW_SESSION');
      expect(await f.harness.credentials.activeCredentials('plugin-a'), _new);
      final account = await f.account();
      expect(account.status, AccountStatus.active);
      expect(account.lastRefreshResult, RefreshResult.refreshed);
      expect(account.lastRefreshAt, isNotNull);
      expect(f.invalidations, isEmpty);
    });

    test('three concurrent calls refresh once', () async {
      final f = await _Fixture.create();

      await Future.wait([f.search('a'), f.search('b'), f.search('c')]);

      expect(f.refreshes, 1);
      expect(await f.harness.credentials.activeCredentials('plugin-a'), _new);
      expect(f.invalidations, isEmpty);
    });

    test('a call that began before another call refreshed is rerun without '
        'refreshing again', () async {
      final f = await _Fixture.create();
      var calls = 0;

      final result = await f.harness.guard.run(f.plugin, () async {
        calls++;
        if (calls == 1) {
          // 這次呼叫還在路上時，別的呼叫已經把憑證換成新的了。
          await f.harness.credentials.save(_account(), _new);
          throw CredentialInvalid(
            pluginId: 'plugin-a',
            cause: StateError('rejected'),
            stackTrace: StackTrace.current,
          );
        }
        return 'done';
      });

      expect(result, 'done');
      expect(calls, 2);
      expect(f.refreshes, 0);
    });

    test('is marked invalidated when the plugin cannot refresh, and says so '
        'once', () async {
      final f = await _Fixture.create(refresh: false);

      await expectLater(f.search(), throwsA(isA<CredentialInvalid>()));

      expect(f.refreshes, 0);
      expect(
        await f.harness.credentials.state('plugin-a'),
        CredentialState.invalidated,
      );
      expect((await f.account()).status, AccountStatus.invalidated);
      // 憑證保留，只是不再帶。
      expect(await f.harness.credentials.credentialCookieNames('plugin-a'), {
        'SESSDATA',
      });
      expect(f.invalidations, hasLength(1));

      // 之後的請求不帶憑證（401 只是匿名被拒），不再提示。
      f.harness.adapter.requests.clear();
      await f.search();
      expect(f.harness.adapter.requests.single.headers['cookie'], isNull);
      expect(f.invalidations, hasLength(1));

      // 重新登入後下一次失效再提示。
      await f.harness.credentials.save(_account(), _old);
      await expectLater(f.search(), throwsA(isA<CredentialInvalid>()));
      expect(f.invalidations, hasLength(2));
    });

    test('is marked invalidated when the refresh gives nothing new', () async {
      final f = await _Fixture.create(credentials: _nothingNew);

      await expectLater(f.search(), throwsA(isA<CredentialInvalid>()));

      expect(f.refreshes, 1);
      final account = await f.account();
      expect(account.status, AccountStatus.invalidated);
      expect(account.lastRefreshResult, RefreshResult.failed);
      expect(f.invalidations, hasLength(1));
    });

    test('is marked invalidated when the refresh is refused', () async {
      final f = await _Fixture.create(credentials: _refused);

      await expectLater(f.search(), throwsA(isA<CredentialInvalid>()));

      expect(f.refreshes, 1);
      expect((await f.account()).status, AccountStatus.invalidated);
      expect(f.invalidations, hasLength(1));
    });

    test('is marked invalidated, with no loop, when the rerun is refused '
        'too', () async {
      final f = await _Fixture.create(handler: (_) => reply(401));

      await expectLater(f.search(), throwsA(isA<CredentialInvalid>()));

      expect(f.paths, ['/s', '/refresh', '/s']);
      expect((await f.account()).status, AccountStatus.invalidated);
      expect(f.invalidations, hasLength(1));
    });

    test('is kept when the refresh fails on the network', () async {
      final f = await _Fixture.create(credentials: _offline);

      await expectLater(f.search(), throwsA(isA<NetworkError>()));

      final account = await f.account();
      expect(account.status, AccountStatus.active);
      expect(account.lastRefreshResult, RefreshResult.failed);
      expect(
        await f.harness.credentials.state('plugin-a'),
        CredentialState.active,
      );
      expect(f.invalidations, isEmpty);
    });
  });

  group('other failures', () {
    test(
      'rate limits and network errors do not refresh or invalidate',
      () async {
        final f = await _Fixture.create();

        await expectLater(f.search('rate'), throwsA(isA<RateLimited>()));
        await expectLater(f.search('net'), throwsA(isA<NetworkError>()));

        expect(f.refreshes, 0);
        expect(
          await f.harness.credentials.state('plugin-a'),
          CredentialState.active,
        );
        expect(f.invalidations, isEmpty);
      },
    );

    test('an anonymous 401 is not an invalid credential', () async {
      final f = await _Fixture.create(credentials: null);

      await f.search();

      expect(f.refreshes, 0);
      expect(f.invalidations, isEmpty);
    });
  });

  group('startup refresh', () {
    test('writes the new credentials and the result', () async {
      final f = await _Fixture.create();

      await f.service.refreshOnStartup([f.plugin]);

      expect(await f.harness.credentials.activeCredentials('plugin-a'), _new);
      expect((await f.account()).lastRefreshResult, RefreshResult.refreshed);
    });

    test('records "unchanged" when there is nothing new', () async {
      final f = await _Fixture.create(credentials: _nothingNew);

      await f.service.refreshOnStartup([f.plugin]);

      final account = await f.account();
      expect(account.status, AccountStatus.active);
      expect(account.lastRefreshResult, RefreshResult.unchanged);
      expect(account.lastRefreshAt, isNotNull);
    });

    test('marks a refused credential invalidated and says so', () async {
      final f = await _Fixture.create(credentials: _refused);

      await f.service.refreshOnStartup([f.plugin]);

      final account = await f.account();
      expect(account.status, AccountStatus.invalidated);
      expect(account.lastRefreshResult, RefreshResult.failed);
      expect(f.invalidations, hasLength(1));
    });

    test('keeps the account usable on a network error', () async {
      final f = await _Fixture.create(credentials: _offline);

      await f.service.refreshOnStartup([f.plugin]);

      final account = await f.account();
      expect(account.status, AccountStatus.active);
      expect(account.lastRefreshResult, RefreshResult.failed);
      expect(f.invalidations, isEmpty);
    });

    test('skips signed-out accounts and plugins that cannot refresh', () async {
      final signedOut = await _Fixture.create(credentials: null);
      await signedOut.service.refreshOnStartup([signedOut.plugin]);
      expect(signedOut.refreshes, 0);

      final noRefresh = await _Fixture.create(refresh: false);
      await noRefresh.service.refreshOnStartup([noRefresh.plugin]);
      expect(noRefresh.paths, isEmpty);
    });
  });

  group('the startup refresh provider', () {
    Future<(FakeNetworkInterfaces, _Fixture, ProviderContainer)> start({
      required bool available,
    }) async {
      final f = await _Fixture.create();
      final interfaces = FakeNetworkInterfaces(available: available);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          networkInterfacesProvider.overrideWithValue(interfaces),
          logProvider.overrideWithValue(f.harness.log),
          accountServiceProvider.overrideWithValue(f.service),
          pluginRegistryProvider.overrideWithBuild(
            (ref, notifier) => {'plugin-a': f.plugin},
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(accountStartupRefreshProvider);
      return (interfaces, f, container);
    }

    test('does not refresh offline, refreshes once when online', () async {
      final (interfaces, f, container) = await start(available: false);
      await pumpUntil(
        () =>
            container.read(networkStatusProvider) == NetworkStatus.noInterface,
      );
      await settle();
      expect(f.refreshes, 0);

      interfaces.change(available: true);
      await pumpUntil(() => f.refreshes == 1, maxRounds: 500);
      await pumpUntil(
        () => container.read(networkStatusProvider) == NetworkStatus.online,
      );

      // 之後斷線再回來也不再刷新。
      interfaces.change(available: false);
      interfaces.change(available: true);
      await settle();
      await settle();
      expect(f.refreshes, 1);
      expect((await f.account()).lastRefreshResult, RefreshResult.refreshed);
    });

    test('refreshes at startup when the network is already up', () async {
      final (_, f, _) = await start(available: true);

      await pumpUntil(() => f.refreshes == 1, maxRounds: 500);

      expect(f.refreshes, 1);
    });
  });
}
