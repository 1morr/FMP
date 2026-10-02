import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';
import 'package:fmp/platform/audio/audio.dart';
import 'package:fmp/platform/audio/audio_android.dart';
import 'package:fmp/platform/audio/audio_windows.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes_android.dart';
import 'package:fmp/platform/cache_sizes/cache_sizes_windows.dart';
import 'package:fmp/platform/connectivity/connectivity_plus_interfaces.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/fonts/fonts_android.dart';
import 'package:fmp/platform/fonts/fonts_windows.dart';
import 'package:fmp/platform/platform.dart';

void main() {
  group('AppPlatform.assemble', () {
    test('Android has a data directory, picks glyphs by locale, plays '
        'with just_audio, sees network interfaces and has a cache', () {
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
      expect(platform.capabilities.cache, same(androidCacheSizes));
      expect(platform.cacheDirectory, isA<CacheDirectory>());
    });

    test('Windows has a data directory, a single instance, named fonts, '
        'plays with media_kit, sees network interfaces and has a cache', () {
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
      expect(platform.capabilities.cache, same(windowsCacheSizes));
      expect(platform.cacheDirectory, isA<CacheDirectory>());
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
        expect(platform.capabilities.cache, isNull);
        expect(platform.cacheDirectory, isNull);
        for (final language in FontLanguage.values) {
          expect(
            platform.capabilities.fontFallback.familiesFor(language),
            isEmpty,
          );
        }
      });
    }
  });

  test('cache sizes follow ADR 0016 and the old app', () {
    // 快取上限的預設：行動 128MB、桌面 256MB（ADR 0016 §決定 3）；記憶體
    // ImageCache 沿用舊版 lib/main.dart:156-164。
    expect(androidCacheSizes.defaultLimitBytes, 128 * 1024 * 1024);
    expect(androidCacheSizes.memoryImages, 100);
    expect(androidCacheSizes.memoryImageBytes, 50 * 1024 * 1024);
    expect(windowsCacheSizes.defaultLimitBytes, 256 * 1024 * 1024);
    expect(windowsCacheSizes.memoryImages, 200);
    expect(windowsCacheSizes.memoryImageBytes, 80 * 1024 * 1024);
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
