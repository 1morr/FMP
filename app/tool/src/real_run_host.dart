import 'dart:convert';
import 'dart:io';

/// 截一張 [pid] 的 App 視窗，存到 [file]（PNG）。用系統的截圖工具，不動游標
/// （docs/development.md〈實跑驅動〉）；失敗就丟例外。
typedef CaptureWindow = Future<void> Function(File file, int pid);

/// 實跑時宿主這一端的截圖服務（docs/development.md〈實跑驅動〉）：只聽
/// 127.0.0.1，驅動走到一步就來要截圖、交讀回的文字。
///
/// - `GET /shot?name=<步驟>&pid=<App 的 pid>`：用 [CaptureWindow] 截圖存成
///   `<out>/<步驟>.png`，截完才回 200，驅動等到回覆才往下做，截到的就是這一步
///   的畫面。截圖失敗回 500，內文是錯誤。
/// - `POST /text?name=<步驟>`：內文（UTF-8）存成 `<out>/<步驟>.txt`。
///
/// 步驟名只收英數字、`-`、`_`，開頭不是 `-`、`_`，其他回 400，不會寫出
/// `out` 之外。
class RealRunCaptureServer {
  RealRunCaptureServer._(this._server, this._out, this._capture) {
    _server.listen(_handle);
  }

  static Future<RealRunCaptureServer> start({
    required Directory out,
    required CaptureWindow capture,
  }) async => RealRunCaptureServer._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    out,
    capture,
  );

  final HttpServer _server;
  final Directory _out;
  final CaptureWindow _capture;

  /// 驅動連的位址，例如 `http://127.0.0.1:53124/`。
  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/');

  Future<void> close() => _server.close(force: true);

  static final _stepName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final name = request.uri.queryParameters['name'] ?? '';
      if (!_stepName.hasMatch(name)) {
        response.statusCode = HttpStatus.badRequest;
        response.write('bad step name: "$name"');
        return;
      }
      switch ((request.method, request.uri.path)) {
        case ('GET', '/shot'):
          final pid = int.tryParse(request.uri.queryParameters['pid'] ?? '');
          if (pid == null) {
            response.statusCode = HttpStatus.badRequest;
            response.write('missing pid');
            return;
          }
          _out.createSync(recursive: true);
          try {
            await _capture(File('${_out.path}/$name.png'), pid);
          } on Object catch (error) {
            response.statusCode = HttpStatus.internalServerError;
            response.write('$error');
          }
        case ('POST', '/text'):
          final text = await utf8.decodeStream(request);
          _out.createSync(recursive: true);
          File('${_out.path}/$name.txt').writeAsStringSync(text);
        default:
          response.statusCode = HttpStatus.notFound;
      }
    } finally {
      await response.close();
    }
  }
}
