import 'package:dio/dio.dart';

import 'package:fmp/core/utils/http_client_factory.dart';
import 'package:fmp/data/models/track.dart';

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

  static const String _acceptJson = 'application/json, text/plain, */*';

  /// 每個音源送給對方的 header，一個音源一筆；加音源時只改這裡。
  ///
  /// - `cdn`：媒體位元組與圖片請求的 Origin / Referer。
  /// - `api` / `apiUserAgent`：API 請求的其餘 header 與預設 UA。
  /// - `imageHosts`：圖片 CDN 的網域（含子網域），[imageHeadersForUrl] 靠它
  ///   從網址認出音源。
  ///
  /// 以前這是三個各自的 switch 加一串主機名 if，四處要一起改才不會漂移。
  static const Map<String, _SourceHeaders> _bySource = {
    SourceIds.bilibili: (
      // 媒體與圖片的 Referer 刻意不帶結尾斜線，API 的帶。
      cdn: {'Referer': bilibiliWebReferer},
      api: {
        'Referer': bilibiliReferer,
        'Origin': bilibiliOrigin,
        'Accept': _acceptJson,
      },
      apiUserAgent: webUserAgent,
      imageHosts: ['hdslb.com', 'bilibili.com'],
    ),
    SourceIds.youtube: (
      cdn: {'Origin': youtubeOrigin, 'Referer': youtubeReferer},
      api: {'Origin': youtubeOrigin, 'Referer': youtubeReferer},
      apiUserAgent: mediaUserAgent,
      imageHosts: ['ytimg.com', 'ggpht.com', 'googleusercontent.com'],
    ),
    SourceIds.netease: (
      cdn: {'Origin': neteaseOrigin, 'Referer': neteaseReferer},
      api: {
        'Referer': neteaseReferer,
        'Origin': neteaseOrigin,
        'Accept': _acceptJson,
      },
      apiUserAgent: neteaseDesktopUserAgent,
      imageHosts: ['music.126.net'],
    ),
  };

  /// 媒體位元組請求的 header。
  ///
  /// **刻意不帶任何帳號憑證。** 三個音源的媒體 URL 都是簽名過的：音質與播放權
  /// 限在串流解析當下就決定了，CDN 只需要 Origin/Referer/User-Agent。曾經有一
  /// 段「對網易的 https URL 附上 Cookie」的分支，實測 eapi 回的是 `http://`，
  /// 那段程式碼在生產環境一次都沒執行過，已移除。
  ///
  /// 認不得的音源只拿得到 User-Agent。送錯的 Referer/Origin 會讓 CDN 拒絕，
  /// 還會把來源洩漏給不相干的主機；漏送只是退化成匿名請求。
  static Map<String, String> mediaHeaders(String sourceType) {
    return {...?_bySource[sourceType]?.cdn, 'User-Agent': mediaUserAgent};
  }

  static Map<String, String> imageHeaders(
    String sourceType, {
    bool includeUserAgent = true,
  }) {
    return {
      ...?_bySource[sourceType]?.cdn,
      if (includeUserAgent) 'User-Agent': mediaUserAgent,
    };
  }

  /// 依 URL 主機回傳圖片請求標頭。
  ///
  /// [includeUserAgent] 預設為 false：UI 圖片載入（ImageLoadingService）
  /// 依賴各圖片 CDN（hdslb.com / ytimg.com / music.126.net）對預設 UA 的
  /// 容忍，實測僅 Referer 是必需的；下載路徑傳 true（或直接使用
  /// [imageHeaders] 的預設）帶上 mediaUserAgent，與媒體流請求保持一致。
  /// 此 UA 非對稱是刻意為之；若未來某 CDN 開始對無 UA 請求回 403，
  /// 應在此補齊並回報，而不是默默放行。
  static Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  }) {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;

    for (final MapEntry(key: sourceType, value: headers) in _bySource.entries) {
      if (headers.imageHosts.any(
        (domain) => _isHostOrSubdomain(host, domain),
      )) {
        return imageHeaders(sourceType, includeUserAgent: includeUserAgent);
      }
    }
    return null;
  }

  static bool _isHostOrSubdomain(String host, String domain) {
    return host == domain || host.endsWith('.$domain');
  }

  static Map<String, String> apiHeaders(
    String sourceType, {
    Map<String, String>? extraHeaders,
    String? userAgent,
  }) {
    final source = _bySource[sourceType];
    return {
      'User-Agent': userAgent ?? source?.apiUserAgent ?? webUserAgent,
      ...?source?.api,
      ...?extraHeaders,
    };
  }

  static Map<String, String> bilibiliSearchApiHeaders({
    required String cookie,
    String? userAgent,
  }) {
    return apiHeaders(
      SourceIds.bilibili,
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

  static Dio createApiDio(
    String sourceType, {
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

typedef _SourceHeaders = ({
  Map<String, String> cdn,
  Map<String, String> api,
  String apiUserAgent,
  List<String> imageHosts,
});
