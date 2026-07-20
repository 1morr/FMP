import 'package:fmp/ui/widgets/lyrics/lyrics_offset_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LyricsOffsetMath (C1d)', () {
    test('calibrationOffsetForLine = line timestamp - current position', () {
      expect(
        LyricsOffsetMath.calibrationOffsetForLine(
          const Duration(milliseconds: 5000),
          3000,
        ),
        2000,
      );
      expect(
        LyricsOffsetMath.calibrationOffsetForLine(
          const Duration(milliseconds: 1000),
          4000,
        ),
        -3000,
      );
      expect(
        LyricsOffsetMath.calibrationOffsetForLine(
          const Duration(milliseconds: 2500),
          2500,
        ),
        0,
      );
    });

    test('format renders sign + one-decimal seconds', () {
      expect(LyricsOffsetMath.format(0), '0.0s');
      expect(LyricsOffsetMath.format(1500), '+1.5s');
      expect(LyricsOffsetMath.format(1000), '+1.0s');
      expect(LyricsOffsetMath.format(-500), '-0.5s');
      expect(LyricsOffsetMath.format(-1250), '-1.3s');
    });
  });
}
