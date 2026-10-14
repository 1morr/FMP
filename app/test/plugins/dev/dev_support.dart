import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:path/path.dart' as p;

import '../plugin_harness.dart';

// 插件開發工具測試共用（M3 PR 16b）：資料夾的複本、平台宣告、容器。

/// `test/fixtures/plugins/` 底下的插件目錄（`fmp-test`、`fmp-test-http`）。
Directory fixturePlugin(String name) =>
    Directory('test/fixtures/plugins/$name');

/// 暫時的開發資料夾，測試結束時刪掉。
Directory tempFolder() {
  final directory = Directory.systemTemp.createTempSync('fmp-dev-folder');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}

/// 把 [source] 目錄複製成 [root] 底下的 [name]（遞迴）。
Directory copyPlugin(Directory source, Directory root, String name) {
  final target = Directory(p.join(root.path, name))
    ..createSync(recursive: true);
  for (final entry in source.listSync(recursive: true)) {
    final relative = p.relative(entry.path, from: source.path);
    if (entry is Directory) {
      Directory(p.join(target.path, relative)).createSync(recursive: true);
    } else if (entry is File) {
      entry.copySync(p.join(target.path, relative));
    }
  }
  return target;
}

/// 目錄裡唯一的安裝檔。
File scriptOf(Directory directory) => directory
    .listSync()
    .whereType<File>()
    .singleWhere((file) => file.path.endsWith('.js'));

/// 把安裝檔 manifest 的版本改成 [version]。
void setVersion(Directory directory, String version) {
  final file = scriptOf(directory);
  file.writeAsStringSync(
    file.readAsStringSync().replaceFirst(
      RegExp(r'"version": "[^"]*"'),
      '"version": "$version"',
    ),
  );
}

PlatformCapabilities capabilities({required bool pluginDevTools}) =>
    PlatformCapabilities(
      dataDirectory: true,
      singleInstance: false,
      fontFallback: FontFallback.none,
      playback: null,
      networkInterfaces: false,
      cache: null,
      secureStorage: false,
      files: true,
      loginWebView: false,
      urlOpener: false,
      restartsItself: false,
      shareFiles: false,
      pluginDevTools: pluginDevTools,
    );

/// 一個已安裝的列（不經安裝流程）：[source] 是整個安裝檔。
Future<void> storeInstalled(
  PluginHarness harness,
  String source, {
  String? version,
  bool enabled = true,
}) async {
  final file = PluginFile.parse(source);
  await harness.plugins.install(
    InstalledPlugin(
      id: file.manifest.id,
      version: version ?? file.manifest.version,
      manifestJson: file.manifestJson,
      script: source,
      installedAt: DateTime.utc(2026),
    ),
  );
  if (!enabled) {
    await harness.plugins.setEnabled(file.manifest.id, enabled: false);
  }
}

/// 開發資料夾測試的容器：資料庫、log、插件載入都用 [harness] 的；開發者設定在
/// [harness] 的資料庫裡（dev flavor：開發者模式預設開）。
ProviderContainer devContainer(
  PluginHarness harness, {
  bool pluginDevTools = true,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(harness.database),
      appFlavorProvider.overrideWithValue(AppFlavor.dev),
      platformCapabilitiesProvider.overrideWithValue(
        capabilities(pluginDevTools: pluginDevTools),
      ),
      logProvider.overrideWithValue(harness.log),
      redactorProvider.overrideWithValue(harness.redactor),
      sourceHttpClientFactoryProvider.overrideWithValue(harness.httpClients),
      mediaHttpClientFactoryProvider.overrideWithValue(
        harness.mediaHttpClients,
      ),
      scriptPluginLoaderProvider.overrideWithValue(harness.loader),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 設定資料夾（`null` 清掉）；開發者模式一併寫成開。
Future<void> selectFolder(PluginHarness harness, Directory? folder) async {
  final repository = DeveloperSettingsRepository(harness.database);
  await repository.write(developerMode: true);
  if (folder == null) {
    await repository.clear(pluginDevFolder: true);
  } else {
    await repository.write(pluginDevFolder: folder.path);
  }
}

/// 開發工具補的標記列（只能經 [PluginRepository.putDevFolderRow] 寫入）。
Future<void> storeMarked(PluginHarness harness, String source) async {
  final file = PluginFile.parse(source);
  await harness.plugins.putDevFolderRow(
    InstalledPlugin(
      id: file.manifest.id,
      version: file.manifest.version,
      manifestJson: file.manifestJson,
      script: source,
      installedAt: DateTime.utc(2026),
    ),
  );
}
