import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioController source error kind usage', () {
    /// 這一條只守「字串分類器不准長回來」。分類本身的行為由
    /// `playback_error_presenter_test.dart` 用真的例外物件釘住 —— 那比比對
    /// 原始碼字面強，所以原本在這裡的正向簽名斷言已經移過去了。
    ///
    /// 掃整個目錄而不是單一檔案：分類器搬到 `playback_error_presenter.dart`
    /// 之後，只掃 `audio_provider.dart` 的斷言會變成恆真，守門形同解除。
    test('no playback error is classified by string matching', () {
      final audioSources = Directory(
        '${Directory.current.path}/lib/services/audio',
      ).listSync(recursive: true).whereType<File>().where(
            (file) => file.path.endsWith('.dart'),
          );
      expect(audioSources, isNotEmpty);

      for (final file in audioSources) {
        final source = file.readAsStringSync();
        for (final forbidden in const [
          '_isStringNetworkError',
          '_isStringMediaOpenError',
          'bool _isNetworkError(dynamic error)',
          '_shouldHandleTrackCompleted',
        ]) {
          expect(source.contains(forbidden), isFalse,
              reason: '${file.path} still classifies by string: $forbidden');
        }
      }
    });

    test('the error presenter keeps the kind helpers it was given', () {
      final source =
          File('lib/services/audio/playback_error_presenter.dart')
              .readAsStringSync();

      expect(source, contains('error.kind.isRetryable'));
      expect(source, contains('error.kind.shouldSkipTrack'));
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

      // 釋放改由 `ref.onDispose` 觸發，方法名隨之改成 `_teardown`。
      final disposeStart = source.indexOf('void _teardown()');
      expect(disposeStart, isNot(-1));
      final disposeBody = source.substring(disposeStart);

      expect(disposeBody, contains('unawaited(_audioService.dispose()'));
      expect(disposeBody, contains('catchError'));
      expect(disposeBody, contains('logError('));
    });
  });
}
