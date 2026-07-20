import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('radio HTTP policy usage', () {
    test('bilibili live client uses SourceHttpPolicy for live HTTP', () {
      final source =
          File('lib/data/sources/bilibili_live_client.dart').readAsStringSync();

      expect(source, contains('SourceHttpPolicy.createBilibiliLiveDio'));
      expect(source, contains('SourceHttpPolicy.bilibiliLiveHeaders'));
      expect(source, contains('/room/v1/Room/playUrl'));
      expect(
        source,
        isNot(contains("'Referer': 'https://live.bilibili.com/'")),
      );
    });

    test('sources delegate Bilibili live mechanics to live client', () {
      final bilibiliSource =
          File('lib/data/sources/bilibili_source.dart').readAsStringSync();
      final radioSource =
          File('lib/services/radio/radio_source.dart').readAsStringSync();

      expect(bilibiliSource, contains('BilibiliLiveClient'));
      expect(radioSource, contains('BilibiliLiveClient'));
      expect(bilibiliSource, isNot(contains('/room/v1/Room/playUrl')));
      expect(radioSource, isNot(contains('/room/v1/Room/playUrl')));
    });

    test('radio cover preloader relies on the URL-based header policy', () {
      final source =
          File('lib/ui/widgets/panels/track_detail_panel.dart').readAsStringSync();

      // Radio covers must not pass explicit headers: ImageLoadingService
      // applies SourceHttpPolicy.imageHeadersForUrl automatically, matching
      // every other RadioCoverImage call site (see audit finding #52).
      expect(source, isNot(contains('SourceHttpPolicy.bilibiliLiveHeaders')));
      expect(
        source,
        isNot(contains("headers: {'Referer': 'https://www.bilibili.com'}")),
      );
    });
  });
}
