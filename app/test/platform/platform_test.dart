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
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/platform.dart';

void main() {
  group('AppPlatform.assemble', () {
    test('Android has a data directory, picks glyphs by locale, plays '
        'with just_audio without choosing an output device, sees network '
        'interfaces and has a cache', () {
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
      // 輸出跟著系統；後端的 outputDevices 為空（createAudioBackend 的 assert、
      // 真後端契約）。
      expect(platform.capabilities.playback?.outputDeviceSelection, isFalse);
      expect(platform.capabilities.networkInterfaces, isTrue);
      expect(platform.networkInterfaces, isA<ConnectivityPlusInterfaces>());
      expect(platform.capabilities.cache, same(androidCacheSizes));
      expect(platform.cacheDirectory, isA<CacheDirectory>());
      expect(platform.capabilities.mediaControls?.supportsSeek, isTrue);
    });

    test('Windows has a data directory, a single instance, named fonts, '
        'plays with media_kit and chooses output devices, sees network '
        'interfaces and has a cache', () {
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
      expect(platform.capabilities.playback?.outputDeviceSelection, isTrue);
      expect(platform.capabilities.networkInterfaces, isTrue);
      expect(platform.networkInterfaces, isA<ConnectivityPlusInterfaces>());
      expect(platform.capabilities.cache, same(windowsCacheSizes));
      expect(platform.cacheDirectory, isA<CacheDirectory>());
      // Windows 的 SMTC 在 M2 PR 16b 才有。
      expect(platform.capabilities.mediaControls, isNull);
      expect(platform.mediaControls, isNull);
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
        expect(platform.capabilities.mediaControls, isNull);
        expect(platform.mediaControls, isNull);
        for (final language in FontLanguage.values) {
          expect(
            platform.capabilities.fontFallback.familiesFor(language),
            isEmpty,
          );
        }
      });
    }
  });

  group('system media controls on Android', () {
    test(
      'initializing keeps the declaration and exposes the controls',
      () async {
        final controls = _FakeControls();
        final platform = await AppPlatform.assemble(
          TargetPlatform.android,
          AppFlavor.dev,
          androidMediaControls: () async => controls,
        ).withMediaControls(onFailure: (_, _) => fail('should not fail'));

        expect(platform.mediaControls, same(controls));
        expect(platform.capabilities.mediaControls?.supportsSeek, isTrue);
      },
    );

    test('a failed initialization is logged and declares none', () async {
      final failures = <Object>[];
      final platform = await AppPlatform.assemble(
        TargetPlatform.android,
        AppFlavor.dev,
        androidMediaControls: () async => throw StateError('no service'),
      ).withMediaControls(onFailure: (error, _) => failures.add(error));

      expect(failures, hasLength(1));
      expect(platform.mediaControls, isNull);
      expect(platform.capabilities.mediaControls, isNull);
      // 其他能力不受影響。
      expect(platform.capabilities.playback, same(androidPlaybackSupport));
      expect(platform.dataDirectory, isA<AndroidAppDataDirectory>());
    });

    test('a platform without the capability initializes nothing', () async {
      final platform = await AppPlatform.assemble(
        TargetPlatform.windows,
        AppFlavor.dev,
      ).withMediaControls(onFailure: (_, _) => fail('should not run'));

      expect(platform.mediaControls, isNull);
    });
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

final class _FakeControls implements SystemMediaControls {
  @override
  Stream<MediaCommand> get commands => const Stream.empty();

  @override
  Future<void> publish(NowPlaying nowPlaying) async {}

  @override
  Future<void> dispose() async {}
}
