import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/playlist_import/playlist_import_source.dart';
import 'package:fmp/services/import/playlist_import_service.dart';

void main() {
  group('PlaylistImportResult.selectedTracks', () {
    test('copies selected tracks before writing original platform metadata',
        () {
      final selected = Track()
        ..id = 42
        ..sourceId = 'matched-bv'
        ..sourceType = SourceType.bilibili
        ..title = 'Matched Song'
        ..artist = 'Matched Artist';

      final result = PlaylistImportResult(
        playlist: const ImportedPlaylist(
          name: 'QQ Playlist',
          sourceUrl: 'https://y.qq.com/n/ryqq/playlist/123',
          source: PlaylistSource.qqMusic,
          tracks: [],
          totalCount: 1,
        ),
        matchedTracks: [
          MatchedTrack(
            original: const ImportedTrack(
              title: 'Original Song',
              artists: ['Original Artist'],
              sourceId: 'qq-songmid-1',
              source: PlaylistSource.qqMusic,
            ),
            selectedTrack: selected,
            status: MatchStatus.userSelected,
          ),
        ],
      );

      final tracks = result.selectedTracks;

      expect(tracks, hasLength(1));
      expect(identical(tracks.single, selected), isFalse);
      expect(tracks.single.id, selected.id);
      expect(tracks.single.sourceId, selected.sourceId);
      expect(tracks.single.originalSongId, 'qq-songmid-1');
      expect(tracks.single.originalSource, 'qqmusic');
      expect(selected.originalSongId, isNull);
      expect(selected.originalSource, isNull);
    });
  });
}
