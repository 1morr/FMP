import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Source ownership', () {
    test('runtime code does not construct ad-hoc YouTubeSource instances', () {
      const checkedFiles = [
        'lib/services/audio/audio_provider.dart',
        'lib/providers/playlist_provider.dart',
        'lib/providers/popular_provider.dart',
        'lib/services/import/import_service.dart',
        'lib/services/cache/ranking_cache_service.dart',
      ];

      final offenders = <String>[];
      for (final path in checkedFiles) {
        final source = File(path).readAsStringSync();
        if (source.contains('YouTubeSource(')) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty);
    });

    test('runtime code does not use RankingCacheService singleton', () {
      const checkedFiles = [
        'lib/providers/refresh_settings_provider.dart',
        'lib/ui/pages/settings/developer_options_page.dart',
      ];

      final offenders = <String>[];
      for (final path in checkedFiles) {
        final source = File(path).readAsStringSync();
        if (source.contains('RankingCacheService.instance')) {
          offenders.add(path);
        }
      }

      expect(offenders, isEmpty);
    });
  });
}
