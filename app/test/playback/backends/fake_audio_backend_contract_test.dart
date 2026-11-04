import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/output_device.dart';

import '../fake_audio_backend.dart';
import 'audio_backend_contract.dart';

// 假後端跑同一份契約：控制器的測試靠它代表真後端，所以它的行為要和真後端
// 對得上（真後端的那一份在 integration_test/audio_backend_contract_test.dart）。
void main() {
  final missing = Uri.parse('asset:///missing.wav');
  final forbidden = Uri.parse('asset:///forbidden.wav');
  final stalled = Uri.parse('asset:///stalled.wav');
  late FakeAudioBackend latest;
  final tracks = _FakeTrackServer(() => latest);
  group('FakeAudioBackend', () {
    audioBackendContract(
      define: (description, body) => test(description, body),
      create: () async => latest = FakeAudioBackend(
        durationOf: (url) => Duration(
          milliseconds: int.tryParse(url.queryParameters['ms'] ?? '') ?? 400,
        ),
        failsToOpen: (url) => url == missing || url == forbidden,
        httpStatusOf: (url) => url == forbidden ? 403 : null,
        stallsOnOpen: (url) => url == stalled,
        tick: const Duration(milliseconds: 20),
        outputDevices: FakeOutputDevices(const [
          OutputDevice(id: 'wasapi/{a}', name: 'Speakers'),
        ]),
      ),
      track: Uri.parse('asset:///tone.wav'),
      missing: missing,
      forbidden: () => forbidden,
      stalled: () => stalled,
      server: () => tracks,
      reportsHttpStatus: true,
      selectsOutputDevice: true,
      trackLength: const Duration(milliseconds: 400),
      slack: const Duration(seconds: 2),
    );
  });
}

/// 假後端沒有伺服器：請求是它自己記下的開流（[FakeAudioBackend.requests]），
/// 載入一下就好，所以 `held` 不擋什麼。
final class _FakeTrackServer implements TrackServer {
  _FakeTrackServer(this._backend);

  final FakeAudioBackend Function() _backend;
  var _count = 0;

  @override
  Uri track(Duration length, {bool held = false}) =>
      Uri.parse('asset:///served-${++_count}.wav?ms=${length.inMilliseconds}');

  @override
  int requestsTo(Uri url) => _backend().requests.where((u) => u == url).length;

  @override
  void release(Uri url) {}
}
