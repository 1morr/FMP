import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/repository/plugin_downloader.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_plugin.dart';

final pluginInstallerProvider = Provider<PluginInstaller>(
  (ref) => PluginInstaller(
    loader: ref.watch(scriptPluginLoaderProvider),
    repository: ref.watch(pluginRepositoryProvider),
    register: (plugin) =>
        ref.read(pluginRegistryProvider.notifier).register(plugin),
    unregister: (id) =>
        ref.read(pluginRegistryProvider.notifier).unregister(id),
    removeCache: (id) async =>
        (await ref.read(cacheStoreProvider.future)).removePlugin(id),
  ),
);

/// 安裝、更新、移除插件（ADR 0014 §決定 6、ADR 0030 §決定 8–10）。安裝前的確認
/// （能力、網域、警告）是呼叫端（插件頁）的事；[installPrepared] 只擋掉該確認而
/// 沒確認的。
///
/// 依序：解析 manifest（不執行腳本）→ 在 runtime 載入並檢查匯出與能力一致 →
/// 寫進 `installed_plugins` → 加入插件清單。任一步失敗都不留下半套：已載入的
/// runtime 關閉、資料庫沒有寫入。
///
/// 已安裝同 id 的插件視為更新：資料列覆蓋、storage 保留（`PluginRepository`
/// 以 upsert 寫入），清單裡的舊 runtime 關閉。
final class PluginInstaller {
  PluginInstaller({
    required this._loader,
    required this._repository,
    required this._register,
    required this._unregister,
    required this._removeCache,
    this._now = DateTime.now,
  });

  final ScriptPluginLoader _loader;
  final PluginRepository _repository;
  final Future<void> Function(SourcePlugin plugin) _register;
  final Future<void> Function(String pluginId) _unregister;
  final Future<void> Function(String pluginId) _removeCache;
  final DateTime Function() _now;

  /// 安裝檔的位元組（UTF-8）。錯誤都是 `AppError`，見 [PluginFile.decode]、
  /// [ScriptPluginLoader.load]。
  Future<SourcePlugin> installBytes(Uint8List bytes) =>
      _install(() => PluginFile.decode(bytes));

  /// 安裝檔的文字。
  Future<SourcePlugin> installSource(String source) =>
      _install(() => PluginFile.parse(source));

  /// 安裝或更新 [prepared]（`PluginDownloader.prepare` 的結果）。
  ///
  /// [prepared] 需要確認（[PreparedPlugin.needsConfirmation]）而 [confirmed] 不是
  /// 真：丟 [StateError]，什麼都不做（確認是呼叫端的責任，這裡只是不讓漏掉的
  /// 通過）。
  Future<SourcePlugin> installPrepared(
    PreparedPlugin prepared, {
    required bool confirmed,
  }) {
    if (prepared.needsConfirmation && !confirmed) {
      throw StateError(
        'The install of ${prepared.file.manifest.id} '
        'needs the confirmation of the user',
      );
    }
    return _install(
      () => prepared.file,
      sourceIndexUrl: prepared.sourceIndexUrl,
      checksJson: prepared.checksJson,
    );
  }

  /// 移除 [pluginId]（ADR 0030 §決定 10）：關閉 runtime → 刪快取項目 → 刪
  /// `installed_plugins` 列（`plugin_storage` 由外鍵 cascade）。曲目與電台保留。
  ///
  /// 每一步都可重複：中途失敗就停在那一步並丟出錯誤，再呼叫一次從頭跑完。之後的
  /// 里程碑在對應的位置加：憑證與遮蔽登記、WebView cookie、帳號與每音源設定（M3
  /// 帳號 PR）、排程器的工作（背景排程 PR），都在刪 `installed_plugins` 列之前。
  Future<void> remove(String pluginId) async {
    try {
      await _unregister(pluginId);
      await _removeCache(pluginId);
      await _repository.remove(pluginId);
    } on Object catch (error, stackTrace) {
      throw AppError.wrap(error, stackTrace, pluginId: pluginId);
    }
  }

  Future<SourcePlugin> _install(
    PluginFile Function() parse, {
    String? sourceIndexUrl,
    String? checksJson,
  }) async {
    final file = parse();
    final plugin = await _loader.load(file);
    final bool disabled;
    try {
      // 更新停用中的插件：寫入新版本，但仍是停用、不加入清單。
      disabled = !((await _repository.byId(file.manifest.id))?.enabled ?? true);
      await _repository.install(
        InstalledPlugin(
          id: file.manifest.id,
          version: file.manifest.version,
          manifestJson: file.manifestJson,
          script: file.source,
          installedAt: _now().toUtc(),
          sourceIndexUrl: sourceIndexUrl,
          checksJson: checksJson,
        ),
      );
    } on Object catch (error, stackTrace) {
      plugin.close();
      throw AppError.wrap(error, stackTrace, pluginId: file.manifest.id);
    }
    if (disabled) {
      plugin.close();
      return plugin;
    }
    await _register(plugin);
    return plugin;
  }
}
