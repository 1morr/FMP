import 'package:dio/dio.dart';

import '../../core/utils/http_client_factory.dart';
import '../models/track.dart';
import 'source_url_policy.dart';

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
  static const String bilibiliLiveReferer = 'https://live.bilibili.com/';
  static const String bilibiliSearchOrigin = 'https://search.bilibili.com';
  static const String bilibiliSearchReferer = 'https://search.bilibili.com/';
  static const String bilibiliSearchAcceptLanguage = 'zh-CN,zh;q=0.9,en;q=0.8';
  static const String youtubeOrigin = 'https://www.youtube.com';
  static const String youtubeReferer = 'https://www.youtube.com/';
  static const String neteaseOrigin = 'https://music.163.com';
  static const String neteaseReferer = 'https://music.163.com/';

  static Map<String, String> mediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
    String? requestUrl,
    bool includeCredentials = true,
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

    if (sourceType == SourceType.netease &&
        authHeaders != null &&
        includeCredentials &&
        canAttachNeteaseMediaCredentials(requestUrl)) {
      for (final key in const ['Cookie', 'Origin', 'Referer', 'User-Agent']) {
        final value = authHeaders[key];
        if (value != null && value.isNotEmpty) {
          headers[key] = value;
        }
      }
    }

    return headers;
  }

  static Map<String, String> imageHeaders(
    SourceType sourceType, {
    bool includeUserAgent = true,
  }) {
    final headers = switch (sourceType) {
      SourceType.bilibili => <String, String>{
          'Referer': bilibiliWebReferer,
        },
      SourceType.youtube => <String, String>{
          'Origin': youtubeOrigin,
          'Referer': youtubeReferer,
        },
      SourceType.netease => <String, String>{
          'Origin': neteaseOrigin,
          'Referer': neteaseReferer,
        },
    };

    if (includeUserAgent) {
      headers['User-Agent'] = mediaUserAgent;
    }
    return headers;
  }

  static Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  }) {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;

    if (_isHostOrSubdomain(host, 'hdslb.com') ||
        _isHostOrSubdomain(host, 'bilibili.com')) {
      return imageHeaders(
        SourceType.bilibili,
        includeUserAgent: includeUserAgent,
      );
    }
    if (_isHostOrSubdomain(host, 'ytimg.com') ||
        _isHostOrSubdomain(host, 'ggpht.com') ||
        _isHostOrSubdomain(host, 'googleusercontent.com')) {
      return imageHeaders(
        SourceType.youtube,
        includeUserAgent: includeUserAgent,
      );
    }
    if (_isHostOrSubdomain(host, 'music.126.net')) {
      return imageHeaders(
        SourceType.netease,
        includeUserAgent: includeUserAgent,
      );
    }
    return null;
  }

  static bool canAttachNeteaseMediaCredentials(String? requestUrl) {
    if (requestUrl == null || requestUrl.isEmpty) return false;
    final uri = Uri.tryParse(requestUrl);
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;

    final host = SourceUrlPolicy.normalizeHost(uri.host);
    if (host.isEmpty) return false;

    return host == 'music.163.com' ||
        host.endsWith('.music.163.com') ||
        host == 'music.126.net' ||
        host.endsWith('.music.126.net');
  }

  static bool _isHostOrSubdomain(String host, String domain) {
    return host == domain || host.endsWith('.$domain');
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

  static Map<String, String> bilibiliSearchApiHeaders({
    required String cookie,
    String? userAgent,
  }) {
    return apiHeaders(
      SourceType.bilibili,
      userAgent: userAgent,
      extraHeaders: {
        'Referer': bilibiliSearchReferer,
        'Origin': bilibiliSearchOrigin,
        'Accept-Language': bilibiliSearchAcceptLanguage,
        'Cookie': cookie,
      },
    );
  }

  static Map<String, String> bilibiliLiveHeaders({String? userAgent}) {
    return {
      'Referer': bilibiliLiveReferer,
      'User-Agent': userAgent ?? mediaUserAgent,
    };
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

  static Dio createBilibiliLiveDio({String? userAgent}) {
    return HttpClientFactory.create(
      headers: bilibiliLiveHeaders(userAgent: userAgent),
    );
  }
}
