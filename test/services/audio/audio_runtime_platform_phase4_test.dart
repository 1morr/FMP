import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_runtime_platform.dart';
import 'package:fmp/services/audio/just_audio_service.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';

void main() {
  group('Audio runtime platform phase 4', () {
    test('selectAudioRuntimePlatform chooses desktop for windows and linux', () {
      expect(
        selectAudioRuntimePlatform('windows'),
        AudioRuntimePlatform.desktop,
      );
      expect(
        selectAudioRuntimePlatform('linux'),
        AudioRuntimePlatform.desktop,
      );
    });

    test('selectAudioRuntimePlatform chooses mobile for android and ios', () {
      expect(
        selectAudioRuntimePlatform('android'),
        AudioRuntimePlatform.mobile,
      );
      expect(
        selectAudioRuntimePlatform('ios'),
        AudioRuntimePlatform.mobile,
      );
    });

    test('audioServiceProvider selects desktop backend for desktop override', () {
      final container = ProviderContainer(
        overrides: [
          audioRuntimePlatformProvider.overrideWithValue(
            AudioRuntimePlatform.desktop,
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(audioServiceProvider);

      expect(service, isA<MediaKitAudioService>());
    });

    test('audioServiceProvider selects mobile backend for mobile override', () {
      final container = ProviderContainer(
        overrides: [
          audioRuntimePlatformProvider.overrideWithValue(
            AudioRuntimePlatform.mobile,
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(audioServiceProvider);

      expect(service, isA<JustAudioService>());
    });
  });
}
