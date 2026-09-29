import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_android.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory_windows.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/fonts/fonts_android.dart';
import 'package:fmp/platform/fonts/fonts_windows.dart';
import 'package:fmp/platform/platform.dart';

void main() {
  group('AppPlatform.assemble', () {
    test('Android has a data directory and picks glyphs by locale', () {
      final platform = AppPlatform.assemble(
        TargetPlatform.android,
        AppFlavor.dev,
      );

      expect(platform.capabilities.dataDirectory, isTrue);
      expect(platform.dataDirectory, isA<AndroidAppDataDirectory>());
      expect(platform.capabilities.singleInstance, isFalse);
      expect(platform.capabilities.fontFallback, same(androidFontFallback));
    });

    test('Windows has a data directory, a single instance and named fonts', () {
      final platform = AppPlatform.assemble(
        TargetPlatform.windows,
        AppFlavor.dev,
      );

      expect(platform.capabilities.dataDirectory, isTrue);
      expect(platform.dataDirectory, isA<WindowsAppDataDirectory>());
      expect(platform.capabilities.singleInstance, isTrue);
      expect(platform.capabilities.fontFallback, same(windowsFontFallback));
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
        for (final language in FontLanguage.values) {
          expect(
            platform.capabilities.fontFallback.familiesFor(language),
            isEmpty,
          );
        }
      });
    }
  });
}
