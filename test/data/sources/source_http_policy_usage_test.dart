import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('direct source HTTP policy usage', () {
    test('audio source adapters use SourceHttpPolicy for Dio defaults', () {
      final files = {
        'lib/data/sources/bilibili_source.dart': 'SourceType.bilibili',
        'lib/data/sources/youtube_source.dart': 'SourceType.youtube',
        'lib/data/sources/netease_source.dart': 'SourceType.netease',
      };

      for (final entry in files.entries) {
        final source = File(entry.key).readAsStringSync();

        expect(source, contains('SourceHttpPolicy.createApiDio'));
        expect(source, contains(entry.value));
        expect(source, isNot(contains('HttpClientFactory.create')));
      }
    });

    test('InnerTube request options reuse policy headers', () {
      final source =
          File('lib/data/sources/youtube_source.dart').readAsStringSync();

      expect(source, contains('SourceHttpPolicy.apiHeaders'));
      expect(source, isNot(contains("'Origin': 'https://www.youtube.com'")));
      expect(source, isNot(contains("'Referer': 'https://www.youtube.com/'")));
    });

    test('Netease source does not depend on account service for policy UA', () {
      final source =
          File('lib/data/sources/netease_source.dart').readAsStringSync();

      expect(source, isNot(contains('NeteaseAccountService')));
    });
  });
}
