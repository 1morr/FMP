import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/platform.dart';
import 'package:fmp/playback/backends/audio_backends.dart';
import 'package:integration_test/integration_test.dart';

import '../test/playback/backends/audio_backend_contract.dart';

// 後端契約的真後端那一份（ADR 0018 §如何確認）：跑執行平台宣告的後端——
// Android 是 just_audio、Windows 是 media_kit。音檔是測試插件的 tone.wav（2 秒，
// dev flavor 的 asset），所以要帶 `--flavor dev`（預設就是 dev）：
//
//   flutter test integration_test/audio_backend_contract_test.dart -d windows
//   flutter test integration_test/audio_backend_contract_test.dart -d emulator-5554
//
// 會出聲。假後端的那一份在 test/playback/backends/，由 `flutter test` 跑。
//
// 「HTTP 拒絕」「一直不回應」與經 HTTP 的音檔（`/tracks/`，靜音的 WAV、支援
// Range，數每個路徑的請求）是測試自己在 loopback 起的伺服器（其他路徑一律回
// 403），不連外網；
// Android 的 debug 建置以 `android/app/src/debug/res/xml/network_security_config.xml`
// 只對 127.0.0.1 放行明文。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final support = AppPlatform.current(AppFlavor.dev).capabilities.playback;
  if (support == null) {
    test('this platform declares no playback backend', () {}, skip: true);
    return;
  }
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);

  late HttpServer server;
  late _LoopbackTracks tracks;
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tracks = _LoopbackTracks(server.port);
    server.listen((request) async {
      // 不回應：引擎一直停在載入中，`tearDownAll` 關掉伺服器時才斷線。
      if (request.uri.path == '/stalled.m4a') return;
      if (await tracks.serve(request)) return;
      request.response
        ..statusCode = HttpStatus.forbidden
        ..write('forbidden');
      await request.response.close();
    });
  });
  tearDownAll(() => server.close(force: true));

  group(support.backend.name, () {
    audioBackendContract(
      define: (description, body) => testWidgets(
        description,
        (tester) => tester.runAsync(body),
        timeout: const Timeout(Duration(minutes: 1)),
      ),
      create: () async => createAudioBackend(support, log: log),
      track: Uri.parse('asset:///test/fixtures/plugins/test_plugin/tone.wav'),
      missing: Uri.parse(
        'asset:///test/fixtures/plugins/test_plugin/missing.wav',
      ),
      forbidden: () =>
          Uri.parse('http://127.0.0.1:${server.port}/forbidden.wav'),
      stalled: () => Uri.parse('http://127.0.0.1:${server.port}/stalled.m4a'),
      server: () => tracks,
      reportsHttpStatus: support.backend == AudioBackendKind.mediaKit,
      selectsOutputDevice: support.outputDeviceSelection,
      trackLength: const Duration(seconds: 2),
    );
  });

  tearDownAll(() {
    for (final record in log.history) {
      if (record.level.index >= LogLevel.warning.index) {
        debugPrint('FMP_BACKEND_LOG ${record.message} ${record.fields}');
      }
    }
  });
}

/// `/tracks/<n>.wav?ms=<長度>`：產生長那麼久的靜音 WAV（AVPlayer 要 Range，所以
/// 回 206），記下每個路徑被請求幾次；`held` 的路徑到 [release] 才回應。
final class _LoopbackTracks implements TrackServer {
  _LoopbackTracks(this._port);

  final int _port;
  var _count = 0;
  final _requests = <String, int>{};
  final _held = <String, Completer<void>>{};

  @override
  Uri track(Duration length, {bool held = false}) {
    final path = '/tracks/${++_count}.wav';
    if (held) _held[path] = Completer<void>();
    return Uri.parse(
      'http://127.0.0.1:$_port$path?ms=${length.inMilliseconds}',
    );
  }

  @override
  int requestsTo(Uri url) => _requests[url.path] ?? 0;

  @override
  void release(Uri url) {
    final held = _held.remove(url.path);
    if (held != null && !held.isCompleted) held.complete();
  }

  /// 是 `/tracks/` 的請求就回應並回傳 `true`。
  Future<bool> serve(HttpRequest request) async {
    final path = request.uri.path;
    if (!path.startsWith('/tracks/')) return false;
    _requests[path] = (_requests[path] ?? 0) + 1;
    await _held[path]?.future;
    final ms = int.tryParse(request.uri.queryParameters['ms'] ?? '') ?? 2000;
    final wav = _silentWav(Duration(milliseconds: ms));
    final response = request.response
      ..headers.contentType = ContentType('audio', 'wav')
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final range = RegExp(r'^bytes=(\d+)-(\d*)$')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    var start = 0;
    var end = wav.length - 1;
    if (range != null) {
      start = int.parse(range.group(1)!);
      if (range.group(2)!.isNotEmpty) {
        end = math.min(end, int.parse(range.group(2)!));
      }
      response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${wav.length}',
        );
    }
    response.contentLength = end - start + 1;
    if (request.method != 'HEAD') {
      response.add(Uint8List.sublistView(wav, start, end + 1));
    }
    // 引擎拿到需要的部分就斷線（AVPlayer 的探測請求），不算錯。
    await response.close().then<void>((_) {}, onError: (Object _) {});
    return true;
  }

  /// 22.05 kHz、16 位元、單聲道的靜音 PCM WAV。
  static Uint8List _silentWav(Duration length) {
    const rate = 22050;
    final dataBytes = rate * length.inMilliseconds ~/ 1000 * 2;
    final bytes = ByteData(44 + dataBytes);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, rate, Endian.little)
      ..setUint32(28, rate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataBytes, Endian.little);
    return bytes.buffer.asUint8List();
  }
}
