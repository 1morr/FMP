import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadService media handoff usage', () {
    test('download service dio defaults are not tied to bilibili referer', () {
      final source = File(
        'lib/services/download/download_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains("'Referer': 'https://www.bilibili.com'")));
    });

    test('download isolate applies receive timeout to stalled responses', () {
      final source = File(
        'lib/services/download/download_service.dart',
      ).readAsStringSync();

      expect(
        source,
        matches(
          RegExp(r'response\.timeout\(\s*AppConstants\.networkReceiveTimeout'),
        ),
      );
      expect(source, contains('on TimeoutException catch'));
    });
  });
}
