import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/fonts/fonts.dart';
import 'package:fmp/platform/fonts/fonts_android.dart';
import 'package:fmp/platform/fonts/fonts_windows.dart';

void main() {
  group('Windows', () {
    test('Traditional Chinese uses JhengHei', () {
      expect(windowsFontFallback.familiesFor(FontLanguage.zhTw), [
        'Microsoft JhengHei UI',
        'Microsoft JhengHei',
      ]);
    });

    test('Simplified Chinese uses YaHei', () {
      expect(windowsFontFallback.familiesFor(FontLanguage.zhCn), [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
      ]);
    });

    test('English puts the Traditional list before the Simplified one', () {
      expect(windowsFontFallback.familiesFor(FontLanguage.en), [
        'Microsoft JhengHei UI',
        'Microsoft JhengHei',
        'Microsoft YaHei UI',
        'Microsoft YaHei',
      ]);
    });
  });

  test('Android names no fonts in any language', () {
    // 系統 Noto CJK 沒有 family 名稱，指名無效（fonts_android.dart）。
    for (final language in FontLanguage.values) {
      expect(androidFontFallback.familiesFor(language), isEmpty);
    }
  });
}
