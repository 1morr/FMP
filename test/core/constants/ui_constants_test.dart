import 'package:fmp/core/constants/ui_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kGrayscaleColorMatrix (REC.709 luma)', () {
    test('has exactly 20 elements (4x5 ColorFilter matrix)', () {
      expect(kGrayscaleColorMatrix, hasLength(20));
    });

    test('matches the REC.709 luma weights with identity alpha row', () {
      // 三個 RGB 列複製同一組 REC.709 亮度權重；第四列維持 alpha=1。
      const expected = <double>[
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0.2126, 0.7152, 0.0722, 0, 0, //
        0, 0, 0, 1, 0, //
      ];
      expect(kGrayscaleColorMatrix, expected);
    });
  });
}
