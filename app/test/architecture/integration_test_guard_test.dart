import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/full_gate.dart';
import 'integration_test_guard.dart';

/// plan〈測試策略〉 的零聯網也涵蓋 integration_test：`flutter_test_config.dart` 只套用
/// 在 `test/` 底下，所以 `integration_test/` 的每個測試檔都要在 `main()` 裡
/// 自己呼叫 `installNoNetworkGuard()`。
///
/// 變異驗證兩個方向都要有：拿掉防線要紅；改無關的格式、命名或註解不能紅。
void main() {
  test('every integration test installs the no-network guard', () {
    final app = Directory.current;
    final files = integrationTestFiles(app);
    expect(files, isNotEmpty);

    final missing = filesMissingNoNetworkGuard({
      for (final path in files)
        path: File('${app.path}/$path').readAsStringSync(),
    });
    expect(missing, isEmpty, reason: 'call installNoNetworkGuard() in main()');
  });

  const guarded = '''
import 'package:integration_test/integration_test.dart';
import '../test/support/no_network.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard();
  testWidgets('starts', (tester) async {});
}
''';

  List<String> check(String source) =>
      filesMissingNoNetworkGuard({'integration_test/a_test.dart': source});

  group('turns red on', () {
    test('a file that never installs the guard', () {
      expect(check(guarded.replaceAll('  installNoNetworkGuard();\n', '')), [
        'integration_test/a_test.dart',
      ]);
    });

    test('the call commented out', () {
      expect(
        check(
          guarded.replaceAll(
            'installNoNetworkGuard();',
            '// installNoNetworkGuard();',
          ),
        ),
        isNotEmpty,
      );
    });

    test('the call outside main()', () {
      final source = guarded.replaceAll('  installNoNetworkGuard();\n', '');
      expect(check('$source\nvoid helper() => installNoNetworkGuard();\n'), [
        'integration_test/a_test.dart',
      ]);
    });

    test('a different function with a similar name', () {
      expect(
        check(
          guarded.replaceAll(
            'installNoNetworkGuard();',
            'installNoNetworkGuardLater();',
          ),
        ),
        isNotEmpty,
      );
    });
  });

  group('stays green on', () {
    test('the guarded file', () {
      expect(check(guarded), isEmpty);
    });

    test('different formatting, names and comments', () {
      const source = '''
// 搜尋到播放的主要流程。
import '../test/support/no_network.dart';
import 'package:integration_test/integration_test.dart';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding
      .ensureInitialized();
  installNoNetworkGuard( );   // 放在 binding 之後
  group('search', () { testWidgets('plays one track', (t) async {}); });
}
''';
      expect(check(source), isEmpty);
    });

    test('the guard installed from setUpAll inside main()', () {
      expect(
        check(
          guarded.replaceAll(
            '  installNoNetworkGuard();\n',
            '  setUpAll(() => installNoNetworkGuard());\n',
          ),
        ),
        isEmpty,
      );
    });
  });
}
