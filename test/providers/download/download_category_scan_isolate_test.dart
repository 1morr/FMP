import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/download/download_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  group('downloaded category detail scan isolate support', () {
    test('scanFolderTrackDtosInIsolate returns transferable metadata DTOs',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'download_category_scan_isolate_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final videoDir = Directory(p.join(tempDir.path, 'yt-1_Test Video'));
      await videoDir.create(recursive: true);
      await File(p.join(videoDir.path, 'audio.m4a')).writeAsBytes([1, 2, 3]);
      await File(p.join(videoDir.path, 'metadata.json')).writeAsString(
        jsonEncode({
          'sourceId': 'yt-1',
          'sourceType': 'youtube',
          'title': 'Test Video',
          'artist': 'Tester',
          'durationMs': 123000,
          'thumbnailUrl': 'https://img.example/thumb.jpg',
          'downloadedAt': '2026-04-25T12:00:00.000',
        }),
      );

      final dtos = await scanFolderTrackDtosInIsolate(
        ScanFolderTracksParams(tempDir.path),
      );
      final track = dtos.single.toTrack();

      expect(dtos, hasLength(1));
      expect(track.sourceId, 'yt-1');
      expect(track.sourceType, SourceType.youtube);
      expect(track.title, 'Test Video');
      expect(track.artist, 'Tester');
      expect(
        track.playlistInfo.single.downloadPath,
        p.join(videoDir.path, 'audio.m4a'),
      );
    });

    test('downloadedCategoryTracksProvider uses Isolate.run entrypoint', () {
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
    });
  });
}
