/// 搜尋頁與歌單詳情頁的四條源碼規則。
///
/// 動態列少了 key，Flutter 照樣畫得出來，只是重排時狀態跟著位置走；搜尋頁
/// 直接呼叫 `getVideoPages` 或直接讀音源 provider 也一樣能跑，只是把音源身分
/// 帶回了 UI。四條都沒有失敗訊號，只有讀源碼看得到。
///
/// 服務層的分頁行為在 `test/ui/pages/search/search_service_paging_test.dart`。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('search page static rules', () {
    test('search page delegates bilibili page loading to notifier and service APIs', () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final searchProviderSource = File(
        'lib/providers/search/search_provider.dart',
      ).readAsStringSync();
      final searchServiceSource = File(
        'lib/services/search/search_service.dart',
      ).readAsStringSync();

      expect(
        searchProviderSource.contains(
          'Future<List<VideoPage>> loadVideoPagesForTrack(Track track)',
        ),
        isTrue,
        reason:
            'SearchNotifier should expose a track-owned video-page entry for the search page.',
      );

      expect(
        searchServiceSource.contains(
          'Future<List<VideoPage>> loadVideoPagesForTrack(Track track)',
        ),
        isTrue,
        reason:
            'SearchService should own bilibili video-page loading behind a helper API.',
      );

      expect(
        RegExp(
          r'ref\s*\.read\(searchProvider\.notifier\)'
          r'\s*\.loadVideoPagesForTrack\(track\)',
        ).hasMatch(searchPageSource),
        isTrue,
        reason:
            'SearchPage should delegate video-page loading to the notifier boundary.',
      );

      expect(
        searchPageSource.contains('sourceManagerProvider'),
        isFalse,
        reason:
            'SearchPage should no longer assemble source-manager lookups for bilibili page loading.',
      );

      expect(
        searchPageSource.contains('buildAuthHeaders('),
        isFalse,
        reason:
            'SearchPage should no longer build auth headers for bilibili page loading.',
      );

      expect(
        searchPageSource.contains('getVideoPages(track.sourceId'),
        isFalse,
        reason:
            'SearchPage should no longer call BilibiliSource.getVideoPages directly.',
      );
    });
  });
}
