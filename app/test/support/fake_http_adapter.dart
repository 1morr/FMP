import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 假的 dio 最底層 adapter：不聯網，每個請求交給 [handler] 回應，並記下
/// 送到這一層時的 [RequestOptions]（攔截器都跑完之後的樣子）。
final class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  /// 送到 adapter 的請求，依序。
  final requests = <RequestOptions>[];

  final _waiting = <({int count, Completer<void> reached})>[];

  /// 第 [count] 個請求送到這一層（[handler] 已經叫過）時完成；已經送到就立刻完成。
  ///
  /// 請求要先經過事件迴圈以外的進度（drift 的背景 isolate、檔案 I/O）才到得了這裡時用它等，
  /// 不用 `pumpUntil` 數輪數：負載下那邊多慢都和主 isolate 跑了幾輪無關。等不到就是
  /// 測試逾時。
  Future<void> received(int count) {
    if (requests.length >= count) return Future.value();
    final reached = Completer<void>();
    _waiting.add((count: count, reached: reached));
    return reached.future;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final FutureOr<ResponseBody> response;
    try {
      response = handler(options);
    } finally {
      _waiting.removeWhere((waiting) {
        if (requests.length < waiting.count) return false;
        waiting.reached.complete();
        return true;
      });
    }
    return response;
  }

  @override
  void close({bool force = false}) {}
}

/// 一個回應。[headers] 的名稱照 HTTP 慣例寫，這裡轉成小寫（dart:io 的
/// adapter 也給小寫）。
ResponseBody reply(
  int status, {
  String body = '',
  Map<String, String> headers = const {},
  Map<String, List<String>> multiHeaders = const {},
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    for (final MapEntry(:key, :value) in headers.entries)
      key.toLowerCase(): [value],
    for (final MapEntry(:key, :value) in multiHeaders.entries)
      key.toLowerCase(): value,
  },
);

/// 轉址到 [location]。
ResponseBody redirect(String location, {int status = 302}) =>
    reply(status, headers: {'Location': location});
