import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';

void main() {
  test('source manager exposes narrow source capabilities', () {
    final manager = SourceManager();
    addTearDown(manager.dispose);

    for (final sourceType in SourceType.values) {
      expect(
        manager.audioStreamSource(sourceType),
        isA<AudioStreamSource>(),
        reason: '${sourceType.name} should resolve audio streams',
      );
      expect(
        manager.trackInfoSource(sourceType),
        isA<TrackInfoSource>(),
        reason: '${sourceType.name} should load track info',
      );
      expect(
        manager.searchSource(sourceType),
        isA<SearchSource>(),
        reason: '${sourceType.name} should support search',
      );
      expect(
        manager.playlistParsingSource(sourceType),
        isA<PlaylistParsingSource>(),
        reason: '${sourceType.name} should parse internal playlists',
      );
      expect(
        manager.availabilitySource(sourceType),
        isA<AvailabilitySource>(),
        reason: '${sourceType.name} should check availability',
      );
    }
  });

  test('url detection returns source type without broad source exposure', () {
    final manager = SourceManager();
    addTearDown(manager.dispose);

    expect(
      manager.sourceTypeForUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      SourceType.youtube,
    );
    expect(
      manager.sourceTypeForUrl('https://www.bilibili.com/video/BV1xx411c7mD'),
      SourceType.bilibili,
    );
  });

  test('source manager owns a mutable copy of registered capabilities', () {
    final manager = SourceManager(sources: const []);

    expect(manager.dispose, returnsNormally);
  });

  test('base_source.dart no longer declares broad BaseSource interface', () {
    final source = File('lib/data/sources/base_source.dart').readAsStringSync();
    expect(source, isNot(contains('abstract class BaseSource')));
    expect(source, isNot(contains('extends BaseSource')));
  });
}
