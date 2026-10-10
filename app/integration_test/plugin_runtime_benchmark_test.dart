import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/repositories/plugin_storage_repository.dart';
import 'package:fmp/plugins/accounts/account_guard.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/script_source_plugin.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/credentials.dart';

// flutter_js 的實機量測（M1 phase2-plan §7；PRD 9a 第 8 項）。每個插件在自己的
// 背景 isolate，所以「建立 runtime」含 isolate 的 spawn。只量，不斷言；
// 結果以 `FMP_BENCH` 開頭的行印出。測試插件是 dev flavor 的 asset，所以要帶
// `--flavor dev`（預設就是 dev）：
//
//   flutter test integration_test/plugin_runtime_benchmark_test.dart -d emulator-5554
//   flutter test integration_test/plugin_runtime_benchmark_test.dart -d windows
//
// 用 profile 以外的模式量到的是 debug（JIT）數字，Dart 端的部分偏慢；QuickJS
// 本身是原生碼，不受影響。
//
// 另量一個外部插件（例如 fmp-plugins 的 youtube.js）的載入時間：加
// `--dart-define=FMP_BENCH_PLUGIN=<插件檔的路徑>`。只載入、不呼叫，不連網。
// Android 的 `flutter test` 會重裝 App、清掉私有目錄，所以檔案不在時最多等 60 秒，
// 讓呼叫的人在安裝後以 `run-as` 把檔案複製進 App 的私有目錄（verify-on-device）。

const _testPluginAsset = 'test/fixtures/plugins/test_plugin/test_plugin.js';
const _externalPluginPath = String.fromEnvironment('FMP_BENCH_PLUGIN');

/// 一個不做事的插件：只量 runtime、宿主 API 與 module 載入的固定成本。
const _emptyPlugin = '''
/* ==FMP Plugin==
{"id": "fmp-empty", "name": "Empty", "version": "1", "author": "FMP",
 "apiVersion": 1, "capabilities": ["search"], "allowedHosts": []}
==/FMP Plugin== */
export function search() { return { items: [], hasMore: false }; }
''';

/// search 裡連續 20 次宿主非同步呼叫（主 isolate 回覆的 `credentials.get`），
/// 量跨 isolate 的來回。
const _hostCallPlugin = '''
/* ==FMP Plugin==
{"id": "fmp-host-calls", "name": "Host calls", "version": "1", "author": "FMP",
 "apiVersion": 1, "capabilities": ["search"], "allowedHosts": []}
==/FMP Plugin== */
export async function search() {
  for (let i = 0; i < 20; i++) await fmp.credentials.get();
  return { items: [], hasMore: false };
}
''';

void _report(String name, Object value) =>
    debugPrint('FMP_BENCH $name: $value');

double _ms(Duration d) => d.inMicroseconds / 1000;

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

double _mb(int bytes) => bytes / (1024 * 1024);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plugin runtime cost', (tester) async {
    final redactor = Redactor();
    final log = Log(redactor: redactor, minimumLevel: LogLevel.info);
    final database = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(database.close);
    final credentials = credentialStoreFor(
      database,
      redactor: redactor,
      log: log,
    );
    final loader = ScriptPluginLoader(
      log: log,
      redactor: redactor,
      httpClients: SourceHttpClientFactory(log: log, credentials: credentials),
      storage: PluginStorageRepository(database),
      credentials: credentials,
      guard: AccountGuard(credentials: credentials, log: log),
    );
    final testPlugin = PluginFile.parse(
      await rootBundle.loadString(_testPluginAsset),
    );
    final emptyPlugin = PluginFile.parse(_emptyPlugin);
    final opened = <ScriptSourcePlugin>[];
    addTearDown(() {
      for (final plugin in opened) {
        plugin.close();
      }
    });

    Future<(ScriptSourcePlugin, double)> timedLoad(PluginFile file) async {
      final watch = Stopwatch()..start();
      final plugin = await loader.load(file);
      return (plugin, _ms(watch.elapsed));
    }

    _report('platform', Platform.operatingSystemVersion);
    _report(
      'mode',
      kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    );

    // 第一次含載入原生庫（dlopen）與 Dart 端的第一次編譯。
    final (coldEmpty, coldEmptyMs) = await timedLoad(emptyPlugin);
    coldEmpty.close();
    _report('create runtime (first, empty plugin) ms', coldEmptyMs);

    final emptyTimes = <double>[];
    for (var i = 0; i < 9; i++) {
      final (plugin, ms) = await timedLoad(emptyPlugin);
      plugin.close();
      emptyTimes.add(ms);
    }
    _report(
      'create runtime (empty plugin, median of 9) ms',
      _median(emptyTimes),
    );

    final testTimes = <double>[];
    for (var i = 0; i < 9; i++) {
      final (plugin, ms) = await timedLoad(testPlugin);
      plugin.close();
      testTimes.add(ms);
    }
    _report('load test plugin (median of 9) ms', _median(testTimes));

    if (_externalPluginPath.isNotEmpty) {
      final file = File(_externalPluginPath);
      for (var i = 0; i < 60 && !file.existsSync(); i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final external = PluginFile.parse(await file.readAsString());
      final externalTimes = <double>[];
      for (var i = 0; i < 9; i++) {
        final (plugin, ms) = await timedLoad(external);
        plugin.close();
        externalTimes.add(ms);
      }
      _report(
        'load ${external.manifest.id} plugin (median of 9) ms',
        _median(externalTimes),
      );
    }

    final (plugin, _) = await timedLoad(testPlugin);
    opened.add(plugin);
    final query = SearchQuery(keyword: 'bench');
    final firstSearch = Stopwatch()..start();
    await plugin.search(query);
    _report('search round trip (first) ms', _ms(firstSearch.elapsed));
    final searchTimes = <double>[];
    for (var i = 0; i < 21; i++) {
      final watch = Stopwatch()..start();
      await plugin.search(query);
      searchTimes.add(_ms(watch.elapsed));
    }
    _report('search round trip (median of 21) ms', _median(searchTimes));
    plugin.close();
    opened.remove(plugin);

    // 拆開上面的往返：沒有宿主呼叫的 search，與 search 裡那一次 storage 讀取。
    final (empty, _) = await timedLoad(emptyPlugin);
    opened.add(empty);
    final emptySearchTimes = <double>[];
    for (var i = 0; i < 21; i++) {
      final watch = Stopwatch()..start();
      await empty.search(query);
      emptySearchTimes.add(_ms(watch.elapsed));
    }
    _report(
      'search round trip without host calls (median of 21) ms',
      _median(emptySearchTimes),
    );
    final (hostCalls, _) = await timedLoad(PluginFile.parse(_hostCallPlugin));
    opened.add(hostCalls);
    final hostCallTimes = <double>[];
    for (var i = 0; i < 21; i++) {
      final watch = Stopwatch()..start();
      await hostCalls.search(query);
      hostCallTimes.add(_ms(watch.elapsed));
    }
    _report(
      'host call round trip across isolates (median of 21, per call) ms',
      ((_median(hostCallTimes) - _median(emptySearchTimes)) / 20)
          .toStringAsFixed(3),
    );
    hostCalls.close();
    opened.remove(hostCalls);
    // 對照：不經 QuickJS 的純 Dart isolate 來回，看上一列有多少是訊息本身。
    final echoes = ReceivePort();
    final replies = StreamIterator<Object?>(echoes);
    await Isolate.spawn(_echo, echoes.sendPort);
    await replies.moveNext();
    final echoPort = replies.current! as SendPort;
    final echoTimes = <double>[];
    for (var i = 0; i < 21; i++) {
      final watch = Stopwatch()..start();
      echoPort.send(i);
      await replies.moveNext();
      echoTimes.add(_ms(watch.elapsed));
    }
    echoPort.send(null);
    await replies.cancel();
    _report(
      'plain Dart isolate round trip (median of 21) ms',
      _median(echoTimes).toStringAsFixed(3),
    );
    final storage = PluginStorageRepository(database);
    final readTimes = <double>[];
    for (var i = 0; i < 21; i++) {
      final watch = Stopwatch()..start();
      await storage.read('fmp-test', 'titlePrefix');
      readTimes.add(_ms(watch.elapsed));
    }
    _report('storage read in Dart (median of 21) ms', _median(readTimes));
    empty.close();
    opened.remove(empty);

    // RSS：先讓前面的 runtime 釋放、事件佇列跑完，再量基準。
    await tester.pump(const Duration(milliseconds: 500));
    final baseline = ProcessInfo.currentRss;
    _report('rss baseline MB', _mb(baseline).toStringAsFixed(1));
    for (var count = 1; count <= 3; count++) {
      final (loaded, _) = await timedLoad(testPlugin);
      await loaded.search(query);
      opened.add(loaded);
      await tester.pump(const Duration(milliseconds: 200));
      if (count == 1 || count == 3) {
        _report(
          'rss delta with $count runtime(s) MB',
          _mb(ProcessInfo.currentRss - baseline).toStringAsFixed(1),
        );
      }
    }
  });
}

/// 對照組的背景 isolate：收到什麼回什麼，收到 `null` 就結束。
void _echo(SendPort toMain) {
  final commands = ReceivePort();
  toMain.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      commands.close();
    } else {
      toMain.send(message);
    }
  });
}
