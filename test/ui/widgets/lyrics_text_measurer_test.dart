import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/ui/widgets/lyrics/lyrics_text_measurer.dart';

void main() {
  group('LyricsTextMeasurer.fontSizesFromReferenceWidth (C1b)', () {
    const min = 14.0, max = 30.0, ref = 20.0, ratio = 0.65, bold = 0.95;

    test('null reference width falls back to max main size', () {
      final r = LyricsTextMeasurer.fontSizesFromReferenceWidth(
        referenceWidth: null,
        availableWidth: 300,
        minFontSize: min,
        maxFontSize: max,
        refFontSize: ref,
        subFontRatio: ratio,
        boldSafetyFactor: bold,
      );
      expect(r.main, max);
      expect(r.sub, (max * ratio).clamp(min, max));
    });

    test('zero reference width falls back to max main size', () {
      final r = LyricsTextMeasurer.fontSizesFromReferenceWidth(
        referenceWidth: 0,
        availableWidth: 300,
        minFontSize: min,
        maxFontSize: max,
        refFontSize: ref,
        subFontRatio: ratio,
        boldSafetyFactor: bold,
      );
      expect(r.main, max);
    });

    test('very wide reference text clamps main to min font size', () {
      // 代表行寬度遠大於可用寬度 → 字級應降到下限。
      final r = LyricsTextMeasurer.fontSizesFromReferenceWidth(
        referenceWidth: 10000,
        availableWidth: 100,
        minFontSize: min,
        maxFontSize: max,
        refFontSize: ref,
        subFontRatio: ratio,
        boldSafetyFactor: bold,
      );
      expect(r.main, min);
      expect(r.sub, min); // sub = main*ratio 會更低，clamp 到 min
    });

    test('very narrow reference text clamps main to max font size', () {
      final r = LyricsTextMeasurer.fontSizesFromReferenceWidth(
        referenceWidth: 1,
        availableWidth: 1000,
        minFontSize: min,
        maxFontSize: max,
        refFontSize: ref,
        subFontRatio: ratio,
        boldSafetyFactor: bold,
      );
      expect(r.main, max);
    });

    test('sub scales with main and stays within [min, max]', () {
      final r = LyricsTextMeasurer.fontSizesFromReferenceWidth(
        referenceWidth: 100,
        availableWidth: 100,
        minFontSize: min,
        maxFontSize: max,
        refFontSize: ref,
        subFontRatio: ratio,
        boldSafetyFactor: bold,
      );
      // safeWidth=95, main=20*(95/100)=19, sub=19*0.65=12.35 → clamp 到 14。
      expect(r.main, closeTo(19.0, 0.1));
      expect(r.sub, min); // 12.35 clamp 到 minFontSize
      expect(r.sub, greaterThanOrEqualTo(min));
      expect(r.sub, lessThanOrEqualTo(max));
    });
  });

  group('LyricsTextMeasurer.medianReferenceWidth', () {
    testWidgets('returns 0 when all lines are empty', (tester) async {
      final w = LyricsTextMeasurer.medianReferenceWidth(
        texts: ['', '', ''],
        refFontSize: 20,
        styleBuilder: (fs, w) => TextStyle(fontSize: fs, fontWeight: w),
        textDirection: TextDirection.ltr,
      );
      expect(w, 0);
    });

    testWidgets('returns a positive median width for non-empty lines',
        (tester) async {
      final w = LyricsTextMeasurer.medianReferenceWidth(
        texts: const ['hello', 'a really long lyrics line', 'mid'],
        refFontSize: 20,
        styleBuilder: (fs, w) => TextStyle(fontSize: fs, fontWeight: w),
        textDirection: TextDirection.ltr,
      );
      expect(w, greaterThan(0));
    });
  });
}
