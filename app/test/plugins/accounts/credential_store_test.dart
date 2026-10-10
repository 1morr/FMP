import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/accounts/account_guard.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';

import '../../core/network/harness.dart' show allowedHosts;
import '../../support/credentials.dart';
import '../../support/fake_http_adapter.dart';
import '../../support/memory_database.dart';

const _sessdata = 'FAKE_SESSDATA_123';
const _credentials = LoginCredentials(
  cookies: {'SESSDATA': _sessdata, 'bili_jct': 'FAKE_JCT_4567'},
  extra: {'refresh_token': 'FAKE_REFRESH_89'},
);
const _renewed = LoginCredentials(cookies: {'SESSDATA': 'FAKE_SESSDATA_NEW'});

Account _account(
  String pluginId, {
  AccountStatus status = AccountStatus.active,
}) => Account(
  pluginId: pluginId,
  userId: 'u',
  displayName: 'Someone',
  status: status,
  loggedInAt: DateTime.utc(2026, 10, 9),
);

/// [gate] 非空時，讀到值之後等它完成才回傳：模擬平台的讀取已經拿到舊值、還沒
/// 交回來的那段時間。
final class _GatedStorage implements SecureStorage {
  final _inner = InMemorySecureStorage();
  Completer<void>? gate;

  /// 依序讀過的鍵。
  final reads = <String>[];

  Map<String, String> get values => _inner.values;

  set readError(Object? error) => _inner.readError = error;

  set writeError(Object? error) => _inner.writeError = error;

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    final value = await _inner.read(key);
    if (gate case final gate?) await gate.future;
    return value;
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<void> deleteAll() => _inner.deleteAll();
}

/// 一個 [CredentialStore] 和它用到的東西。
final class _Setup {
  _Setup() {
    database = memoryDatabase();
    log = Log(redactor: redactor, minimumLevel: LogLevel.debug);
    accounts = AccountRepository(database);
    plugins = PluginRepository(database);
    settings = SourceSettingsRepository(database);
  }

  late final AppDatabase database;
  final redactor = Redactor();
  late final Log log;
  final storage = _GatedStorage();
  late final AccountRepository accounts;
  late final PluginRepository plugins;
  late final SourceSettingsRepository settings;

  CredentialStore create() {
    final store = CredentialStore(
      storage: storage,
      accounts: accounts,
      plugins: plugins,
      settings: settings,
      redactor: redactor,
      log: log,
    );
    addTearDown(store.dispose);
    return store;
  }

  /// 在 `installed_plugins` 放一列；[login] 為假時 manifest 沒有宣告 `login`。
  Future<void> install(String id, {bool login = true}) => plugins.install(
    InstalledPlugin(
      id: id,
      version: '1.0.0',
      manifestJson: jsonEncode({
        'id': id,
        'name': id,
        'version': '1.0.0',
        'author': 'FMP tests',
        'apiVersion': 1,
        'capabilities': ['search', if (login) 'login'],
        'allowedHosts': ['example.test'],
        if (login)
          'login': {
            'methods': ['qr'],
          },
      }),
      script: '',
      installedAt: DateTime.utc(2026),
    ),
  );

  /// 已經存在 secure storage 與帳號表的登入。
  Future<void> seed(
    String id, {
    LoginCredentials credentials = _credentials,
    AccountStatus status = AccountStatus.active,
  }) async {
    storage.values['credentials.$id'] = jsonEncode(credentials.toJson());
    await accounts.upsert(_account(id, status: status));
  }

  List<LogRecord> warnings() => [
    for (final record in log.history)
      if (record.level == LogLevel.warning && record.tag == 'credentials')
        record,
  ];
}

void main() {
  group('saving and reading', () {
    test(
      'save writes the storage and the account, then serves memory',
      () async {
        final setup = _Setup();
        final store = setup.create();

        await store.save(_account('bilibili'), _credentials);

        expect(
          jsonDecode(setup.storage.values['credentials.bilibili']!),
          _credentials.toJson(),
        );
        expect(await setup.accounts.list(), [_account('bilibili')]);
        expect(await store.state('bilibili'), CredentialState.active);
        expect(await store.activeCredentials('bilibili'), _credentials);
        final material = await store.credentialMaterial('bilibili');
        expect(material?.cookies, _credentials.cookies);
        expect(material?.headers, isEmpty);
        expect(await store.credentialCookieNames('bilibili'), {
          'SESSDATA',
          'bili_jct',
        });
      },
    );

    test('a plugin without credentials has none of everything', () async {
      final store = _Setup().create();

      expect(await store.state('bilibili'), CredentialState.none);
      expect(await store.activeCredentials('bilibili'), isNull);
      expect(await store.credentialMaterial('bilibili'), isNull);
      expect(await store.credentialCookieNames('bilibili'), isEmpty);
    });

    test('credentials of two plugins do not mix', () async {
      final setup = _Setup();
      final store = setup.create();

      await store.save(_account('a'), _credentials);
      await store.save(
        _account('b'),
        const LoginCredentials(cookies: {'x': 'FAKE_OTHER_1'}),
      );

      expect((await store.activeCredentials('a'))?.cookies.keys, [
        'SESSDATA',
        'bili_jct',
      ]);
      expect((await store.activeCredentials('b'))?.cookies, {
        'x': 'FAKE_OTHER_1',
      });
    });

    test('a failed storage write leaves no account row', () async {
      final setup = _Setup();
      final store = setup.create();
      setup.storage.writeError = StateError('keystore');

      await expectLater(
        store.save(_account('bilibili'), _credentials),
        throwsStateError,
      );

      expect(await setup.accounts.list(), isEmpty);
      expect(await store.state('bilibili'), CredentialState.none);
    });

    // 憑證寫好、帳號列沒寫進去：登入失敗、這次執行不帶它，下次啟動對齊刪掉。
    test('a failed account write fails the save; the next start removes the '
        'credentials', () async {
      final setup = _Setup();
      await setup.install('bilibili');
      final store = setup.create();
      await store.ready;
      await setup.database.customStatement(
        'CREATE TRIGGER fail_accounts BEFORE INSERT ON accounts '
        "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
      );

      await expectLater(
        store.save(_account('bilibili'), _credentials),
        throwsA(anything),
      );

      expect(setup.storage.values, contains('credentials.bilibili'));
      expect(await store.state('bilibili'), CredentialState.none);
      expect(await store.credentialMaterial('bilibili'), isNull);
      // 遮蔽只在寫入成功後登記（登入流程裡 loginVerify 呼叫前已經登記過）。
      expect(setup.redactor.redact(_sessdata), _sessdata);

      await setup.database.customStatement('DROP TRIGGER fail_accounts');
      final next = setup.create();
      await next.ready;

      expect(setup.storage.values, isEmpty);
      expect(await next.state('bilibili'), CredentialState.none);
    });

    test(
      'delete clears the storage and the memory, and can be repeated',
      () async {
        final setup = _Setup();
        final store = setup.create();
        await store.save(_account('bilibili'), _credentials);

        await store.delete('bilibili');
        await store.delete('bilibili');

        expect(setup.storage.values, isEmpty);
        expect(await store.state('bilibili'), CredentialState.none);
        expect(await store.credentialMaterial('bilibili'), isNull);
      },
    );
  });

  group('loading at startup', () {
    test('reads what was saved before', () async {
      final setup = _Setup();
      await setup.install('bilibili');
      await setup.seed('bilibili');

      final store = setup.create();

      expect(await store.state('bilibili'), CredentialState.active);
      expect(await store.activeCredentials('bilibili'), _credentials);
    });

    test(
      'an invalidated credential is kept, not sent, but its names stay',
      () async {
        final setup = _Setup();
        await setup.install('bilibili');
        await setup.seed('bilibili', status: AccountStatus.invalidated);

        final store = setup.create();

        expect(await store.state('bilibili'), CredentialState.invalidated);
        expect(await store.credentialMaterial('bilibili'), isNull);
        expect(await store.activeCredentials('bilibili'), isNull);
        // 保留的憑證名稱仍不准從 cookie jar 送出。
        expect(
          await store.credentialCookieNames('bilibili'),
          contains('SESSDATA'),
        );
        expect(setup.storage.values, contains('credentials.bilibili'));
      },
    );

    test('an account row without credentials is removed', () async {
      final setup = _Setup();
      await setup.install('bilibili');
      await setup.accounts.upsert(_account('bilibili'));

      final store = setup.create();

      expect(await store.state('bilibili'), CredentialState.none);
      expect(await setup.accounts.list(), isEmpty);
      expect(setup.warnings(), hasLength(1));
    });

    test('credentials without an account row are removed', () async {
      final setup = _Setup();
      await setup.install('bilibili');
      setup.storage.values['credentials.bilibili'] = jsonEncode(
        _credentials.toJson(),
      );

      final store = setup.create();

      expect(await store.state('bilibili'), CredentialState.none);
      expect(setup.storage.values, isEmpty);
      expect(setup.warnings(), hasLength(1));
      // 沒有載入的憑證，值也沒有被登記到遮蔽函式。
      expect(setup.redactor.redact(_sessdata), _sessdata);
    });

    test('a plugin that does not declare login is not read', () async {
      final setup = _Setup();
      await setup.install('bilibili', login: false);
      setup.storage.values['credentials.bilibili'] = jsonEncode(
        _credentials.toJson(),
      );

      final store = setup.create();
      await store.ready;

      // 沒讀它：沒有對齊（憑證還在、沒有 warning）。
      expect(setup.storage.reads, isNot(contains('credentials.bilibili')));
      expect(setup.storage.values, contains('credentials.bilibili'));
      expect(setup.warnings(), isEmpty);
      // 同樣的插件宣告了 login 就讀（對照）。
      await setup.install('bilibili');
      final declared = setup.create();
      await declared.ready;
      expect(setup.storage.reads, contains('credentials.bilibili'));
    });

    test('an account of a plugin that is gone is still aligned', () async {
      final setup = _Setup();
      await setup.accounts.upsert(_account('removed'));

      final store = setup.create();
      await store.ready;

      expect(await setup.accounts.list(), isEmpty);
    });
  });

  group('a read failure', () {
    test('keeps everything and is not an absent credential', () async {
      final setup = _Setup();
      await setup.install('bilibili');
      await setup.seed('bilibili');
      setup.storage.readError = StateError('keystore');

      final store = setup.create();

      expect(await store.state('bilibili'), CredentialState.unreadable);
      expect(await store.credentialMaterial('bilibili'), isNull);
      expect(await store.activeCredentials('bilibili'), isNull);
      // 沒有刪除任何東西：憑證還在，帳號列還在。
      expect(setup.storage.values, contains('credentials.bilibili'));
      expect(await setup.accounts.list(), hasLength(1));
    });

    test('content that cannot be parsed is kept too', () async {
      final setup = _Setup();
      await setup.install('bilibili');
      await setup.accounts.upsert(_account('bilibili'));
      setup.storage.values['credentials.bilibili'] = 'not json';

      final store = setup.create();

      expect(await store.state('bilibili'), CredentialState.unreadable);
      expect(setup.storage.values['credentials.bilibili'], 'not json');
      expect(await setup.accounts.list(), hasLength(1));
    });

    test('is read again after 30 seconds, once', () {
      fakeAsync((async) {
        final setup = _Setup();
        late CredentialStore store;

        Future<void> run() async {
          await setup.install('bilibili');
          await setup.seed('bilibili');
          setup.storage.readError = StateError('keystore');
          store = setup.create();
          await store.ready;
        }

        run();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        CredentialState? state;
        Future<void> look() async => state = await store.state('bilibili');
        look();
        async.flushMicrotasks();
        expect(state, CredentialState.unreadable);

        // 29 秒還沒到。
        setup.storage.readError = null;
        async.elapse(credentialRetryDelay - const Duration(seconds: 1));
        look();
        async.flushMicrotasks();
        expect(state, CredentialState.unreadable);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        look();
        async.flushMicrotasks();
        expect(state, CredentialState.active);
        // 重讀成功後沒有待執行的計時器。
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('a failed re-read is not tried again', () {
      fakeAsync((async) {
        final setup = _Setup();
        late CredentialStore store;

        Future<void> run() async {
          await setup.install('bilibili');
          await setup.seed('bilibili');
          setup.storage.readError = StateError('keystore');
          store = setup.create();
          await store.ready;
        }

        run();
        async.flushMicrotasks();
        async.elapse(credentialRetryDelay);
        async.flushMicrotasks();

        CredentialState? state;
        store.state('bilibili').then((value) => state = value);
        async.flushMicrotasks();
        expect(state, CredentialState.unreadable);
        expect(async.pendingTimers, isEmpty);
        expect(setup.storage.values, contains('credentials.bilibili'));
      });
    });

    // 重讀已經拿到舊值時使用者登出或重新登入：重讀的結果不能蓋掉之後的寫入。
    for (final (name, change, expected) in [
      (
        'a logout during the re-read stays logged out',
        (CredentialStore store) => store.delete('bilibili'),
        null,
      ),
      (
        'a login during the re-read keeps the new credentials',
        (CredentialStore store) => store.save(_account('bilibili'), _renewed),
        _renewed,
      ),
    ]) {
      test(name, () {
        fakeAsync((async) {
          final setup = _Setup();
          late CredentialStore store;

          Future<void> run() async {
            await setup.install('bilibili');
            await setup.seed('bilibili');
            setup.storage.readError = StateError('keystore');
            store = setup.create();
            await store.ready;
          }

          run();
          async.flushMicrotasks();
          setup.storage.readError = null;
          final gate = setup.storage.gate = Completer<void>();
          async.elapse(credentialRetryDelay);
          async.flushMicrotasks();

          change(store);
          async.flushMicrotasks();
          setup.storage.gate = null;
          gate.complete();
          async.flushMicrotasks();

          LoginCredentials? active;
          Set<String>? names;
          Future<void> look() async {
            active = await store.activeCredentials('bilibili');
            names = await store.credentialCookieNames('bilibili');
          }

          look();
          async.flushMicrotasks();
          expect(active, expected);
          expect(names, expected?.cookies.keys.toSet() ?? isEmpty);
          // 遮蔽登記跟著最後留下的那份。
          if (expected != null) {
            for (final value in expected.values) {
              expect(setup.redactor.redact(value), '***');
            }
          }
        });
      });
    }
  });

  group('redaction', () {
    test('values are registered on save and cancelled on delete', () async {
      final setup = _Setup();
      final store = setup.create();

      await store.save(_account('bilibili'), _credentials);

      for (final value in _credentials.values) {
        expect(setup.redactor.redact('x $value y'), 'x *** y');
      }

      await store.delete('bilibili');
      expect(setup.redactor.redact(_sessdata), _sessdata);
    });

    test(
      'values shorter than the minimum are skipped without failing',
      () async {
        final setup = _Setup();
        final store = setup.create();
        expect('ab'.length, lessThan(Redactor.minimumSecretLength));

        await store.save(
          _account('bilibili'),
          const LoginCredentials(
            cookies: {'home_feed_column': '5', 'SESSDATA': _sessdata},
            extra: {'flag': 'ab'},
          ),
        );

        expect(await store.state('bilibili'), CredentialState.active);
        expect(setup.redactor.redact('column 5, flag ab'), 'column 5, flag ab');
        expect(setup.redactor.redact(_sessdata), '***');
        await store.delete('bilibili');
      },
    );

    test('the values are in neither the log nor the network record', () async {
      final setup = _Setup();
      final store = setup.create();
      await store.save(_account('bilibili'), _credentials);
      final adapter = FakeHttpAdapter((_) => reply(200));
      final client = SourceHttpClientFactory(
        log: setup.log,
        credentials: store,
        createAdapter: () => adapter,
      ).create(pluginId: 'bilibili', allowedHosts: allowedHosts);

      final response = await client.send(
        SourceRequest(
          Uri.parse('https://example.test/a?SESSDATA=$_sessdata'),
          auth: AuthRequirement.userPreference,
        ),
      );
      setup.log.info('login finished: SESSDATA=$_sessdata', tag: 'test');
      setup.log.warning(
        'bad cookie',
        tag: 'test',
        fields: {'cookie': 'x $_sessdata y'},
      );

      expect(response.credentialsAttached, isTrue);
      expect(adapter.requests.single.headers['cookie'], contains(_sessdata));
      final history = setup.log.history.map((r) => '$r ${r.fields}').join('\n');
      for (final value in _credentials.values) {
        expect(history, isNot(contains(value)));
      }
      expect(history, contains('network'));
    });
  });

  group('logging out', () {
    test('removes the credentials and the account, keeps source settings, '
        'and later requests carry nothing', () async {
      final setup = _Setup();
      final store = setup.create();
      await store.save(_account('bilibili'), _credentials);
      await setup.settings.setBrowseAsLoggedIn('bilibili', value: false);
      final adapter = FakeHttpAdapter((options) {
        if (options.uri.path == '/seed') {
          return reply(
            200,
            headers: {'Set-Cookie': 'buvid3=FAKE_BUVID_123; Path=/'},
          );
        }
        return reply(200);
      });
      final factory = SourceHttpClientFactory(
        log: setup.log,
        credentials: store,
        createAdapter: () => adapter,
      );
      final client = factory.create(
        pluginId: 'bilibili',
        allowedHosts: allowedHosts,
      );
      final service = AccountService(
        credentials: store,
        accounts: setup.accounts,
        settings: setup.settings,
        clearCookies: factory.clearCookies,
        plugins: setup.plugins,
        loginWebView: null,
        guard: AccountGuard(credentials: store, log: setup.log),
      );
      await client.send(SourceRequest(Uri.parse('https://example.test/seed')));
      await setup.settings.setBrowseAsLoggedIn('bilibili', value: true);

      await service.logout('bilibili');

      expect(setup.storage.values, isEmpty);
      expect(await setup.accounts.list(), isEmpty);
      expect(await store.state('bilibili'), CredentialState.none);
      expect(await setup.settings.browseAsLoggedIn('bilibili'), isTrue);
      adapter.requests.clear();
      final response = await client.send(
        SourceRequest(
          Uri.parse('https://example.test/a'),
          auth: AuthRequirement.userPreference,
        ),
      );
      // 憑證不帶了，記憶體 jar 的匿名 cookie 也一併清掉。
      expect(adapter.requests.single.headers['cookie'], isNull);
      expect(response.credentialsAttached, isFalse);
      expect(setup.redactor.redact(_sessdata), _sessdata);
    });

    test('removing a plugin also drops its source settings', () async {
      final setup = _Setup();
      final store = setup.create();
      await store.save(_account('bilibili'), _credentials);
      await setup.settings.setBrowseAsLoggedIn('bilibili', value: false);
      final service = AccountService(
        credentials: store,
        accounts: setup.accounts,
        settings: setup.settings,
        clearCookies: (_) async {},
        plugins: setup.plugins,
        loginWebView: null,
        guard: AccountGuard(credentials: store, log: setup.log),
      );

      await service.removePlugin('bilibili');
      await service.removePlugin('bilibili');

      expect(setup.storage.values, isEmpty);
      expect(await setup.accounts.list(), isEmpty);
      expect(await setup.settings.browseAsLoggedIn('bilibili'), isNull);
    });
  });

  group('the browse switch', () {
    test('is on until the user turns it off', () async {
      final setup = _Setup();
      final store = setup.create();
      expect(await store.browseAsLoggedIn('bilibili'), isTrue);

      await setup.settings.setBrowseAsLoggedIn('bilibili', value: false);
      expect(await store.browseAsLoggedIn('bilibili'), isFalse);
    });
  });
}
