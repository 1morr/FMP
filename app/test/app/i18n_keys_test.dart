import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 新字串要在同一張票補齊三種語言（plan §0）；slang 的 fallback 會把漏翻
/// 默默換成 zh-TW，所以在這裡直接比 key。
void main() {
  const dir = 'lib/app/i18n';
  const locales = ['zh-TW', 'zh-CN', 'en'];

  Set<String> keysOf(String locale) {
    final json = jsonDecode(File('$dir/$locale.i18n.json').readAsStringSync());
    final keys = <String>{};
    void walk(Object? node, String prefix) {
      if (node is Map<String, Object?>) {
        node.forEach((k, v) => walk(v, prefix.isEmpty ? k : '$prefix.$k'));
      } else {
        keys.add(prefix);
      }
    }

    walk(json, '');
    return keys;
  }

  test('the i18n directory holds exactly zh-TW, zh-CN and en', () {
    final files = Directory(dir)
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((name) => name.endsWith('.i18n.json'))
        .toSet();
    expect(files, {for (final l in locales) '$l.i18n.json'});
  });

  for (final locale in locales.skip(1)) {
    test('$locale has the same keys as zh-TW', () {
      expect(keysOf(locale), keysOf('zh-TW'));
    });
  }
}
