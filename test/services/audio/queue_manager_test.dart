import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/track.dart';

void main() {
  group('PlayQueue model', () {
    group('properties', () {
      test('length returns correct value', () {
        final queue = PlayQueue()..trackIds = [1, 2, 3, 4, 5];

        expect(queue.length, equals(5));
      });

      test('isEmpty returns true for empty queue', () {
        final queue = PlayQueue();

        expect(queue.isEmpty, isTrue);
        expect(queue.isNotEmpty, isFalse);
      });

      test('isNotEmpty returns true for non-empty queue', () {
        final queue = PlayQueue()..trackIds = [1, 2, 3];

        expect(queue.isNotEmpty, isTrue);
        expect(queue.isEmpty, isFalse);
      });
    });

    group('navigation', () {
      test('hasNext returns true when not at end', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 0;

        expect(queue.hasNext, isTrue);
      });

      test('hasNext returns false when at last track', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 2;

        expect(queue.hasNext, isFalse);
      });

      test('hasPrevious returns false when at first track', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 0;

        expect(queue.hasPrevious, isFalse);
      });

      test('hasPrevious returns true when not at beginning', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 1;

        expect(queue.hasPrevious, isTrue);
      });
    });

    group('currentTrackId', () {
      test('returns null for empty queue', () {
        final queue = PlayQueue();

        expect(queue.currentTrackId, isNull);
      });

      test('returns correct track id', () {
        final queue = PlayQueue()
          ..trackIds = [10, 20, 30]
          ..currentIndex = 1;

        expect(queue.currentTrackId, equals(20));
      });

      test('returns null when index out of bounds', () {
        final queue = PlayQueue()
          ..trackIds = [1, 2, 3]
          ..currentIndex = 10;

        expect(queue.currentTrackId, isNull);
      });
    });

    group('LoopMode', () {
      test('default loop mode is none', () {
        final queue = PlayQueue();

        expect(queue.loopMode, equals(LoopMode.none));
      });

      test('can set loop mode to all', () {
        final queue = PlayQueue()..loopMode = LoopMode.all;

        expect(queue.loopMode, equals(LoopMode.all));
      });

      test('can set loop mode to one', () {
        final queue = PlayQueue()..loopMode = LoopMode.one;

        expect(queue.loopMode, equals(LoopMode.one));
      });
    });

    group('shuffle', () {
      test('default shuffle is disabled', () {
        final queue = PlayQueue();

        expect(queue.isShuffleEnabled, isFalse);
      });

      test('can enable shuffle', () {
        final queue = PlayQueue()..isShuffleEnabled = true;

        expect(queue.isShuffleEnabled, isTrue);
      });

      test('originalOrder is null by default', () {
        final queue = PlayQueue();

        expect(queue.originalOrder, isNull);
      });

      test('can store original order', () {
        final queue = PlayQueue()..originalOrder = [3, 1, 2];

        expect(queue.originalOrder, equals([3, 1, 2]));
      });
    });

    group('volume', () {
      test('default volume is 1.0', () {
        final queue = PlayQueue();

        expect(queue.lastVolume, equals(1.0));
      });

      test('can set volume', () {
        final queue = PlayQueue()..lastVolume = 0.5;

        expect(queue.lastVolume, equals(0.5));
      });
    });

    group('position', () {
      test('default position is 0', () {
        final queue = PlayQueue();

        expect(queue.lastPositionMs, equals(0));
      });

      test('can set position', () {
        final queue = PlayQueue()..lastPositionMs = 30000; // 30 seconds

        expect(queue.lastPositionMs, equals(30000));
      });
    });
  });

  group('Track model queue operations', () {
    test('copyForQueue creates independent copy', () {
      final original = Track()
        ..id = 100
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Original Title'
        ..artist = 'Artist Name'
        ..durationMs = 180000;

      final copy = original.copyForQueue();

      expect(copy.id, equals(0)); // Reset to auto-increment
      expect(copy.sourceId, equals(original.sourceId));
      expect(copy.title, equals(original.title));
      expect(copy.artist, equals(original.artist));
      expect(copy.durationMs, equals(original.durationMs));
    });

    test('copyForQueue preserves download paths', () {
      final original = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test'
        ..playlistIds = [1, 2]
        ..downloadPaths = ['/path/to/audio1.m4a', '/path/to/audio2.m4a'];

      final copy = original.copyForQueue();

      expect(copy.playlistIds, equals(original.playlistIds));
      expect(copy.downloadPaths, equals(original.downloadPaths));
    });

    test('copyForQueue preserves multi-page info', () {
      final original = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'P01 - Introduction'
        ..cid = 12345
        ..pageNum = 1
        ..parentTitle = 'Full Video';

      final copy = original.copyForQueue();

      expect(copy.cid, equals(original.cid));
      expect(copy.pageNum, equals(original.pageNum));
      expect(copy.parentTitle, equals(original.parentTitle));
    });
  });

  group('Track audio URL validation', () {
    test('hasValidAudioUrl returns false when url is null', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test';

      expect(track.hasValidAudioUrl, isFalse);
    });

    test('hasValidAudioUrl returns true when url exists without expiry', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test'
        ..audioUrl = 'https://example.com/audio.m4a';

      expect(track.hasValidAudioUrl, isTrue);
    });

    test('hasValidAudioUrl returns true when not expired', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test'
        ..audioUrl = 'https://example.com/audio.m4a'
        ..audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));

      expect(track.hasValidAudioUrl, isTrue);
    });

    test('hasValidAudioUrl returns false when expired', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Test'
        ..audioUrl = 'https://example.com/audio.m4a'
        ..audioUrlExpiry = DateTime.now().subtract(const Duration(hours: 1));

      expect(track.hasValidAudioUrl, isFalse);
    });
  });

  group('Track multi-page operations', () {
    test('isPartOfMultiPage returns false for single page', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'Single Video';

      expect(track.isPartOfMultiPage, isFalse);
    });

    test('isPartOfMultiPage returns true for multi-page', () {
      final track = Track()
        ..sourceId = 'test123'
        ..sourceType = SourceType.bilibili
        ..title = 'P01 - Intro'
        ..pageNum = 1;

      expect(track.isPartOfMultiPage, isTrue);
    });

    test('groupKey is same for pages of same video', () {
      final page1 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P01'
        ..pageNum = 1
        ..cid = 111;

      final page2 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P02'
        ..pageNum = 2
        ..cid = 222;

      expect(page1.groupKey, equals(page2.groupKey));
    });

    test('uniqueKey is different for pages of same video', () {
      final page1 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P01'
        ..cid = 111;

      final page2 = Track()
        ..sourceId = 'BV123456'
        ..sourceType = SourceType.bilibili
        ..title = 'P02'
        ..cid = 222;

      expect(page1.uniqueKey, isNot(equals(page2.uniqueKey)));
    });
  });
}
