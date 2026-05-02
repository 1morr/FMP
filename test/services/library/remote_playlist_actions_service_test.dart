import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/library/remote_playlist_actions_service.dart';

void main() {
  group('RemotePlaylistActionsService', () {
    test(
      'batch Bilibili removal filters Bilibili tracks and removes parsed aids',
      () async {
        final requestedAidTracks = <String>[];
        int? removedFolderId;
        List<int>? removedAids;
        final service = _service(
          getBilibiliAid: (track) async {
            requestedAidTracks.add(track.sourceId);
            return switch (track.sourceId) {
              'BV1' => 101,
              'BV2' => 202,
              _ => throw StateError('unexpected track ${track.sourceId}'),
            };
          },
          removeBilibiliTracks: ({
            required folderId,
            required videoAids,
          }) async {
            removedFolderId = folderId;
            removedAids = videoAids;
          },
        );

        final removed = await service.removeTracksFromRemote(
          sourceUrl: 'https://space.bilibili.com/1/favlist?fid=12345',
          importSourceType: SourceType.bilibili,
          tracks: [
            _track(SourceType.bilibili, 'BV1'),
            _track(SourceType.youtube, 'yt1'),
            _track(SourceType.bilibili, 'BV2'),
          ],
        );

        expect(removed, isTrue);
        expect(requestedAidTracks, ['BV1', 'BV2']);
        expect(removedFolderId, 12345);
        expect(removedAids, [101, 202]);
      },
    );

    test('single Bilibili removal delegates to batch removal', () async {
      int? removedFolderId;
      List<int>? removedAids;
      final service = _service(
        getBilibiliAid: (_) async => 303,
        removeBilibiliTracks: ({required folderId, required videoAids}) async {
          removedFolderId = folderId;
          removedAids = videoAids;
        },
      );

      final removed = await service.removeTrackFromRemote(
        sourceUrl: 'https://www.bilibili.com/medialist/detail/ml98765',
        importSourceType: SourceType.bilibili,
        track: _track(SourceType.bilibili, 'BV3'),
      );

      expect(removed, isTrue);
      expect(removedFolderId, 98765);
      expect(removedAids, [303]);
    });

    test(
      'YouTube removal parses playlist id, skips missing setVideoId, and removes found videos',
      () async {
        final lookupCalls = <String>[];
        final removeCalls = <String>[];
        final service = _service(
          getYoutubeSetVideoId: (playlistId, videoId) async {
            lookupCalls.add('$playlistId:$videoId');
            if (videoId == 'missing') return null;
            return 'set-$videoId';
          },
          removeYoutubeTrack: (playlistId, videoId, setVideoId) async {
            removeCalls.add('$playlistId:$videoId:$setVideoId');
          },
        );

        final removed = await service.removeTracksFromRemote(
          sourceUrl: 'https://www.youtube.com/playlist?list=PL123',
          importSourceType: SourceType.youtube,
          tracks: [
            _track(SourceType.youtube, 'keep'),
            _track(SourceType.bilibili, 'BV1'),
            _track(SourceType.youtube, 'missing'),
          ],
        );

        expect(removed, isTrue);
        expect(lookupCalls, ['PL123:keep', 'PL123:missing']);
        expect(removeCalls, ['PL123:keep:set-keep']);
      },
    );

    test('NetEase removal parses playlist id from URL and sends source IDs',
        () async {
      String? removedPlaylistId;
      List<String>? removedTrackIds;
      final service = _service(
        removeNeteaseTracks: (playlistId, trackIds) async {
          removedPlaylistId = playlistId;
          removedTrackIds = trackIds;
        },
      );

      final removed = await service.removeTracksFromRemote(
        sourceUrl: 'https://music.163.com/#/playlist?id=24680',
        importSourceType: SourceType.netease,
        tracks: [
          _track(SourceType.netease, '11'),
          _track(SourceType.youtube, 'yt1'),
          _track(SourceType.netease, '22'),
        ],
      );

      expect(removed, isTrue);
      expect(removedPlaylistId, '24680');
      expect(removedTrackIds, ['11', '22']);
    });

    test('invalid playlist URL returns false and does not invoke callbacks',
        () async {
      var getAidCalled = false;
      var removeCalled = false;
      final service = _service(
        getBilibiliAid: (_) async {
          getAidCalled = true;
          return 1;
        },
        removeBilibiliTracks: ({required folderId, required videoAids}) async {
          removeCalled = true;
        },
      );

      final removed = await service.removeTracksFromRemote(
        sourceUrl: 'https://space.bilibili.com/1/favlist',
        importSourceType: SourceType.bilibili,
        tracks: [_track(SourceType.bilibili, 'BV1')],
      );

      expect(removed, isFalse);
      expect(getAidCalled, isFalse);
      expect(removeCalled, isFalse);
    });

    test(
      'single YouTube removal with missing setVideoId returns false and does not remove',
      () async {
        final lookupCalls = <String>[];
        var removeCalled = false;
        final service = _service(
          getYoutubeSetVideoId: (playlistId, videoId) async {
            lookupCalls.add('$playlistId:$videoId');
            return null;
          },
          removeYoutubeTrack: (playlistId, videoId, setVideoId) async {
            removeCalled = true;
          },
        );

        final removed = await service.removeTrackFromRemote(
          sourceUrl: 'https://www.youtube.com/playlist?list=PL123',
          importSourceType: SourceType.youtube,
          track: _track(SourceType.youtube, 'missing'),
        );

        expect(removed, isFalse);
        expect(lookupCalls, ['PL123:missing']);
        expect(removeCalled, isFalse);
      },
    );
  });
}

RemotePlaylistActionsService _service({
  Future<int> Function(Track track)? getBilibiliAid,
  Future<void> Function({required int folderId, required List<int> videoAids})?
      removeBilibiliTracks,
  Future<String?> Function(String playlistId, String videoId)?
      getYoutubeSetVideoId,
  Future<void> Function(String playlistId, String videoId, String setVideoId)?
      removeYoutubeTrack,
  Future<void> Function(String playlistId, List<String> trackIds)?
      removeNeteaseTracks,
}) {
  return RemotePlaylistActionsService(
    getBilibiliAid:
        getBilibiliAid ?? (_) => throw UnimplementedError('getBilibiliAid'),
    removeBilibiliTracks: removeBilibiliTracks ??
        ({required folderId, required videoAids}) =>
            throw UnimplementedError('removeBilibiliTracks'),
    getYoutubeSetVideoId: getYoutubeSetVideoId ??
        (playlistId, videoId) =>
            throw UnimplementedError('getYoutubeSetVideoId'),
    removeYoutubeTrack: removeYoutubeTrack ??
        (playlistId, videoId, setVideoId) =>
            throw UnimplementedError('removeYoutubeTrack'),
    removeNeteaseTracks: removeNeteaseTracks ??
        (playlistId, trackIds) =>
            throw UnimplementedError('removeNeteaseTracks'),
  );
}

Track _track(SourceType sourceType, String sourceId) {
  return Track()
    ..sourceType = sourceType
    ..sourceId = sourceId
    ..title = sourceId;
}
