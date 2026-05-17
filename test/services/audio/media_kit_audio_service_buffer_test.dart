import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';

void main() {
  group('MediaKitAudioService desktop buffering', () {
    test('uses a larger desktop network buffer profile', () {
      expect(
        MediaKitAudioService.desktopPlayerBufferSizeBytes,
        16 * 1024 * 1024,
      );
      expect(
        MediaKitAudioService.desktopDemuxerMaxBytes,
        8 * 1024 * 1024,
      );
      expect(
        MediaKitAudioService.desktopDemuxerMaxBackBytes,
        1024 * 1024,
      );
      expect(
        MediaKitAudioService.desktopBufferSeconds,
        30,
      );
    });
  });
}
