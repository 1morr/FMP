import 'dart:io';
import 'dart:math' as math;

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/fixture/fixture_adapters.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/domain/account.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/plugins/accounts/account_guard.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/dev/account_scrub.dart';
import 'package:fmp/plugins/dev/describe_error.dart';
import 'package:fmp/plugins/dev/plugin_folder.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:path/path.dart' as p;

// 一個檢查案例的隔離執行環境（ADR 0015 §決定 5–7）：記憶體資料庫、空的憑證存放、
// 新的 runtime 與 client，案例之間不共用 storage 與 cookie。真實與錄製模式下
// `requiresLogin` 的案例例外：把已存的憑證放進記憶體的憑證存放（只給請求，不刷新、
// 不寫回）。命令列契約執行器
// （test/plugins/contract/）與 App 內開發工具共用這份程式碼。

/// 一次案例執行的結果。
final class CaseRun {
  const CaseRun({
    required this.loaded,
    this.result,
    this.error,
    this.problems = const [],
    this.matched = false,
  });

  /// 插件載入成功。
  final bool loaded;
  final Object? result;
  final AppError? error;

  /// 不含能力名稱前綴：'load: …'、'threw X, not an AppError'、
  /// 'tried to reach a host outside allowedHosts (…)'、期望不符、expiresAt 的問題。
  final List<String> problems;

  /// 結果符合案例的期望。
  final bool matched;
}

Future<void> noWait(Duration _) async {}

Future<void> realWait(Duration delay) => Future<void>.delayed(delay);

bool alwaysWrite() => true;

/// `mutates` 的案例在真實與錄製模式略過的理由（命令列與開發工具同一句）。
const mutatesSkipReason = 'mutates the remote';

/// 空的 [SecureStorage]：隔離環境沒有憑證，也不會寫入。
final class _EmptySecureStorage implements SecureStorage {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) =>
      throw StateError('The isolated case environment never stores secrets');

  @override
  Future<void> delete(String key) async {}

  @override
  Future<void> deleteAll() async {}
}

/// 注入的憑證放的記憶體 [SecureStorage]：只活到案例結束，不碰平台的 secure storage。
final class _MemorySecureStorage implements SecureStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}

/// 一個案例的環境：每個案例一份記憶體資料庫，案例結束就關（drift 在 debug 下會對
/// 同時開著的多個 `AppDatabase` 警告）。
final class _IsolatedEnvironment {
  _IsolatedEnvironment({
    required this.transport,
    required this.log,
    required this.redactor,
    this.recordIds,
    this.wait = noWait,
  });

  final CaseTransport transport;
  final Log log;
  final Redactor redactor;
  final NetworkRecordIds? recordIds;

  /// 重試與限流的等待：重播不等，錄製與真實照真的時間等。
  final Future<void> Function(Duration delay) wait;

  AppDatabase? _database;
  final _stores = <CredentialStore>[];

  Future<void> close() async {
    // 只 dispose，不 delete：delete 會取消遮蔽函式裡的憑證登記，而那份登記是 App 的
    // 憑證存放共用的。
    for (final store in _stores) {
      store.dispose();
    }
    await _database?.close();
  }

  CredentialStore _store(AppDatabase database, SecureStorage storage) {
    final store = CredentialStore(
      storage: storage,
      accounts: AccountRepository(database),
      plugins: PluginRepository(database),
      settings: SourceSettingsRepository(database),
      redactor: redactor,
      log: log,
    );
    _stores.add(store);
    return store;
  }

  /// [injected] 是這個案例的請求要帶的已存憑證（真實與錄製、`requiresLogin` 的非 login
  /// 案例）；`null` 是空的憑證存放，請求都匿名。
  ///
  /// 失效處理（`AccountGuard`）永遠看空的存放：它看不到憑證就不會呼叫 `loginRefresh`。
  /// 這裡刷新會換掉音源端的 token，而新的 token 只活在這個案例的記憶體，真實的憑證存放
  /// 留著作廢的舊 token。憑證被拒時案例照實失敗。
  Future<ScriptSourcePlugin> load(
    PluginFile file, {
    LoginCredentials? injected,
  }) async {
    final database = _database = openInMemoryDatabase();
    // storage 有外鍵：先放一列（內容不重要）。
    await PluginRepository(database).install(
      InstalledPlugin(
        id: file.manifest.id,
        version: file.manifest.version,
        manifestJson: file.manifestJson,
        script: '',
        installedAt: DateTime.utc(2026),
      ),
    );
    final guarded = _store(database, _EmptySecureStorage());
    var credentials = guarded;
    if (injected != null) {
      // 空的那份先載完：它載入時會把「有帳號列、沒憑證」的列刪掉。
      await guarded.ready;
      credentials = _store(database, _MemorySecureStorage());
      await credentials.save(
        Account(
          pluginId: file.manifest.id,
          userId: '',
          displayName: '',
          status: AccountStatus.active,
          loggedInAt: DateTime.utc(2026),
        ),
        injected,
      );
    }
    final loader = ScriptPluginLoader(
      log: log,
      redactor: redactor,
      httpClients: SourceHttpClientFactory(
        log: log,
        credentials: credentials,
        recordIds: recordIds,
        createAdapter: transport.createAdapter,
        wait: wait,
        random: math.Random(7),
      ),
      storage: PluginStorageRepository(database),
      credentials: credentials,
      guard: AccountGuard(credentials: guarded, log: log),
    );
    return loader.load(file);
  }
}

/// 在隔離環境跑 [check]：記憶體資料庫放一列 installed_plugins、空的憑證存放、
/// 新的 [ScriptPluginLoader] 與 [SourceHttpClientFactory]；跑完關 runtime 與資料庫。
/// [credentials] 是這個插件已存的憑證，兩種用法：login 案例當 `loginVerify` 的輸入（換掉
/// checks.json 的假憑證）；其他 `requiresLogin` 的案例在 [transport] 是真實連線（錄製
/// 或真實）時放進隔離環境的憑證存放，請求依 ADR 0012 的規則帶它。重播
/// （[ReplayTransport]）一律不放：fixture 是遮過的，也不連網。
///
/// `mutates` 的案例不能以真實連線跑（[StateError]，不載入、不呼叫插件）：呼叫端要先略過。
///
/// 檢查：錯誤都是 `AppError`、案例的期望（DTO 驗證失敗是 `ParseError`，期望成功時
/// 就不符；`expiresAtPattern` 也算期望）、沒有試著連清單外的網域。
Future<CaseRun> runIsolatedCase({
  required PluginFile file,
  required PluginCheck check,
  required CaseTransport transport,
  required Log log,
  required Redactor redactor,
  required String reportTag,
  String reportMessage = 'Plugin case',
  LoginCredentials? credentials,
  NetworkRecordIds? recordIds,
  Future<void> Function(Duration delay) wait = noWait,
}) async {
  if (check.mutates && transport is NetworkTransport) {
    throw StateError(
      '${check.capability.wireName} mutates the remote: it is never run '
      'against the network',
    );
  }
  final injected =
      check.requiresLogin &&
          check.capability != PluginCapability.login &&
          transport is NetworkTransport
      ? credentials
      : null;
  final environment = _IsolatedEnvironment(
    transport: transport,
    log: log,
    redactor: redactor,
    recordIds: recordIds,
    wait: wait,
  );
  try {
    final ScriptSourcePlugin source;
    try {
      source = await environment.load(file, injected: injected);
    } on AppError catch (error) {
      return CaseRun(
        loaded: false,
        problems: [
          'load: ${describeError(error, log, tag: reportTag, message: reportMessage)}',
        ],
      );
    }
    Object? result;
    AppError? error;
    final problems = <String>[];
    try {
      result = await check.run(source, credentials: credentials);
    } on AppError catch (thrown) {
      error = thrown;
    } on Object catch (thrown) {
      problems.add('threw ${thrown.runtimeType}, not an AppError');
    } finally {
      source.close();
    }
    // 每個錯誤只 report 一次。
    final descriptions = Map<AppError, String>.identity();
    String describe(AppError error) => descriptions.putIfAbsent(
      error,
      () => describeError(error, log, tag: reportTag, message: reportMessage),
    );
    if (error != null) {
      final description = describe(error);
      // 網路層不送出清單外的請求，丟 Unsupported（原因 `Host not allowed`、
      // `Redirect to a host not allowed`）。插件自己接住吞掉的看不到。
      if (error is Unsupported && description.contains('not allowed')) {
        problems.add(
          'tried to reach a host outside allowedHosts ($description)',
        );
      }
    }
    // 沒丟 AppError 以外的東西、沒試著出網域，才比對期望。
    final mismatches = problems.isEmpty
        ? [
            ...check.expectation.evaluate(
              result: result,
              error: error,
              describe: describe,
            ),
            ...check.extraProblems(result),
          ]
        : null;
    problems.addAll(mismatches ?? const <String>[]);
    return CaseRun(
      loaded: true,
      result: result,
      error: error,
      problems: problems,
      matched: mismatches?.isEmpty ?? false,
    );
  } finally {
    await environment.close();
  }
}

/// 只載入一次（能力與匯出一致、腳本讀得懂）；載入得了回 `null`，否則回錯誤。
Future<AppError?> loadIsolated({
  required PluginFile file,
  required Log log,
  required Redactor redactor,
}) async {
  final environment = _IsolatedEnvironment(
    transport: const CaseTransports().replay(
      const [],
      redactor,
      AllowedHosts(file.manifest.allowedHosts),
    ),
    log: log,
    redactor: redactor,
  );
  try {
    (await environment.load(file)).close();
    return null;
  } on AppError catch (error) {
    return error;
  } finally {
    await environment.close();
  }
}

/// [recordCase] 的結果。
final class RecordResult {
  const RecordResult({
    this.problems = const [],
    this.skipped,
    this.written,
    this.run,
  });

  /// 已帶 '<能力>: ' 前綴。
  final List<String> problems;

  /// '<能力>: requires a login'、'<能力>: mutates the remote'、
  /// '<能力>: has hand-edited fixtures'。
  final String? skipped;

  /// 寫了幾個檔；沒寫是 `null`。
  final int? written;

  /// 略過時是 `null`。
  final CaseRun? run;
}

/// 以 [transport]（錄製）跑 [check]，寫進 `<folder>/fixtures/<能力>/`。
///
/// `mutates` → 略過（不呼叫插件）；`requiresLogin` 而沒給 [credentials] → 略過；有
/// `meta.edited` 的 fixture → 略過（手寫或手改的）；結果符合期望且錄製沒有問題才寫，
/// 否則原檔不動並回報原因。網路層重試成功的請求照樣寫：失敗的那幾次沒有回應，不會被
/// 錄到。[shouldWrite] 在寫檔前一刻呼叫，回假就不寫。
///
/// 帶憑證錄的案例（`requiresLogin`）寫檔前先換掉流量裡的帳號資訊，換完仍看得到就不寫
/// （見下）。login 案例的帳號來自結果；其他案例的帳號是 [account]（App 的 `accounts`
/// 列），沒給就不錄：沒有已知的值可換，不能靠鍵名猜。
Future<RecordResult> recordCase(
  PluginFolder folder,
  PluginCheck check, {
  required NetworkTransport transport,
  required Log log,
  required Redactor redactor,
  required String reportTag,
  String reportMessage = 'Plugin case',
  LoginCredentials? credentials,
  LoginAccount? account,
  NetworkRecordIds? recordIds,
  Future<void> Function(Duration delay) wait = realWait,
  bool Function() shouldWrite = alwaysWrite,
}) async {
  final name = check.capability.wireName;
  if (check.mutates) return RecordResult(skipped: '$name: $mutatesSkipReason');
  if (check.requiresLogin && credentials == null) {
    return RecordResult(skipped: '$name: requires a login');
  }
  final isLogin = check.capability == PluginCapability.login;
  if (check.requiresLogin && !isLogin && account == null) {
    return RecordResult(
      problems: [
        '$name: fixtures not written: no stored account to scrub the '
            'recorded traffic with',
      ],
    );
  }
  final existing = folder.fixtures[name] ?? const [];
  if (existing.any((named) => named.fixture.edited != null)) {
    return RecordResult(skipped: '$name: has hand-edited fixtures');
  }
  final run = await runIsolatedCase(
    file: folder.file!,
    check: check,
    transport: transport,
    log: log,
    redactor: redactor,
    reportTag: reportTag,
    reportMessage: reportMessage,
    credentials: credentials,
    recordIds: recordIds,
    wait: wait,
  );
  final problems = [for (final problem in run.problems) '$name: $problem'];
  if (!run.loaded) return RecordResult(problems: problems, run: run);
  if (transport.problems.isNotEmpty) {
    return RecordResult(
      problems: [
        ...problems,
        for (final problem in transport.problems) '$name: $problem',
      ],
      run: run,
    );
  }
  if (!run.matched) {
    return RecordResult(
      problems: [
        ...problems,
        '$name: fixtures not written: the outcome does not match checks.json',
      ],
      run: run,
    );
  }
  // 要登入的案例以已存的憑證錄（App 內）：fixture 會進公開的插件 repo，回應裡的帳號資訊
  // 先換成 `***`（scrubAccount），換完仍看得到才不寫（accountLeaks 是最後一道）。以
  // 帳號的值為準（login 是結果、其他是 accounts 列），不靠鍵名。
  var recorded = transport.recorded;
  final known = switch (run.result) {
    _ when !check.requiresLogin => null,
    final LoginAccount verified when isLogin => verified,
    _ => isLogin ? null : account,
  };
  // login 案例期望失敗時沒有結果可取帳號，照舊不換（原行為）。
  if (known != null) {
    recorded = scrubAccount(recorded, known);
    final leaked = accountLeaks(recorded, known);
    if (leaked.isNotEmpty) {
      return RecordResult(
        problems: [
          ...problems,
          '$name: fixtures not written: the recorded traffic still contains '
              "the account's ${leaked.join(', ')} after scrubbing",
        ],
        run: run,
      );
    }
  }
  if (!shouldWrite()) return RecordResult(problems: problems, run: run);
  writeFixtures(
    Directory(p.join(folder.directory.path, 'fixtures', name)),
    recorded,
  );
  return RecordResult(problems: problems, written: recorded.length, run: run);
}
