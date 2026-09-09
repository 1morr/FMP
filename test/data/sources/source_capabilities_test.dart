import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';

void main() {
  test('source manager exposes narrow source capabilities', () {
    final manager = SourceManager();
    addTearDown(manager.dispose);

    for (final sourceType in SourceIds.values) {
      expect(
        manager.audioStreamSource(sourceType),
        isA<AudioStreamSource>(),
        reason: '$sourceType should resolve audio streams',
      );
      expect(
        manager.trackInfoSource(sourceType),
        isA<TrackInfoSource>(),
        reason: '$sourceType should load track info',
      );
      expect(
        manager.searchSource(sourceType),
        isA<SearchSource>(),
        reason: '$sourceType should support search',
      );
      expect(
        manager.playlistParsingSource(sourceType),
        isA<PlaylistParsingSource>(),
        reason: '$sourceType should parse internal playlists',
      );
    }
  });

  test('url detection returns source type without broad source exposure', () {
    final manager = SourceManager();
    addTearDown(manager.dispose);

    expect(
      manager.sourceTypeForUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      SourceIds.youtube,
    );
    expect(
      manager.sourceTypeForUrl('https://www.bilibili.com/video/BV1xx411c7mD'),
      SourceIds.bilibili,
    );
  });

  test('source manager owns a mutable copy of registered capabilities', () {
    final manager = SourceManager(sources: const []);

    expect(manager.dispose, returnsNormally);
  });

  test(
    'source manager exposes detail, pages, dynamic playlist, ranking, and live capabilities',
    () {
      final manager = SourceManager();
      addTearDown(manager.dispose);

      expect(
        manager.trackDetailSource(SourceIds.bilibili),
        isA<TrackDetailSource>(),
      );
      expect(
        manager.trackDetailSource(SourceIds.youtube),
        isA<TrackDetailSource>(),
      );
      expect(
        manager.trackDetailSource(SourceIds.netease),
        isA<TrackDetailSource>(),
      );

      expect(
        manager.pagedVideoSource(SourceIds.bilibili),
        isA<PagedVideoSource>(),
      );
      expect(manager.pagedVideoSource(SourceIds.youtube), isNull);
      expect(manager.pagedVideoSource(SourceIds.netease), isNull);

      expect(
        manager.dynamicPlaylistSource(SourceIds.youtube),
        isA<DynamicPlaylistSource>(),
      );
      expect(manager.dynamicPlaylistSource(SourceIds.bilibili), isNull);
      expect(manager.dynamicPlaylistSource(SourceIds.netease), isNull);

      expect(manager.rankingSource(SourceIds.bilibili), isA<RankingSource>());
      expect(manager.rankingSource(SourceIds.youtube), isA<RankingSource>());
      expect(manager.rankingSource(SourceIds.netease), isA<RankingSource>());

      expect(manager.liveSource(SourceIds.bilibili), isA<LiveSource>());
      expect(manager.liveSource(SourceIds.youtube), isNull);
      expect(manager.liveSource(SourceIds.netease), isNull);
    },
  );
}
