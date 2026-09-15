import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/core/utils/thumbnail_url_utils.dart';

/// 候選 URL 所指向的來源高度（px），無法判定時回傳 null（未分檔的原圖）。
int? _candidateSourceHeight(String url) {
  final bilibili = RegExp(r'@(\d+)w\.jpg$').firstMatch(url);
  if (bilibili != null) {
    // Bilibili 的 `@{w}w` 保持長寬比，16:9 封面的高是寬的 9/16。
    return (int.parse(bilibili.group(1)!) * 9 / 16).floor();
  }
  if (url.contains('/maxresdefault.')) {
    return ThumbnailUrlUtils.youtubeMaxresdefaultHeight;
  }
  if (url.contains('/mqdefault.')) {
    return ThumbnailUrlUtils.youtubeMqdefaultHeight;
  }
  final netease = RegExp(r'\?param=(\d+)y\d+$').firstMatch(url);
  if (netease != null) return int.parse(netease.group(1)!);
  return null;
}

void main() {
  group('ThumbnailUrlUtils', () {
    group('getOptimizedUrl', () {
      test('returns empty string for null url', () {
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            null,
            displaySize: 100,
            devicePixelRatio: 1,
          ),
          '',
        );
      });

      test('returns empty string for empty url', () {
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            '',
            displaySize: 100,
            devicePixelRatio: 1,
          ),
          '',
        );
      });

      test('returns original url for unknown domain', () {
        const url = 'https://example.com/image.jpg';
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            url,
            displaySize: 100,
            devicePixelRatio: 1,
          ),
          url,
        );
      });
    });

    group('quantizeDevicePixelRatio', () {
      test('rounds to the nearest 0.5 so cache keys converge', () {
        expect(ThumbnailUrlUtils.quantizeDevicePixelRatio(2.625), 2.5);
        expect(ThumbnailUrlUtils.quantizeDevicePixelRatio(3.0), 3.0);
        expect(ThumbnailUrlUtils.quantizeDevicePixelRatio(2.75), 3.0);
        expect(ThumbnailUrlUtils.quantizeDevicePixelRatio(1.0), 1.0);
      });

      test('needed source height uses the quantized ratio', () {
        // 56dp × 2.5（由 2.625 量化）= 140，不是 56 × 2.625 = 147。
        expect(ThumbnailUrlUtils.neededSourceHeight(56, 2.625), 140);
        expect(ThumbnailUrlUtils.neededSourceHeight(56, 3.0), 168);
      });
    });

    group('Bilibili URL optimization', () {
      test(
        'does not optimize non-Bilibili hosts that mention Bilibili in path',
        () {
          const url = 'https://example.com/proxy/hdslb.com/image.jpg';
          final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
            url,
            displaySize: 100,
            devicePixelRatio: 1,
          );

          expect(result, equals([url]));
        },
      );

      test('adds size suffix to Bilibili URL', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(
          url,
          displaySize: 100,
          devicePixelRatio: 1,
        );

        expect(result, contains('@'));
        expect(result, contains('w.jpg'));
        expect(
          result,
          startsWith('https://i0.hdslb.com/bfs/archive/test.jpg@'),
        );
      });

      test('replaces existing size suffix', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg@640w.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(
          url,
          displaySize: 50,
          devicePixelRatio: 1,
        );

        // Should not have double @ signs
        expect('@'.allMatches(result).length, 1);
      });

      test('derives the width tier from the needed source height', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg';

        // 需要 50px 高 → 50 × 16/9 = 89px 寬 → 200 檔（200×113）。
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            url,
            displaySize: 50,
            devicePixelRatio: 1,
          ),
          contains('@200w.jpg'),
        );

        // 需要 200px 高 → 356px 寬 → 400 檔（400×225）。200 檔只有 113px 高，
        // 按寬選檔會選到它，那正是 #107 的第二個根因。
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            url,
            displaySize: 200,
            devicePixelRatio: 1,
          ),
          contains('@400w.jpg'),
        );

        // 需要 500px 高 → 889px 寬 → 1280 檔。
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            url,
            displaySize: 500,
            devicePixelRatio: 1,
          ),
          contains('@1280w.jpg'),
        );
      });

      test('falls back down the tier list from the desired tier', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg';

        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 200,
          devicePixelRatio: 1,
        );

        expect(
          result,
          equals([
            'https://i0.hdslb.com/bfs/archive/test.jpg@400w.jpg',
            'https://i0.hdslb.com/bfs/archive/test.jpg@200w.jpg',
            url,
          ]),
        );
      });

      test('strips query string before appending size suffix', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg?t=123';

        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 100,
          devicePixelRatio: 1,
        );

        // query 必須被移除，不能生成 `...jpg?t=123@200w.jpg`
        expect(
          result.first,
          'https://i0.hdslb.com/bfs/archive/test.jpg@200w.jpg',
        );
        // 原始 URL（含 query）仍作為最終回退
        expect(result.last, url);
      });

      test('strips existing size suffix and query string together', () {
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg@640w.jpg?t=123';

        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 100,
          devicePixelRatio: 1,
        );

        expect(
          result.first,
          'https://i0.hdslb.com/bfs/archive/test.jpg@200w.jpg',
        );
        expect('@'.allMatches(result.first).length, 1);
      });

      test('never emits a cropping @{w}w_{h}h parameter', () {
        // 同時指定寬高會對非 16:9 的來源（UP 主頭像、方形歌單封面）居中裁切。
        const url = 'https://i0.hdslb.com/bfs/archive/test.jpg';
        for (final dpr in [1.0, 2.625, 3.0]) {
          final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
            url,
            displaySize: ImageTargetSizes.highest,
            devicePixelRatio: dpr,
          );
          expect(result.join('\n'), isNot(contains('h.jpg')), reason: '$dpr');
        }
      });
    });

    group('YouTube URL optimization', () {
      test('does not optimize non-YouTube hosts that mention ytimg in path', () {
        const url =
            'https://example.com/proxy/i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 480,
          devicePixelRatio: 1,
        );

        expect(result, equals([url]));
      });

      test('optimizes ytimg.com thumbnail', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(
          url,
          displaySize: 100,
          devicePixelRatio: 1,
        );

        expect(result, contains('ytimg.com'));
        expect(result, contains('dQw4w9WgXcQ'));
      });

      test('preserves webp format', () {
        const url = 'https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/hqdefault.webp';
        final result = ThumbnailUrlUtils.getOptimizedUrl(
          url,
          displaySize: 100,
          devicePixelRatio: 1,
        );

        expect(result, contains('.webp'));
        expect(result, contains('vi_webp'));
      });

      test('preserves original jpg format for reliability', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(
          url,
          displaySize: 100,
          devicePixelRatio: 1,
        );

        // 保留原始 JPG 格式，不強制轉 WebP
        // 少數影片完全沒有 WebP 縮圖，強制轉換會導致所有候選 404
        expect(result, contains('.jpg'));
      });

      test('picks the tier whose height covers the box', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';

        // mqdefault 只有 180px 高，蓋得住就用它。
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            url,
            displaySize: 180,
            devicePixelRatio: 1,
          ),
          contains('mqdefault'),
        );
        // 超過 180px 高就只剩 maxresdefault —— 中間的 hqdefault/sddefault
        // 是 4:3 檔位，顯示不用。
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            url,
            displaySize: 181,
            devicePixelRatio: 1,
          ),
          contains('maxresdefault'),
        );
      });

      test('upscales mqdefault to maxresdefault for large source targets', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 720,
          devicePixelRatio: 1,
        );

        // 需要 720px 高 → maxresdefault
        // 原始為 mqdefault，僅生成 16:9 候選 [maxresdefault, 原始 mqdefault]
        expect(
          result,
          equals([
            'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
            'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
          ]),
        );
      });

      test(
        'dedupes youtube candidates when optimized url matches original',
        () {
          const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg';
          final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
            url,
            displaySize: 100,
            devicePixelRatio: 1,
          );

          expect(
            result,
            equals(['https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg']),
          );
        },
      );

      test(
        'maxresdefault original generates mqdefault fallback for small display',
        () {
          const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg';
          final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
            url,
            displaySize: 48,
            devicePixelRatio: 1,
          );

          // 需要 48px 高 → mqdefault (≤180)
          // 僅 16:9 候選：[mqdefault, 原始 maxresdefault]
          expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
            ]),
          );
        },
      );

      test('maxresdefault original stays for large display', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 720,
          devicePixelRatio: 1,
        );

        // desired == original → 僅原始 URL
        expect(
          result,
          equals(['https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg']),
        );
      });

      test(
        'hqdefault canonical generates only 16:9 candidates for large display',
        () {
          const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
          final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
            url,
            displaySize: 480,
            devicePixelRatio: 1,
          );

          // hqdefault is 4:3 and can contain black bars, so it must not be
          // used as a display fallback.
          expect(
            result,
            equals([
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
              'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
            ]),
          );
        },
      );

      test('sddefault canonical excludes original black-bar fallback', () {
        const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          url,
          displaySize: 48,
          devicePixelRatio: 1,
        );

        // sddefault is 4:3 and can contain black bars, so it must not be
        // used as a display fallback.
        expect(
          result,
          equals(['https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg']),
        );
      });

      test(
        'youtube candidates never include known black-bar quality tiers',
        () {
          const blackBarUrls = [
            'https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg',
            'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
            'https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg',
            'https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/hqdefault.webp',
          ];

          for (final url in blackBarUrls) {
            for (final dpr in [1.0, 2.625, 3.0]) {
              final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
                url,
                displaySize: ImageTargetSizes.thumbnail,
                devicePixelRatio: dpr,
              );

              expect(result, isNot(contains(url)), reason: '$url @$dpr');
              expect(result.join('\n'), isNot(contains('/default.')));
              expect(result.join('\n'), isNot(contains('/hqdefault.')));
              expect(result.join('\n'), isNot(contains('/sddefault.')));
            }
          }
        },
      );
    });

    group('Netease URL optimization', () {
      test(
        'does not optimize non-Netease hosts that mention music.126.net',
        () {
          const url = 'https://example.com/proxy/music.126.net/cover.jpg';
          final result = ThumbnailUrlUtils.getOptimizedUrlCandidates(
            url,
            displaySize: 100,
            devicePixelRatio: 1,
          );

          expect(result, equals([url]));
        },
      );

      test('adds param suffix to Netease URL', () {
        const url = 'https://p1.music.126.net/xxx/xxx.jpg';
        final result = ThumbnailUrlUtils.getOptimizedUrl(
          url,
          displaySize: 100,
          devicePixelRatio: 1,
        );

        expect(result, contains('param='));
      });

      test('sizes the square param by the needed height, without 16:9', () {
        const url = 'https://p1.music.126.net/xxx/xxx.jpg';

        // NetEase 封面是方形，`?param=NyN` 的 N 同時是寬和高，不乘 16/9。
        expect(
          ThumbnailUrlUtils.getOptimizedUrl(
            url,
            displaySize: 168,
            devicePixelRatio: 1,
          ),
          contains('?param=200y200'),
        );
      });
    });

    // issue #107：檔位不乘 DPR，且 16:9 來源塞進正方形 box 只有高能用。
    // 量測基準是 Medium_Phone AVD（1080×2400）：`wm density 420` → DPR 2.625，
    // `wm density 480` → DPR 3.0。
    group('physical-pixel tier selection (issue #107)', () {
      const bilibili = 'https://i0.hdslb.com/bfs/archive/test.jpg';
      const youtube = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
      const netease = 'https://p1.music.126.net/xxx/xxx.jpg';

      /// 各來源能給的最高來源高度，box 比它還高時只能取最高檔。
      const maxSourceHeight = {
        bilibili: 720, // @1280w → 1280×720
        youtube: ThumbnailUrlUtils.youtubeMaxresdefaultHeight,
        netease: 800, // ?param=800y800
      };

      /// (元件, box 邏輯邊長 dp, 語義檔位)
      List<(String, double, double)> componentsFor(double dpr) => [
        ('home ranking thumbnail', 48.0, ImageTargetSizes.thumbnail),
        ('mini player cover', 56.0, ImageTargetSizes.thumbnail),
        // 播放器封面是 AspectRatio(1) 的全寬方框：1080px 螢幕寬 ÷ DPR 再扣
        // 兩側 24dp padding。
        ('player page cover', 1080 / dpr - 48, ImageTargetSizes.highest),
      ];

      for (final dpr in [2.625, 3.0]) {
        for (final (label, boxDp, tier) in componentsFor(dpr)) {
          for (final url in [bilibili, youtube, netease]) {
            test('$label covers its box at DPR $dpr ($url)', () {
              final candidates = ThumbnailUrlUtils.getOptimizedUrlCandidates(
                url,
                displaySize: tier,
                devicePixelRatio: dpr,
              );
              final chosenHeight = _candidateSourceHeight(candidates.first);
              expect(chosenHeight, isNotNull, reason: candidates.first);

              final boxPhysicalHeight = boxDp * dpr;
              if (maxSourceHeight[url]! >= boxPhysicalHeight) {
                expect(
                  chosenHeight,
                  greaterThanOrEqualTo(boxPhysicalHeight.ceil()),
                  reason: '$label $url @$dpr → ${candidates.first}',
                );
              } else {
                // 來源本身不夠高，只能取最高檔。
                expect(
                  chosenHeight,
                  maxSourceHeight[url],
                  reason: '$label $url @$dpr → ${candidates.first}',
                );
              }
            });
          }
        }
      }

      test('48dp thumbnail moves off @200w at DPR 3 (the #107 symptom)', () {
        // 修正前：thumbnail 檔位是固定的 160 源像素 → `_selectBilibiliSize`
        // 選 @200w（200×113），48dp 在 DPR 3 需要 144px 高 → 1.27x 放大。
        final before = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          bilibili,
          displaySize: ImageTargetSizes.thumbnail,
          devicePixelRatio: 1,
        );
        expect(before.first, endsWith('@200w.jpg'));

        final after = ThumbnailUrlUtils.getOptimizedUrlCandidates(
          bilibili,
          displaySize: ImageTargetSizes.thumbnail,
          devicePixelRatio: 3.0,
        );
        expect(after.first, endsWith('@400w.jpg'));
      });

      test('the chosen tier grows with DPR for the same semantic tier', () {
        String tierOf(double dpr) =>
            ThumbnailUrlUtils.getOptimizedUrlCandidates(
              bilibili,
              displaySize: ImageTargetSizes.medium,
              devicePixelRatio: dpr,
            ).first;

        expect(tierOf(1.0), endsWith('@400w.jpg'));
        expect(tierOf(2.625), endsWith('@640w.jpg'));
        expect(tierOf(3.0), endsWith('@640w.jpg'));
      });

      test('player cover saturates every source ceiling at both densities', () {
        for (final dpr in [2.625, 3.0]) {
          expect(
            ThumbnailUrlUtils.getOptimizedUrlCandidates(
              bilibili,
              displaySize: ImageTargetSizes.highest,
              devicePixelRatio: dpr,
            ).first,
            endsWith('@1280w.jpg'),
          );
          expect(
            ThumbnailUrlUtils.getOptimizedUrlCandidates(
              youtube,
              displaySize: ImageTargetSizes.highest,
              devicePixelRatio: dpr,
            ).first,
            endsWith('/maxresdefault.jpg'),
          );
          expect(
            ThumbnailUrlUtils.getOptimizedUrlCandidates(
              netease,
              displaySize: ImageTargetSizes.highest,
              devicePixelRatio: dpr,
            ).first,
            endsWith('?param=800y800'),
          );
        }
      });

      test('downloaded covers keep the top tier without a device to ask', () {
        // 落盤圖片沒有 DPR 可問，用固定上限反推，否則下載的封面會比顯示需要
        // 的還小。
        expect(
          ThumbnailUrlUtils.getOptimizedUrlCandidates(
            bilibili,
            displaySize: ImageTargetSizes.high,
            devicePixelRatio: ThumbnailUrlUtils.persistedImageDevicePixelRatio,
          ).first,
          endsWith('@1280w.jpg'),
        );
      });
    });
  });
}
