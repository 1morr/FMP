import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/core/extensions/track_extensions.dart';

void main() {
  group('TrackExtensions', () {
    group('localCoverPath', () {
      test('returns null when downloadedPath is null', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.localCoverPath, isNull);
      });

      test('returns null when cover.jpg does not exist', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..downloadedPath = '/non/existent/path/audio.m4a';

        expect(track.localCoverPath, isNull);
      });

      test('returns cover path when cover.jpg exists', () async {
        // Create temporary directory structure
        final tempDir = await Directory.systemTemp.createTemp('track_test_');
        final videoDir = Directory('${tempDir.path}/video');
        await videoDir.create();
        
        final coverFile = File('${videoDir.path}/cover.jpg');
        await coverFile.writeAsBytes([0xFF, 0xD8, 0xFF]); // Minimal JPEG header
        
        final audioPath = '${videoDir.path}/audio.m4a';

        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..downloadedPath = audioPath;

        expect(track.localCoverPath, equals('${videoDir.path}/cover.jpg'));

        // Cleanup
        await tempDir.delete(recursive: true);
      });
    });

    group('localAvatarPath', () {
      test('returns null when downloadedPath is null', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.localAvatarPath, isNull);
      });

      test('returns null when avatar.jpg does not exist', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..downloadedPath = '/non/existent/path/audio.m4a';

        expect(track.localAvatarPath, isNull);
      });

      test('returns avatar path when avatar.jpg exists', () async {
        // Create temporary directory structure
        final tempDir = await Directory.systemTemp.createTemp('track_test_');
        final videoDir = Directory('${tempDir.path}/video');
        await videoDir.create();
        
        final avatarFile = File('${videoDir.path}/avatar.jpg');
        await avatarFile.writeAsBytes([0xFF, 0xD8, 0xFF]); // Minimal JPEG header
        
        final audioPath = '${videoDir.path}/audio.m4a';

        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..downloadedPath = audioPath;

        expect(track.localAvatarPath, equals('${videoDir.path}/avatar.jpg'));

        // Cleanup
        await tempDir.delete(recursive: true);
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

    group('hasLocalCover', () {
      test('returns false when localCoverPath is null', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.hasLocalCover, isFalse);
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

    group('hasCover', () {
      test('returns false when no cover available', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track';

        expect(track.hasCover, isFalse);
      });

      test('returns true when network cover available', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.bilibili
          ..title = 'Test Track'
          ..thumbnailUrl = 'https://example.com/cover.jpg';

        expect(track.hasCover, isTrue);
      });
    });
  });
}
