import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';

void main() {
  group('MediaKitAudioService desktop buffering', () {
    test('uses a larger desktop network buffer profile', () {
      expect(
        MediaKitAudioService.desktopPlayerBufferSizeBytes,
        32 * 1024 * 1024,
      );
      expect(
        MediaKitAudioService.desktopDemuxerMaxBytes,
        24 * 1024 * 1024,
      );
      expect(
        MediaKitAudioService.desktopDemuxerMaxBackBytes,
        8 * 1024 * 1024,
      );
      expect(
        MediaKitAudioService.desktopBufferSeconds,
        7200,
      );
      expect(
        MediaKitAudioService.desktopLavfReconnectOptions,
        contains('reconnect=1'),
      );
      expect(
        MediaKitAudioService.desktopLavfReconnectOptions,
        contains('reconnect_streamed=1'),
      );
      expect(
        MediaKitAudioService.desktopLavfReconnectOptions,
        contains('reconnect_on_network_error=1'),
      );
    });
  });
}
