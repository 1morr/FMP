import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/utils/thumbnail_url_utils.dart';

void main() {
  group('ThumbnailUrlUtils', () {
    group('getOptimizedUrl', () {
      test('returns empty string for null url', () {
        expect(ThumbnailUrlUtils.getOptimizedUrl(null), '');
      });

      test('returns empty string for empty url', () {
        expect(ThumbnailUrlUtils.getOptimizedUrl(''), '');
      });

      test('returns original url for unknown domain', () {
        const url = 'https://example.com/image.jpg';
        expect(ThumbnailUrlUtils.getOptimizedUrl(url), url);
      });

      test('is documented as a single-url helper without fallback loading', () {
        final source =
            Uri.file('lib/core/utils/thumbnail_url_utils.dart').toFilePath();
        final content = File(source).readAsStringSync();

        expect(content, contains('single URL consumer'));
        expect(content, contains('does not perform fallback loading'));
      });
    });

    group('Bilibili URL optimization', () {
      test('does not optimize non-Bilibili hosts that mention Bilibili in path',
          () {
        const url = 'https://example.com/proxy/hdslb.com/image.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 100,
        );

        expect(result, equals([url]));
      });

      test('adds size suffix to Bilibili URL', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 100);

        expect(result, contains('@'));
        expect(result, contains('w.jpg'));
        expect(
            result, startsWith('https://i0.hdslb.com/bfs/archive/test.jpg@'));
      });

      test('replaces existing size suffix', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg@640w.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 50);

        // Should not have double @ signs
        expect('@'.allMatches(result).length, 1);
      });

      test('selects appropriate size tier', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg';

        // Small display → small size
        final small = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 50);
        expect(small, contains('@200w.jpg'));

        // Large display → larger size
        final large = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 500);
        expect(large, contains('@640w.jpg'));
      });

      test('uses display size directly for URL candidate selection', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg';

        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 200,
        );

        expect(
            result.first, 'https://i0.hdslb.com/bfs/archive/test.jpg@200w.jpg');
      });
    });

    group('YouTube URL optimization', () {
      test('does not optimize non-YouTube hosts that mention ytimg in path',
          () {
        const url =
            'https://example.com/proxy/i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 480,
        );

        expect(result, equals([url]));
      });

      test('optimizes ytimg.com thumbnail', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 100);

        expect(result, contains('ytimg.com'));
        expect(result, contains('dQw4w9WgXcQ'));
      });

      test('preserves webp format', () {
        const url = 'https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/hqdefault.webp';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 100);

        expect(result, contains('.webp'));
        expect(result, contains('vi_webp'));
      });

      test('preserves original jpg format for reliability', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 100);

        // 保留原始 JPG 格式，不強制轉 WebP
        // 少數影片完全沒有 WebP 縮圖，強制轉換會導致所有候選 404
        expect(result, contains('.jpg'));
      });

      test('upscales mqdefault to maxresdefault for large source targets', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 720,
        );

        // displaySize=720 → targetSize=720 → maxresdefault
        // 原始为 mqdefault，仅生成 16:9 候选 [maxresdefault, 原始 mqdefault]
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
            ]));
      });

      test('uses maxresdefault when caller requests a large source target', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';

        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 720,
        );

        expect(
          result.first,
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
        );
      });

      test('dedupes youtube candidates when optimized url matches original',
          () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 100,
        );

        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
            ]));
      });

      test(
          'maxresdefault original generates mqdefault fallback for small display',
          () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 48,
        );

        // displaySize=48, targetSize=48 → mqdefault (≤360)
        // 仅 16:9 候选：[mqdefault, 原始 maxresdefault]
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
            ]));
      });

      test('maxresdefault original stays for large display', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 720,
        );

        // displaySize=720, targetSize=720 → maxresdefault (>360)
        // desired == original → 仅原始 URL
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
            ]));
      });

      test(
          'hqdefault canonical generates only 16:9 candidates for large display',
          () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 480,
        );

        // displaySize=480, targetSize=480 -> maxresdefault.
        // hqdefault is 4:3 and can contain black bars, so it must not be
        // used as a display fallback.
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
            ]));
      });

      test('sddefault canonical excludes original black-bar fallback', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 48,
        );

        // displaySize=48 -> mqdefault. sddefault is 4:3 and can contain
        // black bars, so it must not be used as a display fallback.
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
            ]));
      });

      test('youtube candidates never include known black-bar quality tiers',
          () {
        const blackBarUrls = [
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg',
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg',
          'https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/hqdefault.webp',
        ];

        for (final url in blackBarUrls) {
          final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
            url,
            displaySize: 480,
          );

          expect(result, isNot(contains(url)), reason: url);
          expect(result.join('\n'), isNot(contains('/default.')));
          expect(result.join('\n'), isNot(contains('/hqdefault.')));
          expect(result.join('\n'), isNot(contains('/sddefault.')));
        }
      });
    });

    group('Netease URL optimization', () {
      test('does not optimize non-Netease hosts that mention music.126.net',
          () {
        const url = 'https://example.com/proxy/music.126.net/cover.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 100,
        );

        expect(result, equals([url]));
      });

      test('adds param suffix to Netease URL', () {
        const url = 'https://p1.music.126.net/xxx/xxx.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 100);

        expect(result, contains('param='));
      });
    });
  });
}
