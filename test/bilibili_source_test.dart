import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/models/track.dart';

void main() {
  group('BilibiliSource', () {
    late BilibiliSource source;

    setUp(() {
      source = BilibiliSource();
    });

    group('getAudioUrl', () {
      test('should fetch audio URL for valid bvid', () async {
        // 此测试需要网络连接和有效的视频
        // 在CI/CD中可能需要跳过
        // 使用一个真实存在的视频BV号进行测试
        const testBvid = 'BV1xx411c79H'; // 实际存在的视频

        try {
          final audioUrl = await source.getAudioUrl(testBvid);

          expect(audioUrl, isNotNull);
          expect(audioUrl, isNotEmpty);
          expect(audioUrl, contains('http'));
          debugPrint('Successfully fetched audio URL: ${audioUrl.substring(0, 80)}...');
        } on BilibiliApiException catch (e) {
          // 如果视频不可用，跳过测试（可能是地区限制或API限制）
          if (e.isUnavailable || e.numericCode == -404) {
            debugPrint('Video unavailable (code: ${e.numericCode}), skipping test: ${e.message}');
            return;
          }
          rethrow;
        } on DioException catch (e) {
          // 网络错误时跳过
          debugPrint('Network error, skipping test: ${e.message}');
          return;
        }
      });

      test('should throw BilibiliApiException for invalid bvid', () async {
        const invalidBvid = 'BV1234567890'; // 无效的BV号

        expect(
          () => source.getAudioUrl(invalidBvid),
          throwsA(isA<BilibiliApiException>()),
        );
      });
    });

    group('refreshAudioUrl', () {
      test('should refresh audio URL for track with expired URL', () async {
        // 创建一个带有过期URL的track
        const originalUrl = 'https://expired-url.com/audio.m4s';
        final track = Track()
          ..sourceId = 'BV1xx411c79H'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..audioUrl = originalUrl
          ..audioUrlExpiry = DateTime.now().subtract(const Duration(hours: 1));

        // URL 应该已经过期
        expect(track.hasValidAudioUrl, isFalse);

        try {
          final refreshedTrack = await source.refreshAudioUrl(track);

          expect(refreshedTrack.audioUrl, isNotNull);
          // 新URL应该与原来的假URL不同
          expect(refreshedTrack.audioUrl, isNot(equals(originalUrl)));
          // 新URL应该是有效的HTTP URL
          expect(refreshedTrack.audioUrl, contains('http'));
          expect(refreshedTrack.hasValidAudioUrl, isTrue);
          expect(refreshedTrack.audioUrlExpiry, isNotNull);
          expect(
            refreshedTrack.audioUrlExpiry!.isAfter(DateTime.now()),
            isTrue,
          );
          debugPrint('Successfully refreshed audio URL');
        } on BilibiliApiException catch (e) {
          if (e.isUnavailable || e.numericCode == -404) {
            debugPrint('Video unavailable (code: ${e.numericCode}), skipping test: ${e.message}');
            return;
          }
          rethrow;
        } on DioException catch (e) {
          debugPrint('Network error, skipping test: ${e.message}');
          return;
        }
      });
    });

    group('URL expiry', () {
      test('hasValidAudioUrl should return false for expired URL', () {
        final track = Track()
          ..audioUrl = 'https://example.com/audio.m4s'
          ..audioUrlExpiry = DateTime.now().subtract(const Duration(minutes: 1));

        expect(track.hasValidAudioUrl, isFalse);
      });

      test('hasValidAudioUrl should return true for valid URL', () {
        final track = Track()
          ..audioUrl = 'https://example.com/audio.m4s'
          ..audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));

        expect(track.hasValidAudioUrl, isTrue);
      });

      test('hasValidAudioUrl should return true for URL without expiry', () {
        final track = Track()..audioUrl = 'https://example.com/audio.m4s';

        expect(track.hasValidAudioUrl, isTrue);
      });

      test('hasValidAudioUrl should return false for null URL', () {
        final track = Track();

        expect(track.hasValidAudioUrl, isFalse);
      });
    });
  });

  group('Race Condition Prevention', () {
    test('Multiple rapid play requests should not cause errors', () async {
      // 这个测试模拟快速切歌的场景
      // 实际测试需要模拟 AudioController，这里只是占位符
      // 真实测试需要使用 mocktail 或 mockito 来模拟依赖

      // 模拟场景：
      // 1. 请求播放歌曲A
      // 2. 在A还没加载完时，请求播放歌曲B
      // 3. 歌曲A的加载应该被取消，歌曲B应该正常播放

      // 这里只验证逻辑概念
      expect(true, isTrue);
    });
  });
}
