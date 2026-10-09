import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Linux 不建 flutter_inappwebview 的原生插件（M3 PR 9，ADR 0012 §決定 8）：App 直接依賴
// packages/flutter_inappwebview_linux_stub，Flutter 選它而不選預設的
// flutter_inappwebview_linux（WPE WebKit，建置與執行都要裝 WPE）。這裡讀 Flutter 工具解析
// 的結果（`flutter pub get` 產生的 `.flutter-plugins-dependencies`）與提交的
// `linux/flutter/generated_plugins.cmake`。

const _stub = 'flutter_inappwebview_linux_stub';

/// `.flutter-plugins-dependencies` 裡 Linux 那一組中屬於 flutter_inappwebview 的插件：
/// 名稱 → 有沒有原生建置。
Map<String, bool> linuxWebViewPlugins(String dependenciesJson) {
  final json = jsonDecode(dependenciesJson) as Map<String, Object?>;
  final plugins = json['plugins']! as Map<String, Object?>;
  return {
    for (final plugin
        in (plugins['linux']! as List<Object?>).cast<Map<String, Object?>>())
      if ((plugin['name']! as String).startsWith('flutter_inappwebview'))
        plugin['name']! as String: plugin['native_build'] == true,
  };
}

/// `generated_plugins.cmake` 的 `FLUTTER_PLUGIN_LIST` 與 `FLUTTER_FFI_PLUGIN_LIST` 裡的
/// 每個名稱（註解與空白不算）。
Set<String> cmakePlugins(String cmake) {
  final withoutComments = cmake.replaceAll(RegExp('#[^\n]*'), '');
  final lists = RegExp(
    r'list\s*\(\s*APPEND\s+FLUTTER_(?:FFI_)?PLUGIN_LIST([^)]*)\)',
  ).allMatches(withoutComments);
  return {
    for (final list in lists)
      ...list.group(1)!.split(RegExp(r'\s+')).where((name) => name.isNotEmpty),
  };
}

bool _webView(String name) => name.startsWith('flutter_inappwebview');

void main() {
  final dependencies = File('.flutter-plugins-dependencies').readAsStringSync();
  final cmake = File('linux/flutter/generated_plugins.cmake')
      .readAsStringSync();

  test('Linux resolves flutter_inappwebview to the Dart-only stub', () {
    expect(linuxWebViewPlugins(dependencies), {_stub: false});
  });

  test('the committed Linux plugin list builds no flutter_inappwebview', () {
    expect(cmakePlugins(cmake), isNotEmpty);
    expect(cmakePlugins(cmake).where(_webView), isEmpty);
  });

  group('parser mutations', () {
    test('the endorsed Linux plugin is caught', () {
      final json = jsonDecode(dependencies) as Map<String, Object?>;
      final linux =
          ((json['plugins']! as Map<String, Object?>)['linux']!
                  as List<Object?>)
              .cast<Map<String, Object?>>();
      final stub = linux.firstWhere((plugin) => plugin['name'] == _stub);
      stub['name'] = 'flutter_inappwebview_linux';
      stub['native_build'] = true;
      expect(linuxWebViewPlugins(jsonEncode(json)), {
        'flutter_inappwebview_linux': true,
      });

      final mutated = cmake.replaceFirst(
        RegExp(r'FLUTTER_PLUGIN_LIST\r?\n'),
        'FLUTTER_PLUGIN_LIST\n  flutter_inappwebview_linux\n',
      );
      expect(mutated, isNot(cmake));
      expect(cmakePlugins(mutated).where(_webView), [
        'flutter_inappwebview_linux',
      ]);
    });

    test('formatting and comments do not change the result', () {
      final reformatted = const JsonEncoder.withIndent('    ')
          .convert(jsonDecode(dependencies));
      expect(reformatted, isNot(dependencies));
      expect(linuxWebViewPlugins(reformatted), {_stub: false});

      final commented = cmake
          .replaceFirst(
            'list(APPEND',
            '# flutter_inappwebview_linux\nlist (  APPEND',
          )
          .replaceAll('\n  ', '\n\t');
      expect(commented, isNot(cmake));
      expect(cmakePlugins(commented), cmakePlugins(cmake));
    });
  });
}
