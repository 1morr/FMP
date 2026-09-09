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
    test('dynamic row widgets accept keys via super.key', () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final playlistDetailSource = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'const\s+_SearchResultTile\s*\(\s*\{\s*super\.key,',
          dotAll: true,
        ).hasMatch(searchPageSource),
        isTrue,
        reason:
            '_SearchResultTile should expose super.key before keyed call sites are added.',
      );

      expect(
        RegExp(
          r'const\s+_LocalTrackTile\s*\(\s*\{\s*super\.key,',
          dotAll: true,
        ).hasMatch(searchPageSource),
        isTrue,
        reason:
            '_LocalTrackTile should expose super.key before keyed call sites are added.',
      );

      expect(
        RegExp(
          r'const\s+_TrackListTile\s*\(\s*\{\s*super\.key,',
          dotAll: true,
        ).hasMatch(playlistDetailSource),
        isTrue,
        reason:
            '_TrackListTile should expose super.key before keyed call sites are added.',
      );
    });

    test('dynamic search and playlist rows use stable ValueKeys', () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final playlistDetailSource = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'_SearchResultTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
          dotAll: true,
        ).hasMatch(searchPageSource),
        isTrue,
        reason:
            'Online search result rows should use a stable key derived from track identity.',
      );

      expect(
        RegExp(
          r'_LocalTrackTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
          dotAll: true,
        ).hasMatch(searchPageSource),
        isTrue,
        reason:
            'Expanded local track rows should use a stable key derived from track identity.',
      );

      final playlistKeyMatches = RegExp(
        r'_TrackListTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
        dotAll: true,
      ).allMatches(playlistDetailSource);

      expect(
        playlistKeyMatches.length,
        greaterThanOrEqualTo(2),
        reason:
            'Playlist detail rows should key both single-track and expanded multi-part rows.',
      );
    });

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

    test('playlist mix bootstrap goes through the audio controller boundary', () {
      final playlistCardActionsSource = File(
        'lib/ui/widgets/menus/playlist_card_actions.dart',
      ).readAsStringSync();
      final audioProviderSource = File(
        'lib/services/audio/audio_provider.dart',
      ).readAsStringSync();

      expect(
        audioProviderSource.contains(
          'Future<void> startMixFromPlaylist(Playlist playlist)',
        ),
        isTrue,
        reason:
            'AudioController should expose a narrow app entry for starting mix playback from a playlist.',
      );

      expect(
        audioProviderSource.contains('YouTubeSource? _youtubeSource'),
        isFalse,
        reason:
            'AudioController should not keep a concrete YouTube source fallback.',
      );

      expect(
        audioProviderSource.contains('youtubeSourceProvider'),
        isFalse,
        reason:
            'Audio provider wiring should inject a MixTracksFetcher from a capability.',
      );

      expect(
        playlistCardActionsSource.contains(
          'await controller.startMixFromPlaylist(playlist);',
        ),
        isTrue,
        reason:
            'PlaylistCardActions should call only the audio controller mix entry.',
      );

      expect(
        playlistCardActionsSource.contains('youtubeSourceProvider'),
        isFalse,
        reason:
            'PlaylistCardActions should not read youtube sources directly for mix bootstrap.',
      );

      expect(
        playlistCardActionsSource.contains('fetchMixTracks('),
        isFalse,
        reason:
            'PlaylistCardActions should not fetch mix tracks directly once the controller owns the flow.',
      );
    });
  });
}
