import 'dart:convert';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/json_shape.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

// checks.json：每插件每能力最多一條檢查案例（ADR 0015 §決定 4）。檔案是一個
// 物件，鍵是能力名稱，所以「最多一條」由格式本身保證。能寫案例的能力只有
// SourcePlugin 已有方法的那些（M1 是 search、resolveStream）；其他能力的鍵是
// 不認得的欄位，整個檔案拒收。
//
// 形狀與 `lib/plugins/types/fmp-plugin.d.ts` 的 `FmpChecks` 等一致
// （test/plugins/type_definitions_test.dart 比對）。

/// checks.json 的欄位表，鍵是 `fmp-plugin.d.ts` 裡的 interface 名稱。
const checkShapes = <String, JsonShape>{
  'FmpChecks': {'search': false, 'resolveStream': false},
  'FmpSearchCheck': {'input': true, 'expect': true},
  'FmpResolveStreamCheck': {'input': true, 'expect': true},
  'FmpExpectSuccess': {'minItems': false, 'nonEmpty': false},
  'FmpExpectError': {'error': true, 'reason': false},
};

/// 每個能力的案例形狀與回傳清單裡一筆的 DTO。
const _capabilities = {
  PluginCapability.search: (check: 'FmpSearchCheck', item: 'TrackSummary'),
  PluginCapability.resolveStream: (
    check: 'FmpResolveStreamCheck',
    item: 'StreamCandidate',
  ),
};

/// 一條檢查案例。
final class PluginCheck {
  const PluginCheck(this.capability, this.input, this.expectation);

  final PluginCapability capability;

  /// [SearchQuery] 或 [StreamRequest]。
  final Object input;
  final CheckExpectation expectation;

  /// 以 [plugin] 執行這個案例。
  Future<Object> run(SourcePlugin plugin) => switch (input) {
    final SearchQuery query => plugin.search(query),
    final StreamRequest request => plugin.resolveStream(request),
    _ => throw StateError('No host method for ${capability.wireName}'),
  };
}

/// 解析 checks.json；格式不對拋 [FormatException]。
List<PluginCheck> parseChecks(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (error) {
    throw FormatException('checks.json: not JSON (${error.message})');
  }
  final fields = JsonFields(json, checkShapes['FmpChecks']!, path: 'checks');
  return [
    for (final MapEntry(key: capability, value: (:check, :item))
        in _capabilities.entries)
      if (fields.has(capability.wireName))
        _check(
          capability,
          JsonFields(
            fields.raw(capability.wireName),
            checkShapes[check]!,
            path: 'checks.${capability.wireName}',
          ),
          item,
        ),
  ];
}

PluginCheck _check(
  PluginCapability capability,
  JsonFields fields,
  String item,
) {
  final path = fields.path;
  try {
    return PluginCheck(capability, switch (capability) {
      PluginCapability.search => _searchQuery(fields.raw('input'), path),
      _ => _streamRequest(fields.raw('input'), path),
    }, _expectation(fields.raw('expect'), '$path.expect', item));
  } on ArgumentError catch (error) {
    throw FormatException('$path.input: ${error.message}');
  }
}

SearchQuery _searchQuery(Object? json, String path) {
  final fields = JsonFields(
    json,
    sourceDtoShapes['SearchQuery']!,
    path: '$path.input',
  );
  return SearchQuery(
    keyword: fields.string('keyword'),
    page: fields.integer('page', min: 1),
  );
}

StreamRequest _streamRequest(Object? json, String path) {
  final fields = JsonFields(
    json,
    sourceDtoShapes['StreamRequest']!,
    path: '$path.input',
  );
  final purpose = fields.string('purpose');
  return StreamRequest(
    sourceId: fields.string('sourceId'),
    cid: fields.optionalInteger('cid'),
    purpose: StreamPurpose.values.firstWhere(
      (value) => value.wireName == purpose,
      orElse: () =>
          throw FormatException('$path.input.purpose: unknown "$purpose"'),
    ),
    formats: [
      for (final (index, format) in fields.list('formats').indexed)
        _streamFormat(format, '$path.input.formats[$index]'),
    ],
  );
}

StreamFormat _streamFormat(Object? json, String path) {
  final fields = JsonFields(json, sourceDtoShapes['StreamFormat']!, path: path);
  return StreamFormat(
    container: fields.string('container'),
    codec: fields.string('codec'),
  );
}

CheckExpectation _expectation(Object? json, String path, String item) {
  if (json case {'error': _}) {
    final fields = JsonFields(json, checkShapes['FmpExpectError']!, path: path);
    final error = fields.string('error');
    // 認得的名稱轉出來就是同名的類別；不認得的會變成 UnexpectedError。
    if (structuredScriptError(
          pluginId: 'checks',
          fmpError: error,
          reason: 'region',
        ).typeName !=
        error) {
      throw FormatException('$path.error: unknown error "$error"');
    }
    final reason = fields.optionalString('reason');
    if (reason != null && error != 'Unavailable') {
      throw FormatException('$path.reason: only Unavailable has a reason');
    }
    return ExpectError(
      error,
      reason: reason == null
          ? null
          : UnavailableReason.values.firstWhere(
              (value) => unavailableReasonWireName(value) == reason,
              orElse: () =>
                  throw FormatException('$path.reason: unknown "$reason"'),
            ),
    );
  }
  final fields = JsonFields(json, checkShapes['FmpExpectSuccess']!, path: path);
  final nonEmpty = fields.optionalStringList('nonEmpty') ?? const [];
  for (final name in nonEmpty) {
    if (!sourceDtoShapes[item]!.containsKey(name)) {
      throw FormatException('$path.nonEmpty: $item has no field "$name"');
    }
  }
  return ExpectSuccess(
    minItems: fields.optionalInteger('minItems') ?? 0,
    nonEmpty: nonEmpty,
  );
}

/// 案例的期望。
sealed class CheckExpectation {
  const CheckExpectation();

  /// 比對結果：成功時 [result] 是能力的回傳值，失敗時 [error] 是丟出的錯誤，
  /// [describe] 把錯誤寫成一行（含遮蔽過的原因）。回傳不符之處。
  List<String> evaluate({
    Object? result,
    AppError? error,
    required String Function(AppError error) describe,
  });
}

/// 成功，回傳的清單（search 的 `items`、resolveStream 的 `candidates`）至少
/// [minItems] 筆，每一筆的 [nonEmpty] 欄位都有值。
final class ExpectSuccess extends CheckExpectation {
  const ExpectSuccess({required this.minItems, required this.nonEmpty});

  final int minItems;
  final List<String> nonEmpty;

  @override
  List<String> evaluate({
    Object? result,
    AppError? error,
    required String Function(AppError error) describe,
  }) {
    if (error != null) return ['expected success, got ${describe(error)}'];
    final items = checkItems(result!);
    return [
      if (items.length < minItems)
        'expected at least $minItems items, got ${items.length}',
      for (final (index, item) in items.indexed)
        for (final name in nonEmpty)
          if (_isEmpty(item[name])) 'item $index: "$name" is empty',
    ];
  }

  static bool _isEmpty(Object? value) => switch (value) {
    null => true,
    final String text => text.trim().isEmpty,
    final Iterable<Object?> items => items.isEmpty,
    final Map<Object?, Object?> map => map.isEmpty,
    _ => false,
  };
}

/// 以 [error] 這個 `AppError` 類別失敗；`Unavailable` 可以另外指定 [reason]。
final class ExpectError extends CheckExpectation {
  const ExpectError(this.error, {this.reason});

  final String error;
  final UnavailableReason? reason;

  @override
  List<String> evaluate({
    Object? result,
    AppError? error,
    required String Function(AppError error) describe,
  }) {
    final expected = reason == null
        ? this.error
        : '${this.error} (${unavailableReasonWireName(reason!)})';
    if (error == null) return ['expected $expected, but the call succeeded'];
    final matches =
        error.typeName == this.error &&
        (reason == null || error is Unavailable && error.reason == reason);
    return matches ? const [] : ['expected $expected, got ${describe(error)}'];
  }
}

/// 回傳值裡要檢查的清單，每一筆以 `fmp-plugin.d.ts` 的欄位名稱表示。
List<Map<String, Object?>> checkItems(Object result) => switch (result) {
  final SearchPage page => [for (final track in page.items) trackFields(track)],
  final StreamResult stream => [
    for (final candidate in stream.candidates) candidateFields(candidate),
  ],
  _ => throw ArgumentError.value(result, 'result'),
};

/// [TrackSummary] 的欄位，名稱同 `sourceDtoShapes['TrackSummary']`。
Map<String, Object?> trackFields(TrackSummary track) => {
  'sourceId': track.sourceId,
  'cid': track.cid,
  'title': track.title,
  'uploader': track.uploader,
  'durationMs': track.duration?.inMilliseconds,
  'artwork': track.artwork,
};

/// [StreamCandidate] 的欄位，名稱同 `sourceDtoShapes['StreamCandidate']`。
Map<String, Object?> candidateFields(StreamCandidate candidate) => {
  'url': candidate.url.toString(),
  'headers': candidate.headers,
  'container': candidate.container,
  'codec': candidate.codec,
  'bitrate': candidate.bitrate,
  'expiresAt': candidate.expiresAt?.millisecondsSinceEpoch,
};
