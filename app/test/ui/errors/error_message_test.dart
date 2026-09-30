import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/runtime/script_errors.dart';
import 'package:fmp/ui/errors/error_message.dart';

/// 每個 [ErrorMessageKey] 一個錯誤。
final _byKey = <ErrorMessageKey, AppError>{
  ErrorMessageKey.network: NetworkError(),
  ErrorMessageKey.rateLimited: RateLimited(pluginId: 'bilibili'),
  ErrorMessageKey.authRequired: AuthRequired(pluginId: 'bilibili'),
  ErrorMessageKey.credentialInvalid: CredentialInvalid(pluginId: 'bilibili'),
  ErrorMessageKey.verificationRequired: VerificationRequired(
    pluginId: 'bilibili',
  ),
  ErrorMessageKey.unavailable: Unavailable(reason: UnavailableReason.copyright),
  ErrorMessageKey.notFound: NotFound(),
  ErrorMessageKey.parseError: ParseError(pluginId: 'bilibili'),
  ErrorMessageKey.unexpected: UnexpectedError(),
};

void main() {
  test('the samples cover every key', () {
    expect(_byKey.keys.toSet(), ErrorMessageKey.values.toSet());
    for (final MapEntry(:key, :value) in _byKey.entries) {
      expect(value.messageKey, key);
    }
  });

  for (final locale in AppLocale.values) {
    group(locale.languageTag, () {
      final t = locale.buildSync();

      test('every key has its own message', () {
        final messages = {
          for (final error in _byKey.values)
            errorMessage(t, error, sourceName: 'Bilibili'),
        };
        expect(messages, hasLength(_byKey.length));
        expect(messages, everyElement(isNotEmpty));
      });

      test('the source name goes where the message names the source', () {
        for (final key in [
          ErrorMessageKey.rateLimited,
          ErrorMessageKey.authRequired,
          ErrorMessageKey.credentialInvalid,
          ErrorMessageKey.verificationRequired,
          ErrorMessageKey.parseError,
        ]) {
          final error = _byKey[key]!;
          expect(
            errorMessage(t, error, sourceName: 'Bilibili'),
            contains('Bilibili'),
          );
          expect(
            errorMessage(t, error),
            contains(t.errors.unknownSource),
            reason: 'no source name falls back to the generic word',
          );
        }
      });

      test('an unavailable item says why', () {
        for (final reason in UnavailableReason.values) {
          expect(
            errorMessage(t, Unavailable(reason: reason)),
            contains(unavailableReasonText(t, reason)),
          );
        }
        // 音源把別的類別覆寫成 unavailable 時沒有原因，用不帶原因的句子。
        expect(
          errorMessage(t, NotFound(messageKey: ErrorMessageKey.unavailable)),
          t.errors.unavailable,
        );
      });

      test("a plugin's own message never reaches the text", () {
        for (final name in [
          'RateLimited',
          'ParseError',
          'UnexpectedError',
          'no such class',
        ]) {
          final error = structuredScriptError(
            pluginId: 'fmp-test',
            fmpError: name,
            message: 'FAKE_SERVER_TEXT_123',
          );
          expect(
            errorMessage(t, error, sourceName: 'Test'),
            isNot(contains('FAKE_SERVER_TEXT_123')),
          );
        }
      });
    });
  }
}
