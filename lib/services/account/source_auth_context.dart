import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_http_policy.dart';
import 'bilibili_account_service.dart';
import 'netease_account_service.dart';
import 'youtube_account_service.dart';

typedef SourceSettingsLoader = Future<Settings> Function();

typedef PlaybackUrlResolver = Future<PlaybackUrlResolution> Function(
  SourceType sourceType,
  String url,
  Map<String, String>? authHeaders,
);

typedef NeteasePlaybackRedirectResolver = Future<PlaybackUrlResolution>
    Function(String url, Map<String, String> authHeaders);

abstract interface class SourceAccountAuthLoader {
  Future<Map<String, String>?> load(SourceType sourceType);
}

/// Compatibility adapter for existing account-service header shapes.
///
/// Future source auth header changes should be made here instead of duplicated
/// in callers.
class AccountServiceAuthLoader implements SourceAccountAuthLoader {
  AccountServiceAuthLoader({
    BilibiliAccountService? bilibiliAccountService,
    YouTubeAccountService? youtubeAccountService,
    NeteaseAccountService? neteaseAccountService,
  })  : _bilibiliAccountService = bilibiliAccountService,
        _youtubeAccountService = youtubeAccountService,
        _neteaseAccountService = neteaseAccountService;

  final BilibiliAccountService? _bilibiliAccountService;
  final YouTubeAccountService? _youtubeAccountService;
  final NeteaseAccountService? _neteaseAccountService;

  @override
  Future<Map<String, String>?> load(SourceType sourceType) async {
    switch (sourceType) {
      case SourceType.bilibili:
        final cookies = await _bilibiliAccountService?.getAuthCookieString();
        if (cookies == null) return null;
        return {'Cookie': cookies};
      case SourceType.youtube:
        final youtubeAccountService = _youtubeAccountService;
        if (youtubeAccountService == null) return null;
        return youtubeAccountService.getAuthHeaders();
      case SourceType.netease:
        final cookies = await _neteaseAccountService?.getAuthCookieString();
        if (cookies == null) return null;
        return SourceHttpPolicy.neteaseAuthHeaders(cookies);
    }
  }
}

abstract interface class SourceAuthContext {
  /// Returns source-account headers for source adapter playback purposes.
  ///
  /// These raw headers are for source adapters, stream resolution, and track
  /// detail calls. They are not media request headers and must not be attached
  /// directly to byte requests. Use [playbackNetworkRequest()],
  /// [downloadMediaHeaders()], or the image header helpers for actual media or
  /// image network requests so source media credential rules are enforced.
  Future<Map<String, String>?> authForPlay(SourceType sourceType);

  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  );

  Map<String, String> downloadMediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
    String? requestUrl,
  });

  Map<String, String> imageHeaders(SourceType sourceType);

  Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  });

  Future<Map<String, String>?> playlistImportAuth(
    SourceType sourceType, {
    required bool useAuth,
  });

  Future<Map<String, String>?> playlistRefreshAuth(
    SourceType sourceType, {
    required bool useAuthForRefresh,
  });
}

class PlaybackUrlResolution {
  const PlaybackUrlResolution({
    required this.url,
    this.includeCredentials = true,
  });

  final String url;
  final bool includeCredentials;
}

class PlaybackNetworkRequest {
  const PlaybackNetworkRequest({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String>? headers;
}

class DefaultSourceAuthContext with Logging implements SourceAuthContext {
  DefaultSourceAuthContext({
    required SourceSettingsLoader settingsLoader,
    required SourceAccountAuthLoader accountAuthLoader,
    PlaybackUrlResolver? playbackUrlResolver,
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  })  : _settingsLoader = settingsLoader,
        _accountAuthLoader = accountAuthLoader,
        _playbackUrlResolver = playbackUrlResolver,
        _neteasePlaybackRedirectResolver = neteasePlaybackRedirectResolver;

  factory DefaultSourceAuthContext.fromRepositories({
    required SettingsRepository settingsRepository,
    required SourceAccountAuthLoader accountAuthLoader,
    PlaybackUrlResolver? playbackUrlResolver,
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  }) {
    return DefaultSourceAuthContext(
      settingsLoader: settingsRepository.get,
      accountAuthLoader: accountAuthLoader,
      playbackUrlResolver: playbackUrlResolver,
      neteasePlaybackRedirectResolver: neteasePlaybackRedirectResolver,
    );
  }

  final SourceSettingsLoader _settingsLoader;
  final SourceAccountAuthLoader _accountAuthLoader;
  final PlaybackUrlResolver? _playbackUrlResolver;
  final NeteasePlaybackRedirectResolver? _neteasePlaybackRedirectResolver;

  /// Loads source-account headers for source adapter playback purposes.
  ///
  /// The returned raw credentials are for source adapters, stream resolution,
  /// and track detail calls after `Settings.useAuthForPlay()` allows them. They
  /// are not media request headers and must not be attached directly to byte
  /// requests. Use [playbackNetworkRequest()], [downloadMediaHeaders()], or the
  /// image header helpers for actual media or image network requests so
  /// `SourceHttpPolicy` can enforce credential allowlists.
  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    final settings = await _settingsLoader();
    if (!settings.useAuthForPlay(sourceType)) return null;
    return _accountAuthLoader.load(sourceType);
  }

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    final authHeaders = await authForPlay(track.sourceType);
    final resolver = _playbackUrlResolver ?? _resolvePlaybackUrl;
    final resolved = await resolver(track.sourceType, url, authHeaders);
    return PlaybackNetworkRequest(
      url: resolved.url,
      headers: SourceHttpPolicy.mediaHeaders(
        track.sourceType,
        authHeaders: authHeaders,
        requestUrl: resolved.url,
        includeCredentials: resolved.includeCredentials,
      ),
    );
  }

  @override
  Map<String, String> downloadMediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
    String? requestUrl,
  }) {
    return SourceHttpPolicy.mediaHeaders(
      sourceType,
      authHeaders: authHeaders,
      requestUrl: requestUrl,
    );
  }

  @override
  Map<String, String> imageHeaders(SourceType sourceType) {
    return SourceHttpPolicy.imageHeaders(sourceType);
  }

  @override
  Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  }) {
    return SourceHttpPolicy.imageHeadersForUrl(
      url,
      includeUserAgent: includeUserAgent,
    );
  }

  @override
  Future<Map<String, String>?> playlistImportAuth(
    SourceType sourceType, {
    required bool useAuth,
  }) async {
    if (!useAuth) return null;
    return _accountAuthLoader.load(sourceType);
  }

  @override
  Future<Map<String, String>?> playlistRefreshAuth(
    SourceType sourceType, {
    required bool useAuthForRefresh,
  }) async {
    if (!useAuthForRefresh) return null;
    return _accountAuthLoader.load(sourceType);
  }

  Future<PlaybackUrlResolution> _resolvePlaybackUrl(
    SourceType sourceType,
    String url,
    Map<String, String>? authHeaders,
  ) async {
    if (sourceType != SourceType.netease ||
        authHeaders == null ||
        !SourceHttpPolicy.canAttachNeteaseMediaCredentials(url)) {
      return PlaybackUrlResolution(url: url);
    }

    try {
      final redirectResolver =
          _neteasePlaybackRedirectResolver ?? _resolveNeteasePlaybackRedirects;
      return await redirectResolver(url, authHeaders);
    } catch (_) {
      logWarning(
        'Failed to preflight Netease playback redirects; stripping credentials for playback handoff',
      );
      return PlaybackUrlResolution(url: url, includeCredentials: false);
    }
  }

  Future<PlaybackUrlResolution> _resolveNeteasePlaybackRedirects(
    String url,
    Map<String, String> authHeaders,
  ) async {
    final initialUri = Uri.tryParse(url);
    if (initialUri == null) {
      return PlaybackUrlResolution(url: url, includeCredentials: false);
    }

    final client = HttpClient()
      ..connectionTimeout = AppConstants.networkConnectTimeout;
    try {
      var currentUri = initialUri;
      for (var redirectCount = 0;
          redirectCount <= _maxPlaybackRedirects;
          redirectCount++) {
        final response = await _probeNeteasePlaybackUrl(
          client,
          currentUri,
          authHeaders,
        );
        final statusCode = response.statusCode;
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();

        if (!_isRedirectStatus(statusCode)) {
          return PlaybackUrlResolution(url: currentUri.toString());
        }
        if (location == null || location.isEmpty) {
          return PlaybackUrlResolution(
            url: currentUri.toString(),
            includeCredentials: false,
          );
        }
        if (redirectCount == _maxPlaybackRedirects) {
          return PlaybackUrlResolution(
            url: currentUri.toString(),
            includeCredentials: false,
          );
        }

        final nextUri = currentUri.resolve(location);
        if (!SourceHttpPolicy.canAttachNeteaseMediaCredentials(
          nextUri.toString(),
        )) {
          return PlaybackUrlResolution(
            url: nextUri.toString(),
            includeCredentials: false,
          );
        }
        currentUri = nextUri;
      }
    } finally {
      client.close(force: true);
    }

    return PlaybackUrlResolution(url: url, includeCredentials: false);
  }

  Future<HttpClientResponse> _probeNeteasePlaybackUrl(
    HttpClient client,
    Uri uri,
    Map<String, String> authHeaders,
  ) async {
    final headResponse = await _sendNeteasePlaybackProbe(
      client,
      method: 'HEAD',
      uri: uri,
      authHeaders: authHeaders,
    );
    if (headResponse.statusCode != HttpStatus.methodNotAllowed) {
      return headResponse;
    }

    await headResponse.drain<void>();
    return _sendNeteasePlaybackProbe(
      client,
      method: 'GET',
      uri: uri,
      authHeaders: authHeaders,
      rangeProbe: true,
    );
  }

  Future<HttpClientResponse> _sendNeteasePlaybackProbe(
    HttpClient client, {
    required String method,
    required Uri uri,
    required Map<String, String> authHeaders,
    bool rangeProbe = false,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    SourceHttpPolicy.mediaHeaders(
      SourceType.netease,
      authHeaders: authHeaders,
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
  static const String defaultPlaybackUserAgent =
      SourceHttpPolicy.mediaUserAgent;
}
