import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('radio HTTP policy usage', () {
    test('radio source uses SourceHttpPolicy for Bilibili live headers', () {
      final source =
          File('lib/services/radio/radio_source.dart').readAsStringSync();

      expect(source, contains('SourceHttpPolicy.createBilibiliLiveDio'));
      expect(source, contains('SourceHttpPolicy.bilibiliLiveHeaders'));
      expect(
        source,
        isNot(contains("'Referer': 'https://live.bilibili.com/'")),
      );
    });

    test('bilibili source live helpers use live-specific HTTP policy', () {
      final source =
          File('lib/data/sources/bilibili_source.dart').readAsStringSync();

      expect(source, contains('SourceHttpPolicy.createBilibiliLiveDio'));
      expect(source, contains('_liveDio.get'));
      expect(
        source,
        isNot(contains("'Referer': 'https://live.bilibili.com/'")),
      );
    });

    test('radio cover preloader uses Bilibili live policy headers', () {
      final source =
          File('lib/ui/widgets/panels/track_detail_panel.dart').readAsStringSync();

      expect(source, contains('SourceHttpPolicy.bilibiliLiveHeaders'));
      expect(
        source,
        isNot(contains("headers: {'Referer': 'https://www.bilibili.com'}")),
      );
    });
  });
}
