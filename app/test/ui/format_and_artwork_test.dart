import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/format/byte_size.dart';
import 'package:fmp/ui/format/duration_text.dart';

void main() {
  group('formatDuration', () {
    for (final (duration, text) in [
      (Duration.zero, '0:00'),
      (const Duration(seconds: 5), '0:05'),
      (const Duration(minutes: 3, seconds: 5, milliseconds: 900), '3:05'),
      (const Duration(minutes: 59, seconds: 59), '59:59'),
      (const Duration(hours: 1, minutes: 2, seconds: 3), '1:02:03'),
      (const Duration(seconds: -3), '0:00'),
    ]) {
      test('$duration is $text', () => expect(formatDuration(duration), text));
    }
  });

  group('formatByteSize', () {
    for (final (bytes, text) in [
      (0, '0 B'),
      (1023, '1023 B'),
      (1024, '1 KB'),
      (1536, '2 KB'),
      (512 * 1024, '512 KB'),
      // 四捨五入到 1024 KB 的就是 1 MB，不顯示「1024 KB」。
      (1024 * 1024 - 1, '1.0 MB'),
      (1024 * 1024 - 512, '1.0 MB'),
      (1024 * 1024, '1.0 MB'),
      (12900 * 1024, '12.6 MB'),
      (1024 * 1024 * 1024, '1024.0 MB'),
    ]) {
      test('$bytes is $text', () => expect(formatByteSize(bytes), text));
    }
  });

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
