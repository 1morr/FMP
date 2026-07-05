import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/download/download_path_utils.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DownloadPathUtils', () {
    test('sanitizes sourceId before building download path', () {
      final baseDir = p.join('C:', 'Users', 'tester', 'Music', 'FMP');
      final track = Track()
        ..sourceId = '..\\..\\secret'
        ..sourceType = SourceType.youtube
        ..title = 'Title'
        ..createdAt = DateTime(2026);

      final path = DownloadPathUtils.computeDownloadPath(
        baseDir: baseDir,
        playlistName: 'Playlist',
        track: track,
      );

      expect(path, contains('..＼..＼secret_Title'));
      expect(DownloadPathUtils.isPathInsideBase(path, baseDir), isTrue);
      expect(p.split(path), isNot(contains('secret_Title')));
    });

    test('prefixes Windows reserved device names', () {
      expect(DownloadPathUtils.sanitizeFileName('CON'), '_CON');
      expect(DownloadPathUtils.sanitizeFileName('con.txt'), '_con.txt');
      expect(DownloadPathUtils.sanitizeFileName('LPT1.'), '_LPT1');
      expect(DownloadPathUtils.sanitizeFileName('normal'), 'normal');
    });

    test('folder sourceId matching uses sanitized sourceId', () {
      expect(
        DownloadPathUtils.folderMatchesSourceId(
          '..／evil_Title',
          '../evil',
        ),
        isTrue,
      );
    });

    group('avatar path (D13)', () {
      final baseDir = p.join('C:', 'Users', 'tester', 'Music', 'FMP');

      test('avatar subdir derives from sourceType.name for all sources', () {
        // 關鍵：不再用 bilibili/youtube 二元分支——netease 必須落到自己的
        // 目錄段，否則頭像會誤歸 youtube（D13 silent-failure 叢）。
        for (final type in SourceType.values) {
          final path = DownloadPathUtils.getAvatarPath(
            baseDir: baseDir,
            sourceType: type,
            creatorId: 'creator-1',
          );
          // 路徑內含 .../avatars/{type.name}/creator-1.jpg
          expect(p.split(path), contains('avatars'));
          expect(p.split(path), contains(type.name));
          expect(path, endsWith(p.join('avatars', type.name, 'creator-1.jpg')));
        }
      });

      test('netease avatar is not misrouted to the youtube directory', () {
        final path = DownloadPathUtils.getAvatarPath(
          baseDir: baseDir,
          sourceType: SourceType.netease,
          creatorId: 'up-1',
        );
        expect(p.split(path), contains('netease'));
        expect(p.split(path), isNot(contains('youtube')));
      });

      test('bilibili and youtube avatar subdirs are unchanged by the fix', () {
        final bilibili = DownloadPathUtils.getAvatarPath(
          baseDir: baseDir,
          sourceType: SourceType.bilibili,
          creatorId: 'up-1',
        );
        final youtube = DownloadPathUtils.getAvatarPath(
          baseDir: baseDir,
          sourceType: SourceType.youtube,
          creatorId: 'up-1',
        );
        expect(p.split(bilibili), contains('bilibili'));
        expect(p.split(youtube), contains('youtube'));
      });
    });
  });
}
