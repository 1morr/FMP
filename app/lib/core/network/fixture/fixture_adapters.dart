import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fmp/core/network/allowed_hosts.dart';
import 'package:fmp/core/redaction/redactor.dart';

import 'package:fmp/core/network/fixture/fixture.dart';
import 'package:fmp/core/network/fixture/ip_scrub.dart';

// 錄製與重播接在網路層最底部的 dio `HttpClientAdapter`
// （`SourceHttpClientFactory` 的 `createAdapter`，ADR 0015 §決定 5）：攔截器
// 全部照常執行，只有真正送出這一步換掉。

/// fixture 檔與它的檔名（錯誤訊息用）。
typedef NamedFixture = ({String name, HttpFixture fixture});

/// 重播：第 n 個請求必須對上第 n 個 fixture（method 與 [fixtureUrlMatches]），
/// 對上就回它的回應；對不上、或 fixture 用完了，記進 [problems] 並讓這次請求
/// 失敗，不發真實請求。
final class ReplayAdapter implements HttpClientAdapter {
  ReplayAdapter(this._fixtures, this._redactor, this._allowedHosts);

  final List<NamedFixture> _fixtures;
  final Redactor _redactor;
  final AllowedHosts _allowedHosts;
  int _next = 0;

  /// 比對不到的請求、送到網域清單外的請求。
  final problems = <String>{};

  /// 沒被請求用到的 fixture。
  List<String> get unused => [
    for (final (:name, fixture: _) in _fixtures.skip(_next)) name,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final number = _next + 1;
    // 網路層已經擋過；這裡再看一次，擋不住的話契約測試會說出來。
    if (!_allowedHosts.allows(options.uri)) {
      problems.add(
        'request #$number went to ${options.uri.host}, outside '
        'allowedHosts',
      );
    }
    final actual = Uri.parse(_redactor.redact(options.uri.toString()));
    final described = '${options.method} ${canonicalUrl(actual)}';
    if (_next >= _fixtures.length) {
      return _mismatch('request #$number ($described) has no fixture left');
    }
    final (:name, :fixture) = _fixtures[_next];
    final expected = Uri.parse(fixture.request.url);
    if (fixture.request.method != options.method ||
        !fixtureUrlMatches(expected, actual)) {
      return _mismatch(
        'request #$number ($described) does not match $name '
        '(${fixture.request.method} ${canonicalUrl(expected)})',
      );
    }
    _next++;
    return fixture.response.toResponseBody();
  }

  Never _mismatch(String problem) {
    problems.add(problem);
    // 不是 IOException：網路層把它當成非傳輸錯誤（UnexpectedError），不重試。
    throw StateError('No fixture: $problem');
  }

  @override
  void close({bool force = false}) {}
}

/// 錄製：請求交給 [_network]（真實連線或測試的假 adapter），回應原樣交回給
/// 插件，同時把遮蔽過的一份存進 [recorded]。
///
/// body 不是 UTF-8 時不錄（fixture 沒有二進位 body），記進 [problems]。
final class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this._network, this._redactor, {required this.now});

  final HttpClientAdapter _network;
  final Redactor _redactor;
  final DateTime Function() now;

  final recorded = <HttpFixture>[];
  final problems = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await _network.fetch(options, requestStream, cancelFuture);
    final builder = BytesBuilder(copy: false);
    await response.stream.forEach(builder.add);
    final bytes = builder.takeBytes();
    final String text;
    try {
      text = const Utf8Decoder().convert(bytes);
    } on FormatException {
      problems.add(
        '${options.method} ${options.uri.host}${options.uri.path} returned a '
        'body that is not UTF-8; fixtures only hold text',
      );
      return _copy(response, bytes);
    }
    final json = _json(text);
    recorded.add(
      scrubFixtureIps(
        HttpFixture(
          recordedAt: now().toUtc().toIso8601String(),
          request: FixtureRequest(
            method: options.method,
            url: options.uri.toString(),
            headers: {
              for (final MapEntry(:key, :value) in options.headers.entries)
                if (value != null) key.toLowerCase(): '$value',
            },
            body: switch (options.data) {
              final String body => body,
              _ => null,
            },
          ),
          response: FixtureResponse(
            status: response.statusCode,
            headers: {
              for (final MapEntry(:key, :value) in response.headers.entries)
                if (!droppedResponseHeaders.contains(key.toLowerCase()))
                  key.toLowerCase(): value,
            },
            body: json == null ? text : null,
            jsonBody: json,
          ),
        ).redacted(_redactor),
      ),
    );
    return _copy(response, bytes);
  }

  /// 物件或陣列的 JSON；其他文字是 `null`（存成 `body`）。
  static Object? _json(String text) {
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static ResponseBody _copy(ResponseBody response, Uint8List bytes) =>
      ResponseBody.fromBytes(
        bytes,
        response.statusCode,
        statusMessage: response.statusMessage,
        isRedirect: response.isRedirect,
        headers: response.headers,
      );

  @override
  void close({bool force = false}) => _network.close(force: force);
}

/// 一個案例送出請求的方式（ADR 0015 §決定 5、7）。每個案例建一個、只建一次 client：
/// `SourceHttpClientFactory(createAdapter: transport.createAdapter)`。
sealed class CaseTransport {
  HttpClientAdapter createAdapter();

  /// 比對不到、送到清單外、回應不是 UTF-8 等；空的就是沒有。
  List<String> get problems;
}

/// 重播：包 [ReplayAdapter]。
final class ReplayTransport extends CaseTransport {
  ReplayTransport._(this._adapter);

  final ReplayAdapter _adapter;

  @override
  HttpClientAdapter createAdapter() => _adapter;

  @override
  List<String> get problems => _adapter.problems.toList();

  /// 沒被請求用到的 fixture 名稱。
  List<String> get unused => _adapter.unused;
}

/// 真實連線；[record] 為真時包 [RecordingAdapter]。
final class NetworkTransport extends CaseTransport {
  NetworkTransport._(this._network, this._recorder);

  final HttpClientAdapter Function() _network;
  final RecordingAdapter? _recorder;

  @override
  HttpClientAdapter createAdapter() => _recorder ?? _network();

  @override
  List<String> get problems => _recorder?.problems ?? const [];

  /// 錄到的 fixture；[record] 為假時永遠是空的。
  List<HttpFixture> get recorded => _recorder?.recorded ?? const [];
}

/// 建 [CaseTransport]。真實連線的 adapter 來自 [network]，測試換成假上游。
final class CaseTransports {
  const CaseTransports({this.network = IOHttpClientAdapter.new});

  final HttpClientAdapter Function() network;

  ReplayTransport replay(
    List<NamedFixture> fixtures,
    Redactor redactor,
    AllowedHosts allowedHosts,
  ) => ReplayTransport._(ReplayAdapter(fixtures, redactor, allowedHosts));

  NetworkTransport real() => NetworkTransport._(network, null);

  NetworkTransport record(
    Redactor redactor, {
    DateTime Function() now = DateTime.now,
  }) => NetworkTransport._(
    network,
    RecordingAdapter(network(), redactor, now: now),
  );
}
