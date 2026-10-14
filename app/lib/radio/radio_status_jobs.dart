import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/domain/radio.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/scheduler/background_scheduler.dart';
import 'package:fmp/settings/network_settings.dart';

/// 電台清單，依 `sort_order`，資料庫一改就發新的值。
final radioStationsProvider = StreamProvider<List<RadioStation>>(
  (ref) => ref.watch(radioRepositoryProvider).watch(),
);

/// 最近一次狀態查詢失敗的電台（`radio_stations.id`），只在記憶體（D10）：「查詢失敗」
/// 不寫進資料庫，也不當成未開播；重啟後回到資料庫存的狀態。
final radioQueryFailuresProvider =
    NotifierProvider<RadioQueryFailures, Set<int>>(RadioQueryFailures.new);

final class RadioQueryFailures extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void mark(int id) {
    if (!state.contains(id)) state = {...state, id};
  }

  void clear(int id) {
    if (state.contains(id)) state = {...state}..remove(id);
  }
}

/// 電台狀態工作的 id（ADR 0031 §決定 6）：每個「已啟用、宣告 `live`、清單裡有電台」的
/// 插件一個。
String radioStatusJobId(String pluginId) => 'radio-status:$pluginId';

/// 手動刷新（[RadioStatusJobs.refreshAll]）的結果。
enum RadioRefreshResult {
  /// 每個插件的狀態工作都跑過了（含已經在跑的）。單一電台查詢失敗不算，那一列標
  /// 「查詢失敗」。
  completed,

  /// 離線，沒有發請求。
  offline,

  /// 沒有可以刷新的電台（清單是空的，或它們的插件停用或沒有安裝）。
  nothingToRefresh,
}

/// 電台狀態工作的登記（ADR 0031 §決定 6、M3 design §9.2）：跟著插件清單、電台清單與
/// 「電台狀態刷新間隔」，把 `radio-status:<pluginId>` 登記到排程器或移除。
///
/// - 工作依序對該插件的每個電台呼叫 `liveStatus`，成功就更新資料庫的狀態欄位。單一
///   電台失敗只把那一列標「查詢失敗」，其他繼續；全部失敗才把錯誤丟給排程器退避。
/// - 間隔設定為 0（關閉）時登記為 `interval: null`：不自動跑，但手動刷新仍可用。
/// - 只有工作的設定（插件實例、間隔）或有沒有電台改變時才重新登記；電台增減不打斷
///   進行中的那一次，工作每次跑都重新讀清單。
/// - 插件停用或移除時排程器已經會移除它的工作（PR 17），這裡跟著清單改變把登記簿對
///   齊，重新啟用（新的插件實例）時再登記回來。
///
/// 常駐：由 `FmpApp` 聽著，Riverpod 3 沒人聽的 provider 會被暫停。
final radioStatusJobsProvider = NotifierProvider<RadioStatusJobs, void>(
  RadioStatusJobs.new,
);

final class RadioStatusJobs extends Notifier<void> {
  /// 已登記的工作與它登記時的設定。
  final _registered = <String, ({SourcePlugin plugin, Duration? interval})>{};

  @override
  void build() {
    // 不在 onDispose 裡移除工作：生命週期裡不能再碰別的 provider，而這個 provider 跟
    // 排程器一樣常駐到 App 結束，排程器釋放時工作一起沒了。
    ref.listen(pluginRegistryProvider, (_, _) => _reconcile());
    ref.listen(radioStationsProvider, (_, _) => _reconcile());
    ref.listen(networkProvider, (_, _) => _reconcile());
    _reconcile();
  }

  /// 登記中的狀態工作屬於哪些插件。
  Set<String> registeredPluginIds() => Set.unmodifiable(_registered.keys);

  void _reconcile() {
    final plugins = ref.read(pluginRegistryProvider).value;
    final stations = ref.read(radioStationsProvider).value;
    final network = ref.read(networkProvider).value;
    // 還沒讀出來就不動：用錯的間隔登記再換掉只是白跑。
    if (plugins == null || stations == null || network == null) return;
    final scheduler = ref.read(backgroundSchedulerProvider.notifier);
    final withStations = {for (final station in stations) station.pluginId};
    final desired = {
      for (final plugin in plugins.values)
        if (plugin.manifest.capabilities.contains(PluginCapability.live) &&
            withStations.contains(plugin.manifest.id))
          plugin.manifest.id: plugin,
    };
    for (final pluginId in _registered.keys.toList()) {
      if (desired.containsKey(pluginId)) continue;
      _registered.remove(pluginId);
      scheduler.unregister(radioStatusJobId(pluginId));
    }
    for (final MapEntry(key: pluginId, value: plugin) in desired.entries) {
      final setup = (plugin: plugin, interval: network.radioStatusInterval);
      if (_registered[pluginId] == setup) continue;
      _registered[pluginId] = setup;
      scheduler.register(
        SchedulerJob(
          id: radioStatusJobId(pluginId),
          pluginId: pluginId,
          interval: network.radioStatusInterval,
          run: (context) => _run(pluginId, context),
        ),
      );
    }
  }

  Future<void> _run(String pluginId, JobContext context) async {
    if (!ref.mounted) return;
    final plugin = ref.read(pluginRegistryProvider).value?[pluginId];
    if (plugin == null) return;
    final repository = ref.read(radioRepositoryProvider);
    final failures = ref.read(radioQueryFailuresProvider.notifier);
    final stations = [
      for (final station in await repository.list())
        if (station.pluginId == pluginId) station,
    ];
    var failed = 0;
    AppError? lastError;
    for (final station in stations) {
      if (!context.isCurrent || !ref.mounted) return;
      try {
        final room = await plugin.liveStatus(
          LiveRoomQuery(roomId: station.roomId),
        );
        if (!context.isCurrent || !ref.mounted) return;
        await repository.updateStatus(
          station.id,
          status: switch (room.status) {
            LiveRoomStatus.live => RadioLiveStatus.live,
            LiveRoomStatus.offline => RadioLiveStatus.offline,
          },
          liveTitle: room.title,
          checkedAt: clock.now(),
        );
        if (!context.isCurrent || !ref.mounted) return;
        failures.clear(station.id);
      } on Object catch (error, stackTrace) {
        if (!context.isCurrent || !ref.mounted) return;
        failed++;
        lastError = AppError.wrap(error, stackTrace);
        failures.mark(station.id);
        ref
            .read(logProvider)
            .warning(
              'Radio status check failed',
              tag: 'radio',
              error: error,
              stackTrace: stackTrace,
              fields: {'plugin': pluginId, 'room': station.roomId},
            );
      }
    }
    // 一個壞房間不讓整批退避；全部失敗才算工作失敗。
    if (lastError != null && failed == stations.length) throw lastError;
  }

  /// 手動刷新：對每個登記中的狀態工作 `runNow`（不看間隔，也不看 App 是不是可見）。
  /// 離線時不發請求。工作全部失敗的錯誤在全部工作結束後重新丟出（排程器對手動失敗不
  /// 記 log，由呼叫端決定要不要提示，ADR 0013 §決定 5）。
  Future<RadioRefreshResult> refreshAll() async {
    final scheduler = ref.read(backgroundSchedulerProvider.notifier);
    final pluginIds = _registered.keys.toList();
    if (pluginIds.isEmpty) return RadioRefreshResult.nothingToRefresh;
    Object? firstError;
    StackTrace? firstStack;
    final results = await Future.wait([
      for (final pluginId in pluginIds)
        scheduler
            .runNow(radioStatusJobId(pluginId))
            .then<RunNowResult?>((result) => result)
            .catchError((Object error, StackTrace stackTrace) {
              firstError ??= error;
              firstStack ??= stackTrace;
              return null;
            }),
    ]);
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
    return results.contains(RunNowResult.offline)
        ? RadioRefreshResult.offline
        : RadioRefreshResult.completed;
  }
}
