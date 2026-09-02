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
      expect(source, contains('bool _isRetryableError(Object error)'));
      // 解析層的例外也已型別化：不再有任何字串比對的分類器。
      expect(source, isNot(contains('_isStringNetworkError')));
      expect(source, contains('error is SocketException'));
      expect(source, contains('error is TimeoutException'));
      expect(
          source,
          contains(
              'if (error is SourceApiException) return error.kind.isRetryable;'));
      expect(source, isNot(contains('bool _isNetworkError(dynamic error)')));

      // D2：預算逾時不進退避階梯，adapter 的 TimeoutException 才進。兩者
      // 順序寫反的話，逾時就會變成「重試五次、每次都重新完整解析」。
      final budgetCheck =
          source.indexOf('if (error is PlaybackTimeoutException) return false;');
      final timeoutCheck = source.indexOf('error is TimeoutException');
      expect(budgetCheck, isNot(-1));
      expect(budgetCheck, lessThan(timeoutCheck));
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
      expect(dispatchBody, isNot(contains('.contains(')));
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
