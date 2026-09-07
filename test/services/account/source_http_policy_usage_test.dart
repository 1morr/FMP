import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('account source HTTP policy usage', () {
    test('source account clients use SourceHttpPolicy for Dio defaults', () {
      final files = {
        'lib/services/account/bilibili_account_service.dart':
            'SourceIds.bilibili',
        'lib/services/account/bilibili_favorites_service.dart':
            'SourceIds.bilibili',
        'lib/services/account/youtube_account_service.dart':
            'SourceIds.youtube',
        'lib/services/account/youtube_playlist_service.dart':
            'SourceIds.youtube',
        'lib/services/account/netease_account_service.dart':
            'SourceIds.netease',
        'lib/services/account/netease_playlist_service.dart':
            'SourceIds.netease',
      };

      for (final entry in files.entries) {
        final source = File(entry.key).readAsStringSync();
        expect(source, contains('SourceHttpPolicy.createApiDio'));
        expect(source, contains(entry.value));
        expect(source, isNot(contains('Dio(BaseOptions')));
      }
    });
  });
}
