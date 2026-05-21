import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/lyrics_styled_text.dart';

void main() {
  group('LyricsTextStyles', () {
    test('preserves theme font family and fallback in lyric styles', () {
      const themeStyle = TextStyle(
        fontFamily: 'Microsoft YaHei UI',
        fontFamilyFallback: ['Microsoft YaHei', 'Noto Sans SC'],
      );

      final style = LyricsTextStyles.fromBase(
        themeStyle,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.4,
      );

      expect(style.fontFamily, 'Microsoft YaHei UI');
      expect(style.fontFamilyFallback, ['Microsoft YaHei', 'Noto Sans SC']);
      expect(style.fontSize, 18);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.color, Colors.white);
      expect(style.height, 1.4);
    });
  });
}
