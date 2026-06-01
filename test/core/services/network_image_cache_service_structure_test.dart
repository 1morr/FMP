import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkImageCacheService structure', () {
    late String source;

    setUpAll(() {
      source = File('lib/core/services/network_image_cache_service.dart')
          .readAsStringSync();
    });

    test('keeps cache manager lifecycle in dedicated helpers', () {
      expect(source, contains('static void _resetCacheManager()'));
      expect(source, contains('static void _markTrimmed('));
      expect(source, contains('_resetCacheManager();'));
      expect(source, contains('_markTrimmed('));
    });

    test('separates load accounting from trim scheduling', () {
      expect(source, contains('enum _TrimTiming'));
      expect(source, contains('static _TrimTiming _recordLoadedImage('));
      expect(source, contains('static int get _maxCacheSizeBytes'));
      expect(source, contains('static int get _preemptiveThresholdBytes'));
    });

    test('separates filesystem cache deletion from cache manager cleanup', () {
      expect(
          source, contains('static Future<void> _deleteCacheDirectoryFiles()'));
      expect(source, contains('await _deleteCacheDirectoryFiles();'));
      expect(source, contains('_estimatedCacheSizeBytes = 0;'));
    });
  });
}
