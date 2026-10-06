import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/just_audio_backend.dart';
import 'package:fmp/playback/backends/media_kit_backend.dart';

/// 依平台宣告的 [support] 建立後端。只有這裡與兩個實作檔知道具體的引擎。
///
/// 宣告與實作要對得上（ADR 0009 §如何確認）：宣告能選輸出裝置的平台，後端的
/// `outputDevices` 不為空，反之亦然。真後端的契約（`integration_test/
/// audio_backend_contract_test.dart`，debug 建置）經這裡建後端，所以兩個平台
/// 跑契約時都會檢查。
AudioBackend createAudioBackend(PlaybackSupport support, {required Log log}) {
  final backend = switch (support.backend) {
    AudioBackendKind.justAudio => JustAudioBackend(log: log),
    AudioBackendKind.mediaKit => MediaKitBackend.create(log: log),
  };
  assert(
    support.outputDeviceSelection == (backend.outputDevices != null),
    'PlaybackSupport.outputDeviceSelection disagrees with the backend',
  );
  return backend;
}
