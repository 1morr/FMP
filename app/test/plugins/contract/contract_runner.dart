import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/fixture/fixture_adapters.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/dev/case_runner.dart' as runner;
import 'package:fmp/plugins/dev/describe_error.dart' as describer;
import 'package:fmp/plugins/dev/case_runner.dart'
    show CaseRun, loadIsolated, recordCase, runIsolatedCase;
import 'package:fmp/plugins/dev/plugin_folder.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'credential_scan.dart';

export 'package:fmp/plugins/dev/plugin_folder.dart' show pluginDirectories;

// 插件契約執行器（ADR 0015 §決定 6）的命令列入口：插件目錄的讀取與每個案例的
// 隔離執行環境在 lib/plugins/dev/（App 內開發工具共用），這裡加上只有測試要的
// 檢查：fixture 的網域與憑證掃描、串流 headers 與 log 的憑證檢查。
//
//   <目錄>/<任意名稱>.js           安裝檔（只能有一個）
//   <目錄>/checks.json             檢查案例（lib/plugins/health/checks.dart）
//   <目錄>/fixtures/<能力>/*.json  該案例依序的請求與回應（fixture.dart）
//
// 以重播執行每個案例，回傳違反契約之處（空的就是通過）。每個案例各自一份
// 記憶體資料庫、log、遮蔽函式與 HTTP client，案例之間不共用 storage 與
// cookie。入口是 contract_test.dart（重播）與 record_test.dart（錄製）。

/// 讀好的插件目錄：[PluginFolder.read] 加上 fixture 的網域與憑證掃描。
abstract final class PluginDirectory {
  static PluginFolder read(Directory directory) {
    // 掃描用的名單依 manifest 建一次。
    PluginManifest? scanned;
    late AllowedHosts allowedHosts;
    late Redactor redactor;
    late CredentialNames names;
    return PluginFolder.read(
      directory,
      inspectFixture: (manifest, name, fixture, problems) {
        if (!identical(scanned, manifest)) {
          scanned = manifest;
          allowedHosts = AllowedHosts(manifest.allowedHosts);
          redactor = redactorFor(manifest);
          names = CredentialNames.of(manifest);
        }
        final url = Uri.parse(fixture.request.url);
        if (!allowedHosts.allows(url)) {
          problems.add(
            '$name: ${url.host} is outside allowedHosts, or not https',
          );
        }
        problems.addAll(scanFixture(name, fixture, redactor, names));
      },
    );
  }
}

/// 加上 [manifest] 追加名單的遮蔽函式（載入插件時 `ScriptPluginLoader` 也這樣
/// 加）。
Redactor redactorFor(PluginManifest manifest) => Redactor()
  ..addRules(
    headerNames: manifest.redaction.headerNames,
    keyNames: manifest.redaction.keyNames,
  )
  ..setMediaCdns(manifest.id, manifest.redaction.mediaCdns);

/// 把 [error] 寫成一行：類別名與遮蔽過的原因（原因只有 `log.report` 讀得到）。
String describeError(AppError error, [Log? log]) => describer.describeError(
  error,
  log ?? Log(redactor: Redactor(), minimumLevel: LogLevel.debug),
  tag: 'contract',
  message: 'Contract check',
);

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
Future<List<String>> checkPluginDirectory(PluginFolder plugin) async {
  final file = plugin.file;
  if (file == null) return plugin.problems;
  final redactor = Redactor();
  final log = _facade(redactor);
  final error = await loadIsolated(file: file, log: log, redactor: redactor);
  if (error == null) return plugin.problems;
  return [...plugin.problems, 'load: ${describeError(error, log)}'];
}

/// 以重播執行 [check]：隔離執行（lib/plugins/dev/case_runner.dart）的檢查，加上
/// 串流 headers 與 log 的憑證檢查、每個請求都對上 fixture、每個 fixture 都被用到。
///
/// [log] 換掉這個案例的 log（預設是以案例的遮蔽函式建的門面）：執行器自己的
/// 測試以它造一個沒接上插件遮蔽名單的 log，證明檢查看得到插件寫的 log。
Future<List<String>> runCheck(
  PluginFolder plugin,
  PluginCheck check, {
  Log Function(Redactor redactor) log = _facade,
}) async {
  final name = check.capability.wireName;
  final redactor = Redactor();
  final caseLog = log(redactor);
  final transport = const CaseTransports().replay(
    plugin.fixtures[name] ?? const [],
    redactor,
    AllowedHosts(plugin.manifest.allowedHosts),
  );
  final run = await runIsolatedCase(
    file: plugin.file!,
    check: check,
    transport: transport,
    log: caseLog,
    redactor: redactor,
    reportTag: 'contract',
    reportMessage: 'Contract check',
    fixtureCredentials: runner.fixtureCredentialsOf(plugin.checks),
  );
  final problems = [for (final problem in run.problems) '$name: $problem'];
  if (!run.loaded) return problems;
  return [
    ...problems,
    ..._scanProblems(name, plugin.manifest, run, caseLog, redactor),
    for (final problem in transport.problems) '$name: $problem',
    for (final unused in transport.unused) '$name: $unused was not requested',
  ];
}

/// 錄製（prd 擁有者決定 8）：以 [network] 真的送出每個案例的請求，遮蔽後寫進
/// `fixtures/<能力>/001.json`…（先刪掉那個能力原本的 fixture）。回傳違反之處
/// 與略過的案例。規則在 `recordCase`（lib/plugins/dev/case_runner.dart）：
/// 只有案例的結果符合 checks.json 的期望才寫；`requiresLogin` 的案例（命令列沒有
/// 憑證，design §4.8）與有 `meta.edited` 的 fixture 略過。重試照真的時間等
/// （不像重播立刻重送）；[wait] 換掉等待，給執行器自己的測試用。
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
    final redactor = Redactor();
    final log = _facade(redactor);
    final result = await recordCase(
      plugin,
      check,
      transport: CaseTransports(network: network, now: now).record(redactor),
      log: log,
      redactor: redactor,
      reportTag: 'contract',
      reportMessage: 'Contract check',
      wait: wait ?? runner.realWait,
    );
    if (result.skipped case final reason?) skipped.add(reason);
    if (result.run case final run? when run.loaded) {
      problems.addAll(_scanProblems(name, plugin.manifest, run, log, redactor));
    }
    problems.addAll(result.problems);
  }
  return (problems: problems, skipped: skipped);
}

/// 串流 headers 不帶憑證、log 都遮蔽過（帶 `<能力>: ` 前綴）。
List<String> _scanProblems(
  String name,
  PluginManifest manifest,
  CaseRun run,
  Log log,
  Redactor redactor,
) {
  final names = CredentialNames.of(manifest);
  return [
    if (run.result case final StreamResult stream)
      for (final problem in mediaHeaderProblems(
        stream.candidates,
        redactor,
        names,
      ))
        '$name: $problem',
    for (final problem in inspectLog(log.history, redactor, names))
      '$name: $problem',
  ];
}

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
