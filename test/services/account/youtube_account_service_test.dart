import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:fmp/services/account/youtube_credentials.dart';

void main() {
  group('YouTubeAccountService.getMissingRequiredCookies', () {
    test('returns all missing required cookies', () {
      final missing = YouTubeAccountService.getMissingRequiredCookies({
        'SAPISID': 'sapisid',
      });

      expect(missing, equals(['__Secure-1PSID', '__Secure-3PSID']));
    });

    test('returns empty list when all required cookies exist', () {
      final missing = YouTubeAccountService.getMissingRequiredCookies({
        'SAPISID': 'sapisid',
        '__Secure-1PSID': '1psid',
        '__Secure-3PSID': '3psid',
        'LOGIN_INFO': 'login-info',
      });

      expect(missing, isEmpty);
    });
  });

  group('YouTubeCredentials.isValid', () {
    test('returns true when LOGIN_INFO is missing', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '1psid',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: '',
        savedAt: DateTime(2026),
      );

      expect(credentials.isValid, isTrue);
    });

    test('returns false when __Secure-1PSID is missing', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: '',
        savedAt: DateTime(2026),
      );

      expect(credentials.isValid, isFalse);
    });

    test('returns true when all required cookies exist', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '1psid',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: 'login-info',
        savedAt: DateTime(2026),
      );

      expect(credentials.isValid, isTrue);
    });
  });

  group('YouTubeCredentials.toCookieString', () {
    test('omits empty optional cookies', () {
      final credentials = YouTubeCredentials(
        sid: '',
        hsid: '',
        ssid: '',
        apisid: '',
        sapisid: 'sapisid',
        secure1Psid: '1psid',
        secure3Psid: '3psid',
        secure1Papisid: '',
        secure3Papisid: '',
        loginInfo: '',
        savedAt: DateTime(2026),
      );

      expect(credentials.toCookieString(), contains('SAPISID=sapisid'));
      expect(credentials.toCookieString(), contains('__Secure-1PSID=1psid'));
      expect(credentials.toCookieString(), contains('__Secure-3PSID=3psid'));
      expect(credentials.toCookieString(), isNot(contains('LOGIN_INFO=')));
    });
  });
}
