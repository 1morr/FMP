import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/database/open_app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/login_webview/login_webview.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/platform/secure_storage/secure_storage.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/plugins/install/dev_plugin_entry.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/flutter_test_config.dart' show NoNetworkHttpOverrides;
import '../test/playback/fake_audio_backend.dart';
import '../test/support/credentials.dart';

// ADR 0015 §決定 1 挑出的兩個整合情境：從檔案安裝插件、搜尋→播放。App 從
// `FmpApp` 開始，插件執行環境（QuickJS 背景 isolate）、安裝、資料目錄裡的
// SQLite 都是真的；只有播放後端換成假的：CI 的 runner 沒有音訊裝置，Linux 也
// 還沒有後端（真後端由 audio_backend_contract_test.dart 在實機守）。測試插件
// 是 dev flavor 的 asset，所以要帶 `--flavor dev`（預設就是 dev）：
//
//   flutter test integration_test/install_search_play_test.dart -d windows
//   xvfb-run -a flutter test integration_test/install_search_play_test.dart -d linux
//
// CI 的 Linux 與 Windows 整合測試 job 跑這個檔案。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 零聯網照開（ADR 0015 §決定 3）。flutter_test_config.dart 只套用在 test/
  // 底下，這裡自己設；測試插件不發請求，建立 HttpClient 就代表出錯。
  HttpOverrides.global = NoNetworkHttpOverrides();

  testWidgets(
    'a plugin installed from its file loads again from the database',
    (tester) async {
      final root = await _tempRoot();
      final pluginFile = await _writeTestPlugin(root);
      final data = Directory('${root.path}/data')..createSync();

      // 開發入口（dev）照 App 的路徑安裝：讀檔 → PluginInstaller → 資料庫 → 清單。
      var app = await _AppRun.launch(tester, data, devPlugin: pluginFile.path);
      await _waitFor(tester, () => app.plugins.contains(_pluginId), 'install');
      final stored = await app.container.read(pluginRepositoryProvider).list();
      expect(stored.map((plugin) => plugin.id), [_pluginId]);
      await app.close(tester);

      // 重新啟動、不帶開發入口：插件只能從資料庫載入。
      app = await _AppRun.launch(tester, data);
      await _waitFor(tester, () => app.plugins.contains(_pluginId), 'reload');
      await _search(tester, 'again');
      expect(find.text('Test tone 220 Hz (again)'), findsOneWidget);
      expect(find.text('Test tone 440 Hz (again)'), findsOneWidget);
      await app.close(tester);
    },
  );

  testWidgets('a search result plays on its own; queued results hand over', (
    tester,
  ) async {
    final root = await _tempRoot();
    final pluginFile = await _writeTestPlugin(root);
    final data = Directory('${root.path}/data')..createSync();
    final app = await _AppRun.launch(tester, data, devPlugin: pluginFile.path);
    await _waitFor(tester, () => app.plugins.contains(_pluginId), 'install');

    await _search(tester, 'tone');
    final controller = app.container.read(playbackControllerProvider);
    // 一首只播 1 秒，交接時狀態一直是 Playing、只有佇列往下：輪詢當下的值，
    // 慢一點的 runner 可能整首錯過。改記下每次變動時在播的是哪一首。
    final played = <String?>{};
    var state = controller.state;
    var queue = controller.queue;
    void note() {
      if (state is Playing) {
        played.add(
          queue.mode == QueueMode.temporary
              ? 'temporary ${queue.current?.sourceId}'
              : '${queue.currentIndex}',
        );
      }
    }

    final subscriptions = [
      controller.states.listen((value) {
        state = value;
        note();
      }),
      controller.queueStates.listen((value) {
        queue = value;
        note();
      }),
    ];
    addTearDown(() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });

    // 點一首是臨時播放：不進佇列，播完回到（空的）佇列、停下。
    await tester.tap(find.text('Test tone 220 Hz (tone)'));
    await _waitFor(
      tester,
      () => played.contains('temporary tone-220'),
      'the tapped result plays',
    );
    expect(controller.queue.entries, isEmpty);
    await _waitFor(
      tester,
      () => controller.state is Idle && controller.queue.current == null,
      'the temporary play ends',
    );

    // 以選單把兩首加入佇列，再按播放列的播放：第二首由前瞻接上。介面字串跟著
    // 機器的語言，所以以圖示找選單。
    for (final title in [
      'Test tone 220 Hz (tone)',
      'Test tone 440 Hz (tone)',
    ]) {
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, title),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_to_queue));
      await tester.pump();
    }
    expect(controller.queue.entries.map((entry) => entry.track.sourceId), [
      'tone-220',
      'tone-440',
    ]);
    expect(controller.state, isA<Idle>());
    final opened = app.backend.opened.length;

    await tester.tap(find.byIcon(Icons.play_arrow));
    await _waitFor(tester, () => played.contains('0'), 'the first track plays');
    await _waitFor(
      tester,
      () => played.contains('1'),
      'the second track plays',
    );
    // 第二首是前瞻交給後端、由後端自己接上的，不是重新開流。
    expect(app.backend.opened, hasLength(opened + 1));
    expect(
      app.log.history.where(
        (record) => record.message == 'Look-ahead handover',
      ),
      hasLength(1),
    );
    await app.close(tester);
  });
}

const _pluginId = 'fmp-test';

/// 測試插件的安裝檔（dev flavor 的 asset）。
const _testPluginAsset = 'test/fixtures/plugins/test_plugin/test_plugin.js';

/// 播放能力的宣告。後端是假的，格式只需要涵蓋測試插件的 wav；不用平台的
/// 宣告，因為 Linux 還沒有（`PlatformCapabilities.none`）。
const _playback = PlaybackSupport(
  backend: AudioBackendKind.mediaKit,
  formats: [PlayableFormat('wav', 'pcm_s16le')],
  outputDeviceSelection: false,
);

Future<Directory> _tempRoot() async {
  final root = await Directory.systemTemp.createTemp('fmp_integration_');
  addTearDown(() => root.delete(recursive: true));
  return root;
}

/// 把測試插件寫成 [root] 裡的一個檔案，像使用者下載的安裝檔。
Future<File> _writeTestPlugin(Directory root) async {
  final bytes = await rootBundle.load(_testPluginAsset);
  return File('${root.path}/test_plugin.js').writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
}

/// 在搜尋頁輸入 [keyword] 送出，等第一筆結果出現。
Future<void> _search(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(TextField), keyword);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await _waitFor(
    tester,
    () => find.text('Test tone 220 Hz ($keyword)').evaluate().isNotEmpty,
    'results for "$keyword"',
  );
}

/// 以實際時間等 [condition] 成立：插件在背景 isolate、資料庫在 drift 的
/// isolate，要真的讓時間過去。畫面有轉圈時 `pumpAndSettle` 不會結束，所以
/// 逐格 pump。
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      fail('timed out after $timeout waiting for: $what');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// App 的一次啟動：[data] 當資料目錄，其他照 `main()` 注入。
final class _AppRun {
  _AppRun._(this.database, this.log, this.backend);

  static Future<_AppRun> launch(
    WidgetTester tester,
    Directory data, {
    String? devPlugin,
  }) async {
    final database = await openAppDatabase(data);
    final redactor = Redactor();
    final log = Log(redactor: redactor, minimumLevel: LogLevel.info);
    // 一首 1 秒：很快播到交接。
    final backend = FakeAudioBackend(
      durationOf: (_) => const Duration(seconds: 1),
    );
    final run = _AppRun._(database, log, backend);
    await tester.pumpWidget(
      appProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          dataDirectoryProvider.overrideWithValue(data),
          logProvider.overrideWithValue(log),
          redactorProvider.overrideWithValue(redactor),
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(
              dataDirectory: true,
              singleInstance: false,
              secureStorage: false,
              fontFallback: FontFallback.none,
              playback: _playback,
              networkInterfaces: false,
              files: false,
              loginWebView: false,
              cache: CacheSizes(
                defaultLimitMebibytes: 16,
                memoryImages: 50,
                memoryImageMebibytes: 16,
              ),
            ),
          ),
          // 快取目錄在資料目錄旁（測試插件沒有封面，快取庫不會被開）。
          cacheDirectoryProvider.overrideWithValue(
            CacheDirectory(
              applicationCachePath: () async => '${data.parent.path}/cache',
            ),
          ),
          // 插件的 HTTP client 經 CredentialStore 讀憑證：給一個空的記憶體
          // 存放（CI 的 runner 不一定有 keyring，這個測試也不登入）。
          secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
          loginWebViewProvider.overrideWithValue(null),
          // 網路狀態只看請求結果：這個測試不看系統的網路介面。
          networkInterfacesProvider.overrideWithValue(null),
          audioBackendProvider.overrideWith((ref) {
            ref.onDispose(() => unawaited(backend.dispose()));
            return backend;
          }),
          devPluginPathProvider.overrideWithValue(devPlugin),
        ],
        child: const FmpApp(flavor: AppFlavor.dev),
      ),
    );
    return run;
  }

  final AppDatabase database;
  final Log log;
  final FakeAudioBackend backend;

  ProviderContainer get container =>
      ProviderScope.containerOf(find.byType(FmpApp).evaluate().single);

  /// 清單上已載入的插件 id。
  Set<String> get plugins =>
      container.read(pluginRegistryProvider).value?.keys.toSet() ?? const {};

  /// 拆掉 App（插件的 isolate 隨 provider 關閉）再關資料庫；過程中不能有
  /// error 等級的 log。
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
    expect(
      log.history.where((record) => record.level == LogLevel.error),
      isEmpty,
    );
  }
}
