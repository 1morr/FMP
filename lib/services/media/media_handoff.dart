import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/sources/source_http_policy.dart';

typedef NeteasePlaybackRedirectResolver
    = Future<MediaPlaybackRedirectResolution> Function(
  Uri url,
  Map<String, String> streamResolutionAuth,
);

class MediaHandoffRequest {
  const MediaHandoffRequest({
    required this.sourceType,
    required this.url,
    this.streamResolutionAuth,
    this.rangeStart,
  });

  final SourceType sourceType;
  final Uri url;
  final Map<String, String>? streamResolutionAuth;
  final int? rangeStart;
}

class MediaHandoffResult {
  const MediaHandoffResult({
    required this.url,
    required this.headers,
    required this.credentialsIncluded,
  });

  final Uri url;
  final Map<String, String> headers;
  final bool credentialsIncluded;
}

class MediaPlaybackRedirectResolution {
  const MediaPlaybackRedirectResolution({
    required this.url,
    this.includeCredentials = true,
  });

  final Uri url;
  final bool includeCredentials;
}

abstract interface class MediaHandoff {
  Future<MediaHandoffResult> preparePlayback(MediaHandoffRequest request);

  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request);
}

class DefaultMediaHandoff with Logging implements MediaHandoff {
  DefaultMediaHandoff({
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  }) : _neteasePlaybackRedirectResolver = neteasePlaybackRedirectResolver;

  final NeteasePlaybackRedirectResolver? _neteasePlaybackRedirectResolver;

  @override
  Future<MediaHandoffResult> preparePlayback(
    MediaHandoffRequest request,
  ) async {
    if (!_shouldPreflightNeteasePlayback(request)) {
      return _prepareHeaders(request, url: request.url);
    }

    try {
      final resolver =
          _neteasePlaybackRedirectResolver ?? _resolveNeteasePlaybackRedirects;
      final resolution = await resolver(
        request.url,
        request.streamResolutionAuth!,
      );
      return _prepareHeaders(
        request,
        url: resolution.url,
        includeCredentials: resolution.includeCredentials,
      );
    } catch (_) {
      logWarning(
        'Failed to preflight Netease playback redirects; stripping credentials for playback handoff',
      );
      return _prepareHeaders(
        request,
        url: request.url,
        includeCredentials: false,
      );
    }
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    return _prepareHeaders(request, url: request.url);
  }

  bool _shouldPreflightNeteasePlayback(MediaHandoffRequest request) {
    return request.sourceType == SourceType.netease &&
        request.streamResolutionAuth != null &&
        SourceHttpPolicy.canAttachNeteaseMediaCredentials(
          request.url.toString(),
        );
  }

  MediaHandoffResult _prepareHeaders(
    MediaHandoffRequest request, {
    required Uri url,
    bool includeCredentials = true,
  }) {
    final requestUrl = url.toString();
    final credentialsMayAttach = includeCredentials &&
        request.sourceType == SourceType.netease &&
        request.streamResolutionAuth != null &&
        SourceHttpPolicy.canAttachNeteaseMediaCredentials(requestUrl);
    final headers = SourceHttpPolicy.mediaHeaders(
      request.sourceType,
      authHeaders: request.streamResolutionAuth,
      requestUrl: requestUrl,
      includeCredentials: credentialsMayAttach,
    );
    final rangeStart = request.rangeStart;
    if (rangeStart != null && rangeStart > 0) {
      headers[HttpHeaders.rangeHeader] = 'bytes=$rangeStart-';
    }

    return MediaHandoffResult(
      url: url,
      headers: headers,
      credentialsIncluded: credentialsMayAttach &&
          _containsHeader(headers, HttpHeaders.cookieHeader),
    );
  }

  bool _containsHeader(Map<String, String> headers, String name) {
    final normalizedName = name.toLowerCase();
    return headers.keys.any((key) => key.toLowerCase() == normalizedName);
  }

  Future<MediaPlaybackRedirectResolution> _resolveNeteasePlaybackRedirects(
    Uri url,
    Map<String, String> streamResolutionAuth,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = AppConstants.networkConnectTimeout;
    try {
      var currentUri = url;
      for (var redirectCount = 0;
          redirectCount <= _maxPlaybackRedirects;
          redirectCount++) {
        final response = await _probeNeteasePlaybackUrl(
          client,
          currentUri,
          streamResolutionAuth,
        );
        final statusCode = response.statusCode;
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();

        if (!_isRedirectStatus(statusCode)) {
          return MediaPlaybackRedirectResolution(url: currentUri);
        }
        if (location == null || location.isEmpty) {
          return MediaPlaybackRedirectResolution(
            url: currentUri,
            includeCredentials: false,
          );
        }
        if (redirectCount == _maxPlaybackRedirects) {
          return MediaPlaybackRedirectResolution(
            url: currentUri,
            includeCredentials: false,
          );
        }

        final nextUri = currentUri.resolve(location);
        if (!SourceHttpPolicy.canAttachNeteaseMediaCredentials(
          nextUri.toString(),
        )) {
          return MediaPlaybackRedirectResolution(
            url: nextUri,
            includeCredentials: false,
          );
        }
        currentUri = nextUri;
      }
    } finally {
      client.close(force: true);
    }

    return MediaPlaybackRedirectResolution(
      url: url,
      includeCredentials: false,
    );
  }

  Future<HttpClientResponse> _probeNeteasePlaybackUrl(
    HttpClient client,
    Uri uri,
    Map<String, String> streamResolutionAuth,
  ) async {
    final headResponse = await _sendNeteasePlaybackProbe(
      client,
      method: 'HEAD',
      uri: uri,
      streamResolutionAuth: streamResolutionAuth,
    );
    if (headResponse.statusCode != HttpStatus.methodNotAllowed) {
      return headResponse;
    }

    await headResponse.drain<void>();
    return _sendNeteasePlaybackProbe(
      client,
      method: 'GET',
      uri: uri,
      streamResolutionAuth: streamResolutionAuth,
      rangeProbe: true,
    );
  }

  Future<HttpClientResponse> _sendNeteasePlaybackProbe(
    HttpClient client, {
    required String method,
    required Uri uri,
    required Map<String, String> streamResolutionAuth,
    bool rangeProbe = false,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    SourceHttpPolicy.mediaHeaders(
      SourceType.netease,
      authHeaders: streamResolutionAuth,
      requestUrl: uri.toString(),
    ).forEach(request.headers.set);
    if (rangeProbe) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    }
    return request.close().timeout(AppConstants.networkReceiveTimeout);
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == 308;
  }

  static const int _maxPlaybackRedirects = 5;
}
