import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 只聽 127.0.0.1 的假 CDN：回一段產生出來的無聲 WAV，給 integration_test
/// 讓真的原生播放器播（零聯網：原生播放器的連線不經 Dart 的
/// `HttpOverrides`，所以不能讓它連外）。
///
/// 照 CDN 的行為支援 `Range`（AVPlayer 要求伺服器支援位元組範圍）。設了
/// [requiredHeaders] 時，少帶或帶錯的請求回 403，像 B 站 CDN 檢查 Referer
/// 一樣：播得起來就證明串流的 header 有帶到原生播放器的請求上。
class LocalAudioServer {
  LocalAudioServer._(this._server, this._wav, this.requiredHeaders) {
    _server.listen(_handle);
  }

  /// 在 127.0.0.1 的任一個空埠開始服務 [length] 長的無聲音訊。
  static Future<LocalAudioServer> start({
    Duration length = const Duration(seconds: 30),
    Map<String, String> requiredHeaders = const {},
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LocalAudioServer._(server, silentWav(length), requiredHeaders);
  }

  final HttpServer _server;
  final Uint8List _wav;
  final Map<String, String> requiredHeaders;

  /// 收到的每個請求：方法、路徑與小寫 header 名稱對到值。
  final requests =
      <({String method, String path, Map<String, String> headers})>[];

  /// 音訊的網址；[query] 照原樣接在後面（例如假的簽名參數）。
  Uri url({String query = ''}) => Uri.parse(
    'http://127.0.0.1:${_server.port}/silence.wav${query.isEmpty ? '' : '?$query'}',
  );

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    requests.add((
      method: request.method,
      path: request.uri.path,
      headers: headers,
    ));
    final response = request.response;
    try {
      final missing = requiredHeaders.entries.any(
        (e) => headers[e.key.toLowerCase()] != e.value,
      );
      if (missing) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.uri.path != '/silence.wav') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      var start = 0;
      var end = _wav.length - 1;
      final range = RegExp(r'^bytes=(\d*)-(\d*)$')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range != null) {
        final from = int.tryParse(range[1]!);
        final to = int.tryParse(range[2]!);
        if (from != null) {
          start = from;
          if (to != null && to < end) end = to;
        } else if (to != null) {
          start = _wav.length - to;
        }
        if (start > end || start >= _wav.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */${_wav.length}',
          );
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${_wav.length}',
        );
      }
      response.headers
        ..contentType = ContentType('audio', 'wav')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (request.method != 'HEAD') {
        response.add(Uint8List.sublistView(_wav, start, end + 1));
      }
    } finally {
      // 播放器常常讀到一半就斷線；那不是錯誤。
      await response.close().catchError((_) => null);
    }
  }
}

/// [length] 長的無聲 WAV：8 kHz、16 位元、單聲道 PCM。
Uint8List silentWav(Duration length) {
  const sampleRate = 8000;
  const bytesPerSample = 2;
  final dataLength = sampleRate * bytesPerSample * length.inSeconds;
  final bytes = ByteData(44 + dataLength);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // fmt chunk 長度
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // 單聲道
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * bytesPerSample, Endian.little);
  bytes.setUint16(32, bytesPerSample, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  return bytes.buffer.asUint8List();
}
