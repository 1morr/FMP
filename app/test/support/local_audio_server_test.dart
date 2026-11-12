import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'local_audio_server.dart';

/// integration_test 用的假 CDN。用原始 socket 打它：測試的零聯網防線擋的是
/// `HttpClient`。
void main() {
  late LocalAudioServer server;

  setUp(() async {
    server = await LocalAudioServer.start(
      length: const Duration(seconds: 2),
      requiredHeaders: {'Referer': 'https://example.com'},
    );
  });
  tearDown(() => server.close());

  Future<String> get(Map<String, String> headers) async {
    final url = server.url(query: 'deadline=1&sig=x');
    final socket = await Socket.connect(url.host, url.port);
    socket.write(
      'GET ${url.path}?${url.query} HTTP/1.1\r\n'
      'Host: ${url.host}\r\n'
      '${headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join()}'
      'Connection: close\r\n\r\n',
    );
    final response = await socket
        .cast<List<int>>()
        .transform(latin1.decoder)
        .join();
    socket.destroy();
    return response;
  }

  test('serves the whole file with the right header', () async {
    final response = await get({'Referer': 'https://example.com'});
    expect(response, startsWith('HTTP/1.1 200'));
    expect(response.toLowerCase(), contains('content-type: audio/wav'));
    expect(response.toLowerCase(), contains('content-length: 32044'));
    expect(response, contains('RIFF'));
    expect(server.requests.single.headers['referer'], 'https://example.com');
  });

  test('serves byte ranges', () async {
    final response = await get({
      'Referer': 'https://example.com',
      'Range': 'bytes=0-3',
    });
    expect(response, startsWith('HTTP/1.1 206'));
    expect(response.toLowerCase(), contains('content-range: bytes 0-3/32044'));
    expect(response, endsWith('RIFF'));
  });

  test('refuses a request without the required header', () async {
    expect(await get({}), startsWith('HTTP/1.1 403'));
    expect(
      await get({'Referer': 'https://other.example.com'}),
      startsWith('HTTP/1.1 403'),
    );
  });

  test('silentWav is a valid PCM header of the right length', () {
    final wav = silentWav(const Duration(seconds: 1));
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(wav.length, 44 + 16000);
  });
}
