import 'dart:io';

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
// 「HTTP 拒絕」的網址是測試自己在 loopback 起的伺服器（一律回 403），不連外網；
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
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
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
