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
      expect(source, contains('_onAudioError(String error)'));
      final onAudioErrorStart =
          source.indexOf('void _onAudioError(String error)');
      final onAudioErrorBody = source.substring(onAudioErrorStart);
      expect(onAudioErrorBody, contains('_isStringNetworkError(error)'));
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
