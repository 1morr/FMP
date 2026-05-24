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
  });
}
