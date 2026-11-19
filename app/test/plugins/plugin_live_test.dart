@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/plugins/plugins.dart';

import '../support/fjs.dart';
import '../support/plugin_fixtures.dart';

/// 聯網冒煙測試（architecture〈測試策略〉）：每個插件的每個插件能力打一次真實音源，用它第一
/// 個案例的 `input`，檢查和契約測試同一套契約。預設跳過，手動執行：
///
/// ```sh
/// flutter test --run-skipped --tags live test/plugins/plugin_live_test.dart
/// ```
///
/// 加 `--plain-name <插件 id>` 只跑一個插件。匿名請求，每條只打一次
/// （brief 事實 F2）。
void main() {
  late Directory logDir;
  late Log log;

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_live_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
  });
  tearDown(() async {
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  for (final plugin in pluginDirectories(Directory('plugins'))) {
    for (final MapEntry(key: capability, value: files) in fixtureFiles(
      plugin,
    ).entries) {
      if (files.isEmpty) continue;
      test('${plugin.id} ${capability.name} against the real source', () async {
        final first = PluginFixture.parse(files.first.readAsStringSync());
        final input = first.input;
        final recording = liveRecording();
        final problems = await runContract(
          plugin.bundle,
          capability,
          input,
          log: log,
          httpAdapter: recording,
          expect: first.expect,
        );
        // ignore: avoid_print -- 手動執行，印出打了什麼（已遮蔽）給人看。
        print(
          '${plugin.id} ${capability.name} $input:\n'
          '${recording.summary}',
        );
        expect(problems, isEmpty);
      });
    }
    if (plugin.manifest.searchSorts.isEmpty) continue;
    // 宣告了排序的插件：用第一個不是預設排序的 search 案例再打一次，確認
    // 真實音源接受非預設的排序。
    final sorted =
        [
          for (final file
              in fixtureFiles(plugin)[PluginCapability.search] ?? [])
            PluginFixture.parse(file.readAsStringSync()),
        ].where(
          (f) =>
              f.input['sort'] != null &&
              f.input['sort'] != plugin.manifest.searchSorts.first.name,
        );
    if (sorted.isEmpty) continue;
    test('${plugin.id} search with a non-default sort against the real '
        'source', () async {
      final fixture = sorted.first;
      final recording = liveRecording();
      final problems = await runContract(
        plugin.bundle,
        PluginCapability.search,
        fixture.input,
        log: log,
        httpAdapter: recording,
        expect: fixture.expect,
      );
      // ignore: avoid_print -- 手動執行，印出打了什麼（已遮蔽）給人看。
      print(
        '${plugin.id} search ${fixture.input}:\n'
        '${recording.summary}',
      );
      expect(problems, isEmpty);
    });
  }
}
