import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadService media handoff usage', () {
    test('download service applies image headers to cover and avatar downloads',
        () {
      final source = File('lib/services/download/download_service.dart')
          .readAsStringSync();

      expect(source, contains('_sourceAuthContext.imageHeaders('));
      expect(source, isNot(contains('buildDownloadImageHeaders(')));
      expect(source, contains('Options(headers: imageHeaders)'));
      expect(source, contains('ThumbnailUrlUtils.getOptimizedUrlCandidates('));
      expect(source, contains('ImageTargetSizes.high'));
      expect(source, contains('ImageTargetSizes.low'));
      expect(source, isNot(contains('DownloadImageTargetSizes')));
      expect(source, isNot(contains('displaySize: 480')));
      expect(source, isNot(contains('displaySize: 160')));
      expect(
        source,
        isNot(contains('await _dio.download(track.thumbnailUrl!, coverPath);')),
      );
      expect(
        source,
        isNot(contains(
            'await _dio.download(videoDetail.ownerFace, avatarPath);')),
      );
    });

    test('download service dio defaults are not tied to bilibili referer', () {
      final source = File('lib/services/download/download_service.dart')
          .readAsStringSync();

      expect(
        source,
        isNot(contains("'Referer': 'https://www.bilibili.com'")),
      );
    });

    test('download isolate applies receive timeout to stalled responses', () {
      final source = File('lib/services/download/download_service.dart')
          .readAsStringSync();

      expect(
        source,
        contains('response.timeout(AppConstants.networkReceiveTimeout)'),
      );
      expect(source, contains('on TimeoutException catch'));
    });

    test('download isolate delegates hop headers and range to MediaHandoff',
        () {
      final source = File('lib/services/download/download_service.dart')
          .readAsStringSync();

      expect(source, contains('DefaultMediaHandoff()'));
      expect(source, contains('prepareDownloadHop('));
      expect(source, contains('MediaHandoffRequest('));
      expect(source, contains('rangeStart: params.resumePosition > 0'));
      expect(source, isNot(contains('buildDownloadMediaHeaders(')));
      expect(source, isNot(contains("request.headers.set('Range'")));
      expect(source, isNot(contains('download_media_headers.dart')));
    });
  });
}
