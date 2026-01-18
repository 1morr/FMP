import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/core/extensions/track_extensions.dart';
import 'package:fmp/providers/download/file_exists_cache.dart';

/// Test helper: FileExistsCache with pre-populated state
class TestFileExistsCache extends FileExistsCache {
  TestFileExistsCache(Map<String, bool> initialState) : super() {
    state = initialState;
  }

  /// Update a single path's existence
  void setExists(String path, bool exists) {
    state = {...state, path: exists};
  }
}

void main() {
  group('TrackExtensions', () {
    group('getLocalCoverPath', () {
      test('returns null when no download path', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        final cache = TestFileExistsCache({});
        expect(track.getLocalCoverPath(cache), isNull);
      });

      test('returns null when cover.jpg does not exist in cache', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..playlistIds = [0]
          ..downloadPaths = ['/some/path/audio.m4a'];

        final cache = TestFileExistsCache({
          '/some/path/cover.jpg': false,
        });
        expect(track.getLocalCoverPath(cache), isNull);
      });

      test('returns cover path when cover.jpg exists in cache', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..playlistIds = [0]
          ..downloadPaths = ['/some/path/audio.m4a'];

        final cache = TestFileExistsCache({
          '/some/path/cover.jpg': true,
        });
        expect(track.getLocalCoverPath(cache), equals('/some/path/cover.jpg'));
      });

      test('returns first existing cover path from multiple download paths', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..playlistIds = [0, 1]
          ..downloadPaths = ['/path1/audio.m4a', '/path2/audio.m4a'];

        final cache = TestFileExistsCache({
          '/path1/cover.jpg': false,
          '/path2/cover.jpg': true,
        });
        expect(track.getLocalCoverPath(cache), equals('/path2/cover.jpg'));
      });
    });

    group('getLocalAvatarPath', () {
      test('returns null when no download path', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        final cache = TestFileExistsCache({});
        expect(track.getLocalAvatarPath(cache), isNull);
      });

      test('returns null when avatar.jpg does not exist in cache', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..playlistIds = [0]
          ..downloadPaths = ['/some/path/audio.m4a'];

        final cache = TestFileExistsCache({
          '/some/path/avatar.jpg': false,
        });
        expect(track.getLocalAvatarPath(cache), isNull);
      });

      test('returns avatar path when avatar.jpg exists in cache', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..playlistIds = [0]
          ..downloadPaths = ['/some/path/audio.m4a'];

        final cache = TestFileExistsCache({
          '/some/path/avatar.jpg': true,
        });
        expect(track.getLocalAvatarPath(cache), equals('/some/path/avatar.jpg'));
      });
    });

    group('formattedDuration', () {
      test('returns --:-- when durationMs is null', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.formattedDuration, equals('--:--'));
      });

      test('formats seconds correctly', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..durationMs = 45000; // 45 seconds

        expect(track.formattedDuration, equals('00:45'));
      });

      test('formats minutes and seconds correctly', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..durationMs = 185000; // 3:05

        expect(track.formattedDuration, equals('03:05'));
      });

      test('formats hours correctly', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..durationMs = 3725000; // 1:02:05

        expect(track.formattedDuration, equals('01:02:05'));
      });
    });

    group('hasNetworkCover', () {
      test('returns false when thumbnailUrl is null', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.hasNetworkCover, isFalse);
      });

      test('returns false when thumbnailUrl is empty', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..thumbnailUrl = '';

        expect(track.hasNetworkCover, isFalse);
      });

      test('returns true when thumbnailUrl is not empty', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..thumbnailUrl = 'https://example.com/cover.jpg';

        expect(track.hasNetworkCover, isTrue);
      });
    });

    group('localAudioPath', () {
      test('returns null when no download path', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.localAudioPath, isNull);
      });

      test('returns null when audio file does not exist', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..playlistIds = [0]
          ..downloadPaths = ['/non/existent/path/audio.m4a'];

        expect(track.localAudioPath, isNull);
      });

      test('returns audio path when file exists', () async {
        // Create temporary directory structure
        final tempDir = await Directory.systemTemp.createTemp('track_test_');
        final videoDir = Directory('${tempDir.path}/video');
        await videoDir.create();

        final audioFile = File('${videoDir.path}/audio.m4a');
        await audioFile.writeAsBytes([0x00, 0x00, 0x00]); // Minimal file

        final audioPath = '${videoDir.path}/audio.m4a';

        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..playlistIds = [0]
          ..downloadPaths = [audioPath];

        expect(track.localAudioPath, equals(audioPath));

        // Cleanup
        await tempDir.delete(recursive: true);
      });
    });

    group('hasLocalAudio', () {
      test('returns false when localAudioPath is null', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.hasLocalAudio, isFalse);
      });
    });

    group('isDownloaded', () {
      test('returns false when no local audio', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.isDownloaded, isFalse);
      });
    });
  });
}
