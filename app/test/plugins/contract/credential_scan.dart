import 'dart:convert';

import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redaction_lists.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/source_dto.dart';

import 'fixture.dart';
import 'ip_scrub.dart';

// 憑證檢查：fixture、插件的 log、串流 headers 裡不得有未遮蔽的憑證
// （ADR 0015 §如何確認、ADR 0011、ADR 0012）。兩道獨立的檢查：
//
// 1. 以正式的遮蔽函式再遮一次，結果必須不變（已經遮過）；
// 2. 依名單直接看欄位：名單上的 header 與鍵名，值必須是 `***`（或空、null）。
//    不經 Redactor 的正規式，Redactor 本身漏遮時由這一道抓到。
//
// 名單就是 Redactor 的名單（`redaction_lists.dart` 加 manifest 追加的），比對
// 方式也相同：header 名稱整個相同、鍵名以它結尾，都不分大小寫。

/// 憑證的 header 與鍵名。
final class CredentialNames {
  CredentialNames({
    Iterable<String> headerNames = const [],
    Iterable<String> keyNames = const [],
  }) : _headers = {
         for (final name in [...builtInHeaderNames, ...headerNames])
           name.toLowerCase(),
       },
       _keys = {
         for (final name in [...builtInKeyNames, ...keyNames])
           name.toLowerCase(),
       } {
    // 名稱、結尾引號、`:` 或 `=`、開頭引號或 `[`、值（到分隔符為止）。header
    // 名稱前面不是字元或 `-`；鍵名前面不設邊界（以它結尾就算），同 Redactor。
    // `[` 開頭的值 Redactor 遮成 `[***]`（多值的 header、JSON 陣列），不跳過
    // `[` 就會把遮好的值當成沒遮。
    const separator = r'''\\?["']?[ \t]*[:=][ \t]*\[?[ \t]*\\?["']?''';
    const value = r'''([^"'&;\s,}\])\\]*)''';
    _text = RegExp(
      '(?:(?<![\\w-])(${_alternation(_headers)})|(${_alternation(_keys)}))'
      '$separator$value',
      caseSensitive: false,
    );
  }

  /// [manifest] 追加的名單也算。
  factory CredentialNames.of(PluginManifest manifest) => CredentialNames(
    headerNames: manifest.redaction.headerNames,
    keyNames: manifest.redaction.keyNames,
  );

  final Set<String> _headers;
  final Set<String> _keys;
  late final RegExp _text;

  bool isSensitive(String name) {
    final lower = name.toLowerCase();
    return _headers.contains(lower) || _keys.any(lower.endsWith);
  }

  /// 文字裡 `名稱: 值`、`名稱=值`、`"名稱": "值"` 的值沒遮的，回傳名稱。
  List<String> unredactedInText(String text) => [
    for (final match in _text.allMatches(text))
      if (!_isRedacted(match[3]!)) match[1] ?? match[2]!,
  ];

  /// JSON 值（物件、陣列、字串）裡沒遮的憑證，回傳它們的路徑。
  List<String> unredactedInJson(Object? value, String path) => switch (value) {
    final Map<Object?, Object?> map => [
      for (final MapEntry(:key, value: entry) in map.entries)
        if (isSensitive('$key') && entry != null && entry != redactedValue)
          '$path.$key'
        else
          ...unredactedInJson(entry, '$path.$key'),
    ],
    final List<Object?> items => [
      for (final (index, item) in items.indexed)
        ...unredactedInJson(item, '$path[$index]'),
    ],
    final String text => [
      for (final name in unredactedInText(text)) '$path ("$name")',
    ],
    _ => const [],
  };

  static bool _isRedacted(String value) =>
      value.isEmpty || value == redactedValue || value == 'null';

  static String _alternation(Iterable<String> names) =>
      (names.toList()..sort((a, b) => b.length.compareTo(a.length)))
          .map(RegExp.escape)
          .join('|');
}

/// fixture 裡沒遮的憑證（兩道檢查）。[name] 放在訊息開頭。
List<String> scanFixture(
  String name,
  HttpFixture fixture,
  Redactor redactor,
  CredentialNames names,
) {
  final original = fixture.toJson();
  final again = fixture.redacted(redactor).toJson();
  final problems = <String>[
    for (final part in ['request', 'response'])
      for (final key in {
        ...(original[part]! as Map).keys,
        ...(again[part]! as Map).keys,
      })
        if (jsonEncode((original[part]! as Map)[key]) !=
            jsonEncode((again[part]! as Map)[key]))
          '$name: $part.$key changes when redacted again',
  ];
  final request = fixture.request;
  final response = fixture.response;
  problems.addAll([
    for (final key in names.unredactedInText(request.url))
      '$name: request.url has an unredacted "$key"',
    ..._headerProblems(name, 'request', {
      for (final MapEntry(:key, :value) in request.headers.entries)
        key: [value],
    }, names),
    ..._headerProblems(name, 'response', response.headers, names),
    for (final path in [
      ...names.unredactedInJson(request.body, 'request.body'),
      ...names.unredactedInJson(response.body, 'response.body'),
      ...names.unredactedInJson(response.jsonBody, 'response.jsonBody'),
    ])
      '$name: $path is not redacted',
    ...ipProblems(name, fixture),
  ]);
  return problems;
}

List<String> _headerProblems(
  String name,
  String part,
  Map<String, List<String>> headers,
  CredentialNames names,
) => [
  for (final MapEntry(key: header, value: values) in headers.entries)
    for (final value in values)
      if (header == 'set-cookie'
          ? !_cookieValueRedacted(value)
          : names.isSensitive(header)
          ? value != redactedValue
          : names.unredactedInText(value).isNotEmpty)
        '$name: $part.headers.$header is not redacted',
];

/// `名稱=***; 屬性`（`redactSetCookie` 的輸出）或整個 `***`。
bool _cookieValueRedacted(String value) {
  if (value == redactedValue) return true;
  final pair = value.split(';').first;
  final equals = pair.indexOf('=');
  return equals > 0 && pair.substring(equals + 1).trim() == redactedValue;
}

/// log 裡沒遮的憑證（兩道檢查）：訊息、error、stackTrace 與結構化欄位。
List<String> inspectLog(
  Iterable<LogRecord> records,
  Redactor redactor,
  CredentialNames names,
) => [
  for (final (index, record) in records.indexed)
    for (final problem in [
      for (final (part, text) in [
        ('message', record.message),
        ('error', record.error),
        ('stackTrace', record.stackTrace),
      ])
        if (text != null) ...[
          if (redactor.redact(text) != text)
            '$part changes when redacted again',
          for (final key in names.unredactedInText(text))
            '$part has an unredacted "$key"',
        ],
      if (jsonEncode(redactor.redactValue(record.fields)) !=
          jsonEncode(record.fields))
        'fields change when redacted again',
      for (final path in names.unredactedInJson(record.fields, 'fields'))
        '$path is not redacted',
    ])
      'log record #${index + 1} (${record.tag}): $problem',
];

/// 串流候選的 headers 不得帶憑證（ADR 0012：媒體請求不帶憑證）。M1 還沒有
/// 媒體 client，所以直接看插件回傳的 headers：名單上的 header，或值裡有
/// 會被遮蔽的內容。
List<String> mediaHeaderProblems(
  List<StreamCandidate> candidates,
  Redactor redactor,
  CredentialNames names,
) => [
  for (final (index, candidate) in candidates.indexed)
    for (final MapEntry(key: name, :value) in candidate.headers.entries)
      if (names.isSensitive(name) ||
          redactor.redact('$name: $value') != '$name: $value')
        'candidate #${index + 1}: header "$name" carries a credential; media '
            'requests must not (ADR 0012)',
];
