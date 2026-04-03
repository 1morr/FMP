import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/player_state.dart';

void main() {
  group('PlayerState', () {
    test('default values', () {
      const state = PlayerState();

      expect(state.isPlaying, isFalse);
      expect(state.isBuffering, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.position, Duration.zero);
      expect(state.duration, isNull);
      expect(state.speed, 1.0);
      expect(state.volume, 1.0);
      expect(state.isShuffleEnabled, isFalse);
      expect(state.currentTrack, isNull);
      expect(state.hasCurrentTrack, isFalse);
      expect(state.queue, isEmpty);
      expect(state.upcomingTracks, isEmpty);
      expect(state.canPlayPrevious, isFalse);
      expect(state.canPlayNext, isFalse);
      expect(state.isMixMode, isFalse);
      expect(state.error, isNull);
      expect(state.isNetworkError, isFalse);
      expect(state.isRetrying, isFalse);
      expect(state.retryAttempt, 0);
    });

    group('progress', () {
      test('returns 0 when duration is null', () {
        const state = PlayerState(
          position: Duration(seconds: 30),
        );

        expect(state.progress, 0.0);
      });

      test('returns 0 when duration is zero', () {
        const state = PlayerState(
          position: Duration(seconds: 30),
          duration: Duration.zero,
        );

        expect(state.progress, 0.0);
      });

      test('returns correct progress', () {
        const state = PlayerState(
          position: Duration(seconds: 30),
          duration: Duration(seconds: 120),
        );

        expect(state.progress, 0.25);
      });

      test('returns 1.0 at end', () {
        const state = PlayerState(
          position: Duration(seconds: 120),
          duration: Duration(seconds: 120),
        );

        expect(state.progress, 1.0);
      });
    });

    group('bufferedProgress', () {
      test('returns 0 when duration is null', () {
        const state = PlayerState(
          bufferedPosition: Duration(seconds: 60),
        );

        expect(state.bufferedProgress, 0.0);
      });

      test('returns correct buffered progress', () {
        const state = PlayerState(
          bufferedPosition: Duration(seconds: 60),
          duration: Duration(seconds: 120),
        );

        expect(state.bufferedProgress, 0.5);
      });
    });

    group('copyWith', () {
      test('preserves values when no changes', () {
        const original = PlayerState(
          isPlaying: true,
          position: Duration(seconds: 30),
          volume: 0.8,
        );

        final copy = original.copyWith();

        expect(copy.isPlaying, isTrue);
        expect(copy.position, const Duration(seconds: 30));
        expect(copy.volume, 0.8);
      });

      test('updates specified values', () {
        const original = PlayerState(isPlaying: false);

        final copy = original.copyWith(
          isPlaying: true,
          position: const Duration(seconds: 10),
        );

        expect(copy.isPlaying, isTrue);
        expect(copy.position, const Duration(seconds: 10));
      });

      test('clearPlayingTrack removes track', () {
        final track = Track()
          ..sourceId = 'test'
          ..sourceType = SourceType.bilibili
          ..title = 'Test';

        final state = PlayerState(playingTrack: track);
        expect(state.playingTrack, isNotNull);

        final cleared = state.copyWith(clearPlayingTrack: true);
        expect(cleared.playingTrack, isNull);
        expect(cleared.currentTrack, isNull);
        expect(cleared.hasCurrentTrack, isFalse);
      });

      test('error is nullable in copyWith', () {
        const state = PlayerState(error: 'something went wrong');
        expect(state.error, 'something went wrong');

        // copyWith without error should clear it (error field uses null semantics)
        final cleared = state.copyWith();
        expect(cleared.error, isNull);
      });
    });

    group('currentTrack compatibility', () {
      test('currentTrack returns playingTrack', () {
        final track = Track()
          ..sourceId = 'test123'
          ..sourceType = SourceType.youtube
          ..title = 'Test Song';

        final state = PlayerState(playingTrack: track);

        expect(state.currentTrack, equals(track));
        expect(state.hasCurrentTrack, isTrue);
      });
    });
  });
}
