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

  test(
      'source manager exposes detail, pages, dynamic playlist, ranking, and live capabilities',
      () {
    final manager = SourceManager();
    addTearDown(manager.dispose);

    expect(manager.trackDetailSource(SourceType.bilibili),
        isA<TrackDetailSource>());
    expect(manager.trackDetailSource(SourceType.youtube),
        isA<TrackDetailSource>());
    expect(manager.trackDetailSource(SourceType.netease),
        isA<TrackDetailSource>());

    expect(
        manager.pagedVideoSource(SourceType.bilibili), isA<PagedVideoSource>());
    expect(manager.pagedVideoSource(SourceType.youtube), isNull);
    expect(manager.pagedVideoSource(SourceType.netease), isNull);

    expect(manager.dynamicPlaylistSource(SourceType.youtube),
        isA<DynamicPlaylistSource>());
    expect(manager.dynamicPlaylistSource(SourceType.bilibili), isNull);
    expect(manager.dynamicPlaylistSource(SourceType.netease), isNull);

    expect(manager.rankingSource(SourceType.bilibili), isA<RankingSource>());
    expect(manager.rankingSource(SourceType.youtube), isA<RankingSource>());
    expect(manager.rankingSource(SourceType.netease), isA<RankingSource>());

    expect(manager.liveSource(SourceType.bilibili), isA<LiveSource>());
    expect(manager.liveSource(SourceType.youtube), isNull);
    expect(manager.liveSource(SourceType.netease), isNull);
  });
}
