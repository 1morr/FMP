import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';

void main() {
  group('SmtcMetadataDeduplicator', () {
    test('suppresses repeated identical metadata fingerprints', () {
      final deduplicator = SmtcMetadataDeduplicator();
      const metadata = SmtcMetadataFingerprint(
        title: 'Song',
        artist: 'Artist',
        thumbnail: 'https://example.com/cover.jpg',
      );

      expect(deduplicator.shouldPublish(metadata), isTrue);

      deduplicator.markPublished(metadata);

      expect(deduplicator.shouldPublish(metadata), isFalse);
    });

    test('allows changed thumbnails', () {
      final deduplicator = SmtcMetadataDeduplicator();
      const first = SmtcMetadataFingerprint(
        title: 'Song',
        artist: 'Artist',
        thumbnail: 'https://example.com/cover-a.jpg',
      );
      const second = SmtcMetadataFingerprint(
        title: 'Song',
        artist: 'Artist',
        thumbnail: 'https://example.com/cover-b.jpg',
      );

      deduplicator.markPublished(first);

      expect(deduplicator.shouldPublish(second), isTrue);
    });

    test('allows previous track metadata after different metadata is published',
        () {
      final deduplicator = SmtcMetadataDeduplicator();
      const track = SmtcMetadataFingerprint(
        title: 'Song',
        artist: 'Artist',
        thumbnail: 'https://example.com/cover.jpg',
      );
      const radio = SmtcMetadataFingerprint(
        title: 'Radio',
        artist: 'Host',
        thumbnail: null,
      );

      deduplicator.markPublished(track);
      deduplicator.markPublished(radio);

      expect(deduplicator.shouldPublish(track), isTrue);
    });
  });
}
