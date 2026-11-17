import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/real_run_host.dart';
import '../support/no_network.dart';

/// 實跑時驅動向宿主要截圖、交讀回的文字（docs/development.md〈實跑驅動〉）。
void main() {
  late Directory out;
  late HttpClient client;

  setUp(() {
    out = Directory.systemTemp.createTempSync('fmp_real_run_');
    // 只連這個測試在 127.0.0.1 開的服務，不出本機。
    client = realHttpClient();
  });
  tearDown(() {
    client.close(force: true);
    out.deleteSync(recursive: true);
  });

  Future<(int, String)> request(
    String method,
    Uri uri, {
    String body = '',
  }) async {
    final request = await client.openUrl(method, uri);
    request.add(utf8.encode(body));
    final response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response));
  }

  test('a shot request is answered after the screenshot is on disk', () async {
    final shooting = Completer<void>();
    final requested = <(String, int)>[];
    final server = await RealRunCaptureServer.start(
      out: out,
      capture: (file, pid) async {
        requested.add((file.path, pid));
        await shooting.future;
        file.writeAsBytesSync([1, 2, 3]);
      },
    );
    addTearDown(server.close);

    var answered = false;
    final response = request(
      'GET',
      server.url.resolve('shot?name=01-launch&pid=4242'),
    ).whenComplete(() => answered = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(answered, isFalse);

    shooting.complete();
    expect((await response).$1, HttpStatus.ok);
    expect(requested, [('${out.path}/01-launch.png', 4242)]);
    expect(File('${out.path}/01-launch.png').readAsBytesSync(), [1, 2, 3]);
  });

  test('read-back text is saved as UTF-8', () async {
    final server = await RealRunCaptureServer.start(
      out: out,
      capture: (_, _) async {},
    );
    addTearDown(server.close);

    final (status, _) = await request(
      'POST',
      server.url.resolve('text?name=04-queue'),
      body: '佇列\n周末午後 · lofi\n',
    );

    expect(status, HttpStatus.ok);
    expect(
      File('${out.path}/04-queue.txt').readAsStringSync(),
      '佇列\n周末午後 · lofi\n',
    );
  });

  test('a failed screenshot is reported to the driver', () async {
    final server = await RealRunCaptureServer.start(
      out: out,
      capture: (_, _) async => throw const ProcessException('screencapture', [
        '-l',
        '0',
      ], 'no window'),
    );
    addTearDown(server.close);

    final (status, body) = await request(
      'GET',
      server.url.resolve('shot?name=01-launch&pid=1'),
    );

    expect(status, HttpStatus.internalServerError);
    expect(body, contains('no window'));
  });

  test('names that are not a plain step name are refused', () async {
    var captured = 0;
    final server = await RealRunCaptureServer.start(
      out: out,
      capture: (_, _) async => captured++,
    );
    addTearDown(server.close);

    for (final name in ['../escape', 'a/b', '', '.hidden']) {
      final (shot, _) = await request(
        'GET',
        server.url.replace(
          path: '/shot',
          queryParameters: {'name': name, 'pid': '1'},
        ),
      );
      final (text, _) = await request(
        'POST',
        server.url.replace(path: '/text', queryParameters: {'name': name}),
        body: 'x',
      );
      expect((shot, text), (HttpStatus.badRequest, HttpStatus.badRequest));
    }
    expect(captured, 0);
    expect(out.listSync(recursive: true), isEmpty);
  });
}
