import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 2 Task 2 key coverage regression', () {
    test('dynamic row widgets accept keys via super.key', () {
      final searchPageSource = File(
        'lib/ui/pages/search/search_page.dart',
      ).readAsStringSync();
      final playlistDetailSource = File(
        'lib/ui/pages/library/playlist_detail_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(r'const\s+_SearchResultTile\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(searchPageSource),
        isTrue,
        reason: '_SearchResultTile should expose super.key before keyed call sites are added.',
      );

      expect(
        RegExp(r'const\s+_LocalTrackTile\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(searchPageSource),
        isTrue,
        reason: '_LocalTrackTile should expose super.key before keyed call sites are added.',
      );

      expect(
        RegExp(r'const\s+_TrackListTile\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(playlistDetailSource),
        isTrue,
        reason: '_TrackListTile should expose super.key before keyed call sites are added.',
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
        reason: 'Online search result rows should use a stable key derived from track identity.',
      );

      expect(
        RegExp(
          r'_LocalTrackTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
          dotAll: true,
        ).hasMatch(searchPageSource),
        isTrue,
        reason: 'Expanded local track rows should use a stable key derived from track identity.',
      );

      final playlistKeyMatches = RegExp(
        r'_TrackListTile\s*\(\s*key:\s*ValueKey\([^\)]*track\.groupKey[^\)]*track\.pageNum\s*\?\?\s*1',
        dotAll: true,
      ).allMatches(playlistDetailSource);

      expect(
        playlistKeyMatches.length,
        greaterThanOrEqualTo(2),
        reason: 'Playlist detail rows should key both single-track and expanded multi-part rows.',
      );
    });
  });
}
