import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/plugins/accounts/credential_store.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/repository/plugin_downloader.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/plugins/plugins_page.dart';
import 'package:material_ui/material_ui.dart';

import '../../plugins/plugin_harness.dart';
import '../../support/fake_login_webview.dart';
import 'shell_harness.dart';

/// 一個插件的安裝檔：每個能力匯出一個同名函式（內容不重要，插件頁不呼叫它們）。
/// [login] 是 manifest 的 `login`：給了就加上 `login` 能力與它要的匯出。
String pluginScript(
  String id, {
  String name = '',
  String version = '1.0.0',
  List<String> capabilities = const ['search'],
  List<String> hosts = const ['example.test'],
  String description = '',
  Map<String, Object?>? login,
}) {
  final manifest = jsonEncode({
    'id': id,
    'name': name.isEmpty ? 'Plugin $id' : name,
    'version': version,
    'author': 'FMP tests',
    'apiVersion': 1,
    'capabilities': [...capabilities, if (login != null) 'login'],
    'allowedHosts': hosts,
    if (description.isNotEmpty) 'description': description,
    'login': ?login,
  });
  final header = '/* ==FMP Plugin==\n$manifest\n==/FMP Plugin== */\n';
  final exports = PluginFile.parse(header).manifest.requiredExports;
  return '$header'
      '${[for (final e in exports) 'export function $e() { return null; }'].join('\n')}\n';
}

/// 假的檔案對話框：回傳 [file]（`null` 是取消），記下問過的副檔名。
final class FakeFileDialogs implements FileDialogs {
  FakeFileDialogs([this.file]);

  PickedFile? file;
  final extensions = <String>[];

  @override
  Future<PickedFile?> pickFile({required String extension}) async {
    extensions.add(extension);
    return file;
  }
}

/// 一個沒有回應的插件（看門狗判定之後的樣子）：插件頁只讀它的 manifest 與 health。
final class UnresponsivePlugin implements SourcePlugin {
  UnresponsivePlugin(String source)
    : manifest = PluginFile.parse(source).manifest;

  @override
  final PluginManifest manifest;

  @override
  PluginHealth get health => PluginHealth.unresponsive;

  @override
  Future<void> get whenUnresponsive async {}

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 插件頁的測試環境：外殼的 [ShellHarness]，加上和它共用資料庫的真插件載入器
/// （[PluginHarness]，QuickJS）、查表的假下載（[remote]，沒列出的網址是
/// `NetworkError`，不聯網）與假的檔案對話框。快取庫開不起來：移除插件時略過快取那一步
/// （那一步由 `plugin_installer_test.dart` 守）。
final class PluginPageHarness {
  PluginPageHarness._({
    this.dialogs,
    this.loginWebView,
    bool registrySources = false,
    bool secureStorage = true,
    List<Override> overrides = const [],
  }) {
    shell = ShellHarness(
      database: plugins.database,
      fileDialogs: dialogs,
      loginWebView: loginWebView,
      cacheUnavailable: true,
      registrySources: registrySources,
      secureStorage: secureStorage,
      extraOverrides: [
        ...overrides,
        redactorProvider.overrideWithValue(plugins.redactor),
        credentialStoreProvider.overrideWithValue(plugins.credentials),
        sourceHttpClientFactoryProvider.overrideWithValue(plugins.httpClients),
        mediaHttpClientFactoryProvider.overrideWithValue(
          plugins.mediaHttpClients,
        ),
        scriptPluginLoaderProvider.overrideWithValue(plugins.loader),
        pluginDownloaderProvider.overrideWithValue(
          PluginDownloader(fetch: _fetch, log: plugins.log),
        ),
      ],
    );
  }

  /// 建好環境，並在 `testWidgets` 的假時間 zone 裡把憑證的載入跑完。
  ///
  /// [CredentialStore] 一建立就在當下的 zone 讀資料庫（[CredentialStore.ready]）。
  /// 那是假時間 zone，它的 microtask 只在 `pump` 時執行；若測試先進 `runAsync` 寫資料庫，
  /// 載入的查詢排在 drift 的鎖後面、輪到它時卻等不到 `pump`，後面的寫入就永遠等不到鎖。
  /// 所以先 `pump` 一次讓它跑完（記憶體資料庫只需要 microtask）。
  ///
  /// [secureStorage] 是平台宣告（帳號頁的登入按鈕看它）；憑證一律存在 [PluginHarness]
  /// 的記憶體 secure storage。[loginWebView] 給了平台就宣告網頁登入。[overrides] 加在外殼
  /// 的 override 之後。
  static Future<PluginPageHarness> create(
    WidgetTester tester, {
    FakeFileDialogs? dialogs,
    FakeLoginWebView? loginWebView,
    bool registrySources = false,
    bool secureStorage = true,
    List<Override> overrides = const [],
  }) async {
    final harness = PluginPageHarness._(
      dialogs: dialogs,
      loginWebView: loginWebView,
      registrySources: registrySources,
      secureStorage: secureStorage,
      overrides: overrides,
    );
    var loaded = false;
    unawaited(harness.plugins.credentials.ready.then((_) => loaded = true));
    await tester.pump();
    if (!loaded) {
      throw StateError('The credential store did not finish loading');
    }
    return harness;
  }

  final plugins = PluginHarness();
  final FakeFileDialogs? dialogs;
  final FakeLoginWebView? loginWebView;
  late final ShellHarness shell;

  /// 網址 → 內容。
  final remote = <String, String>{};

  /// 依序被要過的網址。
  final fetched = <String>[];

  Future<Uint8List> _fetch(Uri url, {required int maxBytes}) async {
    fetched.add(url.toString());
    final body = remote[url.toString()];
    if (body == null) throw NetworkError();
    return Uint8List.fromList(utf8.encode(body));
  }

  /// 已安裝 [source]（直接寫進資料庫；開頁時由插件清單載入）。
  Future<void> install(
    String source, {
    String? indexUrl,
    bool enabled = true,
  }) async {
    final file = PluginFile.parse(source);
    await plugins.plugins.install(
      InstalledPlugin(
        id: file.manifest.id,
        version: file.manifest.version,
        manifestJson: file.manifestJson,
        script: file.source,
        installedAt: DateTime.utc(2026, 10, 9),
        sourceIndexUrl: indexUrl,
      ),
    );
    if (!enabled) {
      await plugins.plugins.setEnabled(file.manifest.id, enabled: false);
    }
  }

  /// 加一個自訂插件庫。
  Future<void> addIndex(String url) =>
      PluginIndexRepository(plugins.database)
          .add(url, DateTime.utc(2026, 10, 9));

  /// 在 [url] 放一份 index，列出 [sources]（每個的 `.js` 放在 index 旁邊、SHA-256 照
  /// 內容算）。[apiVersions] 改掉某個 id 在 index 裡寫的 `apiVersion`；
  /// [entryOverrides] 改掉某個 id 那一筆的任意欄位（index 與 `.js` 說法不一的情況）。
  void publish(
    List<String> sources, {
    String url = officialPluginIndexUrl,
    Map<String, int> apiVersions = const {},
    Map<String, String> sha256Overrides = const {},
    Map<String, Map<String, Object?>> entryOverrides = const {},
  }) {
    final entries = <Map<String, Object?>>[];
    for (final source in sources) {
      final manifest = PluginFile.parse(source).manifest;
      final fileUrl = url.replaceFirst(
        RegExp(r'[^/]*$'),
        '${manifest.id}-${manifest.version}.js',
      );
      remote[fileUrl] = source;
      entries.add({
        'id': manifest.id,
        'name': manifest.name,
        'author': manifest.author,
        'description': manifest.description,
        'version': manifest.version,
        'apiVersion': apiVersions[manifest.id] ?? 1,
        'capabilities': [for (final c in manifest.capabilities) c.wireName],
        'allowedHosts': manifest.allowedHosts,
        'url': fileUrl,
        'sha256':
            sha256Overrides[manifest.id] ??
            sha256.convert(utf8.encode(source)).toString(),
        ...?entryOverrides[manifest.id],
      });
    }
    remote[url] = jsonEncode({'indexVersion': 1, 'plugins': entries});
  }

  ProviderContainer container(WidgetTester tester) => shell.container(tester);

  /// 以 [size] 的視窗開插件頁，等插件清單、資料庫與 index 都讀好。
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
    Brightness brightness = Brightness.light,
  }) async {
    await shell.pumpApp(
      tester,
      const PluginsPage(),
      size: size,
      brightness: brightness,
    );
    await settle(tester);
  }

  /// 讓資料庫、插件的背景 isolate 與假下載跑完（要真的事件迴圈），再畫一次。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  /// 已安裝的插件（資料庫）。
  Future<List<InstalledPlugin>> stored(WidgetTester tester) async =>
      (await tester.runAsync(() => plugins.plugins.list()))!;

  /// 插件清單上的 id。
  Set<String> registered(WidgetTester tester) => {
    ...?container(tester).read(pluginRegistryProvider).value?.keys,
  };
}
