import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/download/download_media_headers.dart';

void main() {
  group('buildDownloadMediaHeaders', () {
    test('bilibili media headers do not leak auth cookies', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.bilibili,
        authHeaders: const {'Cookie': 'SESSDATA=secret'},
      );

      expect(headers['Referer'], 'https://www.bilibili.com');
      expect(headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(headers.containsKey('Cookie'), isFalse);
    });

    test('youtube media headers do not leak authorization headers', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.youtube,
        authHeaders: const {'Authorization': 'Bearer secret'},
      );

      expect(headers['Origin'], 'https://www.youtube.com');
      expect(headers['Referer'], 'https://www.youtube.com/');
      expect(headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('netease media headers preserve netease auth for media requests', () {
      final headers = buildDownloadMediaHeaders(
        SourceType.netease,
        requestUrl: 'https://m701.music.126.net/song.m4a',
        authHeaders: const {
          'Cookie': 'MUSIC_U=token',
          'Origin': 'https://music.163.com',
          'Referer': 'https://music.163.com/',
          'User-Agent': 'NetEase-UA',
          'X-Api-Only': 'drop-me',
        },
      );

      expect(headers['Cookie'], 'MUSIC_U=token');
      expect(headers['Origin'], 'https://music.163.com');
      expect(headers['Referer'], 'https://music.163.com/');
      expect(headers['User-Agent'], 'NetEase-UA');
      expect(headers.containsKey('X-Api-Only'), isFalse);
    });
  });

  group('buildDownloadImageHeaders', () {
    test('youtube image headers use youtube policy instead of bilibili referer',
        () {
      final headers = buildDownloadImageHeaders(
        SourceType.youtube,
        authHeaders: const {
          'Authorization': 'Bearer secret',
          'Cookie': 'SID=secret',
        },
      );

      expect(headers['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(headers['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(headers['Referer'], isNot(SourceHttpPolicy.bilibiliWebReferer));
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers.containsKey('Cookie'), isFalse);
    });

    test('netease image headers never include credential cookies', () {
      final headers = buildDownloadImageHeaders(
        SourceType.netease,
        authHeaders: const {
          'Cookie': 'MUSIC_U=token',
          'Origin': 'https://music.163.com',
          'Referer': 'https://music.163.com/',
          'User-Agent': 'NetEase-UA',
          'X-Api-Only': 'drop-me',
        },
      );

      expect(headers.containsKey('Cookie'), isFalse);
      expect(headers['Origin'], SourceHttpPolicy.neteaseOrigin);
      expect(headers['Referer'], SourceHttpPolicy.neteaseReferer);
      expect(headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(headers.containsKey('X-Api-Only'), isFalse);
    });

    test('download service applies image headers to cover and avatar downloads',
        () {
      final source = File('lib/services/download/download_service.dart')
          .readAsStringSync();

      expect(source, contains('buildDownloadImageHeaders('));
      expect(source, contains('Options(headers: imageHeaders)'));
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
  });
}
