import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:path/path.dart' as p;

import 'checks.dart';
import 'credential_scan.dart';
import 'fixture.dart';
import 'fixture_adapters.dart';

// 插件契約執行器（ADR 0015 §決定 6）。對一個插件目錄：
//
//   <目錄>/<任意名稱>.js           安裝檔（只能有一個）
//   <目錄>/checks.json             檢查案例（checks.dart）
//   <目錄>/fixtures/<能力>/*.json  該案例依序的請求與回應（fixture.dart）
//
// 以重播執行每個案例，回傳違反契約之處（空的就是通過）。每個案例各自一份
// 記憶體資料庫、log、遮蔽函式與 HTTP client，案例之間不共用 storage 與
// cookie。入口是 contract_test.dart（重播）與 record_test.dart（錄製）。

/// 插件目錄的清單：[root] 本身有 `.js` 檔就是一個插件目錄，否則是它底下有
/// `.js` 檔的子目錄（依名稱排序）。
List<Directory> pluginDirectories(Directory root) {
  if (_scripts(root).isNotEmpty) return [root];
  return [
    for (final entry
        in root.listSync()..sort((a, b) => a.path.compareTo(b.path)))
      if (entry is Directory && _scripts(entry).isNotEmpty) entry,
  ];
}

List<File> _scripts(Directory directory) => [
  for (final entry in directory.listSync())
    if (entry is File && entry.path.endsWith('.js')) entry,
];

/// 讀好的插件目錄。讀的時候發現的問題在 [problems]，其他部分盡量讀。
final class PluginDirectory {
  PluginDirectory._(this.directory);

  /// 讀 [directory]：安裝檔、checks.json、fixture（格式、網域、憑證）。
  factory PluginDirectory.read(Directory directory) {
    final plugin = PluginDirectory._(directory);
    final scripts = _scripts(directory);
    if (scripts.length != 1) {
      plugin.problems.add(
        'expected one .js install file, found ${scripts.length}',
      );
      return plugin;
    }
    try {
      plugin.file = PluginFile.parse(scripts.single.readAsStringSync());
    } on AppError catch (error) {
      plugin.problems.add('install file: ${describeError(error)}');
      return plugin;
    }
    plugin
      .._readChecks()
      .._readFixtures();
    return plugin;
  }

  final Directory directory;
  PluginFile? file;
  final checks = <PluginCheck>[];

  /// 依能力名稱（`fixtures/` 底下的目錄名），依檔名排序。
  final fixtures = <String, List<NamedFixture>>{};
  final problems = <String>[];

  PluginManifest get manifest => file!.manifest;

  /// 測試名稱用。
  String get label => switch (file) {
    null => p.basename(directory.path),
    final file => '${file.manifest.id} (${p.basename(directory.path)})',
  };

  void _readChecks() {
    final checksFile = File(p.join(directory.path, 'checks.json'));
    if (!checksFile.existsSync()) {
      problems.add('checks.json is missing');
      return;
    }
    try {
      checks.addAll(parseChecks(checksFile.readAsStringSync()));
    } on FormatException catch (error) {
      problems.add('checks.json: ${error.message}');
      return;
    }
    for (final check in checks) {
      if (!manifest.capabilities.contains(check.capability)) {
        problems.add(
          'checks.json: ${check.capability.wireName} is not a declared '
          'capability',
        );
      }
    }
  }

  void _readFixtures() {
    final root = Directory(p.join(directory.path, 'fixtures'));
    if (!root.existsSync()) return;
    final checked = {for (final check in checks) check.capability.wireName};
    final allowedHosts = AllowedHosts(manifest.allowedHosts);
    final redactor = redactorFor(manifest);
    final names = CredentialNames.of(manifest);
    for (final entry in root.listSync()) {
      final name = p.basename(entry.path);
      if (entry is! Directory) {
        problems.add('fixtures/$name: fixtures go in fixtures/<capability>/');
        continue;
      }
      if (!checked.contains(name)) {
        problems.add('fixtures/$name: checks.json has no $name check');
      }
      final files = [
        for (final file in entry.listSync())
          if (file is File && file.path.endsWith('.json')) file,
      ]..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      fixtures[name] = [
        for (final file in files)
          if (_readFixture(file, 'fixtures/$name/${p.basename(file.path)}')
              case final fixture?)
            (name: 'fixtures/$name/${p.basename(file.path)}', fixture: fixture),
      ];
      for (final (:name, :fixture) in fixtures[name]!) {
        final url = Uri.parse(fixture.request.url);
        if (!allowedHosts.allows(url)) {
          problems.add(
            '$name: ${url.host} is outside allowedHosts, or not https',
          );
        }
        problems.addAll(scanFixture(name, fixture, redactor, names));
      }
    }
  }

  HttpFixture? _readFixture(File file, String name) {
    try {
      return HttpFixture.fromJson(jsonDecode(file.readAsStringSync()));
    } on FormatException catch (error) {
      problems.add('$name: ${error.message}');
      return null;
    }
  }
}

/// 加上 [manifest] 追加名單的遮蔽函式（載入插件時 `ScriptPluginLoader` 也這樣
/// 加）。
Redactor redactorFor(PluginManifest manifest) => Redactor()
  ..addRules(
    headerNames: manifest.redaction.headerNames,
    keyNames: manifest.redaction.keyNames,
    mediaCdns: manifest.redaction.mediaCdns,
  );

/// 把 [error] 寫成一行：類別名與遮蔽過的原因（原因只有 `log.report` 讀得到）。
String describeError(AppError error, [Log? log]) {
  final target = log ?? Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
  target.report('Contract check', error, tag: 'contract');
  final cause = target.history.last.error;
  return cause == null ? error.typeName : '${error.typeName}: $cause';
}

/// 整個插件目錄：[PluginDirectory.read]、[checkPluginDirectory]、每個案例的
/// [runCheck]。回傳所有違反之處。
Future<List<String>> runContract(Directory directory) async {
  final plugin = PluginDirectory.read(directory);
  return [
    ...await checkPluginDirectory(plugin),
    for (final check in plugin.checks) ...await runCheck(plugin, check),
  ];
}

/// 讀取時的問題，加上載入一次（能力與匯出一致、腳本讀得懂）。
Future<List<String>> checkPluginDirectory(PluginDirectory plugin) async {
  final file = plugin.file;
  if (file == null) return plugin.problems;
  final environment = _Environment(
    (redactor) => ReplayAdapter(
      const [],
      redactor,
      AllowedHosts(file.manifest.allowedHosts),
    ),
  );
  try {
    (await environment.load(file)).close();
    return plugin.problems;
  } on AppError catch (error) {
    return [
      ...plugin.problems,
      'load: ${describeError(error, environment.log)}',
    ];
  } finally {
    await environment.close();
  }
}

/// 以重播執行 [check]：[_execute] 的檢查，加上每個請求都對上 fixture、每個
/// fixture 都被用到。
///
/// [log] 換掉這個案例的 log（預設是以案例的遮蔽函式建的門面）：執行器自己的
/// 測試以它造一個沒接上插件遮蔽名單的 log，證明檢查看得到插件寫的 log。
Future<List<String>> runCheck(
  PluginDirectory plugin,
  PluginCheck check, {
  Log Function(Redactor redactor) log = _facade,
}) async {
  final name = check.capability.wireName;
  late final ReplayAdapter replay;
  final environment = _Environment(
    (redactor) => replay = ReplayAdapter(
      plugin.fixtures[name] ?? const [],
      redactor,
      AllowedHosts(plugin.manifest.allowedHosts),
    ),
    log: log,
  );
  final (:problems, matched: _) = await _execute(plugin, check, environment);
  if (!environment.loaded) return problems;
  return [
    ...problems,
    for (final problem in replay.problems) '$name: $problem',
    for (final unused in replay.unused) '$name: $unused was not requested',
  ];
}

/// 錄製（prd 擁有者決定 8）：以 [network] 真的送出每個案例的請求，遮蔽後寫進
/// `fixtures/<能力>/001.json`…（先刪掉那個能力原本的 fixture）。回傳違反之處
/// 與略過的案例。
///
/// 只有案例的結果符合 checks.json 的期望才寫；不符（例如連線失敗是
/// `NetworkError`）就那個案例什麼都不寫，原本的 fixture 不動，並回報原因。
/// 網路層重試成功的請求照樣寫：失敗的那幾次沒有回應，不會被錄到。
///
/// 只錄得了不需要登入的案例：認證來源是 `NoCredentials`，要登入的請求會以
/// `AuthRequired` 失敗。`meta.edited` 的 fixture 是手寫或手改的，那個案例略過
/// 不錄。重試照真的時間等（不像重播立刻重送）；[wait] 換掉等待，給執行器自己
/// 的測試用。
Future<({List<String> problems, List<String> skipped})> recordContract(
  Directory directory, {
  required HttpClientAdapter Function() network,
  DateTime Function() now = DateTime.now,
  Future<void> Function(Duration delay)? wait,
}) async {
  final plugin = PluginDirectory.read(directory);
  if (plugin.file == null) {
    return (problems: plugin.problems, skipped: const <String>[]);
  }
  final problems = <String>[];
  final skipped = <String>[];
  for (final check in plugin.checks) {
    final name = check.capability.wireName;
    final existing = plugin.fixtures[name] ?? const [];
    if (existing.any((named) => named.fixture.edited != null)) {
      skipped.add('$name: has hand-edited fixtures');
      continue;
    }
    late final RecordingAdapter recorder;
    final environment = _Environment(
      (redactor) => recorder = RecordingAdapter(network(), redactor, now: now),
      wait: wait ?? _delay,
    );
    final outcome = await _execute(plugin, check, environment);
    problems.addAll(outcome.problems);
    if (!environment.loaded) continue;
    if (recorder.problems.isNotEmpty) {
      problems.addAll([
        for (final problem in recorder.problems) '$name: $problem',
      ]);
      continue;
    }
    if (!outcome.matched) {
      problems.add(
        '$name: fixtures not written: the outcome does not match checks.json',
      );
      continue;
    }
    _writeFixtures(
      Directory(p.join(directory.path, 'fixtures', name)),
      recorder.recorded,
    );
  }
  return (problems: problems, skipped: skipped);
}

void _writeFixtures(Directory target, List<HttpFixture> fixtures) {
  if (target.existsSync()) {
    for (final entry in target.listSync()) {
      if (entry is File && entry.path.endsWith('.json')) entry.deleteSync();
    }
  }
  if (fixtures.isEmpty) {
    if (target.existsSync() && target.listSync().isEmpty) target.deleteSync();
    return;
  }
  target.createSync(recursive: true);
  for (final (index, fixture) in fixtures.indexed) {
    File(p.join(target.path, '${'${index + 1}'.padLeft(3, '0')}.json'))
        .writeAsStringSync(fixture.encode());
  }
}

/// 載入插件、執行 [check]，檢查：錯誤都是 `AppError`、案例的期望（DTO 驗證
/// 失敗是 `ParseError`，期望成功時就不符）、沒有試著連清單外的網域、串流
/// headers 不帶憑證、log 都遮蔽過。[matched]：結果符合案例的期望。
Future<({List<String> problems, bool matched})> _execute(
  PluginDirectory plugin,
  PluginCheck check,
  _Environment environment,
) async {
  try {
    return await _executeLoaded(plugin, check, environment);
  } finally {
    await environment.close();
  }
}

Future<({List<String> problems, bool matched})> _executeLoaded(
  PluginDirectory plugin,
  PluginCheck check,
  _Environment environment,
) async {
  final name = check.capability.wireName;
  final ScriptSourcePlugin source;
  try {
    source = await environment.load(plugin.file!);
  } on AppError catch (error) {
    return (
      problems: ['$name: load: ${describeError(error, environment.log)}'],
      matched: false,
    );
  }
  Object? result;
  AppError? error;
  final problems = <String>[];
  try {
    result = await check.run(source);
  } on AppError catch (thrown) {
    error = thrown;
  } on Object catch (thrown) {
    problems.add('$name: threw ${thrown.runtimeType}, not an AppError');
  } finally {
    source.close();
  }
  // 每個錯誤只 report 一次。
  final descriptions = Map<AppError, String>.identity();
  String describe(AppError error) => descriptions.putIfAbsent(
    error,
    () => describeError(error, environment.log),
  );
  final names = CredentialNames.of(plugin.manifest);
  if (error != null) {
    final description = describe(error);
    // 網路層不送出清單外的請求，丟 Unsupported（原因 `Host not allowed`、
    // `Redirect to a host not allowed`）。插件自己接住吞掉的看不到。
    if (error is Unsupported && description.contains('not allowed')) {
      problems.add(
        '$name: tried to reach a host outside allowedHosts ($description)',
      );
    }
  }
  // 沒丟 AppError 以外的東西、沒試著出網域，才比對期望。
  final mismatches = problems.isEmpty
      ? check.expectation.evaluate(
          result: result,
          error: error,
          describe: describe,
        )
      : null;
  problems.addAll([
    for (final problem in mismatches ?? const <String>[]) '$name: $problem',
  ]);
  if (result case final StreamResult stream) {
    problems.addAll([
      for (final problem in mediaHeaderProblems(
        stream.candidates,
        environment.redactor,
        names,
      ))
        '$name: $problem',
    ]);
  }
  problems.addAll([
    for (final problem in inspectLog(
      environment.log.history,
      environment.redactor,
      names,
    ))
      '$name: $problem',
  ]);
  return (problems: problems, matched: mismatches?.isEmpty ?? false);
}

/// 一個案例的執行環境。
final class _Environment {
  _Environment(
    this._adapter, {
    this._wait = _noWait,
    Log Function(Redactor redactor) log = _facade,
  }) : _createLog = log;

  final HttpClientAdapter Function(Redactor redactor) _adapter;

  /// 重試與限流的等待：重播不等，錄製照真的時間等。
  final Future<void> Function(Duration delay) _wait;
  final Log Function(Redactor redactor) _createLog;
  final redactor = Redactor();

  /// 插件與宿主寫的 log；檢查的是它的歷史。
  late final Log log = _createLog(redactor);

  /// 插件載入成功過。
  bool loaded = false;

  /// 每個案例一份記憶體資料庫，案例結束就關（drift 在 debug 下會對同時開著的
  /// 多個 `AppDatabase` 警告）。
  AppDatabase? _database;

  Future<void> close() async => _database?.close();

  Future<ScriptSourcePlugin> load(PluginFile file) async {
    final database = _database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
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
    final loader = ScriptPluginLoader(
      log: log,
      redactor: redactor,
      httpClients: SourceHttpClientFactory(
        log: log,
        createAdapter: () => _adapter(redactor),
        wait: _wait,
        random: math.Random(7),
      ),
      storage: PluginStorageRepository(database),
    );
    final plugin = await loader.load(file);
    loaded = true;
    return plugin;
  }
}

Future<void> _noWait(Duration _) async {}

Future<void> _delay(Duration delay) => Future<void>.delayed(delay);

/// 案例的 log：經 [redactor] 的門面，debug 以上都留。
Log _facade(Redactor redactor) =>
    Log(redactor: redactor, minimumLevel: LogLevel.debug);

/// 找不到任何插件目錄時的說明。
String noPluginDirectories(Directory root) =>
    'no plugin directory in ${root.absolute.path}: a plugin directory holds '
    'exactly one .js install file';

/// `FMP_PLUGIN_DIR` 指的目錄；沒設就是 `null`。
Directory? pluginDirectoryFromEnvironment() =>
    switch (Platform.environment['FMP_PLUGIN_DIR']) {
      null || '' => null,
      final path => Directory(path),
    };
