import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:path/path.dart' as p;

/// Windows 的 App 身分（app/AGENTS.md § App 身分）：prod 與舊版相同
/// （ADR 0008 §決定 3），dev 每一項都不同（ADR 0015 §決定 8）。
///
/// 以 `cmake -P` 執行 `windows/runner/app_identity.cmake`，取得 runner 編進
/// 執行檔的值。CI 的 Linux 有 cmake；Windows 的 PATH 上沒有時用 Visual Studio
/// 附的那一份。
void main() {
  const prod = {
    'FMP_APP_USER_MODEL_ID': 'com.personal.fmp',
    'FMP_SINGLE_INSTANCE_NAME': 'FMP_MainInstance',
    'FMP_DISPLAY_NAME': 'FMP',
    'FMP_PRODUCT_NAME': 'fmp',
  };

  test('prod keeps the legacy identity', () {
    expect(runIdentity('prod').values, prod);
  });

  test('dev differs in every identity value', () {
    final dev = runIdentity('dev').values;
    expect(dev, {
      'FMP_APP_USER_MODEL_ID': 'com.personal.fmp.dev',
      'FMP_SINGLE_INSTANCE_NAME': 'FMP_MainInstance-dev',
      'FMP_DISPLAY_NAME': 'FMP Dev',
      'FMP_PRODUCT_NAME': 'fmp-dev',
    });
    for (final key in prod.keys) {
      expect(dev[key], isNot(prod[key]), reason: key);
    }
  });

  test('the Dart display name matches the window title', () {
    for (final flavor in AppFlavor.values) {
      expect(
        runIdentity(flavor.name).values['FMP_DISPLAY_NAME'],
        flavor.displayName,
      );
    }
  });

  test('an unknown or missing flavor fails the build', () {
    for (final flavor in ['staging', null]) {
      final result = runIdentity(flavor);
      expect(result.exitCode, isNot(0), reason: '$flavor');
      expect(result.stderr, contains('expected dev or prod'));
    }
  });

  group('executable name', () {
    final cmakeLists = File('windows/CMakeLists.txt').readAsStringSync();

    test('is fmp.exe for every flavor', () {
      // flavor 不改 BINARY_NAME；flutter 工具也只讀這一行找執行檔。
      expect(binaryName(cmakeLists), 'fmp');
    });

    test('a renamed binary is detected', () {
      final mutated = cmakeLists.replaceFirst(
        'set(BINARY_NAME "fmp")',
        'set(BINARY_NAME "fmp-dev")',
      );
      expect(mutated, isNot(cmakeLists));
      expect(binaryName(mutated), 'fmp-dev');
    });

    test('spacing and comments do not change the result', () {
      final reformatted = cmakeLists.replaceFirst(
        'set(BINARY_NAME "fmp")',
        '# 執行檔名\n  set(BINARY_NAME   "fmp" )  ',
      );
      expect(reformatted, isNot(cmakeLists));
      expect(binaryName(reformatted), 'fmp');
    });
  });
}

/// flutter 工具找 Windows 執行檔名的同一條規則（flutter_tools
/// `lib/src/cmake.dart` 的 `getCmakeExecutableName`）。
String? binaryName(String cmakeLists) {
  final pattern = RegExp(r'^\s*set\(BINARY_NAME\s*"(.*)"\s*\)\s*$');
  for (final line in cmakeLists.split('\n')) {
    final match = pattern.firstMatch(line.trimRight());
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

typedef IdentityResult = ({
  int exitCode,
  String stderr,
  Map<String, String> values,
});

IdentityResult runIdentity(String? flavor) {
  final temp = Directory.systemTemp.createTempSync('fmp_windows_identity_');
  addTearDown(() => temp.deleteSync(recursive: true));
  final identityFile = p
      .join(Directory.current.path, 'windows', 'runner', 'app_identity.cmake')
      .replaceAll(r'\', '/');
  final script = File(p.join(temp.path, 'print_identity.cmake'))
    ..writeAsStringSync(
      'include("$identityFile")\n'
      'foreach(name FMP_APP_USER_MODEL_ID FMP_SINGLE_INSTANCE_NAME '
      'FMP_DISPLAY_NAME FMP_PRODUCT_NAME)\n'
      r'  message(NOTICE "${name}=${${name}}")'
      '\nendforeach()\n',
    );
  final result = Process.runSync(_cmake, [
    if (flavor != null) '-DFLUTTER_APP_FLAVOR=$flavor',
    '-P',
    script.path,
  ]);
  final stderr = result.stderr as String;
  final line = RegExp(r'^(FMP_\w+)=(.*)$');
  final values = <String, String>{
    for (final text in stderr.split(RegExp(r'\r?\n')))
      if (line.firstMatch(text) case final match?)
        match.group(1)!: match.group(2)!,
  };
  return (exitCode: result.exitCode, stderr: stderr, values: values);
}

final String _cmake = _findCmake();

String _findCmake() {
  try {
    if (Process.runSync('cmake', ['--version']).exitCode == 0) {
      return 'cmake';
    }
  } on ProcessException {
    // PATH 上沒有，改找 Visual Studio 附的 cmake（flutter 建置 Windows 也用它）。
  }
  const vswhere =
      r'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe';
  if (File(vswhere).existsSync()) {
    final found = Process.runSync(vswhere, [
      '-latest',
      '-products',
      '*',
      '-find',
      r'**\bin\cmake.exe',
    ]);
    final path = (found.stdout as String).trim().split(RegExp(r'\r?\n')).first;
    if (path.isNotEmpty) {
      return path;
    }
  }
  throw StateError('cmake not found on PATH or via vswhere');
}
