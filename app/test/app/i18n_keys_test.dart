import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 新字串要在同一張票補齊三種語言（architecture〈工程慣例〉）；slang 的 fallback 會把漏翻
/// 默默換成 zh-TW，所以在這裡直接比 key。
///
/// 變異驗證兩個方向都要有：任一邊多一個或少一個 key 要紅；改譯文、排版或
/// key 的順序不能紅。
void main() {
  const dir = 'lib/app/i18n';
  const locales = ['zh-TW', 'zh-CN', 'en'];

  Set<String> keysOf(String locale) =>
      i18nKeys(File('$dir/$locale.i18n.json').readAsStringSync());

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
      expect(keyMismatches(keysOf('zh-TW'), keysOf(locale)), isEmpty);
    });
  }

  group('keyMismatches', () {
    const base = '{"app": {"title": "FMP", "tagline": "新版"}}';

    test('turns red when a key is missing or extra on either side', () {
      const missing = '{"app": {"title": "FMP"}}';
      const extra = '{"app": {"title": "FMP", "tagline": "x", "more": "y"}}';
      expect(keyMismatches(i18nKeys(base), i18nKeys(missing)), {'app.tagline'});
      expect(keyMismatches(i18nKeys(base), i18nKeys(extra)), {'app.more'});
    });

    test('stays green on translations, layout and key order', () {
      const other = '''
{
  "app": {
    "tagline": "New version",
    "title": "FMP"
  }
}
''';
      expect(keyMismatches(i18nKeys(base), i18nKeys(other)), isEmpty);
    });
  });
}

/// slang JSON 的所有葉節點 key，巢狀的以 `.` 連起來。
Set<String> i18nKeys(String json) {
  final keys = <String>{};
  void walk(Object? node, String prefix) {
    if (node is Map<String, Object?>) {
      node.forEach((k, v) => walk(v, prefix.isEmpty ? k : '$prefix.$k'));
    } else {
      keys.add(prefix);
    }
  }

  walk(jsonDecode(json), '');
  return keys;
}

/// 只出現在其中一邊的 key。
Set<String> keyMismatches(Set<String> base, Set<String> other) =>
    base.difference(other).union(other.difference(base));
