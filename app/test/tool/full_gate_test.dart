import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/full_gate.dart';
import '../../tool/src/steps.dart';

/// 完整版閘門（plan §4）的平台步驟。外部指令經 [Shell]，這裡換成假的：
/// 記下跑過的指令，依前綴決定結果與輸出。
void main() {
  final app = Directory('/repo/app');
  final out = StringBuffer();
  late _FakeShell shell;
  late Directory logs;

  setUp(() {
    out.clear();
    shell = _FakeShell();
    logs = Directory.systemTemp.createTempSync('fmp_gate_');
  });
  tearDown(() => logs.deleteSync(recursive: true));

  Future<int> runGate({
    List<String> tests = const ['integration_test/app_test.dart'],
  }) => runSteps(
    platformSteps(
      app: app,
      shell: shell,
      integrationTests: tests,
      out: out,
      winpcLogs: logs,
    ),
    out,
  );

  test('builds all four platforms, then runs integration tests on all four, '
      'one file per invocation', () async {
    final code = await runGate(
      tests: ['integration_test/a_test.dart', 'integration_test/b_test.dart'],
    );

    expect(code, 0);
    expect(shell.ran.where((c) => c.startsWith('flutter build')), [
      'flutter build macos --debug',
      'flutter build ios --simulator --debug',
      'flutter build apk --debug',
    ]);
    expect(shell.ran.where((c) => c.startsWith('flutter test')), [
      'flutter test integration_test/a_test.dart -d macos',
      'flutter test integration_test/b_test.dart -d macos',
      'flutter test integration_test/a_test.dart -d SIM-UDID --no-uninstall',
      'flutter test integration_test/b_test.dart -d SIM-UDID --no-uninstall',
      'flutter test integration_test/a_test.dart -d emulator-5554 --no-uninstall',
      'flutter test integration_test/b_test.dart -d emulator-5554 --no-uninstall',
    ]);
    expect(
      out.toString(),
      allOf(
        contains('ok   build macos'),
        contains('ok   build windows'),
        contains('ok   integration_test android: integration_test/b_test.dart'),
        contains('ok   integration_test windows: integration_test/a_test.dart'),
      ),
    );
    // 建置全部做完才開始跑 integration_test。
    final lastBuild = shell.ran.lastIndexWhere((c) => c.contains(' build '));
    final firstTest = shell.ran.indexWhere((c) => c.startsWith('flutter test'));
    expect(lastBuild, lessThan(firstTest));
  });

  test('a failing platform step exits non-zero and names the platform and '
      'the step', () async {
    shell.failing.add('flutter build ios');

    final code = await runGate();

    expect(code, isNot(0));
    expect(out.toString(), contains('FAIL build ios'));
    expect(out.toString(), contains('ok   build android'));
  });

  test('without a running iOS simulator the iOS integration test fails '
      'instead of picking the physical iPhone', () async {
    shell.outputs['flutter devices --machine'] = _devicesJson.replaceAll(
      '"emulator": true, "sdk": "iOS 27.1"',
      '"emulator": false, "sdk": "iOS 27.1"',
    );

    final code = await runGate();

    expect(code, isNot(0));
    expect(
      out.toString(),
      contains('FAIL integration_test ios: integration_test/app_test.dart'),
    );
    expect(shell.ran, isNot(contains(contains('REAL-IPHONE'))));
  });

  group('Windows', () {
    test('runs on winpc and keeps the fetched log on the Mac', () async {
      final code = await runGate();

      expect(code, 0);
      expect(
        shell.ran.indexOf('tool/winpc/sync.sh'),
        allOf(
          isNonNegative,
          lessThan(shell.ran.indexWhere((c) => c.contains('fmpbuild'))),
        ),
      );
      expect(
        shell.ran,
        containsAll([
          'tool/winpc/run_task.sh fmpbuild C:/fmp-wt/build.ps1 -Mode debug',
          'tool/winpc/run_task.sh fmptest C:/fmp-wt/test.ps1 '
              '-File integration_test/app_test.dart',
        ]),
      );
      expect(
        File('${logs.path}/build.log').readAsStringSync(),
        contains('exit build=0'),
      );
      expect(File('${logs.path}/test-app_test.log').existsSync(), isTrue);
    });

    test('a non-zero stage in the remote log fails the Windows step', () async {
      shell.outputs['ssh winpc Get-Content'] =
          'exit pubget=0\nexit build=1\n=== done\n';

      expect(await runGate(), isNot(0));
      expect(out.toString(), contains('FAIL build windows'));
    });

    test(
      'a remote log that never reached the end fails the Windows step',
      () async {
        shell.outputs['ssh winpc Get-Content'] = 'exit pubget=0\n';

        expect(await runGate(), isNot(0));
        expect(out.toString(), contains('FAIL build windows'));
      },
    );

    test('a failed sync fails the Windows build without running it', () async {
      shell.failing.add('tool/winpc/sync.sh');

      expect(await runGate(), isNot(0));
      expect(out.toString(), contains('FAIL build windows'));
      expect(
        shell.ran,
        isNot(contains(startsWith('tool/winpc/run_task.sh fmpbuild'))),
      );
    });
  });

  test('integration tests are the *_test.dart files under integration_test/, '
      'in a stable order', () {
    final root = Directory.systemTemp.createTempSync('fmp_app_');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final path in [
      'integration_test/search_test.dart',
      'integration_test/app_test.dart',
      'integration_test/support/robot.dart',
      'test/ui/page_test.dart',
    ]) {
      File('${root.path}/$path').createSync(recursive: true);
    }

    expect(integrationTestFiles(root), [
      'integration_test/app_test.dart',
      'integration_test/search_test.dart',
    ]);
  });
}

class _FakeShell implements Shell {
  final ran = <String>[];

  /// 指令以這些前綴開頭時回傳非零。
  final failing = <String>{};

  /// `capture` 的輸出，依前綴比對。
  final outputs = <String, String>{
    'flutter devices --machine': _devicesJson,
    'ssh winpc Get-Content': 'exit pubget=0\nexit build=0\n=== done\n',
  };

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    final command = [executable, ...arguments].join(' ');
    ran.add(command);
    return failing.any(command.startsWith) ? 1 : 0;
  }

  @override
  Future<String> capture(
    String executable,
    List<String> arguments, {
    required Directory workingDirectory,
  }) async {
    final command = [executable, ...arguments].join(' ');
    ran.add(command);
    for (final MapEntry(:key, :value) in outputs.entries) {
      if (command.startsWith(key)) return value;
    }
    return '';
  }
}

/// `flutter devices --machine` 的形狀（2026-11-11，Flutter 3.47.5），名稱與
/// id 改成假的。實體 iPhone 與 Android 實機不能被選到。
const _devicesJson = '''
[
  {"name": "phone", "id": "emulator-5554", "isSupported": true,
   "targetPlatform": "android-arm64", "emulator": true, "sdk": "Android 17 (API 37)"},
  {"name": "real phone", "id": "REAL-ANDROID", "isSupported": true,
   "targetPlatform": "android-arm64", "emulator": false, "sdk": "Android 16"},
  {"name": "my iPhone", "id": "REAL-IPHONE", "isSupported": true,
   "targetPlatform": "ios", "emulator": false, "sdk": "iOS 27.2"},
  {"name": "iPhone Sim", "id": "SIM-UDID", "isSupported": true,
   "targetPlatform": "ios", "emulator": true, "sdk": "iOS 27.1"},
  {"name": "macOS", "id": "macos", "isSupported": true,
   "targetPlatform": "darwin", "emulator": false, "sdk": "macOS 27.0.1"}
]
''';
