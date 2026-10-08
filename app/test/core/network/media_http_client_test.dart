import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/auth.dart';
import 'package:fmp/core/network/http_rules.dart';
import 'package:fmp/core/network/media_headers.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/core/network/source_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_http_adapter.dart';
import '../../support/pump_until.dart';
import 'harness.dart';

/// [future] 丟出的錯誤；沒丟就讓測試失敗。
Future<Object> errorOf(Future<Object?> future) async {
  try {
    await future;
  } on Object catch (error) {
    return error;
  }
  fail('expected an error');
}

Uint8List bytes(int count) => Uint8List(count);

void main() {
  late Directory temp;
  late File destination;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fmp_media_test');
    destination = File(p.join(temp.path, 'cover.jpg'));
    addTearDown(() => temp.delete(recursive: true));
  });

  /// 暫存目錄裡的檔名（下載失敗後應該什麼都沒有）。
  List<String> files() => [
    for (final entity in temp.listSync()) p.basename(entity.path),
  ];

  group('credentials (ADR 0012 §如何確認)', () {
    test('no Cookie or Authorization, even when the API client of the same '
        'plugin has credentials', () async {
      final adapter = FakeHttpAdapter(
        (options) => reply(
          200,
          body: 'x',
          headers: {'Set-Cookie': 'buvid3=FAKE_BUVID_123; Path=/'},
        ),
      );
      final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
      final recordIds = NetworkRecordIds();
      final source = SourceHttpClientFactory(
        log: log,
        credentials: FakeCredentials(
          cookies: {'SESSDATA': 'FAKE_SESSDATA_123'},
          headers: {'Authorization': 'Bearer FAKE_TOKEN_123'},
        ),
        recordIds: recordIds,
        createAdapter: () => adapter,
      ).create(pluginId: pluginId, allowedHosts: allowedHosts);
      final media = MediaHttpClientFactory(
        log: log,
        recordIds: recordIds,
        createAdapter: () => adapter,
      ).create(pluginId: pluginId, allowedHosts: allowedHosts);

      // API client 帶了憑證，jar 裡也有 example.test 的 cookie。
      await source.send(
        SourceRequest(
          Uri.parse('https://example.test/api'),
          auth: AuthRequirement.userPreference,
        ),
      );
      await source.send(SourceRequest(Uri.parse('https://example.test/a')));
      expect(adapter.requests[0].headers['Authorization'], isNotNull);
      expect(adapter.requests[1].headers['cookie'], contains('buvid3'));

      await media.download(
        Uri.parse('https://example.test/cover.jpg'),
        destination: destination,
        maxBytes: 1024,
        headers: {
          'Cookie': 'SESSDATA=FAKE_SESSDATA_123',
          'Authorization': 'Bearer FAKE_TOKEN_123',
          'X-Session': 'FAKE_SESSION_123',
          'Referer': 'https://example.test/',
        },
      );

      final sent = adapter.requests.last.headers;
      expect(
        sent.keys.map((name) => name.toLowerCase()),
        everyElement(isIn(mediaHeaderNames)),
      );
      expect(sent, {'Referer': 'https://example.test/'});
      // 兩種 client 共用紀錄 id；媒體的那筆沒帶憑證。
      final records = [
        for (final record in log.history)
          if (record.tag == networkLogTag) record,
      ];
      expect(records.map((r) => r.fields['id']), [1, 2, 3]);
      expect(records.map((r) => r.fields['client']), [
        'source',
        'source',
        'media',
      ]);
      expect(records.last.fields['credentials'], isFalse);
    });

    test('every hop carries only the media headers', () async {
      final harness = MediaHarness(
        (options) => switch (options.uri.path) {
          '/a' => redirect('https://cdn.example/b'),
          _ => reply(200, body: 'x'),
        },
      );
      const headers = {
        'Referer': 'https://example.test/',
        'User-Agent': 'FMP',
        'Range': 'bytes=0-',
      };
      await harness.download(
        'https://example.test/a',
        to: destination,
        headers: {...headers, 'Cookie': 'a=b'},
      );

      expect(harness.adapter.requests, hasLength(2));
      for (final request in harness.adapter.requests) {
        expect(request.headers, headers);
      }
    });
  });

  group('allowed hosts and redirects', () {
    for (final url in [
      'https://evil-example.test/a',
      'http://example.test/a',
      'https://example.test@evil.test/a',
      // dart:io 會把網址裡的 user info 變成 `Authorization: Basic …`，繞過
      // mediaRequestHeaders；假 adapter 看不到那個 header，所以整個拒絕。
      'https://user:FAKE_PASSWORD_123@example.test/a',
      // 只有使用者或只有密碼也會變成 `Basic`；只有 `https://@host` 不會。
      'https://user@example.test/a',
      'https://:FAKE_PASSWORD_123@example.test/a',
      'https://%75ser@example.test/a',
    ]) {
      test('$url is refused without a request', () async {
        final harness = MediaHarness((_) => reply(200));
        final error = await errorOf(harness.download(url, to: destination));
        expect(error, isA<Unsupported>());
        expect((error as Unsupported).networkRecordId, isNull);
        expect(harness.adapter.requests, isEmpty);
        expect(harness.records, isEmpty);
        expect(harness.outcomes, isEmpty);
      });
    }

    /// `/r/<n>` 轉到 `/r/<n-1>`，`/r/0` 回 200。
    ResponseBody chain(RequestOptions options) {
      final remaining = int.parse(options.uri.pathSegments.last);
      return remaining == 0
          ? reply(200, body: 'done')
          : redirect('/r/${remaining - 1}');
    }

    test('up to $maxRedirects redirects are followed', () async {
      final harness = MediaHarness(chain);
      final download = await harness.download(
        'https://example.test/r/5',
        to: destination,
      );
      expect(download.url, Uri.parse('https://example.test/r/0'));
      expect(destination.readAsStringSync(), 'done');
      expect(harness.adapter.requests, hasLength(6));
    });

    test('the sixth redirect fails', () async {
      final harness = MediaHarness(chain);
      final error = await errorOf(
        harness.download('https://example.test/r/6', to: destination),
      );
      expect(error, isA<Unsupported>());
      expect(harness.adapter.requests, hasLength(6));
      expect(
        (error as Unsupported).networkRecordId,
        harness.records.last.fields['id'],
      );
      expect(files(), isEmpty);
    });

    for (final (name, target) in [
      ('outside the allowed hosts', 'https://evil-example.test/x'),
      ('to http', 'http://example.test/x'),
      ('with user info', 'https://user:FAKE_PASSWORD_123@cdn.example/x'),
    ]) {
      test('a redirect $name fails before it is sent', () async {
        final harness = MediaHarness((_) => redirect(target));
        final error = await errorOf(
          harness.download('https://example.test/a', to: destination),
        );
        expect(error, isA<Unsupported>());
        expect(harness.adapter.requests, hasLength(1));
        expect(files(), isEmpty);
      });
    }

    test('the body of a redirect is not read', () async {
      final body = StreamController<Uint8List>();
      var released = false;
      body.onCancel = () => released = true;
      final harness = MediaHarness(
        (options) => switch (options.uri.path) {
          '/a' => streamed(body, status: 302, headers: {'Location': '/b'}),
          _ => reply(200, body: 'x'),
        },
      );
      await harness.download('https://example.test/a', to: destination);
      await pumpUntil(() => released, reason: 'the response was not released');
    });
  });

  group('size limit', () {
    test('a download within the limit lands in the destination', () async {
      final harness = MediaHarness(
        (_) => reply(
          200,
          body: '12345678',
          headers: {'Content-Type': 'image/jpeg', 'Content-Length': '8'},
        ),
      );
      final download = await harness.download(
        'https://example.test/a',
        to: destination,
        maxBytes: 8,
      );
      expect(download.statusCode, 200);
      expect(download.bytes, 8);
      expect(download.headers['content-type'], ['image/jpeg']);
      expect(destination.readAsStringSync(), '12345678');
      expect(files(), ['cover.jpg']);
    });

    test('an empty body is an empty file', () async {
      final harness = MediaHarness((_) => reply(204));
      final download = await harness.download(
        'https://example.test/a',
        to: destination,
      );
      expect(download.bytes, 0);
      expect(destination.lengthSync(), 0);
      expect(files(), ['cover.jpg']);
    });

    test('a Content-Length over the limit stops before reading', () async {
      final body = StreamController<Uint8List>();
      var released = false;
      body.onCancel = () => released = true;
      final harness = MediaHarness(
        (_) => streamed(body, headers: {'Content-Length': '9'}),
      );
      final error = await errorOf(
        harness.download(
          'https://example.test/a',
          to: destination,
          maxBytes: 8,
        ),
      );
      expect(error, isA<Unsupported>());
      await pumpUntil(() => released, reason: 'the response was not released');
      expect(files(), isEmpty);
      final record = harness.records.single;
      expect(record.level, LogLevel.warning);
      expect(record.fields['status'], 200);
      expect(record.fields['error'], 'Unsupported');
      expect((error as Unsupported).networkRecordId, record.fields['id']);
    });

    test('a body that grows past the limit stops and leaves no file', () async {
      final body = StreamController<Uint8List>();
      var released = false;
      body.onCancel = () => released = true;
      // 沒有 Content-Length：只能邊收邊數。第一塊已經寫進暫存檔。
      final harness = MediaHarness((_) => streamed(body));
      final download = errorOf(
        harness.download(
          'https://example.test/a',
          to: destination,
          maxBytes: 6,
        ),
      );
      body
        ..add(bytes(4))
        ..add(bytes(4));

      expect(await download, isA<Unsupported>());
      await pumpUntil(() => released, reason: 'the response was not released');
      expect(files(), isEmpty);
      expect(harness.records.single.fields['bytes'], 8);
    });

    test('a download replaces an existing file', () async {
      destination.writeAsStringSync('old');
      final harness = MediaHarness((_) => reply(200, body: 'new'));
      await harness.download('https://example.test/a', to: destination);
      expect(destination.readAsStringSync(), 'new');
      expect(files(), ['cover.jpg']);
    });

    test('a failed download leaves an existing file as it was', () async {
      destination.writeAsStringSync('old');
      final harness = MediaHarness((_) => reply(200, body: '123456789'));
      await errorOf(
        harness.download(
          'https://example.test/a',
          to: destination,
          maxBytes: 8,
        ),
      );
      expect(destination.readAsStringSync(), 'old');
      expect(files(), ['cover.jpg']);
    });
  });

  group('timeouts', () {
    test('the connect timeout of 10 seconds reaches the adapter', () async {
      final harness = MediaHarness(
        (options) => throw DioException.connectionTimeout(
          requestOptions: options,
          timeout: options.connectTimeout!,
        ),
      );
      final error = await errorOf(
        harness.download('https://example.test/a', to: destination),
      );
      // dio 的 IOHttpClientAdapter 以這兩個值限制連線與等回應標頭。
      final sent = harness.adapter.requests.single;
      expect(sent.connectTimeout, const Duration(seconds: 10));
      expect(sent.receiveTimeout, const Duration(seconds: 15));
      expect(error, isA<NetworkError>());
      expect(harness.outcomes, [RequestOutcome.networkError]);
    });

    test('15 seconds without data is a NetworkError (fake clock)', () {
      final body = StreamController<Uint8List>();
      var released = false;
      body.onCancel = () => released = true;
      fakeAsync((async) {
        final harness = MediaHarness((_) => streamed(body));
        Object? error;
        unawaited(
          harness
              .download('https://example.test/a', to: destination)
              .then<void>((_) {}, onError: (Object e) => error = e),
        );
        async.elapse(const Duration(seconds: 14));
        expect(error, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(error, isA<NetworkError>());
        expect(released, isTrue);
        expect(harness.outcomes, [RequestOutcome.networkError]);
        expect(harness.records.single.fields['error'], 'NetworkError');
        expect(async.pendingTimers, isEmpty);
      });
      expect(files(), isEmpty);
    });

    test('the whole download, redirects included, has 30 seconds (fake '
        'clock)', () {
      fakeAsync((async) {
        // 每跳 20 秒才回標頭：單一跳都不超過，兩跳加起來超過。
        final harness = MediaHarness(
          (options) => Future.delayed(
            const Duration(seconds: 20),
            () => switch (options.uri.path) {
              '/a' => redirect('/b'),
              _ => reply(200, body: 'x'),
            },
          ),
        );
        Object? error;
        unawaited(
          harness
              .download('https://example.test/a', to: destination)
              .then<void>((_) {}, onError: (Object e) => error = e),
        );
        async.elapse(const Duration(seconds: 29));
        expect(error, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(error, isA<NetworkError>());
        expect(harness.adapter.requests, hasLength(2));
        expect(harness.outcomes, [
          RequestOutcome.responded,
          RequestOutcome.networkError,
        ]);
        final timedOut = harness.records.last;
        expect(timedOut.fields['error'], 'NetworkError');
        expect(timedOut.fields['ms'], 10000);
        expect((error as NetworkError).networkRecordId, timedOut.fields['id']);

        // 假 adapter 的第二跳到 40 秒才回；之後不該留下任何計時器。
        async.elapse(const Duration(seconds: 10));
        expect(async.pendingTimers, isEmpty);
      });
      expect(files(), isEmpty);
    });

    test('no timer is left once a download ends (fake clock)', () {
      fakeAsync((async) {
        final harness = MediaHarness(
          (options) => switch (options.uri.path) {
            '/a' => redirect('/b'),
            _ => reply(404),
          },
        );
        Object? error;
        unawaited(
          harness
              .download('https://example.test/a', to: destination)
              .then<void>((_) {}, onError: (Object e) => error = e),
        );
        // dio 內部以零秒的計時器排程；1 秒遠小於整個下載的 30 秒上限。
        async.elapse(const Duration(seconds: 1));
        expect(error, isA<NotFound>());
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('cancel', () {
    test('abortTrigger cancels a download in progress', () async {
      final body = StreamController<Uint8List>();
      var released = false;
      body.onCancel = () => released = true;
      final abort = Completer<void>();
      final harness = MediaHarness((_) => streamed(body));
      final download = errorOf(
        harness.download(
          'https://example.test/a',
          to: destination,
          abortTrigger: abort.future,
        ),
      );
      await pumpUntil(() => harness.adapter.requests.isNotEmpty);
      abort.complete();

      expect(await download, isA<RequestCancelled>());
      await pumpUntil(() => released, reason: 'the response was not released');
      expect(harness.outcomes, isEmpty);
      final record = harness.records.single;
      expect(record.level, LogLevel.debug);
      expect(record.fields['error'], 'Cancelled');
      expect(files(), isEmpty);
    });

    test('a cancel after the first chunk deletes the partial file', () async {
      final body = StreamController<Uint8List>();
      final abort = Completer<void>();
      final harness = MediaHarness((_) => streamed(body));
      final download = errorOf(
        harness.download(
          'https://example.test/a',
          to: destination,
          abortTrigger: abort.future,
        ),
      );
      body.add(bytes(4));
      await pumpUntil(
        () => files().isNotEmpty,
        reason: 'the partial file was not created',
      );
      abort.complete();

      expect(await download, isA<RequestCancelled>());
      expect(harness.records.single.fields['bytes'], 4);
      expect(files(), isEmpty);
    });
  });

  group('error mapping', () {
    Future<Object> failWith(ResponseBody response) => errorOf(
      MediaHarness((_) => response)
          .download('https://example.test/a', to: destination),
    );

    test('404 and 410 are NotFound', () async {
      for (final status in [404, 410]) {
        final error = await failWith(reply(status));
        expect(error, isA<NotFound>(), reason: '$status');
        expect((error as NotFound).networkRecordId, 1);
      }
    });

    test('429 is RateLimited with its Retry-After', () async {
      final error = await failWith(reply(429, headers: {'Retry-After': '7'}));
      expect(error, isA<RateLimited>());
      expect((error as RateLimited).retryAfter, const Duration(seconds: 7));
    });

    test('503 is RateLimited only with Retry-After', () async {
      expect(
        await failWith(reply(503, headers: {'Retry-After': '7'})),
        isA<RateLimited>(),
      );
      expect(await failWith(reply(503)), isA<UnexpectedError>());
    });

    test(
      'any other status is an UnexpectedError with its status logged',
      () async {
        for (final status in [300, 304, 400, 403, 500, 302]) {
          // 302 沒有 Location：不是能跟的轉址。
          final harness = MediaHarness((_) => reply(status));
          final error = await errorOf(
            harness.download('https://example.test/a', to: destination),
          );
          expect(error, isA<UnexpectedError>(), reason: '$status');
          final record = harness.records.single;
          expect(record.level, LogLevel.warning);
          expect(record.fields['status'], status);
          expect(record.fields['error'], 'UnexpectedError');
        }
        expect(files(), isEmpty);
      },
    );

    test('206 for a Range request is a download', () async {
      final harness = MediaHarness((_) => reply(206, body: 'part'));
      final download = await harness.download(
        'https://example.test/a',
        to: destination,
        headers: {'Range': 'bytes=4-7'},
      );
      expect(download.statusCode, 206);
      expect(destination.readAsStringSync(), 'part');
    });

    test('an error status is not read', () async {
      final body = StreamController<Uint8List>();
      var released = false;
      body.onCancel = () => released = true;
      final error = await failWith(streamed(body, status: 404));
      expect(error, isA<NotFound>());
      await pumpUntil(() => released, reason: 'the response was not released');
    });

    test('transport errors are NetworkError', () async {
      for (final failure in <DioException Function(RequestOptions)>[
        (o) => DioException.connectionError(
          requestOptions: o,
          reason: 'refused',
          error: const SocketException('refused'),
        ),
        (o) => DioException(
          requestOptions: o,
          error: const HandshakeException('handshake failed'),
        ),
      ]) {
        final error = await errorOf(
          MediaHarness((options) => throw failure(options))
              .download('https://example.test/a', to: destination),
        );
        expect(error, isA<NetworkError>());
      }
    });

    test('a connection lost while receiving is a NetworkError', () async {
      final body = StreamController<Uint8List>();
      final harness = MediaHarness((_) => streamed(body));
      final download = errorOf(
        harness.download('https://example.test/a', to: destination),
      );
      body
        ..add(bytes(4))
        ..addError(const HttpException('Connection closed while receiving'));

      expect(await download, isA<NetworkError>());
      expect(harness.outcomes, [RequestOutcome.networkError]);
      expect(harness.records.single.fields['bytes'], 4);
      expect(files(), isEmpty);
    });
  });

  group('network log', () {
    test('one record per hop with every field', () async {
      await withClock(Clock.fixed(DateTime.utc(2026, 10, 1)), () async {
        final harness = MediaHarness(
          (options) => switch (options.uri.path) {
            '/a' => redirect('https://cdn.example/b?size=large'),
            _ => reply(200, body: 'FAKE_MEDIA_BODY'),
          },
        );
        await harness.download('https://example.test/a', to: destination);

        final [hop, last] = harness.records;
        expect(hop.level, LogLevel.debug);
        expect(hop.message, 'HTTP request');
        expect(hop.fields, {
          'id': 1,
          'pluginId': pluginId,
          'client': 'media',
          'method': 'GET',
          'host': 'example.test',
          'path': '/a',
          'status': 302,
          'ms': 0,
          'credentials': false,
          'retry': 0,
        });
        expect(last.fields, {
          'id': 2,
          'pluginId': pluginId,
          'client': 'media',
          'method': 'GET',
          'host': 'cdn.example',
          'path': '/b',
          'query': 'size=large',
          'status': 200,
          'ms': 0,
          'bytes': 'FAKE_MEDIA_BODY'.length,
          'credentials': false,
          'retry': 0,
        });
      });
    });

    test(
      'fake secrets in the query are redacted and bodies are not logged',
      () async {
        final logFile = LogFile(Directory(p.join(temp.path, logDirectoryName)));
        final harness = MediaHarness(
          (_) => reply(200, body: 'FAKE_MEDIA_BODY_123'),
          logFile: logFile,
        );
        await harness.download(
          'https://example.test/a?access_key=FAKE_ACCESS_KEY_123&size=large',
          to: destination,
        );

        await logFile.flush();
        final stored = await logFile.currentFile.readAsString();
        final history = jsonEncode([
          for (final record in harness.log.history) record.toJsonLine(),
        ]);
        for (final output in [history, stored]) {
          expect(output, contains('size=large'));
          for (final secret in ['FAKE_ACCESS_KEY_123', 'FAKE_MEDIA_BODY_123']) {
            expect(output, isNot(contains(secret)));
          }
        }
      },
    );
  });

  // ADR 0016 §決定 6：每一跳的結果進網路狀態，最多一次。
  group('network status', () {
    test('any response is responded, once per hop', () async {
      final harness = MediaHarness(
        (options) => switch (options.uri.path) {
          '/a' => redirect('/b'),
          _ => reply(200, body: 'x'),
        },
      );
      await harness.download('https://example.test/a', to: destination);
      expect(harness.outcomes, [
        RequestOutcome.responded,
        RequestOutcome.responded,
      ]);

      final notFound = MediaHarness((_) => reply(404));
      await errorOf(
        notFound.download('https://example.test/a', to: destination),
      );
      expect(notFound.outcomes, [RequestOutcome.responded]);
    });

    test('a transport error is a network error', () async {
      final harness = MediaHarness(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'refused',
        ),
      );
      await errorOf(
        harness.download('https://example.test/a', to: destination),
      );
      expect(harness.outcomes, [RequestOutcome.networkError]);
    });

    // 插件更新時 PluginRegistry 關掉舊的 client；之後還拿著它的呼叫端不該讓
    // 網路狀態以為連不上（API client 關閉後的請求也不回報）。
    test('a closed client sends nothing and reports nothing', () async {
      final harness = MediaHarness((_) => reply(200, body: 'x'))
        ..client.close();
      final error = await errorOf(
        harness.download('https://example.test/a', to: destination),
      );
      expect(error, isA<UnexpectedError>());
      expect((error as UnexpectedError).networkRecordId, isNull);
      expect(harness.adapter.requests, isEmpty);
      expect(harness.records, isEmpty);
      expect(harness.outcomes, isEmpty);
    });
  });
}
