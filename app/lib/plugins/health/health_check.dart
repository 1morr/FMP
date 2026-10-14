import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/health/checks.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';

// 音源健康檢查（ADR 0025 §決定 6）：以 App 裡已載入的插件（真實連線、帶已存憑證）跑
// `installed_plugins.checks_json` 的案例。手動觸發，一次只跑一個插件；結果只留在記憶體，
// 另以 tag `health` 經 log 門面寫一筆一個案例，不另外存。

/// 一個案例的結果。
enum HealthOutcome { passed, failed, skipped }

/// 一個案例跑完的結果。
final class HealthCaseResult {
  const HealthCaseResult({
    required this.capability,
    required this.outcome,
    required this.elapsed,
    this.errorType,
    this.problems = const [],
  });

  final PluginCapability capability;
  final HealthOutcome outcome;
  final Duration elapsed;

  /// 插件丟出的 [AppError] 類別（[AppError.typeName]）；沒丟就是 `null`。
  final String? errorType;

  /// 與期望不符之處（已遮蔽）；通過與略過是空的。
  final List<String> problems;
}

/// 一個插件跑完的結果。
final class HealthPluginResult {
  const HealthPluginResult({
    this.cases = const [],
    this.problem,
    this.notLoaded = false,
  });

  final List<HealthCaseResult> cases;

  /// checks.json 讀不懂，整個插件沒跑成；已遮蔽。
  final String? problem;

  /// 插件啟用但不在已載入的清單上（載入失敗），整個插件沒跑成。
  final bool notLoaded;
}

/// 健康檢查的狀態：[running] 是正在跑的插件 id，[busy] 是一輪（單一或全部）還沒結束。
final class HealthState {
  const HealthState({this.busy = false, this.running, this.results = const {}});

  final bool busy;
  final String? running;

  /// 本次執行期間每個插件最後一次的結果。
  final Map<String, HealthPluginResult> results;

  HealthState copyWith({
    bool? busy,
    String? Function()? running,
    Map<String, HealthPluginResult>? results,
  }) => HealthState(
    busy: busy ?? this.busy,
    running: running == null ? this.running : running(),
    results: results ?? this.results,
  );
}

/// `checks_json` 解析成案例；沒有（`null`）回 `null`。格式不對丟 [FormatException]。
List<PluginCheck>? readChecks(String? checksJson) =>
    checksJson == null ? null : parseChecks(checksJson);

final healthCheckProvider = NotifierProvider<HealthCheck, HealthState>(
  HealthCheck.new,
);

final class HealthCheck extends Notifier<HealthState> {
  @override
  HealthState build() => const HealthState();

  /// 依序檢查所有已安裝且啟用的插件，一次一個。已經在跑時什麼都不做。
  Future<void> runAll() async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    try {
      final repository = ref.read(pluginRepositoryProvider);
      final ids = [for (final plugin in await repository.list()) plugin.id];
      for (final id in ids) {
        if (!ref.mounted) return;
        // 每個插件開跑前重讀：前面的插件跑的期間被停用或移除的就不跑。
        final plugin = await repository.byId(id);
        if (!ref.mounted) return;
        if (plugin != null && plugin.enabled) {
          await _run(plugin.id, plugin.checksJson);
        }
      }
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// 檢查 [pluginId]。已經在跑、插件沒安裝或停用時什麼都不做。
  Future<void> runOne(String pluginId) async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    try {
      final installed = await ref.read(pluginRepositoryProvider).byId(pluginId);
      if (installed == null || !installed.enabled || !ref.mounted) return;
      await _run(pluginId, installed.checksJson);
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  Future<void> _run(String pluginId, String? checksJson) async {
    final List<PluginCheck> checks;
    try {
      checks = readChecks(checksJson) ?? const [];
    } on FormatException catch (error) {
      _finish(
        pluginId,
        HealthPluginResult(
          problem: ref.read(redactorProvider).redact(error.message),
        ),
      );
      return;
    }
    if (checks.isEmpty) return;
    state = state.copyWith(running: () => pluginId);
    SourcePlugin? plugin;
    try {
      plugin = (await ref.read(pluginRegistryProvider.future))[pluginId];
    } on Object catch (error, stackTrace) {
      // 清單整個載入失敗：記下來，這個插件標「沒有載入」，不讓按鈕的 Future 帶著錯誤結束。
      ref
          .read(logProvider)
          .error(
            'Plugin registry unavailable',
            error: error,
            stackTrace: stackTrace,
            tag: 'health',
          );
    }
    if (!ref.mounted) return;
    if (plugin == null) {
      _finish(pluginId, const HealthPluginResult(notLoaded: true));
      return;
    }
    final cases = <HealthCaseResult>[];
    for (final check in checks) {
      final result = await _case(pluginId, plugin, check);
      if (!ref.mounted) return;
      cases.add(result);
    }
    _finish(pluginId, HealthPluginResult(cases: cases));
  }

  void _finish(String pluginId, HealthPluginResult result) {
    state = state.copyWith(
      running: () => null,
      results: {...state.results, pluginId: result},
    );
  }

  Future<HealthCaseResult> _case(
    String pluginId,
    SourcePlugin plugin,
    PluginCheck check,
  ) async {
    final stopwatch = Stopwatch()..start();
    final redactor = ref.read(redactorProvider);
    // 要登入的案例：已登入就用已存的憑證，沒登入略過（design §4.8）。
    LoginCredentials? credentials;
    if (check.requiresLogin) {
      credentials = await ref
          .read(credentialStoreProvider)
          .activeCredentials(pluginId);
      if (credentials == null) {
        return _record(
          pluginId,
          HealthCaseResult(
            capability: check.capability,
            outcome: HealthOutcome.skipped,
            elapsed: stopwatch.elapsed,
          ),
        );
      }
    }
    Object? result;
    AppError? error;
    final problems = <String>[];
    try {
      result = await check.run(plugin, credentials: credentials);
    } on AppError catch (thrown) {
      error = thrown;
    } on Object catch (thrown) {
      problems.add('threw ${thrown.runtimeType}, not an AppError');
    }
    stopwatch.stop();
    if (problems.isEmpty) {
      problems.addAll([
        ...check.expectation.evaluate(
          result: result,
          error: error,
          // toString 不含原始 error（可能帶憑證）；仍經遮蔽函式。
          describe: (error) => redactor.redact(error.toString()),
        ),
        ...check.extraProblems(result),
      ]);
    }
    return _record(
      pluginId,
      HealthCaseResult(
        capability: check.capability,
        outcome: problems.isEmpty ? HealthOutcome.passed : HealthOutcome.failed,
        elapsed: stopwatch.elapsed,
        errorType: error?.typeName,
        problems: [for (final problem in problems) redactor.redact(problem)],
      ),
    );
  }

  /// 每個案例一筆 tag `health` 的 log。
  HealthCaseResult _record(String pluginId, HealthCaseResult result) {
    final failed = result.outcome == HealthOutcome.failed;
    ref
        .read(logProvider)
        .write(
          failed ? LogLevel.warning : LogLevel.info,
          'Health check case',
          tag: 'health',
          fields: {
            'pluginId': pluginId,
            'capability': result.capability.wireName,
            'result': result.outcome.name,
            'durationMs': result.elapsed.inMilliseconds,
            'errorType': ?result.errorType,
          },
        );
    return result;
  }
}
