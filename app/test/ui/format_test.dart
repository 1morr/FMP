import 'package:flutter_test/flutter_test.dart';
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
}
