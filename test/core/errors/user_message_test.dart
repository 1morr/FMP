import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/user_message.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/i18n/strings.g.dart';

/// 斷言比的是「挑了哪一句翻譯」而不是字面文字 —— 後者會在改 i18n JSON 時無故
/// 失敗，卻抓不到挑錯句子的 bug。形狀照 `playback_error_presenter_test.dart`。
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

void main() {
  group('sourceErrorReason', () {
    test('every kind produces a non-empty sentence', () {
      // 窮舉的 switch 少一個 kind 分析器就會擋下來，但「回了空字串」它擋不住。
      for (final kind in SourceErrorKind.values) {
        final reason = sourceErrorReason(_Error(kind: kind, message: 'boom'));
        expect(reason.trim(), isNotEmpty, reason: '$kind');
      }
    });

    test('keeps a meaningful diagnostic from the adapter', () {
      expect(
        sourceErrorReason(
          const _Error(kind: SourceErrorKind.unavailable, message: '稿件不可见'),
        ),
        '稿件不可见',
      );
    });

    test('falls back to the kind when the diagnostic is low signal', () {
      expect(
        sourceErrorReason(
          const _Error(kind: SourceErrorKind.unavailable, message: '-404'),
        ),
        t.audio.sourceErrorUnavailable,
      );
    });
  });

  group('userMessageFor', () {
    test('delegates source errors to sourceErrorReason', () {
      const error = _Error(kind: SourceErrorKind.timeout);
      expect(userMessageFor(error), sourceErrorReason(error));
      expect(userMessageFor(error), t.audio.sourceErrorTimeout);
    });

    test('maps the dart:io network exceptions to one network sentence', () {
      expect(
        userMessageFor(const SocketException('failed')),
        t.error.networkError,
      );
      expect(
        userMessageFor(const HttpException('failed')),
        t.error.networkError,
      );
      expect(
        userMessageFor(const TlsException('failed')),
        t.error.networkError,
      );
    });

    test('classifies a DioException that no adapter wrapped', () {
      // 實機驗收：電台播放失敗時一整條 DioException 走到了 toast。
      final error = DioException.connectionError(
        requestOptions: RequestOptions(path: '/x'),
        reason: "Failed host lookup: 'api.live.bilibili.com'",
      );
      expect(userMessageFor(error), t.error.networkError);
      expect(userMessageFor(error), isNot(contains('api.live.bilibili.com')));
    });

    test('maps a timeout', () {
      expect(
        userMessageFor(TimeoutException('slow')),
        t.error.connectionTimeout,
      );
    });

    test('maps a parse failure', () {
      expect(
        userMessageFor(const FormatException('bad json')),
        t.error.dataFormatError,
      );
    });

    test('maps a denied path, and only that path exception', () {
      // PathAccessException 是 FileSystemException 的子型別，switch 的順序決定
      // 它會不會被上一條吃掉 —— 這兩條一起才守得住。
      expect(
        userMessageFor(
          const PathAccessException(
            '/data/x',
            OSError('Permission denied', 13),
          ),
        ),
        t.error.noPermission,
      );
      expect(
        userMessageFor(const FileSystemException('disk gone', '/data/x')),
        t.error.unknownError,
      );
    });

    test('falls back for a type it does not know', () {
      expect(userMessageFor(StateError('bad state')), t.error.unknownError);
      expect(userMessageFor('a bare string'), t.error.unknownError);
    });

    test('never leaks the raw exception text', () {
      // P1-7：使用者看到的不能是 `Exception: <伺服器原文>`。音源錯誤不在此列
      // —— adapter 的診斷本來就是給使用者看的一句話。
      const secret = 'connection refused at 10.0.2.2:8080';
      for (final error in <Object>[
        const SocketException(secret),
        const HttpException(secret),
        TimeoutException(secret),
        const FormatException(secret),
        Exception(secret),
        StateError(secret),
      ]) {
        expect(
          userMessageFor(error),
          isNot(contains(secret)),
          reason: '${error.runtimeType}',
        );
      }
    });
  });
}
