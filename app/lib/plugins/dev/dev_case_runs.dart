import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/network/fixture/fixture_adapters.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/dev/case_runner.dart';
import 'package:fmp/plugins/dev/dev_folder.dart';
import 'package:fmp/plugins/dev/plugin_development.dart';
import 'package:fmp/plugins/dev/plugin_folder.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';

// 開發中插件的「跑案例」（M3 PR 16b，design §3.1、§3.2）。模式只決定案例怎麼跑：每個案例
// 在與命令列契約執行器同一份程式碼的隔離環境（`runIsolatedCase`／`recordCase`）裡，以
// 對應的 adapter 執行；App 裡載入的開發版一律真實連線，不受模式影響。

/// 案例的跑法：重播 fixture（零聯網）、真實連線並錄成 fixture、真實連線。
enum CaseMode { replay, record, real }

enum DevCaseOutcome { passed, failed, skipped }

enum DevSkip { requiresLogin, handEdited }

/// 回傳值顯示的上限（字元數）。
const devCaseValueLimit = 32 * 1024;

/// 一個案例跑完的結果；字串都已遮蔽。
@immutable
final class DevCaseResult {
  const DevCaseResult({
    required this.capability,
    required this.mode,
    required this.outcome,
    required this.elapsed,
    this.errorType,
    this.problems = const [],
    this.skip,
    this.written,
    this.notWritten = false,
    this.value,
    this.truncated = false,
  });

  final PluginCapability capability;
  final CaseMode mode;
  final DevCaseOutcome outcome;
  final Duration elapsed;

  /// 插件丟出的 [AppError] 類別。
  final String? errorType;

  /// 期望不符、重播比對不到與沒用到的 fixture、錄製的問題。
  final List<String> problems;
  final DevSkip? skip;

  /// 錄製寫了幾個檔。
  final int? written;

  /// 錄製而結果不符、沒寫。
  final bool notWritten;

  /// 回傳值，縮排 JSON，最多 [devCaseValueLimit] 字元。
  final String? value;
  final bool truncated;
}

@immutable
final class DevCaseRunsState {
  const DevCaseRunsState({
    this.modes = const {},
    this.running,
    this.batch,
    this.results = const {},
  });

  final Map<String, CaseMode> modes;

  /// 正在跑的案例。
  final ({String pluginId, PluginCapability capability})? running;

  /// 「全部執行」進行中的插件 id（案例之間 [running] 會空一下）。
  final String? batch;
  final Map<String, Map<PluginCapability, DevCaseResult>> results;

  CaseMode modeOf(String pluginId) => modes[pluginId] ?? CaseMode.replay;

  /// 有案例（或一輪）在跑：整個區塊一次只跑一個。
  bool get busy => running != null || batch != null;

  DevCaseRunsState copyWith({
    Map<String, CaseMode>? modes,
    ({String pluginId, PluginCapability capability})? Function()? running,
    String? Function()? batch,
    Map<String, Map<PluginCapability, DevCaseResult>>? results,
  }) => DevCaseRunsState(
    modes: modes ?? this.modes,
    running: running == null ? this.running : running(),
    batch: batch == null ? this.batch : batch(),
    results: results ?? this.results,
  );
}

/// 建案例的 transport（真實連線的 adapter 來自它）；測試以假上游 override。
final caseTransportsProvider = Provider<CaseTransports>(
  (ref) => const CaseTransports(),
);

final devCaseRunsProvider = NotifierProvider<DevCaseRuns, DevCaseRunsState>(
  DevCaseRuns.new,
);

/// 閉包放在獨立的函式：Isolate.run 的閉包不能帶著 Notifier 的 context（送不過去）。
Future<PluginFolder> _readFolder(Directory directory) =>
    Isolate.run(() => PluginFolder.read(directory));

final class DevCaseRuns extends Notifier<DevCaseRunsState> {
  /// 換資料夾、卸載時加一：跑的途中發生的話，結果丟掉、錄製不寫檔。
  var _generation = 0;

  @override
  DevCaseRunsState build() {
    ref.listen(
      pluginDevelopmentProvider.select(
        (development) => development?.folder.path,
      ),
      (previous, next) {
        if (previous == next) return;
        _generation++;
        // 模式與結果只在記憶體，換資料夾或卸載時清掉；正在跑的那個自己會結束。
        state = DevCaseRunsState(running: state.running, batch: state.batch);
      },
    );
    return const DevCaseRunsState();
  }

  /// 那個插件在跑時忽略。
  void setMode(String pluginId, CaseMode mode) {
    if (state.running?.pluginId == pluginId || state.batch == pluginId) return;
    state = state.copyWith(modes: {...state.modes, pluginId: mode});
  }

  /// 跑 [pluginId] 的一個案例；已經有案例在跑、插件不在開發中時什麼都不做。
  Future<void> run(String pluginId, PluginCapability capability) async {
    if (state.busy) return;
    await _runOne(pluginId, capability);
  }

  /// 依序跑 [pluginId] 的每個案例（checks.json 的順序）。
  Future<void> runAll(String pluginId) async {
    if (state.busy) return;
    final plugin = _plugin(pluginId);
    if (plugin == null) return;
    state = state.copyWith(batch: () => pluginId);
    try {
      for (final capability in plugin.cases) {
        if (!ref.mounted) return;
        await _runOne(pluginId, capability);
      }
    } finally {
      if (ref.mounted) state = state.copyWith(batch: () => null);
    }
  }

  DevPlugin? _plugin(String pluginId) => ref
      .read(pluginDevelopmentProvider)
      ?.plugins
      .where((plugin) => plugin.id == pluginId)
      .firstOrNull;

  Future<void> _runOne(String pluginId, PluginCapability capability) async {
    final plugin = _plugin(pluginId);
    if (plugin == null) return;
    final generation = _generation;
    final mode = state.modeOf(pluginId);
    state = state.copyWith(
      running: () => (pluginId: pluginId, capability: capability),
    );
    final stopwatch = Stopwatch()..start();
    DevCaseResult result;
    try {
      result = await _execute(
        pluginId,
        plugin.directory,
        capability,
        mode,
        generation,
        stopwatch,
      );
    } finally {
      if (ref.mounted) state = state.copyWith(running: () => null);
    }
    if (!ref.mounted || generation != _generation) return;
    state = state.copyWith(
      results: {
        ...state.results,
        pluginId: {...?state.results[pluginId], capability: result},
      },
    );
    _log(pluginId, result);
  }

  Future<DevCaseResult> _execute(
    String pluginId,
    Directory directory,
    PluginCapability capability,
    CaseMode mode,
    int generation,
    Stopwatch stopwatch,
  ) async {
    final redactor = ref.read(redactorProvider);
    final log = ref.read(logProvider);
    final name = capability.wireName;
    DevCaseResult failed(List<String> problems) => DevCaseResult(
      capability: capability,
      mode: mode,
      outcome: DevCaseOutcome.failed,
      elapsed: stopwatch.elapsed,
      problems: [for (final problem in problems) redactor.redact(problem)],
    );
    // 每次跑都讀磁碟上的現況（同命令列 `runContract`）；讀檔不佔 UI isolate。
    final PluginFolder folder;
    try {
      folder = await _readFolder(directory);
    } on Object catch (error) {
      return failed(['could not read the plugin directory: $error']);
    }
    final file = folder.file;
    final check = folder.checks
        .where((check) => check.capability == capability)
        .firstOrNull;
    if (file == null) return failed(folder.problems);
    if (check == null) return failed(['checks.json has no $name case']);
    // 要登入的案例：重播用 checks.json 的假憑證，真實與錄製用已存的憑證（沒登入就略過、
    // 不連網）。
    LoginCredentials? credentials;
    if (check.requiresLogin && mode != CaseMode.replay) {
      credentials = await ref
          .read(credentialStoreProvider)
          .activeCredentials(pluginId);
      if (credentials == null) {
        return DevCaseResult(
          capability: capability,
          mode: mode,
          outcome: DevCaseOutcome.skipped,
          elapsed: stopwatch.elapsed,
          skip: DevSkip.requiresLogin,
        );
      }
    }
    final transports = ref.read(caseTransportsProvider);
    final recordIds = ref.read(networkRecordIdsProvider);
    final allowedHosts = AllowedHosts(file.manifest.allowedHosts);
    List<String> own(List<String> problems) => [
      for (final problem in problems)
        redactor.redact(
          problem.startsWith('$name: ')
              ? problem.substring(name.length + 2)
              : problem,
        ),
    ];

    switch (mode) {
      case CaseMode.replay:
        final transport = transports.replay(
          folder.fixtures[name] ?? const [],
          redactor,
          allowedHosts,
        );
        final run = await runIsolatedCase(
          file: file,
          check: check,
          transport: transport,
          log: log,
          redactor: redactor,
          reportTag: 'plugins',
          recordIds: recordIds,
        );
        stopwatch.stop();
        final problems = [
          ...run.problems,
          if (run.loaded) ...transport.problems,
          if (run.loaded)
            for (final unused in transport.unused) '$unused was not requested',
          for (final problem in folder.problems)
            if (problem.startsWith('fixtures/$name')) problem,
        ];
        return _result(
          capability,
          mode,
          stopwatch.elapsed,
          run,
          problems: own(problems),
          passed: run.matched && problems.isEmpty,
        );
      case CaseMode.real:
        final transport = transports.real();
        final run = await runIsolatedCase(
          file: file,
          check: check,
          transport: transport,
          log: log,
          redactor: redactor,
          reportTag: 'plugins',
          credentials: credentials,
          recordIds: recordIds,
          wait: realWait,
        );
        stopwatch.stop();
        final problems = [
          ...run.problems,
          if (run.loaded) ...transport.problems,
        ];
        return _result(
          capability,
          mode,
          stopwatch.elapsed,
          run,
          problems: own(problems),
          passed: run.matched && problems.isEmpty,
        );
      case CaseMode.record:
        final transport = transports.record(redactor);
        final record = await recordCase(
          folder,
          check,
          transport: transport,
          log: log,
          redactor: redactor,
          reportTag: 'plugins',
          credentials: credentials,
          recordIds: recordIds,
          shouldWrite: () => ref.mounted && generation == _generation,
        );
        stopwatch.stop();
        if (record.skipped != null) {
          return DevCaseResult(
            capability: capability,
            mode: mode,
            outcome: DevCaseOutcome.skipped,
            elapsed: stopwatch.elapsed,
            skip: DevSkip.handEdited,
          );
        }
        final run = record.run;
        final written = record.written;
        final problems = record.problems;
        final base = run == null
            ? null
            : _result(
                capability,
                mode,
                stopwatch.elapsed,
                run,
                problems: own(problems),
                passed: written != null && problems.isEmpty,
              );
        if (base == null) return failed(problems);
        return DevCaseResult(
          capability: capability,
          mode: mode,
          outcome: base.outcome,
          elapsed: base.elapsed,
          errorType: base.errorType,
          problems: base.problems,
          written: written,
          notWritten: written == null,
          value: base.value,
          truncated: base.truncated,
        );
    }
  }

  DevCaseResult _result(
    PluginCapability capability,
    CaseMode mode,
    Duration elapsed,
    CaseRun run, {
    required List<String> problems,
    required bool passed,
  }) {
    final rendered = run.result == null ? null : _render(run.result!);
    return DevCaseResult(
      capability: capability,
      mode: mode,
      outcome: passed ? DevCaseOutcome.passed : DevCaseOutcome.failed,
      elapsed: elapsed,
      errorType: run.error?.typeName,
      problems: problems,
      value: rendered?.text,
      truncated: rendered?.truncated ?? false,
    );
  }

  /// 回傳值轉成縮排 JSON（欄位名稱同 `fmp-plugin.d.ts`），經遮蔽函式，最多
  /// [devCaseValueLimit] 字元。帳號資料一律不顯示名稱（有沒有而已）。
  ({String text, bool truncated}) _render(Object result) {
    final redactor = ref.read(redactorProvider);
    final items = [
      for (final item in checkItems(result))
        if (result is LoginAccount)
          {
            'userId': '***',
            'displayName': '***',
            'avatar': (item['avatar'] as List?)?.isNotEmpty ?? false
                ? '***'
                : null,
          }
        else
          _plain(item),
    ];
    final text = const JsonEncoder.withIndent('  ')
        .convert(redactor.redactValue(items));
    return text.length <= devCaseValueLimit
        ? (text: text, truncated: false)
        : (text: text.substring(0, devCaseValueLimit), truncated: true);
  }

  static Object? _plain(Object? value) => switch (value) {
    Artwork() => {'url': value.url.toString(), 'width': value.width},
    Map<Object?, Object?>() => {
      for (final MapEntry(:key, value: entry) in value.entries)
        '$key': _plain(entry),
    },
    Iterable<Object?>() => [for (final item in value) _plain(item)],
    Uri() => value.toString(),
    _ => value,
  };

  void _log(String pluginId, DevCaseResult result) {
    ref
        .read(logProvider)
        .write(
          result.outcome == DevCaseOutcome.failed
              ? LogLevel.warning
              : LogLevel.info,
          'Plugin case',
          tag: pluginId,
          fields: {
            'capability': result.capability.wireName,
            'mode': result.mode.name,
            'result': result.outcome.name,
            'durationMs': result.elapsed.inMilliseconds,
            'errorType': ?result.errorType,
            'written': ?result.written,
          },
        );
  }
}
