import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/json_shape.dart';

// fixture：一次 HTTP 請求與它的回應，一個 JSON 檔（ADR 0015 §決定 5）。欄位名稱
// 沿用 WireMock stub mapping（`request.method`／`url`、`response.status`／
// `headers`／`body`／`jsonBody`），外層加 `meta`。檔案在插件目錄的
// `fixtures/<能力>/`，依檔名排序就是請求的順序。
//
// 形狀與 `lib/plugins/types/fmp-plugin.d.ts` 的 `FmpFixture*` 一致
// （test/plugins/type_definitions_test.dart 比對）。

/// fixture 的欄位表，鍵是 `fmp-plugin.d.ts` 裡的 interface 名稱。
const fixtureShapes = <String, JsonShape>{
  'FmpFixture': {'meta': true, 'request': true, 'response': true},
  'FmpFixtureMeta': {'recordedAt': false, 'edited': false},
  'FmpFixtureRequest': {
    'method': true,
    'url': true,
    'headers': false,
    'body': false,
  },
  'FmpFixtureResponse': {
    'status': true,
    'headers': false,
    'body': false,
    'jsonBody': false,
  },
};

/// 錄製時不留的回應 header（名稱小寫）：body 已經解碼、遮蔽後重新編碼，長度
/// 與編碼都不再是原本的。
const droppedResponseHeaders = {
  'content-length',
  'content-encoding',
  'transfer-encoding',
};

/// 一個 fixture 檔。
final class HttpFixture {
  const HttpFixture({
    this.recordedAt,
    this.edited,
    required this.request,
    required this.response,
  });

  /// 解碼一個 fixture 檔的 JSON；形狀不對拋 [FormatException]。
  factory HttpFixture.fromJson(Object? json) {
    final fields = JsonFields(
      json,
      fixtureShapes['FmpFixture']!,
      path: 'fixture',
    );
    final meta = JsonFields(
      fields.raw('meta'),
      fixtureShapes['FmpFixtureMeta']!,
      path: 'fixture.meta',
    );
    final recordedAt = meta.optionalString('recordedAt');
    if (recordedAt != null && DateTime.tryParse(recordedAt) == null) {
      throw const FormatException('fixture.meta.recordedAt: not ISO 8601');
    }
    return HttpFixture(
      recordedAt: recordedAt,
      edited: meta.optionalString('edited'),
      request: FixtureRequest._fromJson(fields.raw('request')),
      response: FixtureResponse._fromJson(fields.raw('response')),
    );
  }

  /// 錄製時間（ISO 8601，UTC）；手寫的是 `null`。
  final String? recordedAt;

  /// 手寫或手改的理由。有它的案例，錄製模式不覆蓋。
  final String? edited;

  final FixtureRequest request;
  final FixtureResponse response;

  Map<String, Object?> toJson() => {
    'meta': {'recordedAt': ?recordedAt, 'edited': ?edited},
    'request': request.toJson(),
    'response': response.toJson(),
  };

  /// 寫檔的內容：兩格縮排、結尾換行。
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// 經正式的遮蔽函式（ADR 0011 §決定 3）後的 fixture。錄製寫檔前一律經過它；
  /// fixture 掃描以「再遮一次結果不變」確認檔案已經遮過。
  ///
  /// - 網址、request body、文字的 response body：`Redactor.redact`；
  /// - header：`Redactor.redactValue({名稱: 值})`，名單上的 header 整個換成
  ///   `***`；`set-cookie` 例外，只換每個 cookie 的值（`名稱=***; 屬性`），重播
  ///   時 cookie 管理才解析得了；
  /// - `jsonBody`：`Redactor.redactValue`，鍵在名單上的值整個換成 `***`，結果
  ///   仍是合法的 JSON。
  HttpFixture redacted(Redactor redactor) => HttpFixture(
    recordedAt: recordedAt,
    edited: edited,
    request: FixtureRequest(
      method: request.method,
      url: redactor.redact(request.url),
      headers: {
        for (final MapEntry(:key, :value) in request.headers.entries)
          key: _redactHeader(redactor, key, value),
      },
      body: switch (request.body) {
        null => null,
        final body => redactor.redact(body),
      },
    ),
    response: FixtureResponse(
      status: response.status,
      headers: {
        for (final MapEntry(:key, :value) in response.headers.entries)
          key: [for (final item in value) _redactHeader(redactor, key, item)],
      },
      body: switch (response.body) {
        null => null,
        final body => redactor.redact(body),
      },
      jsonBody: switch (response.jsonBody) {
        null => null,
        final json => redactor.redactValue(json),
      },
    ),
  );
}

String _redactHeader(Redactor redactor, String name, String value) {
  if (name == 'set-cookie') return redactSetCookie(redactor, value);
  final redacted = redactor.redactValue({name: value})! as Map;
  return redacted.values.single as String;
}

/// `名稱=值; 屬性` 的值換成 `***`，名稱與屬性經 `Redactor.redact`。
String redactSetCookie(Redactor redactor, String value) {
  final end = value.indexOf(';');
  final pair = end < 0 ? value : value.substring(0, end);
  final attributes = end < 0 ? '' : value.substring(end);
  final equals = pair.indexOf('=');
  final name = equals < 0 ? '' : pair.substring(0, equals).trim();
  if (name.isEmpty) return redactedValue;
  return '${redactor.redact(name)}=$redactedValue'
      '${redactor.redact(attributes)}';
}

/// fixture 的請求。
final class FixtureRequest {
  const FixtureRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
  });

  factory FixtureRequest._fromJson(Object? json) {
    final fields = JsonFields(
      json,
      fixtureShapes['FmpFixtureRequest']!,
      path: 'fixture.request',
    );
    final url = fields.string('url');
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) {
      throw const FormatException('fixture.request.url: not an absolute URL');
    }
    return FixtureRequest(
      method: fields.nonEmptyString('method'),
      url: url,
      headers: {
        for (final MapEntry(:key, :value)
            in (fields.optionalStringMap('headers') ?? {}).entries)
          key.toLowerCase(): value,
      },
      body: fields.optionalString('body'),
    );
  }

  final String method;

  /// 送出的網址（遮蔽過）。比對見 [fixtureUrlMatches]。
  final String url;

  /// 只供閱讀，不參與比對。名稱小寫。
  final Map<String, String> headers;

  /// 只供閱讀，不參與比對。
  final String? body;

  Map<String, Object?> toJson() => {
    'method': method,
    'url': url,
    if (headers.isNotEmpty) 'headers': _sorted(headers),
    'body': ?body,
  };
}

/// fixture 的回應。
final class FixtureResponse {
  const FixtureResponse({
    required this.status,
    this.headers = const {},
    this.body,
    this.jsonBody,
  }) : assert(body == null || jsonBody == null);

  factory FixtureResponse._fromJson(Object? json) {
    final fields = JsonFields(
      json,
      fixtureShapes['FmpFixtureResponse']!,
      path: 'fixture.response',
    );
    final jsonBody = fields.raw('jsonBody');
    if (jsonBody != null && jsonBody is! Map && jsonBody is! List) {
      throw const FormatException(
        'fixture.response.jsonBody: expected an object or an array',
      );
    }
    final body = fields.optionalString('body');
    if (body != null && jsonBody != null) {
      throw const FormatException(
        'fixture.response: body and jsonBody are mutually exclusive',
      );
    }
    return FixtureResponse(
      status: fields.integer('status', min: 100),
      headers: _headerLists(fields.optionalObject('headers') ?? {}),
      body: body,
      jsonBody: jsonBody,
    );
  }

  final int status;

  /// 名稱小寫。
  final Map<String, List<String>> headers;

  /// 文字的 body。
  final String? body;

  /// JSON 的 body（物件或陣列），重播時編碼成緊湊的 JSON 文字。
  final Object? jsonBody;

  /// 交給 dio 的回應。
  ResponseBody toResponseBody() => ResponseBody.fromString(
    switch (jsonBody) {
      null => body ?? '',
      final json => jsonEncode(json),
    },
    status,
    headers: headers,
  );

  Map<String, Object?> toJson() => {
    'status': status,
    if (headers.isNotEmpty) 'headers': _sorted(headers),
    'body': ?body,
    'jsonBody': ?jsonBody,
  };
}

Map<String, List<String>> _headerLists(Map<String, Object?> json) => {
  for (final MapEntry(:key, :value) in json.entries)
    key.toLowerCase(): switch (value) {
      final List<Object?> items when items.every((item) => item is String) =>
        items.cast<String>(),
      _ => throw FormatException(
        'fixture.response.headers.$key: expected an array of strings',
      ),
    },
};

Map<String, T> _sorted<T>(Map<String, T> map) => {
  for (final key in map.keys.toList()..sort()) key: map[key] as T,
};

/// 重播的比對（ADR 0015 §決定 5）：scheme、host、port、路徑與 query 相同；
/// query 不分順序（Polly.js、VCR 的做法）。[fixture] 裡值是 `***` 的 query
/// 參數與路徑段是遮蔽過的欄位，不比對值，只要求它存在。
///
/// 呼叫端先以同一個遮蔽函式遮過 [actual]：遮蔽會拿掉的簽名參數兩邊都不會有。
bool fixtureUrlMatches(Uri fixture, Uri actual) {
  if (fixture.scheme.toLowerCase() != actual.scheme.toLowerCase() ||
      fixture.host.toLowerCase() != actual.host.toLowerCase() ||
      fixture.port != actual.port) {
    return false;
  }
  final expectedPath = fixture.pathSegments;
  final actualPath = actual.pathSegments;
  if (expectedPath.length != actualPath.length) return false;
  for (var i = 0; i < expectedPath.length; i++) {
    if (expectedPath[i] != redactedValue && expectedPath[i] != actualPath[i]) {
      return false;
    }
  }
  final expectedQuery = fixture.queryParametersAll;
  final actualQuery = actual.queryParametersAll;
  if (expectedQuery.length != actualQuery.length) return false;
  for (final MapEntry(key: name, value: expected) in expectedQuery.entries) {
    final values = [...?actualQuery[name]];
    if (values.length != expected.length) return false;
    for (final value in expected) {
      if (value == redactedValue) continue;
      if (!values.remove(value)) return false;
    }
  }
  return true;
}

/// 錯誤訊息用的網址寫法：query 解碼後依名稱、值排序（只給人看，不是合法的
/// 網址）。
String canonicalUrl(Uri uri) {
  final pairs = [
    for (final MapEntry(key: name, value: values)
        in uri.queryParametersAll.entries)
      for (final value in values) (name, value),
  ]..sort((a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
  final query = [for (final (name, value) in pairs) '$name=$value'].join('&');
  return '${uri.scheme}://${uri.authority}${uri.path}'
      '${query.isEmpty ? '' : '?$query'}';
}
