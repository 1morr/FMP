import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 實跑的指令 `tool/real_run.dart`（docs/development.md〈實跑驅動〉）。真的跑情境
/// 要裝置與音源，這裡只測不碰裝置就看得到的：不是實跑情境的檔不收。
void main() {
  test('refuses a file that is not a real-run scenario, before touching any '
      'device', () async {
    for (final file in [
      'integration_test/app_test.dart',
      'integration_test/real_run/driver.dart',
    ]) {
      final result = await Process.run('dart', [
        'tool/real_run.dart',
        '-d',
        'macos',
        file,
      ]);

      expect(result.exitCode, 64, reason: file);
      expect(result.stderr, contains('Not a real-run scenario: $file'));
      expect(result.stderr, isNot(contains('shared-device lock')));
    }
  });
}
