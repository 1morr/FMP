import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fmp/core/errors/retry_policy.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';

import '../../support/fake_http_adapter.dart';

const pluginId = 'test-source';
const allowedHosts = ['example.test', 'cdn.example'];

/// 可以設定的假認證來源。
final class FakeCredentials implements CredentialSource {
  FakeCredentials({this.headers, this.browseAsLoggedInValue = true});

  /// `null`＝未登入。
  final Map<String, String>? headers;
  final bool browseAsLoggedInValue;

  @override
  Future<Map<String, String>?> credentialHeaders(String pluginId) async =>
      headers;

  @override
  Future<bool> browseAsLoggedIn(String pluginId) async => browseAsLoggedInValue;
}

/// 一個 client 加上它的假 adapter、假時鐘與 log。等待立刻完成並把時鐘
/// 往前撥；[waits] 記下每次等了多久。
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

  Future<SourceResponse> get(
    String url, {
    Map<String, String> headers = const {},
    AuthRequirement auth = AuthRequirement.never,
    Future<void>? abortTrigger,
  }) => client.send(
    SourceRequest(Uri.parse(url), headers: headers, auth: auth),
    abortTrigger: abortTrigger,
  );

  /// 網路紀錄（tag `network`），由舊到新。
  List<LogRecord> get records => [
    for (final record in log.history)
      if (record.tag == networkLogTag) record,
  ];
}
