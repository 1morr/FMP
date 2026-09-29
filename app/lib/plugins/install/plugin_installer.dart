import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_plugin.dart';

final pluginInstallerProvider = Provider<PluginInstaller>(
  (ref) => PluginInstaller(
    loader: ref.watch(scriptPluginLoaderProvider),
    repository: ref.watch(pluginRepositoryProvider),
    register: (plugin) =>
        ref.read(pluginRegistryProvider.notifier).register(plugin),
  ),
);

/// 從安裝檔安裝插件（ADR 0014 §決定 6）。選檔的 UI 在 M1 PR 12；安裝前的
/// 確認（能力、網域、警告）在 M3 的插件頁。
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
    this._now = DateTime.now,
  });

  final ScriptPluginLoader _loader;
  final PluginRepository _repository;
  final Future<void> Function(SourcePlugin plugin) _register;
  final DateTime Function() _now;

  /// 安裝檔的位元組（UTF-8）。錯誤都是 `AppError`，見 [PluginFile.decode]、
  /// [ScriptPluginLoader.load]。
  Future<SourcePlugin> installBytes(Uint8List bytes) =>
      _install(() => PluginFile.decode(bytes));

  /// 安裝檔的文字。
  Future<SourcePlugin> installSource(String source) =>
      _install(() => PluginFile.parse(source));

  Future<SourcePlugin> _install(PluginFile Function() parse) async {
    final file = parse();
    final plugin = await _loader.load(file);
    try {
      await _repository.install(
        InstalledPlugin(
          id: file.manifest.id,
          version: file.manifest.version,
          manifestJson: file.manifestJson,
          script: file.source,
          installedAt: _now().toUtc(),
        ),
      );
    } on Object catch (error, stackTrace) {
      plugin.close();
      throw AppError.wrap(error, stackTrace, pluginId: file.manifest.id);
    }
    await _register(plugin);
    return plugin;
  }
}
