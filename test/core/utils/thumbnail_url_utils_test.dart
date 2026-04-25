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
    });

    group('Bilibili URL optimization', () {
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
        final small = ThumbnailUrlUtils.getOptimizedUrl(url,
            displaySize: 50, devicePixelRatio: 1.0);
        expect(small, contains('@200w.jpg'));

        // Large display → larger size
        final large = ThumbnailUrlUtils.getOptimizedUrl(url,
            displaySize: 500, devicePixelRatio: 1.0);
        expect(large, contains('@640w.jpg'));
      });
    });

    group('YouTube URL optimization', () {
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

      test('preserves jpg format', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 100);

        expect(result, contains('.jpg'));
      });

      test('does not upscale mqdefault candidates to maxresdefault', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 200,
          devicePixelRatio: 1.0,
        );

        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
            ]));
      });

      test('dedupes youtube candidates when optimized url matches original',
          () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 100,
          devicePixelRatio: 1.0,
        );

        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
            ]));
      });
    });

    group('Netease URL optimization', () {
      test('adds param suffix to Netease URL', () {
        const url = 'https://p1.music.126.net/xxx/xxx.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(url, displaySize: 100);

        expect(result, contains('param='));
      });
    });
  });
}
