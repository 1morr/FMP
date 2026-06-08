import 'dart:io';

import 'package:dio/dio.dart';

class SourceUrlPolicy {
  SourceUrlPolicy._();

  static const spotifyHosts = {'open.spotify.com'};
  static const spotifyShortHosts = {'spotify.link'};
  static const qqMusicHosts = {'y.qq.com', 'i.y.qq.com'};
  static const qqMusicShortHosts = {'c.y.qq.com', 'url.cn'};
  static const neteaseHosts = {'music.163.com', 'y.music.163.com'};
  static const neteaseShortHosts = {'163cn.tv'};

  static String? parseBilibiliFavoritesId(String url) {
    final fidMatch = RegExp(r'fid=(\d+)').firstMatch(url);
    if (fidMatch != null) {
      return fidMatch.group(1);
    }

    final mlMatch = RegExp(r'ml(\d+)').firstMatch(url);
    if (mlMatch != null) {
      return mlMatch.group(1);
    }

    final detailMatch = RegExp(r'/detail/ml(\d+)').firstMatch(url);
    if (detailMatch != null) {
      return detailMatch.group(1);
    }

    return null;
  }

  static Uri? parseTrustedHttpUrl(
    String url, {
    required Set<String> allowedHosts,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final host = normalizeHost(uri.host);
    if (!allowedHosts.contains(host)) return null;
    if (isLocalOrPrivateHost(host)) return null;
    return uri;
  }

  static bool isTrustedHttpUrl(
    String url, {
    required Set<String> allowedHosts,
  }) {
    return parseTrustedHttpUrl(url, allowedHosts: allowedHosts) != null;
  }

  static Future<String> resolveRedirects(
    Dio dio,
    String url, {
    required Set<String> initialAllowedHosts,
    required Set<String> redirectAllowedHosts,
    bool preferHead = false,
  }) async {
    final initial = parseTrustedHttpUrl(
      url,
      allowedHosts: initialAllowedHosts,
    );
    if (initial == null) {
      throw ArgumentError.value(url, 'url', 'Untrusted source URL');
    }
    var current = initial;

    final allAllowedHosts = {
      ...initialAllowedHosts,
      ...redirectAllowedHosts,
    };

    for (var redirectCount = 0; redirectCount < 5; redirectCount++) {
      final response = await _requestWithoutRedirects(
        dio,
        current,
        preferHead: preferHead,
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        return current.toString();
      }

      final next = current.resolve(location);
      final trustedNext = parseTrustedHttpUrl(
        next.toString(),
        allowedHosts: allAllowedHosts,
      );
      if (trustedNext == null) {
        throw ArgumentError.value(
          next.toString(),
          'location',
          'Untrusted source redirect target',
        );
      }
      current = trustedNext;
    }

    throw StateError('Too many source URL redirects');
  }

  static Future<Response<dynamic>> _requestWithoutRedirects(
    Dio dio,
    Uri uri, {
    required bool preferHead,
  }) async {
    final options = Options(
      followRedirects: false,
      validateStatus: (status) => status != null && status < 400,
    );
    if (preferHead) {
      try {
        return await dio.headUri(uri, options: options);
      } on DioException {
        return dio.getUri(uri, options: options);
      }
    }
    return dio.getUri(uri, options: options);
  }

  static String normalizeHost(String host) {
    var normalized = host.trim().toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static Uri? parseNeteaseFragment(String fragment) {
    if (fragment.isEmpty) return null;
    return Uri.tryParse(
      fragment.startsWith('/') ? 'https://music.163.com$fragment' : fragment,
    );
  }

  static bool isLocalOrPrivateHost(String host) {
    final normalized = normalizeHost(host);
    if (normalized == 'localhost' || normalized.endsWith('.localhost')) {
      return true;
    }

    final address = InternetAddress.tryParse(normalized);
    if (address == null) return false;
    final bytes = address.rawAddress;

    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      return a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127);
    }

    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      final first = bytes[0];
      final second = bytes[1];
      final isLoopback =
          bytes.take(15).every((byte) => byte == 0) && bytes[15] == 1;
      return isLoopback ||
          first == 0 ||
          (first & 0xfe) == 0xfc ||
          (first == 0xfe && (second & 0xc0) == 0x80);
    }

    return false;
  }
}
