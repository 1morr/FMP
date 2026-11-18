import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/backends/hls/hls_packager.dart';

import '../../support/no_network.dart';
import '../../support/fragmented_mp4.dart';

void main() {
  final stream = AudioStream(
    url: Uri.parse('https://cdn.example.com/a.m4s?deadline=1&sig=x'),
    headers: const {'Referer': 'https://www.example.com'},
    segmentBase: const SegmentBase(
      initialization: ByteRange(0, 836),
      index: ByteRange(837, 9432),
    ),
  );
  final index = sidxBox(sizes: [1000, 2000], durations: [240640, 240640]);

  late List<(Uri, Map<String, String>, ByteRange)> fetched;
  late HlsPackager packager;
  setUp(() {
    fetched = [];
    packager = HlsPackager(
      fetchRange: (url, headers, range) async {
        fetched.add((url, headers, range));
        return index;
      },
    );
  });
  tearDown(() => packager.close());

  /// 讀本機伺服器上的清單（只連 127.0.0.1）。
  Future<(int, String)> get(Uri url) async {
    final client = realHttpClient();
    try {
      final response = await (await client.getUrl(url)).close();
      return (response.statusCode, await utf8.decodeStream(response));
    } finally {
      client.close();
    }
  }

  test('fetches the index with the stream headers', () async {
    await packager.playlistFor(stream);
    expect(fetched, [(stream.url, stream.headers, const ByteRange(837, 9432))]);
  });

  test('serves the playlist on the loopback address', () async {
    final url = await packager.playlistFor(stream);

    expect(url.scheme, 'http');
    expect(url.host, InternetAddress.loopbackIPv4.address);
    expect(url.path, endsWith('.m3u8'));
    final (status, body) = await get(url);
    expect(status, HttpStatus.ok);
    expect(body, startsWith('#EXTM3U\n'));
    expect(body, contains('#EXT-X-MAP:URI="${stream.url}",BYTERANGE="837@0"'));
    expect('#EXT-X-BYTERANGE'.allMatches(body), hasLength(2));
  });

  test('each playlist has its own unguessable path', () async {
    final first = await packager.playlistFor(stream);
    final second = await packager.playlistFor(stream);
    expect(first.path, isNot(second.path));
    expect(first.pathSegments.single.length, greaterThanOrEqualTo(32));
    final (status, _) = await get(first.replace(path: '/nope.m3u8'));
    expect(status, HttpStatus.notFound);
  });

  test('keeps only the latest playlists', () async {
    final urls = [
      for (var i = 0; i < HlsPackager.kept + 1; i++)
        await packager.playlistFor(stream),
    ];
    expect((await get(urls.first)).$1, HttpStatus.notFound);
    expect((await get(urls.last)).$1, HttpStatus.ok);
  });

  test('an index it cannot fetch is HlsUnavailable', () async {
    final failing = HlsPackager(
      fetchRange: (_, _, _) async => throw const SocketException('reset'),
    );
    addTearDown(failing.close);
    await expectLater(
      failing.playlistFor(stream),
      throwsA(isA<HlsUnavailable>()),
    );
  });

  test('an index that is not a sidx is HlsUnavailable', () async {
    final garbage = HlsPackager(
      fetchRange: (_, _, _) async => Uint8List.fromList(List.filled(64, 1)),
    );
    addTearDown(garbage.close);
    await expectLater(
      garbage.playlistFor(stream),
      throwsA(isA<HlsUnavailable>()),
    );
  });

  test('HlsUnavailable never carries the signed URL', () async {
    final failing = HlsPackager(
      fetchRange: (url, _, _) async => throw HttpException('403', uri: url),
    );
    addTearDown(failing.close);
    try {
      await failing.playlistFor(stream);
      fail('expected HlsUnavailable');
    } on HlsUnavailable catch (e) {
      expect('$e', isNot(contains('sig=')));
      expect('$e', isNot(contains('cdn.example.com')));
    }
  });
}
