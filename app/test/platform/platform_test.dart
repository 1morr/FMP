import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/audio/audio_android.dart';
import 'package:fmp/platform/audio/audio_windows.dart';
import 'package:fmp/platform/connectivity/connectivity_plus_interfaces.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/fonts/fonts_android.dart';
import 'package:fmp/platform/fonts/fonts_windows.dart';
import 'package:fmp/platform/platform.dart';

void main() {
  group('AppPlatform.assemble', () {
    test('Android has a data directory, picks glyphs by locale, plays '
        'with just_audio and sees network interfaces', () {
      final platform = AppPlatform.assemble(
        TargetPlatform.android,
        AppFlavor.dev,
      );

      expect(platform.capabilities.dataDirectory, isTrue);
      expect(platform.dataDirectory, isA<AndroidAppDataDirectory>());
      expect(platform.capabilities.singleInstance, isFalse);
      expect(platform.capabilities.fontFallback, same(androidFontFallback));
      expect(platform.capabilities.playback, same(androidPlaybackSupport));
      expect(
        platform.capabilities.playback?.backend,
        AudioBackendKind.justAudio,
      );
      expect(platform.capabilities.networkInterfaces, isTrue);
      expect(platform.networkInterfaces, isA<ConnectivityPlusInterfaces>());
    });

    test('Windows has a data directory, a single instance, named fonts, '
        'plays with media_kit and sees network interfaces', () {
      final platform = AppPlatform.assemble(
        TargetPlatform.windows,
        AppFlavor.dev,
      );

      expect(platform.capabilities.dataDirectory, isTrue);
      expect(platform.dataDirectory, isA<WindowsAppDataDirectory>());
      expect(platform.capabilities.singleInstance, isTrue);
      expect(platform.capabilities.fontFallback, same(windowsFontFallback));
      expect(platform.capabilities.playback, same(windowsPlaybackSupport));
      expect(
        platform.capabilities.playback?.backend,
        AudioBackendKind.mediaKit,
      );
      expect(platform.capabilities.networkInterfaces, isTrue);
      expect(platform.networkInterfaces, isA<ConnectivityPlusInterfaces>());
    });

    for (final unverified in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      test('${unverified.name} declares nothing and has no implementation', () {
        final platform = AppPlatform.assemble(unverified, AppFlavor.prod);

        expect(platform.capabilities.dataDirectory, isFalse);
        expect(platform.dataDirectory, isNull);
        expect(platform.capabilities.singleInstance, isFalse);
        expect(platform.capabilities.playback, isNull);
        expect(platform.capabilities.networkInterfaces, isFalse);
        expect(platform.networkInterfaces, isNull);
        for (final language in FontLanguage.values) {
          expect(
            platform.capabilities.fontFallback.familiesFor(language),
            isEmpty,
          );
        }
      });
    }
  });

  test(
    'both verified platforms can play the test plugin and the M1 sources',
    () {
      // 測試插件的 WAV，B 站的 DASH 音訊（fMP4／AAC）：插件照這張表挑候選。
      for (final support in [androidPlaybackSupport, windowsPlaybackSupport]) {
        expect(
          support.formats,
          containsAll(const [
            PlayableFormat('wav', 'pcm_s16le'),
            PlayableFormat('mp4', 'aac'),
          ]),
        );
      }
    },
  );
}
