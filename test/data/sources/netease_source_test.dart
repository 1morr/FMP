import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/sources/netease_exception.dart';
import 'package:fmp/data/sources/netease_source.dart';

void main() {
  group('NeteaseSource getAudioStream', () {
    test('classifies stream item copyright restriction as geo restricted',
        () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 123,
              'url': null,
              'code': -110,
              'message': '因版权方要求，该资源暂时无法播放',
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('123'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isGeoRestricted, 'isGeoRestricted', isTrue)
              .having((e) => e.message, 'message', contains('版权')),
        ),
      );
    });

    test('classifies stream item VIP message as VIP required', () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 123,
              'url': null,
              'code': 403,
              'fee': 0,
              'message': 'VIP song, payment required',
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('123'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isVipRequired, 'isVipRequired', isTrue)
              .having((e) => e.message, 'message', contains('VIP')),
        ),
      );
    });

    test('classifies stream 404 with copyright flag as geo restricted',
        () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 435948605,
              'url': null,
              'code': 404,
              'fee': 0,
              'flag': 256,
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('435948605'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isGeoRestricted, 'isGeoRestricted', isTrue)
              .having((e) => e.code, 'code', 'geo_restricted'),
        ),
      );
    });

    test('classifies stream 404 with VIP flag as VIP required', () async {
      final source = NeteaseSource(
        dio: _dioReturning({
          'code': 200,
          'data': [
            {
              'id': 1831476071,
              'url': null,
              'code': 404,
              'fee': 0,
              'flag': 260,
            },
          ],
        }),
      );

      await expectLater(
        source.getAudioStream('1831476071'),
        throwsA(
          isA<NeteaseApiException>()
              .having((e) => e.isVipRequired, 'isVipRequired', isTrue)
              .having((e) => e.code, 'code', 'vip_required'),
        ),
      );
    });
  });
}

Dio _dioReturning(Map<String, dynamic> data) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: data,
          ),
        );
      },
    ),
  );
  return dio;
}
