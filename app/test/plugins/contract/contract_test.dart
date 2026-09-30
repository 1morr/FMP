import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'contract_runner.dart';

// 插件契約執行器的入口（ADR 0015 §決定 6）：以重播跑插件目錄裡每條檢查案例。
//
// - 不設 `FMP_PLUGIN_DIR`：跑 `test/fixtures/plugins/` 底下的測試插件，裸
//   `flutter test` 就包含它（CI 的 `app` job）。
// - 設了：只跑它指的目錄（一個插件目錄，或底下的每個插件目錄）。插件庫的 CI
//   以固定的 FMP 版本這樣跑，指令見 app/AGENTS.md § 驗證。
void main() {
  final root =
      pluginDirectoryFromEnvironment() ?? Directory('test/fixtures/plugins');
  final directories = root.existsSync()
      ? pluginDirectories(root)
      : const <Directory>[];

  test('finds plugin directories', () {
    expect(directories, isNotEmpty, reason: noPluginDirectories(root));
  });

  for (final directory in directories) {
    final plugin = PluginDirectory.read(directory);
    group(plugin.label, () {
      test('install file, checks.json and fixtures', () async {
        expect(await checkPluginDirectory(plugin), isEmpty);
      });
      for (final check in plugin.checks) {
        test(check.capability.wireName, () async {
          expect(await runCheck(plugin, check), isEmpty);
        });
      }
    });
  }
}
