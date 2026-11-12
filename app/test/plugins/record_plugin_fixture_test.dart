@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';

import '../support/fjs.dart';
import '../support/plugin_fixtures.dart';

/// 錄製一個插件契約測試的案例：打真實音源，遮蔽、裁掉插件用不到的欄位後
/// 寫進 fixture（plan §3）。
///
/// 一次只錄 `FMP_RECORD` 指定的一個案例（音源的匿名風控，brief 事實 F2）：
///
/// ```sh
/// FMP_RECORD=<插件 id>/<插件能力>/<案例> \
///   flutter test --run-skipped --tags live test/plugins/record_plugin_fixture_test.dart
/// ```
///
/// 案例檔 `plugins/<插件 id>/fixtures/<插件能力>/<案例>.json` 要先存在，至少
/// 有 `input`（新案例只寫 `{"input": {…}}`）；錄好會覆寫成完整的 fixture。
/// 回應內文只留插件會讀的欄位：清單在插件的 `fixtures/keep.json`，沒列就不
/// 錄。契約不過（例如被限流）時不寫檔。寫好後看一次 diff 再提交。
void main() {
  final target = Platform.environment['FMP_RECORD'];

  test('record the plugin fixture named by FMP_RECORD', () async {
    if (target == null) {
      markTestSkipped('set FMP_RECORD=<plugin>/<capability>/<case> to record');
      return;
    }
    final parts = target.split('/');
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) {
      fail('FMP_RECORD must be <plugin>/<capability>/<case>, got "$target"');
    }
    final [id, capabilityName, caseName] = parts;
    final plugin = pluginDirectories(Directory('plugins'))
        .where((p) => p.id == id)
        .firstOrNull;
    if (plugin == null) fail('no plugin "$id" under plugins/');
    final capability = plugin.manifest.capabilities
        .where((c) => c.name == capabilityName)
        .firstOrNull;
    if (capability == null) {
      fail('plugin "$id" does not declare "$capabilityName"');
    }
    final keep = keptFields(plugin)[capability];
    if (keep == null) {
      fail(
        'list the response fields the plugin reads for "$capabilityName" '
        'in ${plugin.dir.path}/fixtures/keep.json',
      );
    }
    final file = File(
      '${plugin.dir.path}/fixtures/$capabilityName/$caseName.json',
    );
    final input = PluginFixture.parse(file.readAsStringSync()).input;

    await loadFjsForTests();
    final logDir = Directory.systemTemp.createTempSync('fmp_record_');
    final log = await Log.open(logDir, minimumLevel: LogLevel.debug);
    addTearDown(() async {
      await log.close();
      logDir.deleteSync(recursive: true);
    });

    final recording = liveRecording();
    final problems = await runContract(
      plugin.bundle,
      capability,
      input,
      log: log,
      httpAdapter: recording,
    );
    expect(problems, isEmpty, reason: 'nothing written to ${file.path}');

    final today = DateTime.now().toIso8601String().substring(0, 10);
    final source = PluginFixture(
      input: input,
      recorded: today,
      interactions: recording.recorded,
    ).trimmed(keep).encode();
    expect(unredactedValues(source), isEmpty);
    file.writeAsStringSync(source);
    // ignore: avoid_print -- 錄製是手動執行，印出寫了什麼給人看。
    print(
      'recorded ${recording.recorded.length} request(s) into ${file.path}:\n'
      '${recording.summary}',
    );
  });
}
