import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioController source error kind usage', () {
    test('typed source errors use kind helpers before string fallback', () {
      final source =
          File('lib/services/audio/audio_provider.dart').readAsStringSync();

      expect(source,
          contains('bool _shouldRetrySourceError(SourceApiException error)'));
      expect(source, contains('error.kind.isRetryable'));
      expect(source,
          contains('bool _shouldSkipSourceError(SourceApiException error)'));
      expect(source, contains('error.kind.shouldSkipTrack'));
      expect(source, contains('bool _isStringNetworkError(Object error)'));
      expect(source, contains('bool _isRetryableError(Object error)'));
      expect(
          source,
          contains(
              'if (error is SourceApiException) return error.kind.isRetryable;'));
      expect(source, isNot(contains('bool _isNetworkError(dynamic error)')));
    });

    test('backend playback events are dispatched by type, not by string', () {
      final source =
          File('lib/services/audio/audio_provider.dart').readAsStringSync();

      // 後端事件走型別化的 PlaybackEndReason，不再比對錯誤字串。
      expect(source, contains('_onPlaybackEnded(PlaybackEndReason reason)'));
      expect(source, contains('case OutputDeviceFailed('));
      expect(source, contains('case EndedPrematurely('));
      expect(source, contains('case TransportFailed('));

      // 這兩個字串比對器是 issue #41 的成因，必須已經消失。
      expect(source, isNot(contains('_isStringMediaOpenError')));
      expect(source, isNot(contains('_shouldHandleTrackCompleted')));

      final dispatchStart =
          source.indexOf('void _onPlaybackEnded(PlaybackEndReason reason)');
      expect(dispatchStart, isNot(-1));
      final dispatchBody = source.substring(dispatchStart);
      expect(dispatchBody, isNot(contains('_isStringNetworkError')));
    });

    test('dispose handles async backend cleanup errors', () {
      final source =
          File('lib/services/audio/audio_provider.dart').readAsStringSync();

      final disposeStart = source.indexOf('void dispose()');
      expect(disposeStart, isNot(-1));
      final disposeBody = source.substring(disposeStart);

      expect(disposeBody, contains('unawaited(_audioService.dispose()'));
      expect(disposeBody, contains('catchError'));
      expect(disposeBody, contains('logError('));
    });
  });
}
