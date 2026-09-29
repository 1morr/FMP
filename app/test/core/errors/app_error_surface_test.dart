import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// ADR 0013 §如何確認：UI 不顯示原文。`AppError` 不得有可以直接顯示的字串，
// 使用者訊息只能從 i18n key 取得。Dart 在 flutter test 裡沒有反射，所以解析
// 原始碼（只 parse、不 resolve）列出整個函式庫的公開成員：函式庫內的程式碼都
// 讀得到私有的原始 error，任何公開出口都要審過。檔尾的變異案例證明解析抓得到
// 違規、也不被無關的改動影響（.trellis/spec/app/testing/index.md）。

const _library = 'lib/core/errors/app_error.dart';
const _reportPart = 'lib/core/errors/report_error.dart';

/// 審過的公開成員：`宣告.名稱`（頂層只有名稱）→ 宣告的型別。加欄位、方法或
/// 頂層函式時一起改這裡，並確認它不是給使用者看的文字。
const _reviewedSurface = {
  'AppError.pluginId': 'String?',
  'AppError.retryable': 'bool',
  'AppError.retryAfter': 'Duration?',
  'AppError.messageKey': 'ErrorMessageKey',
  'AppError.messageArgs': 'Map<String, Object>',
  'AppError.expected': 'bool',
  'AppError.networkRecordId': 'int?',
  'AppError.typeName': 'String',
  'AppError.toString()': 'String',
  'Unavailable.reason': 'UnavailableReason',
  'AppErrorReport.report()': 'void',
};

/// 型別是字串、或裝得下任意文字的成員中，允許的例外。
const _allowedTextMembers = {
  // 插件 id，不是訊息；呈現層拿它查插件的顯示名稱。
  'AppError.pluginId',
  // 寫死的類別名，給 log 與網路紀錄的 `type`／`error` 欄位；不含任何值。
  'AppError.typeName',
  // 只給 log，而且不含原始 error（app_error_test.dart 驗證）。
  'AppError.toString()',
};

void main() {
  // 函式庫與它的每個 part：之後多一個 part 也會被掃到。
  final library = File(_library).readAsStringSync();
  final parts = [
    for (final part in parseString(
      content: library,
      path: _library,
    ).unit.directives.whereType<PartDirective>())
      '${p.posix.dirname(_library)}/${part.uri.stringValue}',
  ];
  final sources = {
    _library: library,
    for (final path in parts) path: File(path).readAsStringSync(),
  };

  test('reads the library and its part', () {
    expect(sources.keys, [_library, _reportPart]);
  });

  test('the public surface is the reviewed list', () {
    expect(publicMembers(sources), _reviewedSurface);
  });

  test('no member exposes text that could be shown as is', () {
    expect(textMembers(publicMembers(sources)), isEmpty);
  });

  group('mutations', () {
    /// 在 [path] 的 [anchor] 之後插入 [insert]；anchor 必須存在，否則變異
    /// 沒有發生，案例會假綠。
    Map<String, String> mutate(String path, String anchor, String insert) {
      final source = sources[path]!;
      expect(source, contains(anchor), reason: 'mutation anchor in $path');
      return {...sources, path: source.replaceFirst(anchor, '$anchor$insert')};
    }

    // 名稱 → (檔案, anchor, 插在 anchor 之後的違規)。
    const violations = {
      'a String getter': (
        _library,
        'final class NetworkError extends AppError {',
        "\n  String get message => '';",
      ),
      'an untyped field': (
        _library,
        'final UnavailableReason reason;',
        "\n  final displayText = '';",
      ),
      'a method returning String': (
        _library,
        'final class ParseError extends AppError {',
        "\n  String describe() => '';",
      ),
      'the raw cause made public': (
        _library,
        'final Object? _cause;',
        '\n  Object? get cause => _cause;',
      ),
      'an extension on a subclass': (
        _reportPart,
        "part of 'app_error.dart';",
        '\nextension on NotFound {\n  String? get detail => null;\n}',
      ),
      'a method in the Log extension': (
        _reportPart,
        'extension AppErrorReport on Log {',
        "\n  String describe(AppError error) => '\${error._cause}';",
      ),
      'a top-level function': (
        _library,
        "part 'report_error.dart';",
        "\nString describe(AppError error) => '';",
      ),
      'a getter on an enum': (
        _library,
        'enum UnavailableReason { region, copyright, membership, age, previewOnly',
        "; String get label => '';",
      ),
      'a static getter': (
        _library,
        'final class UnexpectedError extends AppError {',
        "\n  static String get fallback => '';",
      ),
    };
    for (final MapEntry(key: name, value: (path, anchor, insert))
        in violations.entries) {
      test('catches $name', () {
        final members = publicMembers(mutate(path, anchor, insert));
        expect(members, isNot(_reviewedSurface));
        expect(textMembers(members), hasLength(1));
      });
    }

    test('ignores formatting, comments and private members', () {
      final library = sources[_library]!;
      expect(library, contains('_cause'));
      final unrelated = {
        ...sources,
        _library: library
            .replaceAll('_cause', '_originalError')
            .replaceAll('\n', '\n\n')
            .replaceFirst(
              'final class RateLimited extends AppError {',
              'final class RateLimited extends AppError {\n'
                  '  // String get message\n'
                  "  String get _label => 'RateLimited';\n",
            ),
      };

      final members = publicMembers(unrelated);
      expect(members, _reviewedSurface);
      expect(textMembers(members), isEmpty);
    });
  });
}

/// 解析 [sources]（路徑 → 內容）：函式庫裡每個公開宣告的公開成員。
///
/// 範圍是整個函式庫，不只 `AppError` 的類別：同一個函式庫的任何程式碼都讀得到
/// 私有的原始 error，所以頂層函式、enum 的成員、`Log` 的 extension 也算出口。
/// 鍵是 `宣告.名稱`（頂層只有名稱；方法加 `()`、setter 加 `=`；沒名字的
/// extension 用它擴充的型別），值是宣告的型別原文，沒寫型別時為 `null`。
Map<String, String?> publicMembers(Map<String, String> sources) {
  final declarations = [
    for (final MapEntry(key: path, value: content) in sources.entries)
      ...parseString(content: content, path: path).unit.declarations,
  ];
  final bodies = <(String, List<ClassMember>)>[
    for (final declaration in declarations)
      ...switch (declaration) {
        ClassDeclaration(:final namePart, :final body) ||
        ExtensionTypeDeclaration(
          :final namePart,
          :final body,
        ) => [(namePart.typeName.lexeme, body.members)],
        EnumDeclaration(:final namePart, :final body) => [
          (namePart.typeName.lexeme, body.members),
        ],
        MixinDeclaration(:final name, :final body) => [
          (name.lexeme, body.members),
        ],
        ExtensionDeclaration(:final name, :final onClause, :final body) => [
          (
            name?.lexeme ?? onClause?.extendedType.toSource() ?? '',
            body.members,
          ),
        ],
        _ => const <(String, List<ClassMember>)>[],
      },
  ];
  return {
    for (final declaration in declarations)
      ...switch (declaration) {
        FunctionDeclaration(:final name, :final isGetter, :final isSetter)
            when !name.lexeme.startsWith('_') =>
          {
            _key(null, name, isGetter: isGetter, isSetter: isSetter):
                declaration.returnType?.toSource(),
          },
        TopLevelVariableDeclaration(:final variables) => {
          for (final variable in variables.variables)
            if (!variable.name.lexeme.startsWith('_'))
              variable.name.lexeme: variables.type?.toSource(),
        },
        _ => const <String, String?>{},
      },
    for (final (owner, members) in bodies)
      if (!owner.startsWith('_'))
        for (final member in members)
          ...switch (member) {
            // 靜態成員也算：`AppError.fallbackText` 一樣可以被拿去顯示。
            FieldDeclaration(:final fields) => {
              for (final variable in fields.variables)
                if (!variable.name.lexeme.startsWith('_'))
                  '$owner.${variable.name.lexeme}': fields.type?.toSource(),
            },
            MethodDeclaration(:final name, :final isGetter, :final isSetter)
                when !name.lexeme.startsWith('_') =>
              {
                _key(owner, name, isGetter: isGetter, isSetter: isSetter):
                    member.returnType?.toSource(),
              },
            _ => const <String, String?>{},
          },
  };
}

String _key(
  String? owner,
  Token name, {
  required bool isGetter,
  required bool isSetter,
}) {
  final suffix = isGetter
      ? ''
      : isSetter
      ? '='
      : '()';
  return '${owner == null ? '' : '$owner.'}${name.lexeme}$suffix';
}

/// 可能被當成文字顯示的成員：型別是字串、裝得下任意值（`Object`、
/// `dynamic`），或沒寫型別；扣掉 [_allowedTextMembers]。
Set<String> textMembers(Map<String, String?> members) => {
  for (final MapEntry(key: name, value: type) in members.entries)
    if (!_allowedTextMembers.contains(name) &&
        switch (type?.replaceAll('?', '')) {
          null || 'String' || 'Object' || 'dynamic' => true,
          _ => false,
        })
      name,
};
