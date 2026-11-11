import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 假的回應；[headers] 的名稱用小寫。
class FakeResponse {
  const FakeResponse(this.status, [this.body = '', this.headers = const {}]);

  FakeResponse.json(Object json, {int status = 200})
    : this(status, jsonEncode(json), const {
        'content-type': ['application/json; charset=utf-8'],
      });

  final int status;
  final String body;
  final Map<String, List<String>> headers;
}

/// 換掉 dio 真正連網的那一層：每個請求交給 [handler]，記在 [requests]。
/// [handler] 丟出的 [DioException] 照原樣變成請求失敗，用來模擬連不上。
class FakeHttp implements HttpClientAdapter {
  FakeHttp(this.handler);

  final FutureOr<FakeResponse> Function(RequestOptions request) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = await handler(options);
    return ResponseBody.fromString(
      response.body,
      response.status,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}
