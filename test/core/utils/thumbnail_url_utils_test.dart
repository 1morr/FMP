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

      test('upscales mqdefault through intermediate tiers to desired quality',
          () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 200,
          devicePixelRatio: 1.0,
        );

        // displaySize=200 → targetSize=200 → sddefault,
        // 原始为 mqdefault，候选为 [sddefault, hqdefault, 原始 mqdefault]
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
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

      test('maxresdefault original generates lower-quality candidates for small display',
          () {
        // 原始 URL 是既有數據中的 maxresdefault，顯示尺寸只有 48px
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 48,
          devicePixelRatio: 1.0,
        );

        // displaySize=48, targetSize=48 → mqdefault
        // original=maxresdefault (idx=0), desired=mqdefault (idx=3)
        // originalIdx < desiredIdx → 從 desired 向下生成（跳過 original）
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg',
              // 原始 maxresdefault 由 getOptimizedUrlCandidates 追加
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
            ]));
      });

      test('maxresdefault original with medium display generates sddefault candidates',
          () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 120,
          devicePixelRatio: 2.0,
        );

        // displaySize=120*2=240, targetSize=240 → sddefault
        // original=maxresdefault (idx=0), desired=sddefault (idx=1)
        // originalIdx < desiredIdx → 從 sddefault 向下生成（跳過 maxresdefault）
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
            ]));
      });

      test('maxresdefault original with large display deduplicates', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 480,
          devicePixelRatio: 2.0,
        );

        // displaySize=480*2=960 → maxresdefault
        // desired == original → 只追加原始 URL
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
            ]));
      });

      test('sddefault original generates lower-quality candidates for small display',
          () {
        // 既有數據可能是 sddefault
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 48,
          devicePixelRatio: 1.0,
        );

        // displaySize=48 → mqdefault
        // original=sddefault (idx=1), desired=mqdefault (idx=3)
        // originalIdx < desiredIdx → 從 mqdefault 向下生成（跳過 sddefault）
        expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg',
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
