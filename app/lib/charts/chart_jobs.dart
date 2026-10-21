import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/charts/chart_cache.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/chart_settings_repository.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/settings/network_settings.dart';

/// 排行模組的 log tag（M4 design §13）。
const chartsLogTag = 'charts';

/// 排行工作的 id（M4 design §6.2）：每個「已啟用、宣告 `charts`、至少一個啟用榜單」的插件一個。
String chartJobId(String pluginId) => 'charts:$pluginId';

/// 所有榜單的設定（`chart_settings`），資料庫一改就發新的值。
final chartSettingsProvider = StreamProvider<List<ChartSetting>>(
  (ref) => ref.watch(chartSettingsRepositoryProvider).watch(),
);

/// 最近一次更新失敗的榜單，只在記憶體（`radioQueryFailuresProvider` 的做法）：「更新失敗」
/// 不寫進資料庫，重啟後回到沒有標記；快取裡上一次的內容照舊顯示。
final chartFailuresProvider = NotifierProvider<ChartFailures, Set<ChartKey>>(
  ChartFailures.new,
);

final class ChartFailures extends Notifier<Set<ChartKey>> {
  @override
  Set<ChartKey> build() => const {};

  void mark(ChartKey key) {
    if (!state.contains(key)) state = {...state, key};
  }

  void clear(ChartKey key) {
    if (state.contains(key)) state = {...state}..remove(key);
  }

  /// 清掉 [pluginId] 的全部標記（插件停用或榜單全部停用）。
  void clearPlugin(String pluginId) {
    if (state.any((key) => key.pluginId == pluginId)) {
      state = {
        for (final key in state)
          if (key.pluginId != pluginId) key,
      };
    }
  }
}

/// 一個插件在 [chartCatalogProvider] 裡的樣子：顯示名稱與 `chartList` 的結果（`null`＝問過但
/// 取不到，插件壞了）。
@immutable
final class ChartCatalogEntry {
  const ChartCatalogEntry({required this.name, required this.charts});

  /// 插件的顯示名稱（manifest 的 `name`）。
  final String name;

  /// 依插件給的順序；`null`＝取不到。
  final List<ChartRef>? charts;

  @override
  bool operator ==(Object other) {
    if (other is! ChartCatalogEntry || other.name != name) return false;
    final mine = charts;
    final theirs = other.charts;
    if (mine == null || theirs == null) return mine == theirs;
    if (mine.length != theirs.length) return false;
    for (final (index, chart) in mine.indexed) {
      if (chart.chartId != theirs[index].chartId ||
          chart.title != theirs[index].title) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    charts == null
        ? null
        : Object.hashAll([
            for (final chart in charts!) (chart.chartId, chart.title),
          ]),
  );
}

/// [ChartJobs] 已經取得的榜單清單，給首頁、探索頁與設定頁（`chartEntriesProvider`）：鍵是插件清單上
/// 宣告 `charts` 的插件 id，依插件清單的順序；還沒問到或取不到的插件是 `null`（沿用上一份）。
/// `null`＝排行工作還沒對齊過（App 剛啟動，或沒有人讓 [chartJobsProvider] 常駐）。
///
/// 只是一份被動的狀態，自己不依賴任何東西，寫的只有 [ChartJobs]。正式環境裡插件清單與排行工作本來就
/// 常駐（`FmpApp`），被動是為了測試：多數外殼測試 override 了 `searchSourcesProvider`、插件清單沒人
/// 聽，畫面若自己去讀插件清單或 [chartJobsProvider] 就會把它們拉起來——在假時間裡開始的讀取拿著
/// drift 的鎖、擋住 `runAsync` 裡的寫入（同搜尋頁的前例），排行工作也跟著在每個外殼測試裡跑。
final chartCatalogProvider =
    NotifierProvider<ChartCatalog, Map<String, ChartCatalogEntry>?>(
      ChartCatalog.new,
    );

final class ChartCatalog extends Notifier<Map<String, ChartCatalogEntry>?> {
  @override
  Map<String, ChartCatalogEntry>? build() => null;

  /// 換成 [catalog]；內容沒變就不發新的值。
  void publish(Map<String, ChartCatalogEntry> catalog) {
    final current = state;
    // mapEquals 不看順序：插件清單的順序變了也要發。
    if (current != null &&
        listEquals(current.keys.toList(), catalog.keys.toList()) &&
        mapEquals(current, catalog)) {
      return;
    }
    state = Map.unmodifiable(catalog);
  }
}

/// 排行工作的登記（M4 design §6.2、ADR 0017）：跟著插件清單、榜單設定與「排行刷新間隔」，把
/// `charts:<pluginId>` 登記到排程器或移除。
///
/// - 每次執行：`chartList` → 啟用的榜單（`chart_settings.enabled` 不是假；插件新增的榜單預設
///   啟用；插件拿掉的榜單的列留著，以 `chartList` 為準）逐一 `chart` → 寫快取。單一榜單失敗
///   只標那一個「更新失敗」，其他繼續；全部失敗才把錯誤丟給排程器退避。
/// - 登記時 `chartList` 丟錯（插件壞了）也照樣登記：工作每次執行本來就先呼叫 `chartList`
///   （M4 design §4.6），失敗就整次失敗、由排程器退避重試（ADR 0017 §決定 4），手動刷新也
///   拿得到錯誤。這時還不知道有哪些榜單，執行時取到清單才補上（[_learnCharts]）。
/// - 間隔設定為 0（關閉）時登記為 `interval: null`：不自動跑，但 [runNow] 仍可用。
/// - 只有插件實例、間隔或啟用榜單的集合改變時才重新登記；某插件的榜單全部停用（或插件停用、
///   移除）就移除工作。
/// - （重新）登記時有啟用的榜單沒有快取（[_missesCache]）就登記成立即到期（`dueNow`）：重啟後上次
///   失敗的榜單、重新啟用的榜單不必等一整個間隔，畫面不會一直轉圈。仍受可見、在線、退避管。
/// - 榜單停用時刪那個榜單的快取（ADR 0016 §決定 4），插件停用或榜單全部停用時刪該插件的排行
///   快取。移除插件的快取由 `PluginInstaller.remove` 的 `CacheStore.removePlugin` 刪。
///
/// 每次對齊完、每次執行取到 `chartList` 時，把各插件的榜單清單發到 [chartCatalogProvider]。
///
/// 常駐：由 `FmpApp` 聽著，Riverpod 3 沒人聽的 provider 會被暫停。
final chartJobsProvider = NotifierProvider<ChartJobs, void>(ChartJobs.new);

final class ChartJobs extends Notifier<void> {
  /// 已登記的工作與它登記時的設定。
  final _registered = <String, _Setup>{};

  /// 每個插件實例的 `chartList` 結果：插件內的常數，登記時不必每次都呼叫插件。
  final _lists = Expando<ChartList>();

  /// 每次對齊加一：等 `chartList` 的期間又有新的對齊開始時，舊的就放棄，由新的做完。
  var _generation = 0;

  @override
  void build() {
    // 不在 onDispose 裡移除工作：生命週期裡不能再碰別的 provider，而這個 provider 跟排程器
    // 一樣常駐到 App 結束，排程器釋放時工作一起沒了。
    ref.listen(pluginRegistryProvider, (_, _) => _reconcile());
    ref.listen(chartSettingsProvider, (_, _) => _reconcile());
    ref.listen(networkProvider, (_, _) => _reconcile());
    _reconcile();
  }

  /// 手動刷新 [pluginId] 的排行：不看間隔，也不看 App 是不是可見；離線時不發請求
  /// （[RunNowResult.offline]），沒有這個工作是 [RunNowResult.unknown]。全部榜單都失敗的錯誤
  /// 重新丟出（排程器對手動失敗不記 log，由呼叫端決定要不要提示，ADR 0013 §決定 5）。
  Future<RunNowResult> runNow(String pluginId) => ref
      .read(backgroundSchedulerProvider.notifier)
      .runNow(chartJobId(pluginId));

  void _reconcile() {
    final generation = ++_generation;
    unawaited(_apply(generation));
  }

  Future<void> _apply(int generation) async {
    try {
      await _applyUnchecked(generation);
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      ref
          .read(logProvider)
          .report(
            'Failed to register the chart jobs',
            AppError.wrap(error, stackTrace),
            tag: chartsLogTag,
          );
    }
  }

  Future<void> _applyUnchecked(int generation) async {
    final plugins = ref.read(pluginRegistryProvider).value;
    final settings = ref.read(chartSettingsProvider).value;
    final network = ref.read(networkProvider).value;
    // 還沒讀出來就不動：用錯的間隔登記再換掉只是白跑。
    if (plugins == null || settings == null || network == null) return;
    final desired = <String, _Setup>{};
    for (final plugin in plugins.values) {
      if (!plugin.manifest.capabilities.contains(PluginCapability.charts)) {
        continue;
      }
      final list = await _chartList(plugin);
      // 等的期間插件、設定或間隔又變了：新的對齊會接手。
      if (generation != _generation || !ref.mounted) return;
      // 每問完一個就發：一個卡住的插件不擋其他插件的榜單出現在畫面上。
      _publish(plugins);
      final Set<String>? enabled;
      if (list == null) {
        // 取不到清單：照樣登記，讓工作自己呼叫 chartList、失敗時退避重試；不刪任何快取。
        enabled = null;
      } else {
        enabled = {
          for (final chart in _enabledCharts(
            list,
            settings,
            plugin.manifest.id,
          ))
            chart.chartId,
        };
        if (enabled.isEmpty) continue;
      }
      desired[plugin.manifest.id] = _Setup(
        plugin,
        network.chartRefreshInterval,
        enabled,
      );
    }

    // 要（重新）登記的工作裡，有啟用的榜單沒有快取的：登記成立即到期，不等上次成功加間隔。
    final dueNow = <String>{
      for (final MapEntry(key: pluginId, value: setup) in desired.entries)
        if (_registered[pluginId] != setup &&
            await _missesCache(pluginId, setup))
          pluginId,
    };
    if (generation != _generation || !ref.mounted) return;

    final scheduler = ref.read(backgroundSchedulerProvider.notifier);
    final failures = ref.read(chartFailuresProvider.notifier);
    final goneChartCaches = <String>[];
    final disabledCharts = <ChartKey>[];
    for (final pluginId in _registered.keys.toList()) {
      if (desired.containsKey(pluginId)) continue;
      _registered.remove(pluginId);
      scheduler.unregister(chartJobId(pluginId));
      failures.clearPlugin(pluginId);
      goneChartCaches.add(pluginId);
    }
    for (final MapEntry(key: pluginId, value: setup) in desired.entries) {
      final previous = _registered[pluginId];
      if (previous == setup) continue;
      _registered[pluginId] = setup;
      scheduler.register(
        SchedulerJob(
          id: chartJobId(pluginId),
          pluginId: pluginId,
          interval: setup.interval,
          run: (context) => _run(pluginId, context),
        ),
        dueNow: dueNow.contains(pluginId),
      );
      // 停用（或插件拿掉）的榜單：之前啟用、現在不在集合裡。現在的集合不知道（chartList 丟錯）
      // 就不刪；之前的不知道就當成清單上全部都可能有快取。
      final current = setup.chartIds;
      if (previous == null || current == null) continue;
      final before =
          previous.chartIds ??
          {
            for (final chart in _lists[setup.plugin]?.charts ?? <ChartRef>[])
              chart.chartId,
          };
      for (final chartId in before.difference(current)) {
        final key = (pluginId: pluginId, chartId: chartId);
        failures.clear(key);
        disabledCharts.add(key);
      }
    }

    // 工作都登記好了才刪快取：進行中的舊工作已經過期，不會再寫。
    await _dropCaches(goneChartCaches, disabledCharts);
    // 在 await 之後才發：沒有宣告 `charts` 的插件時，上面整段在 build 裡同步跑完，那時不能改
    // 別的 provider。
    if (generation != _generation || !ref.mounted) return;
    _publish(plugins);
  }

  /// 把 [plugins] 裡宣告 `charts` 的插件的榜單清單發到 [chartCatalogProvider]。這個實例還沒取到
  /// （取不到）時沿用上一份（同一個插件換了實例而新的取不到時留著舊的清單），沒有就是 `null`。
  void _publish(Map<String, SourcePlugin> plugins) {
    final catalog = ref.read(chartCatalogProvider.notifier);
    final previous = ref.read(chartCatalogProvider);
    catalog.publish({
      for (final plugin in plugins.values)
        if (plugin.manifest.capabilities.contains(PluginCapability.charts))
          plugin.manifest.id: ChartCatalogEntry(
            name: plugin.manifest.name,
            charts:
                _lists[plugin]?.charts ?? previous?[plugin.manifest.id]?.charts,
          ),
    });
  }

  /// [setup] 啟用的榜單裡有沒有快取的（快取讀不出來也算）：重啟時上次失敗的榜單、重新啟用的榜單、
  /// 被淘汰的榜單都不必等下一輪。間隔關閉時不算（尊重「關閉」，畫面說明怎麼手動載入）；登記時還
  /// 不知道啟用哪些榜單（`chartList` 丟錯）也不算。已標「更新失敗」的榜單不算：畫面已經說它失敗了，
  /// 一個一直抓不到的榜單不該讓整個插件每次設定變更都立刻重抓。標記只在記憶體，所以冷啟動時它仍會
  /// 讓工作立即到期一次。
  Future<bool> _missesCache(String pluginId, _Setup setup) async {
    final chartIds = setup.chartIds;
    if (setup.interval == null || chartIds == null) return false;
    final failures = ref.read(chartFailuresProvider);
    try {
      final cache = await ref.read(chartCacheProvider.future);
      for (final chartId in chartIds) {
        final key = (pluginId: pluginId, chartId: chartId);
        if (failures.contains(key)) continue;
        if (await cache.read(key) == null) return true;
      }
      return false;
    } on Object {
      // 快取庫開不起來（已記過 error）或讀失敗：當成沒有快取。
      return true;
    }
  }

  /// 刪 [plugins] 的全部排行快取與 [charts] 那幾個榜單的快取。
  Future<void> _dropCaches(List<String> plugins, List<ChartKey> charts) async {
    if (plugins.isEmpty && charts.isEmpty) return;
    try {
      final cache = await ref.read(chartCacheProvider.future);
      for (final pluginId in plugins) {
        await cache.removePlugin(pluginId);
      }
      for (final key in charts) {
        await cache.remove(key);
      }
      if (ref.mounted) ref.read(chartCacheRevisionProvider.notifier).bump();
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      // 快取庫開不起來（已記過 error）或刪失敗：留給下次對齊與快取的淘汰。
      ref
          .read(logProvider)
          .warning(
            'Failed to delete the cached charts',
            tag: chartsLogTag,
            error: error,
            stackTrace: stackTrace,
          );
    }
  }

  /// [plugin] 的榜單清單；取不到（插件壞了）是 `null`，下次對齊再試。
  Future<ChartList?> _chartList(SourcePlugin plugin) async {
    if (_lists[plugin] case final cached?) return cached;
    try {
      final list = await plugin.chartList();
      _lists[plugin] = list;
      return list;
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return null;
      ref
          .read(logProvider)
          .warning(
            'Failed to list the charts of a plugin',
            tag: chartsLogTag,
            error: error,
            stackTrace: stackTrace,
            fields: {'pluginId': plugin.manifest.id},
          );
      return null;
    }
  }

  Future<void> _run(String pluginId, JobContext context) async {
    if (!ref.mounted) return;
    final plugin = ref.read(pluginRegistryProvider).value?[pluginId];
    if (plugin == null) return;
    // 每次都先問插件有哪些榜單（M4 design §4.6）；丟錯就整次失敗，由排程器退避。
    final list = await plugin.chartList();
    if (!context.isCurrent || !ref.mounted) return;
    _lists[plugin] = list;
    if (ref.read(pluginRegistryProvider).value case final plugins?
        when identical(plugins[pluginId], plugin)) {
      _publish(plugins);
    }
    final settings = await ref.read(chartSettingsProvider.future);
    if (!context.isCurrent || !ref.mounted) return;
    final charts = _enabledCharts(list, settings, pluginId);
    if (!_learnCharts(pluginId, plugin, list, charts)) return;
    final cache = await ref.read(chartCacheProvider.future);
    if (!context.isCurrent || !ref.mounted) return;
    final failures = ref.read(chartFailuresProvider.notifier);
    var succeeded = 0;
    var failed = 0;
    AppError? lastError;
    for (final chart in charts) {
      if (!context.isCurrent || !ref.mounted) return;
      final key = (pluginId: pluginId, chartId: chart.chartId);
      try {
        final page = await plugin.chart(ChartQuery(chartId: chart.chartId));
        if (!context.isCurrent || !ref.mounted) return;
        await cache.write(
          key,
          ChartCacheEntry(
            fetchedAt: clock.now().toUtc(),
            tracks: List.unmodifiable([
              for (final track in page.tracks) track.toTrackInfo(),
            ]),
          ),
        );
        if (!context.isCurrent || !ref.mounted) return;
        ref.read(chartCacheRevisionProvider.notifier).bump();
        failures.clear(key);
        succeeded++;
      } on Object catch (error, stackTrace) {
        if (!context.isCurrent || !ref.mounted) return;
        failed++;
        lastError = AppError.wrap(error, stackTrace, pluginId: pluginId);
        failures.mark(key);
        ref
            .read(logProvider)
            .warning(
              'Chart update failed',
              tag: chartsLogTag,
              error: error,
              stackTrace: stackTrace,
              fields: {'pluginId': pluginId, 'chartId': chart.chartId},
            );
      }
    }
    ref
        .read(logProvider)
        .info(
          'Chart refresh finished',
          tag: chartsLogTag,
          fields: {
            'pluginId': pluginId,
            'succeeded': succeeded,
            'failed': failed,
          },
        );
    // 一個壞榜單不讓整批退避；全部失敗才算工作失敗。
    if (lastError != null && succeeded == 0) throw lastError;
  }

  /// 登記時取不到 [plugin] 的榜單清單（[_Setup.chartIds] 是 `null`）而這次執行取到了：把啟用的
  /// [charts] 補進登記簿。不重新登記——工作本身不看榜單集合，重新登記只會丟掉這一次；補上之後
  /// 設定再變就照常比對、重新登記。登記時不知道的停用榜單，它們的快取這時才刪；一個都沒啟用
  /// 就移除工作與該插件的快取。回傳這次執行要不要繼續。
  bool _learnCharts(
    String pluginId,
    SourcePlugin plugin,
    ChartList list,
    List<ChartRef> charts,
  ) {
    final setup = _registered[pluginId];
    if (setup == null ||
        setup.chartIds != null ||
        !identical(setup.plugin, plugin)) {
      return true;
    }
    final failures = ref.read(chartFailuresProvider.notifier);
    final enabled = {for (final chart in charts) chart.chartId};
    if (enabled.isEmpty) {
      _registered.remove(pluginId);
      ref
          .read(backgroundSchedulerProvider.notifier)
          .unregister(chartJobId(pluginId));
      failures.clearPlugin(pluginId);
      unawaited(_dropCaches([pluginId], const []));
      return false;
    }
    _registered[pluginId] = _Setup(plugin, setup.interval, enabled);
    final disabled = [
      for (final chart in list.charts)
        if (!enabled.contains(chart.chartId))
          (pluginId: pluginId, chartId: chart.chartId),
    ];
    disabled.forEach(failures.clear);
    unawaited(_dropCaches(const [], disabled));
    return true;
  }

  /// [list] 裡 [pluginId] 要抓的榜單：`chart_settings.enabled` 不是假的。
  static List<ChartRef> _enabledCharts(
    ChartList list,
    List<ChartSetting> settings,
    String pluginId,
  ) {
    final disabled = {
      for (final setting in settings)
        if (setting.pluginId == pluginId && setting.enabled == false)
          setting.chartId,
    };
    return [
      for (final chart in list.charts)
        if (!disabled.contains(chart.chartId)) chart,
    ];
  }
}

/// 一個工作登記時的設定：變了才重新登記。
@immutable
final class _Setup {
  const _Setup(this.plugin, this.interval, this.chartIds);

  final SourcePlugin plugin;
  final Duration? interval;

  /// 啟用的榜單；`null` 是登記時 `chartList` 丟錯、還不知道（執行時取到才補上）。
  final Set<String>? chartIds;

  @override
  bool operator ==(Object other) =>
      other is _Setup &&
      identical(other.plugin, plugin) &&
      other.interval == interval &&
      setEquals(other.chartIds, chartIds);

  @override
  int get hashCode => Object.hash(
    plugin,
    interval,
    chartIds == null ? null : Object.hashAllUnordered(chartIds!),
  );
}
