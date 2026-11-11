import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/log/log.dart';

import '../support/fjs.dart';
import '../support/plugin_fixtures.dart';

/// 插件契約測試（ADR 0038〈如何確認〉、plan §3）：`app/plugins/` 底下每個
/// 插件，對它宣告的每個插件能力，用 `fixtures/<插件能力>/` 裡錄好的每個案例
/// 重播音源的回應（零聯網），檢查回傳照宿主 API 的約定。新增插件或案例不用
/// 改這個檔；新增插件能力時 `checkContract` 的 switch 會編譯不過，提醒補它
/// 的契約。錄製與 `live` 冒煙測試的指令在 plan §3。
void main() {
  late Directory logDir;
  late Log log;

  setUpAll(loadFjsForTests);
  setUp(() async {
    logDir = Directory.systemTemp.createTempSync('fmp_contract_');
    log = await Log.open(logDir, minimumLevel: LogLevel.debug);
  });
  tearDown(() async {
    await log.close();
    logDir.deleteSync(recursive: true);
  });

  final plugins = pluginDirectories(Directory('plugins'));

  test('there are plugins to check', () => expect(plugins, isNotEmpty));

  for (final plugin in plugins) {
    group(plugin.id, () {
      test('every declared capability has fixtures', () {
        expect(fixtureProblems(plugin), isEmpty);
      });

      for (final MapEntry(key: capability, value: files) in fixtureFiles(
        plugin,
      ).entries) {
        for (final file in files) {
          final name = file.uri.pathSegments.last;
          test('${capability.name} keeps the contract: $name', () async {
            final fixture = PluginFixture.parse(file.readAsStringSync());
            expect(
              await runContractCase(
                plugin.bundle,
                capability,
                fixture,
                log: log,
              ),
              isEmpty,
              reason: 'replaying ${file.path}',
            );
          });

          test('${capability.name} fixture $name has no secrets', () {
            expect(unredactedValues(file.readAsStringSync()), isEmpty);
          });
        }
      }
    });
  }
}
