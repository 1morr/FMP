import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_plugin.dart';

import '../support/memory_database.dart';
import 'fake_import_plugin.dart';

/// 測試設定插件清單的 provider：改它就等於插件清單改變（啟用、停用、安裝、移除）。
final _testPlugins = NotifierProvider<_TestPlugins, Map<String, SourcePlugin>>(
  _TestPlugins.new,
);

final class _TestPlugins extends Notifier<Map<String, SourcePlugin>> {
  @override
  Map<String, SourcePlugin> build() => const {};

  void set(Map<String, SourcePlugin> plugins) => state = plugins;
}

/// 記憶體資料庫、假插件清單與真的匯入器、刷新器。
final class LibraryEnv {
  LibraryEnv._(
    List<SourcePlugin>? plugins,
    LogLevel minimumLevel,
    List<Override> overrides,
  ) {
    this.plugins = plugins ?? [FakeImportPlugin()];
    log = Log(redactor: Redactor(), minimumLevel: minimumLevel);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        logProvider.overrideWithValue(log),
        ...overrides,
        pluginRegistryProvider.overrideWithBuild(
          (ref, notifier) => ref.watch(_testPlugins),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  /// 建好並載入插件清單。
  static Future<LibraryEnv> open({
    List<SourcePlugin>? plugins,
    LogLevel minimumLevel = LogLevel.warning,
    List<Override> overrides = const [],
  }) async {
    final env = LibraryEnv._(plugins, minimumLevel, overrides);
    await env.setPlugins();
    return env;
  }

  final AppDatabase database = memoryDatabase();
  late final List<SourcePlugin> plugins;
  late final ProviderContainer container;
  late final Log log;

  FakeImportPlugin get plugin => plugins.whereType<FakeImportPlugin>().first;
  PlaylistRepository get repository =>
      container.read(playlistRepositoryProvider);
  PlaylistRefresher get refresher => container.read(playlistRefresherProvider);
  PlaylistImporter get importer => container.read(playlistImporterProvider);

  /// 插件清單變成 [plugins]（預設是全部），並等到註冊表讀得到新的清單。
  Future<void> setPlugins([Iterable<SourcePlugin>? plugins]) async {
    container.read(_testPlugins.notifier).set({
      for (final plugin in plugins ?? this.plugins) plugin.manifest.id: plugin,
    });
    await container.read(pluginRegistryProvider.future);
  }
}
