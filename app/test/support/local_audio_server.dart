import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// 只聽 127.0.0.1 的假 CDN：預設回一段產生出來的無聲 WAV，也可以給任意
/// 內容（例如 `FragmentedMp4`），給 integration_test 讓真的原生播放器播
/// （零聯網：原生播放器的連線不經 Dart 的 `HttpOverrides`，所以不能讓它連外）。
///
/// 照 CDN 的行為支援 `Range`（AVPlayer 要求伺服器支援位元組範圍）。設了
/// [requiredHeaders] 時，少帶或帶錯的請求回 403，像 B 站 CDN 檢查 Referer
/// 一樣：播得起來就證明串流的 header 有帶到原生播放器的請求上。
/// [requireBrowserUserAgent] 為真時，`User-Agent` 不是瀏覽器的（不以
/// `Mozilla/` 開頭，例如 ExoPlayer 或 AVPlayer 自己的）也回 403，像 B 站
/// 部分串流網址那樣（brief 事實 F22）。設了 [cutAfterBytes] 時，每個回應
/// 傳到那麼多位元組就關掉連線，像 B 站 CDN 偶爾中途斷線（事實 F24）。
class LocalAudioServer {
  LocalAudioServer._(
    this._server,
    this._body,
    this._contentType,
    this._name,
    this.requiredHeaders,
    this.requireBrowserUserAgent,
    this.cutAfterBytes,
  ) {
    _server.listen(_handle);
  }

  /// 在 127.0.0.1 的任一個空埠開始服務 [length] 長的無聲 WAV；給了 [body]
  /// 就改服務它，Content-Type 是 [contentType]、檔名是 [name]。
  static Future<LocalAudioServer> start({
    Duration length = const Duration(seconds: 30),
    Uint8List? body,
    ContentType? contentType,
    String name = 'silence.wav',
    Map<String, String> requiredHeaders = const {},
    bool requireBrowserUserAgent = false,
    int? cutAfterBytes,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LocalAudioServer._(
      server,
      body ?? silentWav(length),
      contentType ?? ContentType('audio', 'wav'),
      name,
      requiredHeaders,
      requireBrowserUserAgent,
      cutAfterBytes,
    );
  }

  final HttpServer _server;
  final Uint8List _body;
  final ContentType _contentType;
  final String _name;
  final Map<String, String> requiredHeaders;
  final bool requireBrowserUserAgent;
  final int? cutAfterBytes;

  /// 收到的每個請求：方法、路徑與小寫 header 名稱對到值。
  final requests =
      <({String method, String path, Map<String, String> headers})>[];

  /// 音訊的網址；[query] 照原樣接在後面（例如假的簽名參數）。
  Uri url({String query = ''}) => Uri.parse(
    'http://127.0.0.1:${_server.port}/$_name${query.isEmpty ? '' : '?$query'}',
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
    var detached = false;
    try {
      final missing =
          requiredHeaders.entries.any(
            (e) => headers[e.key.toLowerCase()] != e.value,
          ) ||
          (requireBrowserUserAgent &&
              !(headers['user-agent'] ?? '').startsWith('Mozilla/'));
      if (missing) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      if (request.uri.path != '/$_name') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      var start = 0;
      var end = _body.length - 1;
      final range = RegExp(r'^bytes=(\d*)-(\d*)$')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      if (range != null) {
        final from = int.tryParse(range[1]!);
        final to = int.tryParse(range[2]!);
        if (from != null) {
          start = from;
          if (to != null && to < end) end = to;
        } else if (to != null) {
          start = _body.length - to;
        }
        if (start > end || start >= _body.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */${_body.length}',
          );
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${_body.length}',
        );
      }
      response.headers
        ..contentType = _contentType
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (request.method == 'HEAD') return;
      final cut = cutAfterBytes;
      if (cut != null && end - start + 1 > cut) {
        // 照宣告的長度送出 header，傳到一半就關掉連線。
        final socket = await response.detachSocket();
        detached = true;
        socket.add(Uint8List.sublistView(_body, start, start + cut));
        await socket.flush().catchError((_) => null);
        socket.destroy();
        return;
      }
      response.add(Uint8List.sublistView(_body, start, end + 1));
    } finally {
      // 播放器常常讀到一半就斷線；那不是錯誤。
      if (!detached) await response.close().catchError((_) => null);
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
