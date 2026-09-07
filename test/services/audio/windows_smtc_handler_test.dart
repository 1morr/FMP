import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/audio/playback_capabilities.dart';
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

    test(
      'allows previous track metadata after different metadata is published',
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
      },
    );
  });

  group('smtcConfigForCapabilities', () {
    test('music keeps next and previous enabled', () {
      final config = smtcConfigForCapabilities(PlaybackCapabilities.music);

      expect(config.nextEnabled, isTrue);
      expect(config.prevEnabled, isTrue);
      expect(config.playEnabled, isTrue);
      expect(config.pauseEnabled, isTrue);
      expect(config.stopEnabled, isTrue);
    });

    test('live radio withdraws next and previous but keeps transport', () {
      final config = smtcConfigForCapabilities(PlaybackCapabilities.liveRadio);

      // issue #40 症狀一：過去這兩個永遠是 true，按下去打進 null。
      expect(config.nextEnabled, isFalse);
      expect(config.prevEnabled, isFalse);
      expect(config.playEnabled, isTrue);
      expect(config.pauseEnabled, isTrue);
      expect(config.stopEnabled, isTrue);
    });

    test('fast forward and rewind are never advertised', () {
      for (final capabilities in [
        PlaybackCapabilities.music,
        PlaybackCapabilities.liveRadio,
        PlaybackCapabilities.none,
      ]) {
        final config = smtcConfigForCapabilities(capabilities);
        expect(config.fastForwardEnabled, isFalse);
        expect(config.rewindEnabled, isFalse);
      }
    });

    test('the same capabilities produce equal configs', () {
      // updateCapabilities 的去重靠套件自己的 == —— 這條釘住那個前提。
      expect(
        smtcConfigForCapabilities(PlaybackCapabilities.music),
        smtcConfigForCapabilities(PlaybackCapabilities.music),
      );
      expect(
        smtcConfigForCapabilities(PlaybackCapabilities.music),
        isNot(smtcConfigForCapabilities(PlaybackCapabilities.liveRadio)),
      );
    });
  });
}
