import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// App 共用的 HTTP client 工廠：每個插件由它建一個 client（ADR 0012 §決定 1）。
final sourceHttpClientFactoryProvider = Provider<SourceHttpClientFactory>(
  (ref) => SourceHttpClientFactory(log: ref.watch(logProvider)),
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
final class PluginRegistry extends AsyncNotifier<Map<String, SourcePlugin>> {
  final _open = <SourcePlugin>{};

  @override
  Future<Map<String, SourcePlugin>> build() async {
    final loader = ref.watch(scriptPluginLoaderProvider);
    final repository = ref.watch(pluginRepositoryProvider);
    final log = ref.watch(logProvider);
    ref.onDispose(() {
      for (final plugin in _open) {
        plugin.close();
      }
      _open.clear();
    });
    final plugins = <String, SourcePlugin>{};
    for (final installed in await repository.list()) {
      try {
        final plugin = await loader.load(PluginFile.parse(installed.script));
        _open.add(plugin);
        _watch(plugin);
        plugins[plugin.manifest.id] = plugin;
      } on AppError catch (error) {
        log.report('Failed to load an installed plugin', error, tag: 'plugins');
      }
    }
    return Map.unmodifiable(plugins);
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
    state = AsyncData(Map.unmodifiable({...current, id: plugin}));
    if (previous != null && !identical(previous, plugin)) {
      _open.remove(previous);
      previous.close();
    }
  }
}
