import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_sync_service.dart';

void main() {
  group('RemotePlaylistSyncService', () {
    test('starts refresh for matching imported playlists only', () async {
      final startedIds = <int>[];
      final service = RemotePlaylistSyncService(
        getImportedPlaylists: () async => [
          _playlist(1, SourceType.youtube,
              'https://www.youtube.com/playlist?list=PL_MATCH'),
          _playlist(2, SourceType.youtube,
              'https://www.youtube.com/playlist?list=PL_OTHER'),
          _playlist(3, SourceType.bilibili,
              'https://space.bilibili.com/1/favlist?fid=123'),
        ],
        startPlaylistRefresh: (playlist) => startedIds.add(playlist.id),
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.youtube,
        remotePlaylistIds: ['PL_MATCH'],
      );

      expect(matched.map((p) => p.id), [1]);
      expect(startedIds, [1]);
    });

    test('parses Netease hash playlist URL and refreshes match', () async {
      final started = <int>[];
      final service = RemotePlaylistSyncService(
        getImportedPlaylists: () async => [
          _playlist(4, SourceType.netease,
              'https://music.163.com/#/playlist?id=24680'),
        ],
        startPlaylistRefresh: (playlist) => started.add(playlist.id),
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.netease,
        remotePlaylistIds: ['24680'],
      );

      expect(matched.map((p) => p.id), [4]);
      expect(started, [4]);
    });

    test('parses Bilibili favorites URLs and skips mix playlists', () async {
      final started = <int>[];
      final mix = _playlist(
          7, SourceType.youtube, 'https://www.youtube.com/playlist?list=PL_MIX')
        ..isMix = true;
      final service = RemotePlaylistSyncService(
        getImportedPlaylists: () async => [
          _playlist(5, SourceType.bilibili,
              'https://space.bilibili.com/1/favlist?fid=13579'),
          _playlist(6, SourceType.bilibili,
              'https://www.bilibili.com/medialist/detail/ml24680'),
          mix,
        ],
        startPlaylistRefresh: (playlist) => started.add(playlist.id),
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.bilibili,
        remotePlaylistIds: ['13579', '24680'],
      );

      expect(matched.map((p) => p.id), [5, 6]);
      expect(started, [5, 6]);
    });

    test('empty remote id set does not read or refresh playlists', () async {
      var readCalled = false;
      var refreshCalled = false;
      final service = RemotePlaylistSyncService(
        getImportedPlaylists: () async {
          readCalled = true;
          return const [];
        },
        startPlaylistRefresh: (_) => refreshCalled = true,
      );

      final matched = await service.refreshMatchingImportedPlaylists(
        sourceType: SourceType.youtube,
        remotePlaylistIds: ['', '   '],
      );

      expect(matched, isEmpty);
      expect(readCalled, isFalse);
      expect(refreshCalled, isFalse);
    });
  });
}

Playlist _playlist(int id, SourceType sourceType, String sourceUrl) {
  return Playlist()
    ..id = id
    ..name = 'Playlist $id'
    ..sourceUrl = sourceUrl
    ..importSourceType = sourceType;
}
