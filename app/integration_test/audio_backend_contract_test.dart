import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
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
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final support = AppPlatform.current(AppFlavor.dev).capabilities.playback;
  if (support == null) {
    test('this platform declares no playback backend', () {}, skip: true);
    return;
  }
  final log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);

  group(support.backend.name, () {
    audioBackendContract(
      define: (description, body) => testWidgets(
        description,
        (tester) => tester.runAsync(body),
        timeout: const Timeout(Duration(minutes: 1)),
      ),
      create: () async => createAudioBackend(support.backend, log: log),
      track: Uri.parse('asset:///test/fixtures/plugins/test_plugin/tone.wav'),
      missing: Uri.parse(
        'asset:///test/fixtures/plugins/test_plugin/missing.wav',
      ),
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
