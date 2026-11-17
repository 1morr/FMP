import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/backends/hls/hls_playlist.dart';

/// 對 [url] 帶 [headers] 要 [range] 那段位元組。
typedef FetchRange = Future<Uint8List> Function(
  Uri url,
  Map<String, String> headers,
  ByteRange range,
);

/// 把單檔 fragmented MP4 的串流包成 byte-range HLS（ADR 0040）：讀它的
/// sidx，產生清單，由只聽 127.0.0.1 的伺服器提供。AVPlayer 照清單一段一段
/// 直接向 CDN 要，連線被 CDN 中途關掉也只影響那一段（事實 M14、M15、F24）。
/// 媒體不經過這裡。
///
/// 伺服器第一次用到才開，只留最近 [kept] 份清單；路徑是隨機字串，清單裡的
/// 簽名網址不讓同機的其他程式猜到。
class HlsPackager {
  HlsPackager({FetchRange? fetchRange})
    : _fetchRange = fetchRange ?? fetchRangeOverHttp;

  /// 留幾份清單：正在播的、預載的下一首，再多留一點給還在讀清單的播放器。
  static const kept = 4;

  final FetchRange _fetchRange;
  final _random = Random.secure();
  final _playlists = <String, List<int>>{};
  Future<HttpServer>? _server;

  /// 產生 [stream] 的清單，回傳它在本機的網址。[stream] 要有
  /// [AudioStream.segmentBase]。抓不到或讀不懂索引時丟 [HlsUnavailable]。
  Future<Uri> playlistFor(AudioStream stream) async {
    final base = stream.segmentBase;
    if (base == null) throw const HlsUnavailable('the stream has no index');
    final Uint8List index;
    try {
      index = await _fetchRange(stream.url, stream.headers, base.index);
    } on Object catch (e) {
      // 例外訊息常帶整個網址（HttpException.uri），只留型別。
      throw HlsUnavailable('fetching the index failed: ${e.runtimeType}');
    }
    final List<MediaSegment> segments;
    try {
      segments = readSegmentIndex(index, indexOffset: base.index.first);
    } on FormatException catch (e) {
      throw HlsUnavailable('reading the index failed: ${e.message}');
    }
    final playlist = hlsPlaylist(
      url: stream.url,
      initialization: base.initialization,
      segments: segments,
    );
    final server = await (_server ??= _start());
    final token = [for (var i = 0; i < 16; i++) _random.nextInt(256)]
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _playlists[token] = utf8.encode(playlist);
    while (_playlists.length > kept) {
      _playlists.remove(_playlists.keys.first);
    }
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/$token.m3u8',
    );
  }

  Future<HttpServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final segments = request.uri.pathSegments;
      final token = segments.length == 1 && segments.single.endsWith('.m3u8')
          ? segments.single.substring(0, segments.single.length - 5)
          : null;
      final body = _playlists[token];
      final response = request.response;
      if (body == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.headers
          ..contentType = ContentType('application', 'vnd.apple.mpegurl')
          ..contentLength = body.length;
        if (request.method != 'HEAD') response.add(body);
      }
      // 播放器讀到一半斷線不是錯誤。
      response.close().catchError((Object _) {});
    });
    return server;
  }

  /// 關掉伺服器；之後不能再用。
  Future<void> close() async {
    _playlists.clear();
    final server = _server;
    _server = null;
    if (server != null) await (await server).close(force: true);
  }
}

/// 播不了 HLS 包裝，呼叫端照舊直接播網址。訊息不含網址。
class HlsUnavailable implements Exception {
  const HlsUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'HlsUnavailable: $reason';
}

/// [FetchRange] 的預設做法：dart:io 的 [HttpClient]，要求 206 且長度剛好。
Future<Uint8List> fetchRangeOverHttp(
  Uri url,
  Map<String, String> headers,
  ByteRange range,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(url);
    headers.forEach(request.headers.set);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=${range.first}-${range.last}',
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException('status ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await response.timeout(const Duration(seconds: 10)).forEach(bytes.add);
    final body = bytes.takeBytes();
    if (body.length != range.length) {
      throw HttpException('got ${body.length} of ${range.length} bytes');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
