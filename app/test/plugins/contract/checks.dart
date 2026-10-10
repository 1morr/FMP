import 'dart:convert';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/stream_preferences.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/json_shape.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

// checks.json：每插件每能力最多一條檢查案例（ADR 0015 §決定 4）。檔案是一個
// 物件，鍵是能力名稱，所以「最多一條」由格式本身保證。能寫案例的能力只有
// SourcePlugin 已有方法的那些（search、resolveStream，login 跑 loginVerify）；
// 其他能力的鍵是不認得的欄位，整個檔案拒收。
//
// 形狀與 `lib/plugins/types/fmp-plugin.d.ts` 的 `FmpChecks` 等一致
// （test/plugins/type_definitions_test.dart 比對）。

/// checks.json 的欄位表，鍵是 `fmp-plugin.d.ts` 裡的 interface 名稱。
const checkShapes = <String, JsonShape>{
  'FmpChecks': {'search': false, 'resolveStream': false, 'login': false},
  'FmpSearchCheck': {'input': true, 'expect': true},
  'FmpResolveStreamCheck': {
    'input': true,
    'expect': true,
    'expiresAtPattern': false,
  },
  'FmpLoginCheck': {'input': true, 'expect': true, 'requiresLogin': true},
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
  PluginCapability.login: (check: 'FmpLoginCheck', item: 'LoginAccount'),
};

/// 一條檢查案例。
final class PluginCheck {
  const PluginCheck(
    this.capability,
    this.input,
    this.expectation, {
    this.expiresAtPattern,
    this.requiresLogin = false,
  });

  final PluginCapability capability;

  /// [SearchQuery]、[StreamRequest] 或 [LoginCredentials]（login 的 `loginVerify`）。
  final Object input;
  final CheckExpectation expectation;

  /// 案例要登入才有意義（design §4.8）：重播照跑，命令列錄製略過。
  final bool requiresLogin;

  /// resolveStream：網址裡的期限（[expiresAtProblems]）。
  final RegExp? expiresAtPattern;

  /// 期望之外要核對的：[expiresAtPattern] 給了就逐一核對 [result] 的候選。
  /// 回傳不符之處。
  List<String> extraProblems(Object? result) =>
      switch ((expiresAtPattern, result)) {
        (final RegExp pattern, final StreamResult stream) => expiresAtProblems(
          pattern,
          stream.candidates,
        ),
        _ => const [],
      };

  /// 以 [plugin] 執行這個案例。
  Future<Object> run(SourcePlugin plugin) => switch (input) {
    final SearchQuery query => plugin.search(query),
    final StreamRequest request => plugin.resolveStream(request),
    final LoginCredentials credentials => plugin.loginVerify(credentials),
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
  final Object input;
  try {
    input = switch (capability) {
      PluginCapability.search => _searchQuery(fields.raw('input'), path),
      PluginCapability.login => _credentials(fields.raw('input'), path),
      _ => _streamRequest(fields.raw('input'), path),
    };
  } on ArgumentError catch (error) {
    throw FormatException('$path.input: ${error.message}');
  }
  if (capability == PluginCapability.login &&
      fields.optionalBool('requiresLogin') != true) {
    throw FormatException('$path.requiresLogin: must be true');
  }
  final expectation = _expectation(fields.raw('expect'), '$path.expect', item);
  final pattern = fields.optionalString('expiresAtPattern');
  if (pattern != null && expectation is! ExpectSuccess) {
    throw FormatException(
      '$path.expiresAtPattern: only a successful expect has candidates',
    );
  }
  return PluginCheck(
    capability,
    input,
    expectation,
    expiresAtPattern: pattern == null
        ? null
        : _expiresAtPattern(pattern, '$path.expiresAtPattern'),
    requiresLogin: capability == PluginCapability.login,
  );
}

LoginCredentials _credentials(Object? json, String path) {
  try {
    return LoginCredentials.fromJson(json);
  } on FormatException catch (error) {
    throw FormatException('$path.input: ${error.message}');
  }
}

/// 剛好一個擷取群組的正規式。
RegExp _expiresAtPattern(String source, String path) {
  final RegExp pattern;
  try {
    pattern = RegExp(source);
  } on FormatException catch (error) {
    throw FormatException('$path: not a regular expression (${error.message})');
  }
  // 加一個空的分支一定比對得到，才數得出群組數。
  final groups = RegExp('$source|').firstMatch('')!.groupCount;
  if (groups != 1) {
    throw FormatException(
      '$path: needs exactly one capture group, has $groups',
    );
  }
  return pattern;
}

/// 每個網址對得上 [pattern] 的候選，`expiresAt` 都要等於擷取到的 unix 秒；
/// 至少要有一個候選對得上，否則這條檢查什麼也沒核對到（例如 fixture 裡的
/// 期限參數被遮掉了）。回傳不符之處。
List<String> expiresAtProblems(
  RegExp pattern,
  List<StreamCandidate> candidates,
) {
  final problems = <String>[];
  var checked = 0;
  for (final (index, candidate) in candidates.indexed) {
    final match = pattern.firstMatch(candidate.url.toString());
    if (match == null) continue;
    checked++;
    final seconds = int.tryParse(match[1] ?? '');
    // DateTime 的上限是 8.64e15 毫秒：超過的不是時間。
    final expected = seconds == null || seconds > 8640000000000
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    if (expected == null) {
      problems.add(
        'candidate $index: expiresAtPattern captured "${match[1]}", '
        'not unix seconds',
      );
    } else if (candidate.expiresAt?.isAtSameMomentAs(expected) != true) {
      problems.add(
        'candidate $index: expiresAt is ${candidate.expiresAt?.toUtc()}, '
        'the URL says $expected',
      );
    }
  }
  if (checked == 0) {
    problems.add('expiresAtPattern matched no candidate URL');
  }
  return problems;
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
  final quality = fields.optionalString('quality');
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
    quality: quality == null
        ? null
        : AudioQuality.values.firstWhere(
            (value) => audioQualityWireName(value) == quality,
            orElse: () => throw FormatException(
              '$path.input.quality: unknown "$quality"',
            ),
          ),
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
  final LoginAccount account => [accountFields(account)],
  _ => throw ArgumentError.value(result, 'result'),
};

/// [LoginAccount] 的欄位，名稱同 `sourceDtoShapes['LoginAccount']`。
Map<String, Object?> accountFields(LoginAccount account) => {
  'userId': account.userId,
  'displayName': account.displayName,
  'avatar': account.avatar,
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
