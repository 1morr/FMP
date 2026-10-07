import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track_info.dart';

void main() {
  // ADR 0016 §決定 4：最接近且不小於顯示尺寸的一張。
  group('pickArtwork', () {
    TrackArtwork art(String name, [int? width]) =>
        TrackArtwork(url: Uri.parse('https://img.example/$name'), width: width);
    String? pick(List<TrackArtwork> artwork, double pixels) =>
        pickArtwork(artwork, pixels)?.url.pathSegments.last;

    test('the smallest one that is big enough', () {
      expect(pick([art('s', 64), art('l', 480), art('m', 160)], 144), 'm');
      expect(pick([art('s', 64), art('m', 144)], 144), 'm');
    });

    test('all too small: one without a width, then the largest', () {
      expect(pick([art('s', 64), art('o'), art('m', 100)], 144), 'o');
      expect(pick([art('s', 64), art('m', 100)], 144), 'm');
    });

    test('a known big-enough one beats one without a width', () {
      expect(pick([art('o'), art('l', 480)], 144), 'l');
    });

    test('nothing to pick', () => expect(pick([], 144), isNull));
  });
}
