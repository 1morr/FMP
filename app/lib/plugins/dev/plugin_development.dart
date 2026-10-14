import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/dev/describe_error.dart';
import 'package:fmp/plugins/dev/dev_folder.dart';
import 'package:fmp/plugins/plugin_registry.dart';

/// 插件開發資料夾的載入（M3 PR 16b，design §3.3、§3.4）：資料夾裡的插件載入成「開發中」，
/// 取代同 id 的已安裝版；卸載（資料夾變成 `null`）時恢復已安裝版。
///
/// 所有動作排進同一條序列，前一個做完才做下一個。狀態 `null`＝沒有生效的資料夾。
final pluginDevelopmentProvider =
    NotifierProvider<PluginDevelopment, DevFolderState?>(PluginDevelopment.new);

// Isolate.run 的閉包放在獨立的函式：不能帶著 Notifier 的 context（送不過去）。
Future<DevScan> _scan(Directory folder) =>
    Isolate.run(() => scanDevFolder(folder));

Future<ScannedPlugin> _scanOne(Directory directory) =>
    Isolate.run(() => scanPluginDirectory(directory));

final class PluginDevelopment extends Notifier<DevFolderState?> {
  Future<void> _tail = Future.value();

  /// 最近一次套用的資料夾路徑；[_applied] 為假時還沒套用過（啟動後第一次，含 `null`，
  /// 為了刪掉上次留下的標記列）。
  String? _appliedPath;
  var _applied = false;

  @override
  DevFolderState? build() {
    ref.listen(pluginDevFolderProvider, (_, next) {
      switch (next) {
        case AsyncData(:final value):
          _enqueueFolder(value);
        case AsyncError(:final error, :final stackTrace):
          ref
              .read(logProvider)
              .error(
                'Plugin development folder unavailable',
                error: error,
                stackTrace: stackTrace,
                tag: 'plugins',
              );
          _enqueueFolder(null);
        case AsyncLoading():
          break;
      }
    }, fireImmediately: true);
    return null;
  }

  /// [pluginId] 在開發中（含載入失敗的）。
  bool isInDevelopment(String pluginId) =>
      state?.plugins.any((plugin) => plugin.id == pluginId) ?? false;

  /// 健康檢查的案例來源：開發中的插件是資料夾的 `checks.json`（沒有檔就是 `null`＝沒有
  /// 案例），其他是已安裝的列存的。
  String? checksJsonFor(InstalledPlugin installed) {
    final plugin = state?.plugins
        .where((plugin) => plugin.id == installed.id)
        .firstOrNull;
    if (plugin == null) return installed.checksJson;
    final file = File(p.join(plugin.directory.path, 'checks.json'));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  /// 重新讀 [pluginId] 的目錄並載入，取代 App 裡的開發版。載入失敗（含 manifest 的 id
  /// 改變）時從清單拿掉、不退回已安裝版，原因在狀態裡。不在開發中時什麼都不做。
  Future<void> reload(String pluginId) => _enqueue(() => _reload(pluginId));

  /// 以目前的資料夾再套用一次（新增或刪掉的插件目錄要靠它）。
  Future<void> rescan() => _enqueue(() async {
    final folder = state?.folder;
    if (folder == null) return;
    await _apply(folder);
  });

  void _enqueueFolder(Directory? folder) {
    if (_applied && folder?.path == _appliedPath) return;
    unawaited(_enqueue(() => _apply(folder)));
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _apply(Directory? folder) async {
    _applied = true;
    _appliedPath = folder?.path;
    final registry = ref.read(pluginRegistryProvider.notifier);
    await ref.read(pluginRegistryProvider.future);
    if (!ref.mounted) return;
    final repository = ref.read(pluginRepositoryProvider);
    final previous = [...?state?.plugins.map((plugin) => plugin.id)];
    if (folder != null) {
      state = DevFolderState(
        folder: folder,
        plugins: state?.plugins ?? const [],
        problems: state?.problems ?? const [],
        busy: true,
      );
    }
    // 1. 上一次開發中的全部卸下。
    for (final id in previous) {
      await registry.unregister(id);
    }
    // 2. 掃描新資料夾。
    final scan = folder == null ? const DevScan() : await _scan(folder);
    if (!ref.mounted) return;
    final redact = ref.read(redactorProvider).redact;
    // 3. 對齊 installed_plugins：標記列只留給新資料夾裡讀得出 manifest 的插件。
    final replaced = <String, String?>{};
    for (final scanned in scan.plugins) {
      final file = scanned.file;
      if (file == null) continue;
      replaced[scanned.id] = await _putRow(repository, scanned);
    }
    await repository.removeDevFolderRows(keep: replaced.keys.toSet());
    // 4. 上一次有、這一次沒有的：恢復已安裝版。
    final now = {for (final scanned in scan.plugins) scanned.id};
    for (final id in previous) {
      if (!now.contains(id)) await registry.restoreInstalled(id);
    }
    // 5. 載入新資料夾的每個插件。
    final plugins = <DevPlugin>[];
    for (final scanned in scan.plugins) {
      plugins.add(await _load(scanned, replaced[scanned.id], redact));
      if (!ref.mounted) return;
    }
    if (folder == null) {
      state = null;
      return;
    }
    state = DevFolderState(
      folder: folder,
      plugins: plugins,
      problems: scan.problems,
    );
  }

  /// 為 [scanned] 補標記列（或更新）；回傳被取代的已安裝版本，沒有已安裝的列是 `null`。
  Future<String?> _putRow(
    PluginRepository repository,
    ScannedPlugin scanned,
  ) async {
    final file = scanned.file!;
    final isMarked = await repository.putDevFolderRow(
      InstalledPlugin(
        id: scanned.id,
        version: file.manifest.version,
        manifestJson: file.manifestJson,
        script: file.source,
        installedAt: DateTime.now().toUtc(),
      ),
    );
    return isMarked ? null : (await repository.byId(scanned.id))?.version;
  }

  /// 載入 [scanned] 並加進清單；失敗就不在清單上（不退回已安裝版）。
  Future<DevPlugin> _load(
    ScannedPlugin scanned,
    String? replacedVersion,
    String Function(String) redact,
  ) async {
    final file = scanned.file;
    final log = ref.read(logProvider);
    DevPlugin result(DevLoad load, {String? problem}) => DevPlugin(
      id: scanned.id,
      directory: scanned.directory,
      load: load,
      problem: problem == null ? null : redact(problem),
      manifest: load == DevLoad.loaded ? file?.manifest : null,
      replacedVersion: replacedVersion,
      cases: scanned.cases,
    );
    final registry = ref.read(pluginRegistryProvider.notifier);
    if (file == null) {
      // 讀不出安裝檔：id 只能用目錄名。它在開發中（插件頁鎖住），所以同名的已安裝版
      // 一樣不留在清單上，與載入失敗相同（不必等下一次重新掃描才卸下）。
      await registry.unregister(scanned.id);
      log.warning(
        'Failed to read a development plugin directory',
        tag: 'plugins',
        fields: {
          'directory': p.basename(scanned.directory.path),
          'problem': redact(scanned.problem ?? 'unreadable'),
        },
      );
      return result(DevLoad.failed, problem: scanned.problem);
    }
    try {
      final loaded = await ref.read(scriptPluginLoaderProvider).load(file);
      if (!ref.mounted) {
        loaded.close();
        return result(DevLoad.loaded);
      }
      await registry.register(loaded);
      return result(DevLoad.loaded, problem: scanned.problem);
    } on AppError catch (error) {
      await registry.unregister(scanned.id);
      final description = describeError(
        error,
        log,
        tag: 'plugins',
        message: 'Failed to load a development plugin',
      );
      return result(DevLoad.failed, problem: description);
    }
  }

  Future<void> _reload(String pluginId) async {
    final current = state;
    final existing = current?.plugins
        .where((plugin) => plugin.id == pluginId)
        .firstOrNull;
    if (current == null || existing == null) return;
    await ref.read(pluginRegistryProvider.future);
    if (!ref.mounted) return;
    state = current.copyWith(busy: true);
    final registry = ref.read(pluginRegistryProvider.notifier);
    final redact = ref.read(redactorProvider).redact;
    final scanned = await _scanOne(existing.directory);
    if (!ref.mounted) return;
    final DevPlugin result;
    final file = scanned.file;
    if (file != null && scanned.id != pluginId) {
      await registry.unregister(pluginId);
      ref
          .read(logProvider)
          .warning(
            'A development plugin changed its id',
            tag: 'plugins',
            fields: {'pluginId': pluginId, 'newId': scanned.id},
          );
      // 載入失敗：沒有開發版的 manifest（插件頁顯示列上的）。
      result = DevPlugin(
        id: pluginId,
        directory: existing.directory,
        load: DevLoad.failed,
        replacedVersion: existing.replacedVersion,
        cases: existing.cases,
        changedId: scanned.id,
      );
    } else if (file == null) {
      // 讀不出安裝檔時 scanned.id 是目錄名：卡片與清單仍以原本的 id 為準。
      result = await _load(
        ScannedPlugin(
          id: pluginId,
          directory: scanned.directory,
          problem: scanned.problem,
        ),
        existing.replacedVersion,
        redact,
      );
    } else {
      final replaced = await _putRow(
        ref.read(pluginRepositoryProvider),
        scanned,
      );
      result = await _load(scanned, replaced, redact);
    }
    if (!ref.mounted) return;
    final latest = state ?? current;
    state = latest.copyWith(
      busy: false,
      plugins: [
        for (final plugin in latest.plugins)
          if (plugin.id == pluginId) result else plugin,
      ],
    );
  }
}
