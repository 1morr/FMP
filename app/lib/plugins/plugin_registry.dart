import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 網路紀錄的 id，兩種 HTTP client 共用：同一次執行裡不重複。
final networkRecordIdsProvider = Provider<NetworkRecordIds>(
  (ref) => NetworkRecordIds(),
);

/// App 共用的 HTTP client 工廠：每個插件由它建一個 client（ADR 0012 §決定 1）。
/// 每次送出的結果回報給網路狀態（ADR 0016 §決定 6）。
final sourceHttpClientFactoryProvider = Provider<SourceHttpClientFactory>(
  (ref) => SourceHttpClientFactory(
    log: ref.watch(logProvider),
    reportOutcome: ref.watch(networkStatusProvider.notifier).report,
    recordIds: ref.watch(networkRecordIdsProvider),
  ),
);

/// 媒體 client 的工廠：每個插件一個不帶憑證的 client（ADR 0012 §決定 1），
/// 結果回報給同一個網路狀態。
final mediaHttpClientFactoryProvider = Provider<MediaHttpClientFactory>(
  (ref) => MediaHttpClientFactory(
    log: ref.watch(logProvider),
    reportOutcome: ref.watch(networkStatusProvider.notifier).report,
    recordIds: ref.watch(networkRecordIdsProvider),
  ),
);

final scriptPluginLoaderProvider = Provider<ScriptPluginLoader>(
  (ref) => ScriptPluginLoader(
    log: ref.watch(logProvider),
    redactor: ref.watch(redactorProvider),
    httpClients: ref.watch(sourceHttpClientFactoryProvider),
    storage: ref.watch(pluginStorageRepositoryProvider),
  ),
);

/// 載入好的插件，鍵是插件 id。App 其他部分從這裡拿 [SourcePlugin]。
final pluginRegistryProvider =
    AsyncNotifierProvider<PluginRegistry, Map<String, SourcePlugin>>(
      PluginRegistry.new,
    );

/// 插件清單：啟動時載入 `installed_plugins` 裡的每個插件，安裝後由
/// `PluginInstaller` 加入。
///
/// 載入失敗的插件經 `log.report` 記下後略過，不擋其他插件（曲目標示「音源
/// 未安裝」等呈現在 M3 的插件頁）。沒有回應的插件留在清單上，狀態看
/// `SourcePlugin.health`。provider 釋放時關閉所有插件。
///
/// 每個插件加入清單時，以它 manifest 的允許網域建一個媒體 client
/// （[mediaClient]），與插件的 API client 同一份網域；插件被取代或清單釋放時
/// 關閉。
final class PluginRegistry extends AsyncNotifier<Map<String, SourcePlugin>> {
  final _open = <SourcePlugin>{};
  final _media = <String, MediaHttpClient>{};

  @override
  Future<Map<String, SourcePlugin>> build() async {
    final loader = ref.watch(scriptPluginLoaderProvider);
    final repository = ref.watch(pluginRepositoryProvider);
    final mediaClients = ref.watch(mediaHttpClientFactoryProvider);
    final log = ref.watch(logProvider);
    ref.onDispose(() {
      for (final plugin in _open) {
        plugin.close();
      }
      _open.clear();
      for (final client in _media.values) {
        client.close();
      }
      _media.clear();
    });
    final plugins = <String, SourcePlugin>{};
    for (final installed in await repository.list()) {
      try {
        final plugin = await loader.load(PluginFile.parse(installed.script));
        _open.add(plugin);
        _watch(plugin);
        _createMediaClient(mediaClients, plugin);
        plugins[plugin.manifest.id] = plugin;
      } on AppError catch (error) {
        log.report('Failed to load an installed plugin', error, tag: 'plugins');
      }
    }
    return Map.unmodifiable(plugins);
  }

  /// [pluginId] 的媒體 client；插件不在清單上（或清單還沒載入完）是 `null`。
  MediaHttpClient? mediaClient(String pluginId) => _media[pluginId];

  /// 為 [plugin] 建媒體 client，取代並關閉同 id 的舊 client。
  void _createMediaClient(MediaHttpClientFactory factory, SourcePlugin plugin) {
    final id = plugin.manifest.id;
    final previous = _media[id];
    _media[id] = factory.create(
      pluginId: id,
      allowedHosts: plugin.manifest.allowedHosts,
    );
    previous?.close();
  }

  /// [plugin] 變成沒有回應時發出新的清單（內容相同），畫面才會讀到它的
  /// `health`。插件留在清單裡、停用到 App 重啟（prd 擁有者決定 7）。
  void _watch(SourcePlugin plugin) {
    plugin.whenUnresponsive.then((_) {
      if (!ref.mounted) return;
      final current = state.value;
      if (current != null && identical(current[plugin.manifest.id], plugin)) {
        state = AsyncData(Map.unmodifiable({...current}));
      }
    });
  }

  /// 加入 [plugin]；已有同 id 的就取代並關閉舊的（更新）。
  Future<void> register(SourcePlugin plugin) async {
    final built = await future;
    // 等的期間別的 register 可能已經改了清單：以最新的為準，才不會蓋掉它。
    final current = state.value ?? built;
    final id = plugin.manifest.id;
    final previous = current[id];
    _open.add(plugin);
    _watch(plugin);
    _createMediaClient(ref.read(mediaHttpClientFactoryProvider), plugin);
    state = AsyncData(Map.unmodifiable({...current, id: plugin}));
    if (previous != null && !identical(previous, plugin)) {
      _open.remove(previous);
      previous.close();
    }
  }
}
