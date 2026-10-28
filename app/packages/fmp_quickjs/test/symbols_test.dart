@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fmp_quickjs/host_library.dart';
import 'package:test/test.dart';

/// flutter_js 在 macOS 以 `DynamicLibrary.process()` 查的每個符號都要在 `src/` 編出的庫裡
/// （ADR 0036 §決定 1）。升級 flutter_js 或換上游原始碼時，這裡會指出缺了哪些。
///
/// 只在 macOS 主機跑：要 `xcrun clang` 與 `nm`。CI 的 macOS job 跑這個套件的測試。
void main() {
  late Directory cache;

  setUpAll(() {
    cache = Directory.systemTemp.createTempSync('fmp_quickjs_test_');
  });

  tearDownAll(() => cache.deleteSync(recursive: true));

  test('the library exports every symbol flutter_js looks up', () {
    final wanted = lookedUpSymbols(
      File.fromUri(_flutterJsRoot().resolve('lib/quickjs/ffi.dart')),
    );
    // ffi.dart 現在查 55 個：找不到就是讀法錯了，不是庫齊全。
    expect(wanted, hasLength(greaterThan(50)));

    final library = buildHostLibrary(
      packageRoot: Directory.current,
      cacheRoot: cache,
    );
    final exported = exportedSymbols(library);

    expect(wanted.difference(exported), isEmpty);
  });

  group('lookedUpSymbols', () {
    test('finds names across line breaks and lookupFunction', () {
      final file = File('${cache.path}/ffi.dart')
        ..writeAsStringSync('''
final a = _qjsLib
    .lookup<
        NativeFunction<
            Void Function(
              Pointer<JSRuntime>,
            )>>('jsFreeRuntime')
    .asFunction();
final b = _qjsLib.lookupFunction<Int32 Function(), int Function()>('jsOne');
''');
      expect(lookedUpSymbols(file), {'jsFreeRuntime', 'jsOne'});
    });

    test('ignores strings that are not lookups', () {
      final file = File('${cache.path}/other.dart')
        ..writeAsStringSync("final name = 'jsNotLookedUp';\nprint('x');\n");
      expect(lookedUpSymbols(file), isEmpty);
    });
  });
}

/// [ffiDart] 裡每個 `lookup<…>('名稱')`、`lookupFunction<…>('名稱')` 的名稱。
Set<String> lookedUpSymbols(File ffiDart) {
  final source = ffiDart.readAsStringSync();
  final pattern = RegExp(
    r"\.lookup(?:Function)?\s*<(?:[^;'])*?>\s*\(\s*'([A-Za-z_][A-Za-z0-9_]*)'",
  );
  return {for (final match in pattern.allMatches(source)) match.group(1)!};
}

/// `nm -gU` 列出的、[library] 定義的全域符號（去掉 Mach-O 的前導底線）。
Set<String> exportedSymbols(String library) {
  final result = Process.runSync('nm', ['-gU', library]);
  if (result.exitCode != 0) throw StateError('nm failed: ${result.stderr}');
  return {
    for (final line in LineSplitter.split(result.stdout as String))
      if (line.trim().split(RegExp(r'\s+')) case [..., final name]
          when name.startsWith('_'))
        name.substring(1),
  };
}

/// flutter_js 在 pub cache 裡的根目錄，從 workspace 根（`app/`）的 package config 讀。
Uri _flutterJsRoot() {
  final configFile = File('../../.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final package = (config['packages'] as List).cast<Map>().firstWhere(
    (package) => package['name'] == 'flutter_js',
  );
  final root = configFile.absolute.uri.resolve(package['rootUri'] as String);
  return root.path.endsWith('/') ? root : Uri.parse('$root/');
}
