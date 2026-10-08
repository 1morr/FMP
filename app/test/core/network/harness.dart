import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';

import '../../support/credentials.dart';
import '../../support/fake_http_adapter.dart';

const pluginId = 'test-source';
const allowedHosts = ['example.test', 'cdn.example'];

/// 可以設定的假認證來源。
final class FakeCredentials implements CredentialSource {
  FakeCredentials({
    this.cookies,
    this.headers = const {},
    this.invalidatedCookies = const {},
    this.browseAsLoggedInValue = true,
  });

  /// `null`＝未登入。
  final Map<String, String>? cookies;

  /// 憑證附加的標頭（憑證不是 cookie 的音源）。
  final Map<String, String> headers;

  /// 已失效的憑證：不帶，但名稱照樣回報（jar 仍不准送出）。
  final Map<String, String> invalidatedCookies;
  final bool browseAsLoggedInValue;

  @override
  Future<CredentialMaterial?> credentialMaterial(String pluginId) async =>
      cookies == null ? null : (cookies: cookies!, headers: headers);

  @override
  Future<Set<String>> credentialCookieNames(String pluginId) async => {
    ...?cookies?.keys,
    ...invalidatedCookies.keys,
  };

  @override
  Future<bool> browseAsLoggedIn(String pluginId) async => browseAsLoggedInValue;
}

/// 一個 client 加上它的假 adapter、假時鐘與 log。等待立刻完成並把時鐘
/// 往前撥；[waits] 記下每次等了多久，[outcomes] 記下回報給網路狀態的結果。
final class Harness {
  Harness(
    FutureOr<ResponseBody> Function(RequestOptions options) handler, {
    CredentialSource credentials = const NoCredentials(),
    RetryPolicy retryPolicy = const RetryPolicy(),
    RateLimitPolicy? rateLimitPolicy,
    LogFile? logFile,
  }) : adapter = FakeHttpAdapter(handler) {
    log = Log(
      redactor: Redactor(),
      minimumLevel: LogLevel.debug,
      file: logFile,
    );
    client =
        SourceHttpClientFactory(
          log: log,
          reportOutcome: outcomes.add,
          credentials: credentials,
          createAdapter: () => adapter,
          now: () => now,
          wait: (duration) async {
            waits.add(duration);
            now = now.add(duration);
          },
          random: math.Random(7),
        ).create(
          pluginId: pluginId,
          allowedHosts: allowedHosts,
          retryPolicy: retryPolicy,
          rateLimitPolicy: rateLimitPolicy,
        );
  }

  final FakeHttpAdapter adapter;
  late final Log log;
  late final SourceHttpClient client;
  DateTime now = DateTime.utc(2026, 9, 29, 12);
  final waits = <Duration>[];
  final outcomes = <RequestOutcome>[];

  Future<SourceResponse> get(
    String url, {
    Map<String, String> headers = const {},
    AuthRequirement auth = AuthRequirement.never,
    Map<String, String> authHeaders = const {},
    Future<void>? abortTrigger,
  }) => client.send(
    SourceRequest(
      Uri.parse(url),
      headers: headers,
      auth: auth,
      authHeaders: authHeaders,
    ),
    abortTrigger: abortTrigger,
  );

  /// 網路紀錄（tag `network`），由舊到新。
  List<LogRecord> get records => [
    for (final record in log.history)
      if (record.tag == networkLogTag) record,
  ];
}

/// 一個媒體 client 加上它的假 adapter 與 log；[outcomes] 記下回報給網路狀態
/// 的結果。時間是 `clock`（`fakeAsync`、`withClock` 改得到）。
final class MediaHarness {
  MediaHarness(
    FutureOr<ResponseBody> Function(RequestOptions options) handler, {
    LogFile? logFile,
  }) : adapter = FakeHttpAdapter(handler) {
    log = Log(
      redactor: Redactor(),
      minimumLevel: LogLevel.debug,
      file: logFile,
    );
    client = MediaHttpClientFactory(
      log: log,
      reportOutcome: outcomes.add,
      createAdapter: () => adapter,
    ).create(pluginId: pluginId, allowedHosts: allowedHosts);
  }

  final FakeHttpAdapter adapter;
  late final Log log;
  late final MediaHttpClient client;
  final outcomes = <RequestOutcome>[];

  Future<MediaDownload> download(
    String url, {
    required File to,
    int maxBytes = 1024,
    Map<String, String> headers = const {},
    Future<void>? abortTrigger,
  }) => client.download(
    Uri.parse(url),
    destination: to,
    maxBytes: maxBytes,
    headers: headers,
    abortTrigger: abortTrigger,
  );

  /// 網路紀錄（tag `network`），由舊到新。
  List<LogRecord> get records => [
    for (final record in log.history)
      if (record.tag == networkLogTag) record,
  ];
}

/// 內容由 [body] 送出的回應。dio 不再讀它（取消）時 [body] 的 `onCancel`
/// 會被叫到。
ResponseBody streamed(
  StreamController<Uint8List> body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => ResponseBody(
  body.stream,
  status,
  headers: {
    for (final MapEntry(:key, :value) in headers.entries)
      key.toLowerCase(): [value],
  },
);
