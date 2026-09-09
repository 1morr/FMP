/// 四條「接線接錯不會報錯」的規則，靠讀源碼釘住。
///
/// 每一條原本都住在一支同名的行為測試裡，從檔名看不出它在 grep 源碼。
/// 共同點是：接錯的後果是安靜的 —— 掃描回到主 isolate（畫面卡住）、歌詞跟著
/// 位置重建（每秒重畫整頁）、清單改完沒人失效（畫面停在舊資料）、移除路徑順手
/// 建了曲目（資料庫多出沒人指向的列）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('provider wiring static rules', () {
    test(
      'downloadedCategoryTracksProvider uses the Isolate.run entrypoint',
      () {
        final source = File(
          'lib/providers/download/download_providers.dart',
        ).readAsStringSync();

        expect(source, contains('Isolate.run'));
        expect(source, contains('scanFolderTrackDtosInIsolate'));
        expect(source, contains('ScanFolderTracksParams(folderPath)'));
        expect(
          source,
          isNot(contains('DownloadScanner.scanFolderForTracks(folderPath)')),
        );
      },
    );

    test(
      'LyricsDisplay consumes the line index provider, not raw position',
      () {
        final source = File(
          'lib/ui/widgets/lyrics/lyrics_display.dart',
        ).readAsStringSync();

        expect(source, contains('currentLyricsLineIndexProvider'));
        expect(
          source,
          isNot(contains('audioControllerProvider.select((s) => s.position)')),
        );
      },
    );

    test('UI mutation sites refresh through the invalidation coordinator', () {
      for (final entry in _libraryMutationSites().entries) {
        final source = entry.value;
        expect(
          source,
          contains('libraryInvalidationCoordinatorProvider'),
          reason:
              '${entry.key} should route UI mutation refreshes through the '
              'coordinator',
        );
        expect(
          source,
          isNot(contains('ref.invalidate(allPlaylistsProvider)')),
          reason:
              '${entry.key} should not directly invalidate allPlaylistsProvider',
        );
        expect(
          source,
          isNot(contains('ref.invalidate(playlistDetailProvider')),
          reason:
              '${entry.key} should not directly invalidate '
              'playlistDetailProvider',
        );
        expect(
          source,
          isNot(contains('ref.invalidate(playlistCoverProvider')),
          reason:
              '${entry.key} should not directly invalidate '
              'playlistCoverProvider',
        );
        expect(
          source,
          isNot(contains('invalidatePlaylistProviders')),
          reason:
              '${entry.key} should not use legacy playlist invalidation helpers',
        );
      }
    });

    test('add-to-playlist removal path does not create tracks', () {
      final source = File(
        'lib/ui/widgets/dialogs/add_to_playlist_dialog.dart',
      ).readAsStringSync();
      final removeLoopStart = source.indexOf('// 先处理移除');
      final addLoopStart = source.indexOf('// 再处理添加');
      expect(removeLoopStart, isNonNegative);
      expect(addLoopStart, greaterThan(removeLoopStart));
      final removeSection = source.substring(removeLoopStart, addLoopStart);

      expect(removeSection, contains('removeTracksFromPlaylist'));
      expect(removeSection, isNot(contains('getOrCreate')));
      expect(removeSection, isNot(contains('removeTrackFromPlaylist')));
    });
  });
}

/// 會改動歌單、因此必須走失效協調器的 UI 入口。
Map<String, String> _libraryMutationSites() {
  const paths = [
    'lib/ui/pages/library/widgets/import_playlist_dialog.dart',
    'lib/ui/widgets/dialogs/add_to_playlist_dialog.dart',
    'lib/ui/pages/library/import_preview_page.dart',
    'lib/ui/pages/library/playlist_detail_page.dart',
    'lib/ui/pages/settings/widgets/account_playlists_sheet.dart',
    'lib/ui/pages/settings/widgets/settings_backup.dart',
  ];

  return {for (final path in paths) path: File(path).readAsStringSync()};
}
