import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/runtime/plugin_host.dart';
import 'package:fmp/plugins/runtime/plugin_runtime.dart';
import 'package:fmp/plugins/runtime/plugin_worker.dart';
import 'package:fmp/plugins/script_source_plugin.dart';

import '../support/credentials.dart';
import '../support/fake_http_adapter.dart';
import '../support/memory_database.dart';

/// 測試插件的安裝檔（`test/fixtures/plugins/test_plugin/`）。
final testPluginFile = File('test/fixtures/plugins/test_plugin/test_plugin.js');

/// 組一個安裝檔：標頭加上 [body]（ES module）。[login] 是 manifest 的 `login`
/// （JSON 文字）。
String pluginSource(
  String body, {
  String id = 'plugin-a',
  List<String> capabilities = const ['search'],
  List<String> allowedHosts = const ['example.test'],
  String? login,
}) =>
    '''
/* ==FMP Plugin==
{
  "id": "$id",
  "name": "Plugin $id",
  "version": "1.0.0",
  "author": "FMP tests",
  "apiVersion": 1,
  "capabilities": [${capabilities.map((c) => '"$c"').join(', ')}],
  ${login == null ? '' : '"login": $login,'}
  "allowedHosts": [${allowedHosts.map((h) => '"$h"').join(', ')}]
}
==/FMP Plugin== */
$body
''';

/// 插件的執行環境加上記憶體資料庫、假 HTTP adapter（不聯網，API 與媒體 client
/// 共用）、log 與遮蔽函式。建立的 runtime 與插件在測試結束時釋放。
final class PluginHarness {
  PluginHarness({
    FutureOr<ResponseBody> Function(RequestOptions options)? handler,
    this.callTimeout = defaultPluginCallTimeout,
    this.livenessGrace = defaultLivenessGrace,
  }) : adapter = FakeHttpAdapter(handler ?? (_) => reply(200)) {
    log = Log(redactor: redactor, minimumLevel: LogLevel.debug);
    database = memoryDatabase();
    plugins = PluginRepository(database);
    storage = PluginStorageRepository(database);
    credentials = credentialStoreFor(
      database,
      redactor: redactor,
      log: log,
      storage: secureStorage,
    );
    // 重試的等待立刻完成。
    httpClients = SourceHttpClientFactory(
      log: log,
      credentials: credentials,
      createAdapter: () => adapter,
      wait: (_) async {},
      random: math.Random(7),
    );
    mediaHttpClients = MediaHttpClientFactory(
      log: log,
      createAdapter: () => adapter,
    );
    loader = ScriptPluginLoader(
      log: log,
      redactor: redactor,
      httpClients: httpClients,
      storage: storage,
      credentials: credentials,
      callTimeout: callTimeout,
      livenessGrace: livenessGrace,
    );
  }

  final FakeHttpAdapter adapter;
  final Duration callTimeout;
  final Duration livenessGrace;
  final redactor = Redactor();
  late final Log log;
  late final AppDatabase database;
  late final PluginRepository plugins;
  late final PluginStorageRepository storage;

  /// 憑證存放：接在記憶體資料庫與 [secureStorage]。
  late final CredentialStore credentials;
  final secureStorage = InMemorySecureStorage();
  late final SourceHttpClientFactory httpClients;

  /// 媒體 client 的工廠，和 [httpClients] 用同一個假 adapter。
  late final MediaHttpClientFactory mediaHttpClients;
  late final ScriptPluginLoader loader;

  /// 在 runtime 載入 [script]（只有 module，沒有標頭），網域清單是
  /// [allowedHosts]；[entryPoint] 換掉背景 isolate 的進入點。[installed] 為真時先在 `installed_plugins` 放一列，
  /// storage 才寫得進去（外鍵）。
  Future<PluginRuntime> runtime(
    String script, {
    String pluginId = 'plugin-a',
    List<String> allowedHosts = const ['example.test'],
    bool installed = true,
    PluginWorkerEntry entryPoint = pluginWorkerMain,
  }) async {
    if (installed) await install(pluginId);
    final host = PluginHost(
      pluginId: pluginId,
      http: httpClients.create(pluginId: pluginId, allowedHosts: allowedHosts),
      storage: storage,
      log: log,
      credentials: credentials,
      redactor: redactor,
    );
    final runtime = await PluginRuntime.start(
      pluginId: pluginId,
      script: script,
      host: host,
      log: log,
      callTimeout: callTimeout,
      livenessGrace: livenessGrace,
      entryPoint: entryPoint,
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  /// 以 [ScriptPluginLoader] 載入安裝檔 [source]；[installed] 同 [runtime]。
  Future<ScriptSourcePlugin> load(
    String source, {
    bool installed = true,
  }) async {
    final file = PluginFile.parse(source);
    if (installed) await install(file.manifest.id);
    final plugin = await loader.load(file);
    addTearDown(plugin.close);
    return plugin;
  }

  /// 在 `installed_plugins` 放一列（內容不重要，只為了外鍵）。
  Future<void> install(String pluginId) => plugins.install(
    InstalledPlugin(
      id: pluginId,
      version: '1.0.0',
      manifestJson: '{}',
      script: '',
      installedAt: DateTime.utc(2026, 9, 30),
    ),
  );

  /// 記憶體歷史裡 tag 為 [tag] 的紀錄。
  List<LogRecord> records(String tag) => [
    for (final record in log.history)
      if (record.tag == tag) record,
  ];
}
