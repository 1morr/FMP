import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 唯一允許直接呼叫 `pumpEventQueue` 的地方。
///
/// `pump_until.dart` 是包裝它的那一層；它自己的測試要拿原始的固定圈數來當對照，
/// 證明「圈數不是同步點」；本檔的合成違規樣本存在字串常量裡，會被自己掃到。
const _allowedFiles = <String>[
  'test/support/pump_until.dart',
  'test/support/pump_until_test.dart',
  'test/support/wait_convention_static_rule_test.dart',
];

/// 找出直接呼叫 `pumpEventQueue` 的行。
///
/// 註解不算 —— 有幾份說明本來就在講這個 API 為什麼不可靠。
List<String> fixedPumpOffenders(String path, String source) {
  final offenders = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final code = lines[i].trim();
    if (code.startsWith('//')) continue;
    if (!code.contains('pumpEventQueue(')) continue;
    offenders.add('$path:${i + 1}: ${code.trim()}');
  }
  return offenders;
}

void main() {
  group('fixed pump counts', () {
    test('only pump_until.dart calls pumpEventQueue directly', () {
      final offenders = <String>[];
      var scanned = 0;

      for (final entity in Directory('test').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (_allowedFiles.contains(path)) continue;

        scanned++;
        offenders.addAll(fixedPumpOffenders(path, entity.readAsStringSync()));
      }

      // 掃描本身要有作用 —— 路徑寫錯時 offenders 也會是空的。
      expect(scanned, greaterThan(200));
      expect(
        offenders,
        isEmpty,
        reason:
            'A fixed pump count is not a synchronisation point (issue #43/#55). '
            'Use pumpUntil for a condition, or drainEventQueue when asserting '
            'that something did not happen. See test/support/pump_until.dart.',
      );
    });

    test('every allowlist entry still exists', () {
      for (final path in _allowedFiles) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path is allowlisted but no longer exists',
        );
      }
    });

    test('guard detects a fixed pump before an assertion', () {
      const source = '''
test('something', () async {
  controller.playTrack(track);
  await pumpEventQueue(times: 10);
  expect(toasts, isNotEmpty);
});
''';

      expect(fixedPumpOffenders('test/fake_test.dart', source), hasLength(1));
    });

    test('guard ignores comments that mention the api', () {
      const source = '''
/// 單次 `pumpEventQueue()` 只等得到第一筆寫入。
// await pumpEventQueue(times: 5);
await pumpUntil(() => done, reason: 'the write to land');
''';

      expect(fixedPumpOffenders('test/fake_test.dart', source), isEmpty);
    });
  });
}
