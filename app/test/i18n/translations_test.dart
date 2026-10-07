import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:path/path.dart' as p;

// ADR 0024 §如何確認：三語言的 key 集合相同，缺一條就紅。slang 設了
// `fallback_strategy: base_locale`，缺的字串會退回繁中照樣編譯，所以這裡是
// 唯一擋住漏翻的地方。檔尾的變異案例證明比對抓得到違規，也不被無關的改動
// 影響（.trellis/spec/app/testing/index.md）。

const _directory = 'lib/i18n';
const _suffix = '.i18n.json';

/// 翻譯檔的內容：語言 → 攤平的 key（`errors.network`）→ 字串。
typedef Catalog = Map<String, Map<String, String>>;

Catalog readCatalog() => {
  for (final file in Directory(_directory).listSync().whereType<File>())
    if (file.path.endsWith(_suffix))
      p.basename(file.path).replaceAll(_suffix, ''): flatten(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      ),
};

/// 巢狀的 JSON 攤平成 `a.b.c` → 字串。
Map<String, String> flatten(Map<String, Object?> json, [String prefix = '']) =>
    {
      for (final MapEntry(:key, :value) in json.entries)
        ...switch (value) {
          final Map<String, Object?> nested => flatten(nested, '$prefix$key.'),
          final String text => {'$prefix$key': text},
          _ => throw FormatException('Unexpected value at $prefix$key: $value'),
        },
    };

/// `{name}` 參數（slang 的 `string_interpolation: braces`）；`\{` 是跳脫。
Set<String> placeholders(String text) => {
  for (final match in RegExp(r'(?<!\\)\{(\w+)\}').allMatches(text))
    match.group(1)!,
};

/// 和 base locale（zh-TW）比，每個語言缺的 key、多的 key、參數不同的 key。
List<String> parityProblems(Catalog catalog) {
  final base = catalog['zh-TW']!;
  return [
    for (final MapEntry(key: locale, value: strings) in catalog.entries)
      if (locale != 'zh-TW') ...[
        for (final key in base.keys)
          if (!strings.containsKey(key)) '$locale is missing $key',
        for (final key in strings.keys)
          if (!base.containsKey(key)) '$locale has $key, zh-TW does not',
        for (final key in strings.keys)
          if (base[key] case final baseText?
              when !_sameSet(
                placeholders(baseText),
                placeholders(strings[key]!),
              ))
            '$locale has other parameters in $key',
      ],
  ];
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

void main() {
  final catalog = readCatalog();

  test('there is one file per supported language', () {
    expect(catalog.keys.toSet(), {'zh-TW', 'zh-CN', 'en'});
    expect({
      for (final locale in AppLocale.values) locale.languageTag,
    }, catalog.keys.toSet());
    expect(AppLocaleUtils.instance.baseLocale, AppLocale.zhTw);
  });

  test('every language has the same keys and parameters', () {
    expect(parityProblems(catalog), isEmpty);
  });

  test('no string is empty', () {
    for (final MapEntry(key: locale, value: strings) in catalog.entries) {
      for (final MapEntry(:key, :value) in strings.entries) {
        expect(value.trim(), isNotEmpty, reason: '$locale $key');
      }
    }
  });

  group('error messages', () {
    for (final MapEntry(key: locale, value: strings) in catalog.entries) {
      test('every ErrorMessageKey has a string in $locale', () {
        for (final key in ErrorMessageKey.values) {
          expect(strings, contains('errors.${key.name}'));
        }
      });

      test('every UnavailableReason has a string in $locale', () {
        for (final reason in UnavailableReason.values) {
          expect(strings, contains('errors.unavailableReasons.${reason.name}'));
        }
      });
    }
  });

  // ADR 0024 §決定 8：有快捷鍵的按鈕，tooltip 附上按鍵（三語言都要）。按鍵是固定
  // 的，寫在 `playback_shortcuts.dart` 的表裡，改那邊要一起改這些字串。
  group('tooltips carry the shortcut', () {
    const keys = {
      'player.playTooltip': ['Space', '空白鍵', '空格键'],
      'player.pauseTooltip': ['Space', '空白鍵', '空格键'],
      'player.previousTooltip': ['Ctrl+←'],
      'player.nextTooltip': ['Ctrl+→'],
      'player.shuffleTooltip': ['Ctrl+S'],
      'player.loopOffTooltip': ['Ctrl+R'],
      'player.loopAllTooltip': ['Ctrl+R'],
      'player.loopOneTooltip': ['Ctrl+R'],
      'player.volumeTooltip': ['Ctrl+↑'],
    };
    for (final MapEntry(key: locale, value: strings) in catalog.entries) {
      test('in $locale', () {
        for (final MapEntry(key: name, value: hints) in keys.entries) {
          expect(
            hints.any(strings[name]!.contains),
            isTrue,
            reason: '$locale $name: ${strings[name]}',
          );
        }
      });
    }
  });

  group('mutations', () {
    Catalog mutate(
      String locale,
      Map<String, String> Function(Map<String, String>) change,
    ) => {
      ...catalog,
      locale: change({...catalog[locale]!}),
    };

    test('catches a missing key', () {
      final mutated = mutate(
        'en',
        (strings) => strings..remove('errors.network'),
      );

      expect(parityProblems(mutated), ['en is missing errors.network']);
    });

    test('catches a key only one language has', () {
      final mutated = mutate(
        'zh-CN',
        (strings) => strings..['errors.extra'] = '多的',
      );

      expect(parityProblems(mutated), [
        'zh-CN has errors.extra, zh-TW does not',
      ]);
    });

    test('catches a renamed parameter', () {
      final mutated = mutate(
        'en',
        (strings) =>
            strings..['errors.rateLimited'] = 'Too many requests to {plugin}.',
      );

      expect(parityProblems(mutated), [
        'en has other parameters in errors.rateLimited',
      ]);
    });

    test('ignores reworded text, reordered keys and JSON formatting', () {
      final reworded = mutate(
        'en',
        (strings) => Map.fromEntries(strings.entries.toList().reversed)
          ..['errors.network'] = 'Offline. Try again.'
          ..['errors.rateLimited'] = '{source} is busy. Escaped \\{brace}.',
      );
      final reformatted = flatten(
        jsonDecode(
          const JsonEncoder.withIndent('        ').convert(
            jsonDecode(File('$_directory/en$_suffix').readAsStringSync()),
          ),
        ) as Map<String, Object?>,
      );

      expect(parityProblems(reworded), isEmpty);
      expect(parityProblems({...catalog, 'en': reformatted}), isEmpty);
    });
  });
}
