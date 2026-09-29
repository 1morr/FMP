import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';

/// 每個子類一個樣本。新增子類時 [_defaults] 的 switch 會編譯失敗，
/// 提醒在這裡補一個。
final _samples = <AppError>[
  NetworkError(),
  RateLimited(),
  AuthRequired(),
  CredentialInvalid(),
  VerificationRequired(),
  Unavailable(reason: UnavailableReason.region),
  NotFound(),
  ParseError(),
  Unsupported(),
  UnexpectedError(),
];

/// ADR 0013：只有網路與限流預設可重試；解析失敗、不支援與預期外視為 bug。
({bool retryable, bool expected, ErrorMessageKey key}) _defaults(
  AppError error,
) => switch (error) {
  NetworkError() => (
    retryable: true,
    expected: true,
    key: ErrorMessageKey.network,
  ),
  RateLimited() => (
    retryable: true,
    expected: true,
    key: ErrorMessageKey.rateLimited,
  ),
  AuthRequired() => (
    retryable: false,
    expected: true,
    key: ErrorMessageKey.authRequired,
  ),
  CredentialInvalid() => (
    retryable: false,
    expected: true,
    key: ErrorMessageKey.credentialInvalid,
  ),
  VerificationRequired() => (
    retryable: false,
    expected: true,
    key: ErrorMessageKey.verificationRequired,
  ),
  Unavailable() => (
    retryable: false,
    expected: true,
    key: ErrorMessageKey.unavailable,
  ),
  NotFound() => (
    retryable: false,
    expected: true,
    key: ErrorMessageKey.notFound,
  ),
  ParseError() => (
    retryable: false,
    expected: false,
    key: ErrorMessageKey.parseError,
  ),
  Unsupported() => (
    retryable: false,
    expected: false,
    key: ErrorMessageKey.unexpected,
  ),
  UnexpectedError() => (
    retryable: false,
    expected: false,
    key: ErrorMessageKey.unexpected,
  ),
};

void main() {
  group('defaults', () {
    for (final error in _samples) {
      test('${error.runtimeType}', () {
        final expected = _defaults(error);
        expect(error.retryable, expected.retryable, reason: 'retryable');
        expect(error.expected, expected.expected, reason: 'expected');
        expect(error.messageKey, expected.key, reason: 'messageKey');
        expect(error.messageArgs, isEmpty);
        expect(error.pluginId, isNull);
        expect(error.retryAfter, isNull);
        expect(error.networkRecordId, isNull);
        // 測試不混淆，runtimeType 就是類別名。
        expect(error.typeName, '${error.runtimeType}');
      });
    }

    test('the samples cover every subclass once', () {
      expect(_samples.map((e) => e.runtimeType).toSet(), hasLength(10));
    });
  });

  test('a source can override retryable and the message', () {
    final error = NotFound(
      pluginId: 'bilibili',
      retryable: true,
      messageKey: ErrorMessageKey.unavailable,
      messageArgs: {'count': 3},
    );

    expect(error.retryable, isTrue);
    expect(error.messageKey, ErrorMessageKey.unavailable);
    expect(error.messageArgs, {'count': 3});
    expect(RateLimited(retryable: false).retryable, isFalse);
  });

  group('wrap', () {
    test('returns an AppError unchanged', () {
      final original = RateLimited(pluginId: 'bilibili');

      expect(
        AppError.wrap(original, StackTrace.current, pluginId: 'youtube'),
        same(original),
      );
    });

    test('wraps anything else as an unexpected bug', () {
      for (final thrown in <Object>[
        StateError('boom'),
        const FormatException('bad'),
        'a thrown string',
      ]) {
        final wrapped = AppError.wrap(
          thrown,
          StackTrace.current,
          pluginId: 'bilibili',
        );

        expect(wrapped, isA<UnexpectedError>());
        expect(wrapped.expected, isFalse);
        expect(wrapped.retryable, isFalse);
        expect(wrapped.pluginId, 'bilibili');
      }
    });
  });

  group('toString is for logs and leaves the cause out', () {
    test('describes the type and the structured fields', () {
      final error = Unavailable(
        reason: UnavailableReason.previewOnly,
        pluginId: 'netease',
        retryAfter: const Duration(seconds: 30),
        networkRecordId: 7,
      );

      expect(
        '$error',
        'Unavailable(pluginId: netease, reason: previewOnly, '
            'retryable: false, retryAfter: 0:00:30.000000, networkRecordId: 7)',
      );
      expect('${NetworkError()}', 'NetworkError(retryable: true)');
    });

    test('never includes the cause or its stack trace', () {
      final error = AppError.wrap(
        StateError('412 for SESSDATA=FAKE_SESSDATA_123'),
        StackTrace.fromString('#0 fetch (FAKE_STACK_SECRET_123)'),
      );

      expect('$error', 'UnexpectedError(retryable: false)');
    });
  });
}
