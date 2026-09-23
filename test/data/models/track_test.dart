import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';

void main() {
  group('formattedDuration', () {
    test('returns --:-- when durationMs is null', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceIds.bilibili
        ..title = 'Test Track';

      expect(track.formattedDuration, equals('--:--'));
    });

    test('formats seconds correctly', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceIds.bilibili
        ..title = 'Test Track'
        ..durationMs = 45000; // 45 seconds

      expect(track.formattedDuration, equals('00:45'));
    });

    test('formats minutes and seconds correctly', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceIds.bilibili
        ..title = 'Test Track'
        ..durationMs = 185000; // 3:05

      expect(track.formattedDuration, equals('03:05'));
    });

    test('formats hours correctly', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceIds.bilibili
        ..title = 'Test Track'
        ..durationMs = 3725000; // 1:02:05

      expect(track.formattedDuration, equals('01:02:05'));
    });
  });
}
