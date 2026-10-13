import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

// ADR 0023 §決定 4：「在 GitHub 回報」開 `bug_report.yml` 範本，使用者把「複製」的報告貼進
// 「錯誤報告」欄位。範本壞了（欄位改名、不再必填、不再當 Markdown 顯示）使用者貼的內容就
// 沒有地方放。測試 cwd 是 `app/`。

/// [source]（範本的 YAML）不符合 App 回報流程的地方；空表示沒問題。
List<String> templateProblems(String source) {
  final problems = <String>[];
  final Object? doc;
  try {
    doc = loadYaml(source);
  } on YamlException catch (error) {
    return ['not valid YAML: ${error.message}'];
  }
  if (doc is! YamlMap) return ['the template is not a mapping'];

  final labels = doc['labels'];
  if (labels is! YamlList || !labels.contains('bug')) {
    problems.add('labels must contain bug');
  }
  final body = doc['body'];
  final fields = <String, YamlMap>{
    if (body is YamlList)
      for (final item in body)
        if (item is YamlMap && item['id'] is String) item['id'] as String: item,
  };
  bool required(String id) {
    final validations = fields[id]?['validations'];
    return validations is YamlMap && validations['required'] == true;
  }

  for (final id in ['description', 'report']) {
    if (!fields.containsKey(id)) {
      problems.add('missing field $id');
    } else if (!required(id)) {
      problems.add('field $id must be required');
    }
  }
  for (final id in ['steps', 'version', 'platform']) {
    if (!fields.containsKey(id)) problems.add('missing field $id');
  }
  final report = fields['report'];
  if (report != null) {
    final attributes = report['attributes'];
    if (attributes is! YamlMap || attributes['render'] != 'markdown') {
      problems.add('field report must render as markdown');
    }
  }
  return problems;
}

void main() {
  final source = File('../.github/ISSUE_TEMPLATE/bug_report.yml')
      .readAsStringSync();

  test('the bug report template fits the report flow', () {
    expect(templateProblems(source), isEmpty);
  });

  group('mutations', () {
    // 造一個違規證明會紅。
    test('catches a missing bug label', () {
      expect(
        templateProblems(source.replaceFirst("['bug']", "['question']")),
        contains('labels must contain bug'),
      );
    });

    test('catches the report field no longer required', () {
      final index = source.indexOf('id: report');
      final mutated =
          source.substring(0, index) +
          source
              .substring(index)
              .replaceFirst('required: true', 'required: false');
      expect(templateProblems(mutated), ['field report must be required']);
    });

    test('catches the report field no longer rendered as markdown', () {
      expect(
        templateProblems(
          source.replaceFirst('render: markdown', 'render: text'),
        ),
        ['field report must render as markdown'],
      );
    });

    test('catches a renamed field', () {
      expect(
        templateProblems(source.replaceFirst('id: report', 'id: details')),
        contains('missing field report'),
      );
    });

    // 改一次無關的格式或文字證明不會紅。
    test('ignores wording, quoting, comments and field order', () {
      final reworded = source
          .replaceFirst('問題描述', '描述問題')
          .replaceFirst("['bug']", '\n  - "bug"')
          .replaceFirst('name: 回報問題', '# 範本\nname: 回報問題');
      expect(templateProblems(reworded), isEmpty);
    });
  });
}
