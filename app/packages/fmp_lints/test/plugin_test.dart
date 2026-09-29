import 'dart:io';

import 'package:fmp_lints/main.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// 規則註冊成 lint rule 後預設關閉：少開一條，那條就靜靜失效。這裡斷言
/// `app/analysis_options.yaml` 開的正好是插件註冊的全部規則。
void main() {
  final names = [for (final rule in fmpRules()) rule.name];

  test('rule names are unique and prefixed', () {
    expect(names.toSet(), hasLength(names.length));
    expect(names, everyElement(startsWith('fmp_')));
  });

  test('app/analysis_options.yaml enables exactly the registered rules', () {
    final options = File('../../analysis_options.yaml').readAsStringSync();
    expect(enabledPluginRules(options), unorderedEquals(names));
  });

  group('enabledPluginRules mutations', () {
    const base = '''
plugins:
  fmp_lints:
    path: packages/fmp_lints
    diagnostics:
      fmp_a: true
      fmp_b: true
''';

    test('a disabled or missing rule is dropped', () {
      expect(
        enabledPluginRules(base.replaceFirst('fmp_b: true', 'fmp_b: false')),
        ['fmp_a'],
      );
      expect(enabledPluginRules(base.replaceFirst('      fmp_b: true\n', '')), [
        'fmp_a',
      ]);
    });

    test('comments, ordering and other sections do not change the result', () {
      const reformatted = '''
# 註解
analyzer:
  exclude: [build/**]
plugins:
  other_plugin: ^1.0.0
  fmp_lints:
    diagnostics: {fmp_b: true, fmp_a: true}  # 行內註解
    path: packages/fmp_lints
''';
      expect(
        enabledPluginRules(reformatted),
        unorderedEquals(['fmp_a', 'fmp_b']),
      );
    });
  });
}

/// [analysisOptions] 的 `plugins: fmp_lints: diagnostics:` 裡設成 `true` 的規則。
List<String> enabledPluginRules(String analysisOptions) {
  final yaml = loadYaml(analysisOptions) as YamlMap;
  final diagnostics =
      ((yaml['plugins'] as YamlMap?)?['fmp_lints'] as YamlMap?)?['diagnostics']
          as YamlMap?;
  return [
    for (final MapEntry(:key, :value) in (diagnostics ?? YamlMap()).entries)
      if (value == true) key as String,
  ];
}
