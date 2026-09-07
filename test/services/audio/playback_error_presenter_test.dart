import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/playback_error_presenter.dart';

/// 斷言比的是「挑了哪一句翻譯」而不是字面文字 —— 後者會在改 i18n JSON 時無故
/// 失敗，卻抓不到挑錯句子的 bug。
class _Error extends SourceApiException {
  const _Error({
    required this.kind,
    this.message = '',
    this.code = 'test_code',
    this.sourceType = SourceIds.youtube,
  });

  @override
  final SourceErrorKind kind;
  @override
  final String message;
  @override
  final String code;
  @override
  final String sourceType;
}

Track _track(String title) => Track()..title = title;

void main() {
  const presenter = PlaybackErrorPresenter();

  group('reasonFor', () {
    test('prefers a meaningful diagnostic from the adapter', () {
      const error = _Error(kind: SourceErrorKind.unavailable, message: '稿件不可见');
      expect(presenter.reasonFor(error), '稿件不可见');
    });

    test('drops a numeric-only diagnostic', () {
      const error = _Error(kind: SourceErrorKind.unavailable, message: '-404');
      expect(presenter.reasonFor(error), t.audio.sourceErrorUnavailable);
    });

    test('drops a diagnostic that just repeats the code', () {
      const error = _Error(
        kind: SourceErrorKind.network,
        message: 'network_error',
        code: 'network_error',
      );
      expect(presenter.reasonFor(error), t.audio.sourceErrorNetwork);
    });

    test('drops the synthetic english diagnostics', () {
      const error = _Error(
        kind: SourceErrorKind.vipRequired,
        message: 'VIP song, payment required',
      );
      expect(presenter.reasonFor(error), t.audio.sourceErrorVipRequired);
    });

    test('permission denied reads differently on bilibili', () {
      const bilibili = _Error(
        kind: SourceErrorKind.permissionDenied,
        sourceType: SourceIds.bilibili,
      );
      const youtube = _Error(kind: SourceErrorKind.permissionDenied);

      expect(
        presenter.reasonFor(bilibili),
        t.audio.sourceErrorBilibiliPermissionDenied,
      );
      expect(presenter.reasonFor(youtube), t.audio.sourceErrorPermissionDenied);
    });

    test('an unknown kind with nothing to say falls back to unknown error', () {
      const error = _Error(kind: SourceErrorKind.unknown, message: '   ');
      expect(presenter.reasonFor(error), t.error.unknownError);
    });
  });

  group('messages', () {
    const error = _Error(kind: SourceErrorKind.geoRestricted);

    test('the skipped wording differs from the plain one', () {
      final plain = presenter.cannotPlay(_track('Song'), error);
      final skipped = presenter.cannotPlay(
        _track('Song'),
        error,
        skipped: true,
      );

      expect(plain, contains('Song'));
      expect(skipped, contains('Song'));
      expect(skipped, isNot(plain));
    });

    test('playbackFailed carries the reason but not the title', () {
      expect(
        presenter.playbackFailed(error),
        contains(t.audio.sourceErrorGeoRestricted),
      );
    });
  });

  group('classification', () {
    test('skip and retry follow the error kind', () {
      expect(
        presenter.shouldSkipTrack(
          const _Error(kind: SourceErrorKind.geoRestricted),
        ),
        isTrue,
      );
      expect(
        presenter.shouldSkipTrack(const _Error(kind: SourceErrorKind.network)),
        isFalse,
      );
      expect(
        presenter.shouldRetrySource(
          const _Error(kind: SourceErrorKind.timeout),
        ),
        isTrue,
      );
      expect(
        presenter.shouldRetrySource(
          const _Error(kind: SourceErrorKind.vipRequired),
        ),
        isFalse,
      );
    });

    test('a spent budget never enters the backoff ladder', () {
      // PlaybackTimeoutException 必須先於 TimeoutException 判定 —— 反過來的話
      // 逾時會變成「重試五次、每次重新完整解析」。
      const timeout = PlaybackTimeoutException(
        PlaybackTimeoutPhase.mediaOpen,
        Duration(seconds: 8),
      );
      expect(presenter.isRetryable(timeout), isFalse);
      expect(presenter.isRetryable(TimeoutException('adapter')), isTrue);
    });

    test('dart:io transport failures are retryable', () {
      expect(presenter.isRetryable(const SocketException('down')), isTrue);
      expect(presenter.isRetryable(const HttpException('bad')), isTrue);
      expect(presenter.isRetryable(const TlsException('handshake')), isTrue);
    });

    test('an unclassified error is not retried', () {
      expect(presenter.isRetryable(StateError('who knows')), isFalse);
    });
  });
}
