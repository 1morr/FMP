import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';

/// 錯誤分類照 brief §13。UI 以 exhaustive switch 依類別決定怎麼呈現；
/// 新增或刪掉類別時這裡會編譯失敗，提醒去對 brief。
String category(AppError error) => switch (error) {
  NetworkError() => 'network',
  RateLimited() => 'rate limited',
  LoginRequired() => 'login required',
  CredentialInvalid() => 'credential invalid',
  VerificationRequired() => 'verification required',
  Unavailable(:final reason) => 'unavailable: ${reason.name}',
  NotFound() => 'not found',
  ParseFailure() => 'parse failure',
  Unsupported() => 'unsupported',
};

void main() {
  test('every category in brief §13 is a case of AppError', () {
    expect(
      [
        const NetworkError(),
        const RateLimited(),
        const LoginRequired(),
        const CredentialInvalid(),
        const VerificationRequired(),
        const Unavailable(UnavailableReason.region),
        const NotFound(),
        const ParseFailure(),
        const Unsupported(),
      ].map(category),
      [
        'network',
        'rate limited',
        'login required',
        'credential invalid',
        'verification required',
        'unavailable: region',
        'not found',
        'parse failure',
        'unsupported',
      ],
    );
  });

  test('unavailable carries one of the four reasons in brief §13', () {
    expect(UnavailableReason.values.map((r) => r.name), [
      'region',
      'copyright',
      'membershipRequired',
      'trialOnly',
    ]);
  });

  test('the log line names the category and the reason', () {
    expect('${const RateLimited()}', 'RateLimited');
    expect(
      '${const Unavailable(UnavailableReason.trialOnly)}',
      'Unavailable(trialOnly)',
    );
  });

  test('an AppError can be thrown and caught as an Exception', () {
    expect(() => throw const NotFound(), throwsA(isA<Exception>()));
  });
}
