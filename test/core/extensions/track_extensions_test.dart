import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/core/extensions/track_extensions.dart';
import 'package:fmp/providers/download/file_exists_cache.dart';
import 'package:path/path.dart' as p;

/// Test helper: FileExistsCache with pre-populated state
class TestFileExistsCache extends FileExistsCache {
  TestFileExistsCache(Set<String> initialState) : super() {
    state = initialState;
  }

  /// Mark a path as existing or not
  void setExists(String path, bool exists) {
    if (exists) {
      state = {...state, path};
    } else {
      final newState = Set<String>.from(state);
      newState.remove(path);
      state = newState;
    }
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

        // Empty set = no files exist
        final cache = TestFileExistsCache({});
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
          '/some/path/cover.jpg',
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

        // Only /path2/cover.jpg exists
        final cache = TestFileExistsCache({
          '/path2/cover.jpg',
        });
        expect(track.getLocalCoverPath(cache), equals('/path2/cover.jpg'));
      });
    });

    group('getLocalAvatarPath', () {
      test('returns null when baseDir is null', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..ownerId = 12345;

        final cache = TestFileExistsCache({});
        expect(track.getLocalAvatarPath(cache, baseDir: null), isNull);
      });

      test('returns null when ownerId is null for Bilibili', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        final cache = TestFileExistsCache({});
        expect(track.getLocalAvatarPath(cache, baseDir: '/downloads'), isNull);
      });

      test('returns null when channelId is null for YouTube', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.youtube
          ..title = 'Test Track';

        final cache = TestFileExistsCache({});
        expect(track.getLocalAvatarPath(cache, baseDir: '/downloads'), isNull);
      });

      test('returns null when avatar does not exist for Bilibili', () {
        const baseDir = '/downloads';

        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..ownerId = 12345;

        // Empty set = file does not exist
        final cache = TestFileExistsCache({});
        expect(track.getLocalAvatarPath(cache, baseDir: baseDir), isNull);
      });

      test('returns avatar path for Bilibili when file exists', () {
        const baseDir = '/downloads';
        final avatarPath = p.join(baseDir, 'avatars', 'bilibili', '12345.jpg');

        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..ownerId = 12345;

        final cache = TestFileExistsCache({
          avatarPath,
        });
        expect(
          track.getLocalAvatarPath(cache, baseDir: baseDir),
          equals(avatarPath),
        );
      });

      test('returns avatar path for YouTube when file exists', () {
        const baseDir = '/downloads';
        final avatarPath = p.join(baseDir, 'avatars', 'youtube', 'UCq-Fj5jknLsUf-MWSy4_brA.jpg');

        final track = Track()
          ..sourceId = 'testYT123'
          ..sourceType = SourceType.youtube
          ..title = 'Test Track'
          ..channelId = 'UCq-Fj5jknLsUf-MWSy4_brA';

        final cache = TestFileExistsCache({
          avatarPath,
        });
        expect(
          track.getLocalAvatarPath(cache, baseDir: baseDir),
          equals(avatarPath),
        );
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
