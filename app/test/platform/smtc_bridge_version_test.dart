import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// `smtc_windows` 的 Dart 端（flutter_rust_bridge）與它編進 Rust 的版本必須
/// 相同，否則執行時 `SMTCWindows.initialize()` 丟 `codegen version … should be
/// the same as runtime version …`。套件的 `pubspec.yaml` 只寫 `^2.11.1`，
/// `rust/Cargo.toml` 卻釘 `=2.11.1`，所以 app 要自己釘同一版。初始化失敗只記
/// log，沒有這個測試就沒人發現。

/// `Cargo.toml` 裡 `flutter_rust_bridge = "=X"` 的 X；找不到為 `null`。
String? cargoBridgeVersion(String cargoToml) => RegExp(
  r'''^\s*flutter_rust_bridge\s*=\s*["']=\s*([^"']+?)\s*["']''',
  multiLine: true,
).firstMatch(cargoToml)?.group(1);

/// `pubspec.lock` 裡 `flutter_rust_bridge` 的 `version`；找不到為 `null`。
String? lockedBridgeVersion(String pubspecLock) {
  final lines = const LineSplitter().convert(pubspecLock);
  final start = lines.indexWhere((l) => l.trim() == 'flutter_rust_bridge:');
  if (start < 0) return null;
  final indent = lines[start].length - lines[start].trimLeft().length;
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    if (line.length - line.trimLeft().length <= indent) return null;
    final match = RegExp(r'''^\s*version:\s*["']?([^"'\s]+)["']?''')
        .firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}

/// package_config.json 裡 [package] 的根目錄（不寫死 pub-cache 的位置）。
String packageRoot(String packageConfigJson, String package) {
  final packages =
      (jsonDecode(packageConfigJson) as Map<String, Object?>)['packages']!
          as List<Object?>;
  final entry = packages.cast<Map<String, Object?>>().firstWhere(
    (e) => e['name'] == package,
  );
  return Uri.parse(entry['rootUri']! as String).toFilePath();
}

void main() {
  test(
    'the locked flutter_rust_bridge is the one smtc_windows compiles in',
    () {
      final config = File(p.join('.dart_tool', 'package_config.json'));
      final root = packageRoot(config.readAsStringSync(), 'smtc_windows');
      final cargo = File(p.join(root, 'rust', 'Cargo.toml')).readAsStringSync();
      final lock = File('pubspec.lock').readAsStringSync();

      final expected = cargoBridgeVersion(cargo);
      expect(expected, isNotNull, reason: 'Cargo.toml no longer pins it');
      expect(lockedBridgeVersion(lock), expected);
    },
  );

  group('parsers', () {
    const cargo = '''
[package]
name = "x"

[dependencies]
flutter_rust_bridge = "=2.11.1"
anyhow = '1'
''';
    const lock = '''
packages:
  flutter_rust_bridge:
    dependency: "direct main"
    description:
      name: flutter_rust_bridge
      sha256: abc
      url: "https://pub.dev"
    source: hosted
    version: "2.11.1"
  flutter_test:
    dependency: "direct dev"
    description: flutter
    source: sdk
    version: "0.0.0"
''';

    test('a different locked version differs from the pinned one', () {
      final other = lock.replaceFirst('"2.11.1"', '"2.13.0"');

      expect(lockedBridgeVersion(other), '2.13.0');
      expect(lockedBridgeVersion(other), isNot(cargoBridgeVersion(cargo)));
    });

    test('equal versions are equal', () {
      expect(lockedBridgeVersion(lock), cargoBridgeVersion(cargo));
    });

    test('whitespace, field order and comments do not change the result', () {
      final reshuffled = cargo
          .replaceFirst(
            'flutter_rust_bridge = "=2.11.1"',
            '# pinned\nflutter_rust_bridge   =   "= 2.11.1"   # why',
          )
          .replaceFirst("anyhow = '1'\n", '');
      expect(cargoBridgeVersion(reshuffled), '2.11.1');

      final reordered = lock
          .replaceFirst('    version: "2.11.1"\n', '')
          .replaceFirst(
            '    dependency: "direct main"\n',
            '    version: "2.11.1"\n    dependency: "direct main"\n',
          );
      expect(lockedBridgeVersion(reordered), '2.11.1');
      expect(lockedBridgeVersion('$lock\n\n'), '2.11.1');
    });

    test('a missing entry is null, not another package\'s version', () {
      expect(cargoBridgeVersion('[dependencies]\nanyhow = "1"\n'), isNull);
      expect(
        lockedBridgeVersion('packages:\n  other:\n    version: "1"\n'),
        isNull,
      );
    });
  });
}
