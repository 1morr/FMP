import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/sources/bilibili_exception.dart';
import 'package:fmp/data/sources/youtube_exception.dart';
import 'package:fmp/data/sources/netease_exception.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/data/models/track.dart';

void main() {
  group('BilibiliApiException', () {
    test('isUnavailable for -404', () {
      const e = BilibiliApiException(numericCode: -404, message: 'Not found');
      expect(e.isUnavailable, isTrue);
      expect(e.code, 'unavailable');
      expect(e.sourceType, SourceType.bilibili);
    });

    test('isUnavailable for 62002', () {
      const e = BilibiliApiException(numericCode: 62002, message: 'Removed');
      expect(e.isUnavailable, isTrue);
    });

    test('isRateLimited for -412', () {
      const e = BilibiliApiException(numericCode: -412, message: 'Rate limited');
      expect(e.isRateLimited, isTrue);
      expect(e.code, 'rate_limited');
    });

    test('isRateLimited for -509', () {
      const e = BilibiliApiException(numericCode: -509, message: 'Rate limited');
      expect(e.isRateLimited, isTrue);
    });

    test('requiresLogin for -101', () {
      const e = BilibiliApiException(numericCode: -101, message: 'Login required');
      expect(e.requiresLogin, isTrue);
      expect(e.code, 'login_required');
    });

    test('isPermissionDenied for -403', () {
      const e = BilibiliApiException(numericCode: -403, message: 'Forbidden');
      expect(e.isPermissionDenied, isTrue);
      expect(e.code, 'permission_denied');
    });

    test('isGeoRestricted for -10403', () {
      const e = BilibiliApiException(numericCode: -10403, message: 'Geo');
      expect(e.isGeoRestricted, isTrue);
      expect(e.code, 'geo_restricted');
    });

    test('isNetworkError for -2', () {
      const e = BilibiliApiException(numericCode: -2, message: 'Network');
      expect(e.isNetworkError, isTrue);
      expect(e.code, 'network_error');
    });

    test('isTimeout for -1', () {
      const e = BilibiliApiException(numericCode: -1, message: 'Timeout');
      expect(e.isTimeout, isTrue);
      expect(e.code, 'timeout');
    });

    test('unknown code maps to api_error', () {
      const e = BilibiliApiException(numericCode: 999, message: 'Unknown');
      expect(e.code, 'api_error');
      expect(e.isUnavailable, isFalse);
      expect(e.isRateLimited, isFalse);
      expect(e.requiresLogin, isFalse);
    });

    test('is SourceApiException', () {
      const e = BilibiliApiException(numericCode: -1, message: 'test');
      expect(e, isA<SourceApiException>());
    });

    test('toString includes code and message', () {
      const e = BilibiliApiException(numericCode: -404, message: 'Not found');
      expect(e.toString(), contains('-404'));
      expect(e.toString(), contains('Not found'));
    });
  });

  group('YouTubeApiException', () {
    test('isUnavailable for multiple codes', () {
      for (final code in ['unavailable', 'not_found', 'unplayable', 'no_stream']) {
        final e = YouTubeApiException(code: code, message: 'test');
        expect(e.isUnavailable, isTrue, reason: '$code should be unavailable');
      }
    });

    test('isRateLimited', () {
      const e = YouTubeApiException(code: 'rate_limited', message: 'test');
      expect(e.isRateLimited, isTrue);
    });

    test('requiresLogin for age_restricted', () {
      const e = YouTubeApiException(code: 'age_restricted', message: 'test');
      expect(e.requiresLogin, isTrue);
      expect(e.isPermissionDenied, isTrue);
    });

    test('isPrivateOrInaccessible', () {
      const e = YouTubeApiException(code: 'private_or_inaccessible', message: 'test');
      expect(e.isPrivateOrInaccessible, isTrue);
      expect(e.isPermissionDenied, isTrue);
    });

    test('isGeoRestricted', () {
      const e = YouTubeApiException(code: 'geo_restricted', message: 'test');
      expect(e.isGeoRestricted, isTrue);
    });

    test('isNetworkError', () {
      const e = YouTubeApiException(code: 'network_error', message: 'test');
      expect(e.isNetworkError, isTrue);
    });

    test('isTimeout', () {
      const e = YouTubeApiException(code: 'timeout', message: 'test');
      expect(e.isTimeout, isTrue);
    });

    test('sourceType is youtube', () {
      const e = YouTubeApiException(code: 'test', message: 'test');
      expect(e.sourceType, SourceType.youtube);
    });

    test('is SourceApiException', () {
      const e = YouTubeApiException(code: 'test', message: 'test');
      expect(e, isA<SourceApiException>());
    });
  });

  group('NeteaseApiException', () {
    test('isUnavailable for -200', () {
      const e = NeteaseApiException(numericCode: -200, message: 'Unavailable');
      expect(e.isUnavailable, isTrue);
      expect(e.code, 'unavailable');
    });

    test('isRateLimited for -460', () {
      const e = NeteaseApiException(numericCode: -460, message: 'Rate limited');
      expect(e.isRateLimited, isTrue);
      expect(e.code, 'rate_limited');
    });

    test('isRateLimited for -462', () {
      const e = NeteaseApiException(numericCode: -462, message: 'Rate limited');
      expect(e.isRateLimited, isTrue);
    });

    test('requiresLogin for 301', () {
      const e = NeteaseApiException(numericCode: 301, message: 'Login');
      expect(e.requiresLogin, isTrue);
      expect(e.code, 'requires_login');
    });

    test('isVipRequired for -10', () {
      const e = NeteaseApiException(numericCode: -10, message: 'VIP');
      expect(e.isVipRequired, isTrue);
    });

    test('isPermissionDenied for 403', () {
      const e = NeteaseApiException(numericCode: 403, message: 'Forbidden');
      expect(e.isPermissionDenied, isTrue);
      expect(e.code, 'forbidden');
    });

    test('isNetworkError for -998', () {
      const e = NeteaseApiException(numericCode: -998, message: 'Network');
      expect(e.isNetworkError, isTrue);
      expect(e.code, 'network_error');
    });

    test('isTimeout for -997', () {
      const e = NeteaseApiException(numericCode: -997, message: 'Timeout');
      expect(e.isTimeout, isTrue);
      expect(e.code, 'timeout');
    });

    test('sourceType is netease', () {
      const e = NeteaseApiException(numericCode: 0, message: 'test');
      expect(e.sourceType, SourceType.netease);
    });

    test('isGeoRestricted is always false', () {
      const e = NeteaseApiException(numericCode: -10403, message: 'test');
      expect(e.isGeoRestricted, isFalse);
    });

    test('is SourceApiException', () {
      const e = NeteaseApiException(numericCode: 0, message: 'test');
      expect(e, isA<SourceApiException>());
    });
  });

  group('SourceApiException polymorphism', () {
    test('all exceptions can be caught as SourceApiException', () {
      final exceptions = <SourceApiException>[
        const BilibiliApiException(numericCode: -404, message: 'test'),
        const YouTubeApiException(code: 'unavailable', message: 'test'),
        const NeteaseApiException(numericCode: -200, message: 'test'),
      ];

      for (final e in exceptions) {
        expect(e.isUnavailable, isTrue, reason: '${e.runtimeType} should be unavailable');
        expect(e.code, isNotEmpty);
        expect(e.message, isNotEmpty);
      }
    });

    test('different sources have correct sourceType', () {
      const b = BilibiliApiException(numericCode: 0, message: 'test');
      const y = YouTubeApiException(code: 'test', message: 'test');
      const n = NeteaseApiException(numericCode: 0, message: 'test');

      expect(b.sourceType, SourceType.bilibili);
      expect(y.sourceType, SourceType.youtube);
      expect(n.sourceType, SourceType.netease);
    });
  });
}
