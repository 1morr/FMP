import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/output_device.dart';

import '../fake_audio_backend.dart';
import 'audio_backend_contract.dart';

// 假後端跑同一份契約：控制器的測試靠它代表真後端，所以它的行為要和真後端
// 對得上（真後端的那一份在 integration_test/audio_backend_contract_test.dart）。
void main() {
  final missing = Uri.parse('asset:///missing.wav');
  final forbidden = Uri.parse('asset:///forbidden.wav');
  group('FakeAudioBackend', () {
    audioBackendContract(
      define: (description, body) => test(description, body),
      create: () async => FakeAudioBackend(
        durationOf: (_) => const Duration(milliseconds: 400),
        failsToOpen: (url) => url == missing || url == forbidden,
        httpStatusOf: (url) => url == forbidden ? 403 : null,
        tick: const Duration(milliseconds: 20),
        outputDevices: FakeOutputDevices(const [
          OutputDevice(id: 'wasapi/{a}', name: 'Speakers'),
        ]),
      ),
      track: Uri.parse('asset:///tone.wav'),
      missing: missing,
      forbidden: () => forbidden,
      reportsHttpStatus: true,
      selectsOutputDevice: true,
      trackLength: const Duration(milliseconds: 400),
      slack: const Duration(seconds: 2),
    );
  });
}
