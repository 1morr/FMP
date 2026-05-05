import 'package:dio/dio.dart';

import '../../core/utils/http_client_factory.dart';
import '../models/track.dart';

class SourceHttpPolicy {
  SourceHttpPolicy._();

  static const String mediaUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const String webUserAgent = HttpClientFactory.defaultUserAgent;
  static const String neteaseDesktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 '
      'NeteaseMusicDesktop/3.0.18.203152';
  static const String neteaseLinuxUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36';

  static const String bilibiliOrigin = 'https://www.bilibili.com';
  static const String bilibiliReferer = 'https://www.bilibili.com/';
  static const String bilibiliWebReferer = 'https://www.bilibili.com';
  static const String youtubeOrigin = 'https://www.youtube.com';
  static const String youtubeReferer = 'https://www.youtube.com/';
  static const String neteaseOrigin = 'https://music.163.com';
  static const String neteaseReferer = 'https://music.163.com/';

  static Map<String, String> mediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
  }) {
    final headers = switch (sourceType) {
      SourceType.bilibili => <String, String>{
          'Referer': bilibiliWebReferer,
          'User-Agent': mediaUserAgent,
        },
      SourceType.youtube => <String, String>{
          'Origin': youtubeOrigin,
          'Referer': youtubeReferer,
          'User-Agent': mediaUserAgent,
        },
      SourceType.netease => <String, String>{
          'Origin': neteaseOrigin,
          'Referer': neteaseReferer,
          'User-Agent': mediaUserAgent,
        },
    };

    if (sourceType == SourceType.netease && authHeaders != null) {
      for (final key in const ['Cookie', 'Origin', 'Referer', 'User-Agent']) {
        final value = authHeaders[key];
        if (value != null && value.isNotEmpty) {
          headers[key] = value;
        }
      }
    }

    return headers;
  }

  static Map<String, String> apiHeaders(
    SourceType sourceType, {
    Map<String, String>? extraHeaders,
    String? userAgent,
  }) {
    final headers = switch (sourceType) {
      SourceType.bilibili => <String, String>{
          'User-Agent': userAgent ?? webUserAgent,
          'Referer': bilibiliReferer,
          'Origin': bilibiliOrigin,
          'Accept': 'application/json, text/plain, */*',
        },
      SourceType.youtube => <String, String>{
          'User-Agent': userAgent ?? mediaUserAgent,
          'Origin': youtubeOrigin,
          'Referer': youtubeReferer,
        },
      SourceType.netease => <String, String>{
          'User-Agent': userAgent ?? neteaseDesktopUserAgent,
          'Referer': neteaseReferer,
          'Origin': neteaseOrigin,
          'Accept': 'application/json, text/plain, */*',
        },
    };

    headers.addAll(extraHeaders ?? const <String, String>{});
    return headers;
  }

  static Map<String, String> neteaseAuthHeaders(String cookie) {
    return {
      'Cookie': cookie,
      'Origin': neteaseOrigin,
      'Referer': neteaseReferer,
      'User-Agent': neteaseDesktopUserAgent,
    };
  }

  static Dio createApiDio(
    SourceType sourceType, {
    Map<String, String>? extraHeaders,
    String? userAgent,
    String? contentType,
  }) {
    return HttpClientFactory.create(
      headers: apiHeaders(
        sourceType,
        extraHeaders: extraHeaders,
        userAgent: userAgent,
      ),
      contentType: contentType,
    );
  }
}
