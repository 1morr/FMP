import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/platform/url_launcher_service.dart';

/// 「在 App 中開啟」與「開啟網頁」的網址。期望值是改成查表之前各分支組出來的
/// 字串，逐字照抄。
void main() {
  Track track(String sourceType, {int? ownerId, String? channelId}) => Track()
    ..sourceType = sourceType
    ..sourceId = 'id'
    ..ownerId = ownerId
    ..channelId = channelId;

  group('video links', () {
    test('every built-in source has an app and a web link', () {
      expect(UrlLauncherService.videoLinkFor(SourceIds.bilibili, 'BV1x'), (
        app: 'bilibili://video/BV1x',
        web: 'https://www.bilibili.com/video/BV1x',
      ));
      expect(UrlLauncherService.videoLinkFor(SourceIds.youtube, 'abc'), (
        app: 'youtube://watch?v=abc',
        web: 'https://www.youtube.com/watch?v=abc',
      ));
      expect(UrlLauncherService.videoLinkFor(SourceIds.netease, '123'), (
        app: 'orpheus://song/123',
        web: 'https://music.163.com/song?id=123',
      ));
    });

    test('an unknown source has none', () {
      expect(UrlLauncherService.videoLinkFor('soundcloud', 'x'), isNull);
    });
  });

  group('channel links', () {
    test('bilibili uses the uploader id, youtube the channel id', () {
      expect(
        UrlLauncherService.channelLinkFor(
          track(SourceIds.bilibili, ownerId: 42, channelId: 'ignored'),
        ),
        (app: 'bilibili://space/42', web: 'https://space.bilibili.com/42'),
      );
      expect(
        UrlLauncherService.channelLinkFor(
          track(SourceIds.youtube, ownerId: 42, channelId: 'UCx'),
        ),
        (
          app: 'youtube://channel/UCx',
          web: 'https://www.youtube.com/channel/UCx',
        ),
      );
    });

    test('an explicit id wins over the one on the track', () {
      expect(
        UrlLauncherService.channelLinkFor(
          track(SourceIds.bilibili, ownerId: 1),
          ownerId: 2,
        )?.web,
        'https://space.bilibili.com/2',
      );
      expect(
        UrlLauncherService.channelLinkFor(
          track(SourceIds.youtube, channelId: 'UCa'),
          channelId: 'UCb',
        )?.web,
        'https://www.youtube.com/channel/UCb',
      );
    });

    test('no link without the id, or for a source with no channel page', () {
      expect(
        UrlLauncherService.channelLinkFor(track(SourceIds.bilibili)),
        isNull,
      );
      expect(
        UrlLauncherService.channelLinkFor(
          track(SourceIds.youtube, channelId: ''),
        ),
        isNull,
      );
      expect(
        UrlLauncherService.channelLinkFor(
          track(SourceIds.netease, ownerId: 7, channelId: 'x'),
        ),
        isNull,
      );
      expect(
        UrlLauncherService.channelLinkFor(track('soundcloud', ownerId: 7)),
        isNull,
      );
    });
  });
}
