import 'dart:io';

import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_http_policy.dart';
import '../media/media_handoff.dart' hide NeteasePlaybackRedirectResolver;
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
  /// directly to byte requests. Use [playbackNetworkRequest()] for playback
  /// byte requests, `MediaHandoff` for download byte requests, and the image
  /// header helpers for image requests so source media credential rules are
  /// enforced.
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

class DefaultSourceAuthContext implements SourceAuthContext {
  DefaultSourceAuthContext({
    required SourceSettingsLoader settingsLoader,
    required SourceAccountAuthLoader accountAuthLoader,
    MediaHandoff? mediaHandoff,
    PlaybackUrlResolver? playbackUrlResolver,
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  })  : _settingsLoader = settingsLoader,
        _accountAuthLoader = accountAuthLoader,
        _mediaHandoff = mediaHandoff ??
            _createMediaHandoff(
              playbackUrlResolver: playbackUrlResolver,
              neteasePlaybackRedirectResolver: neteasePlaybackRedirectResolver,
            );

  factory DefaultSourceAuthContext.fromRepositories({
    required SettingsRepository settingsRepository,
    required SourceAccountAuthLoader accountAuthLoader,
    MediaHandoff? mediaHandoff,
    PlaybackUrlResolver? playbackUrlResolver,
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  }) {
    return DefaultSourceAuthContext(
      settingsLoader: settingsRepository.get,
      accountAuthLoader: accountAuthLoader,
      mediaHandoff: mediaHandoff,
      playbackUrlResolver: playbackUrlResolver,
      neteasePlaybackRedirectResolver: neteasePlaybackRedirectResolver,
    );
  }

  final SourceSettingsLoader _settingsLoader;
  final SourceAccountAuthLoader _accountAuthLoader;
  final MediaHandoff _mediaHandoff;

  /// Loads source-account headers for source adapter playback purposes.
  ///
  /// The returned raw credentials are for source adapters, stream resolution,
  /// and track detail calls after `Settings.useAuthForPlay()` allows them. They
  /// are not media request headers and must not be attached directly to byte
  /// requests. Use [playbackNetworkRequest()] for playback byte requests,
  /// `MediaHandoff` for download byte requests, and the image header helpers
  /// for image requests so `SourceHttpPolicy` can enforce credential allowlists.
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
    final prepared = await _mediaHandoff.preparePlayback(
      MediaHandoffRequest(
        sourceType: track.sourceType,
        url: Uri.parse(url),
        streamResolutionAuth: authHeaders,
      ),
    );
    return PlaybackNetworkRequest(
      url: prepared.url.toString(),
      headers: prepared.headers,
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

  static const String defaultPlaybackUserAgent =
      SourceHttpPolicy.mediaUserAgent;
}

MediaHandoff _createMediaHandoff({
  PlaybackUrlResolver? playbackUrlResolver,
  NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
}) {
  if (playbackUrlResolver != null) {
    return _PlaybackUrlResolverMediaHandoff(playbackUrlResolver);
  }
  return DefaultMediaHandoff(
    neteasePlaybackRedirectResolver: neteasePlaybackRedirectResolver == null
        ? null
        : (url, streamResolutionAuth) async {
            final resolution = await neteasePlaybackRedirectResolver(
              url.toString(),
              streamResolutionAuth,
            );
            return MediaPlaybackRedirectResolution(
              url: Uri.parse(resolution.url),
              includeCredentials: resolution.includeCredentials,
            );
          },
  );
}

class _PlaybackUrlResolverMediaHandoff implements MediaHandoff {
  _PlaybackUrlResolverMediaHandoff(this._resolver);

  final PlaybackUrlResolver _resolver;

  @override
  Future<MediaHandoffResult> preparePlayback(
    MediaHandoffRequest request,
  ) async {
    final resolution = await _resolver(
      request.sourceType,
      request.url.toString(),
      request.streamResolutionAuth,
    );
    final resolvedUrl = Uri.parse(resolution.url);
    final headers = SourceHttpPolicy.mediaHeaders(
      request.sourceType,
      authHeaders: request.streamResolutionAuth,
      requestUrl: resolvedUrl.toString(),
      includeCredentials: resolution.includeCredentials,
    );
    return MediaHandoffResult(
      url: resolvedUrl,
      headers: headers,
      credentialsIncluded: headers.keys.any(
        (key) => key.toLowerCase() == HttpHeaders.cookieHeader,
      ),
    );
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    throw UnsupportedError(
      'PlaybackUrlResolver compatibility adapter supports playback only',
    );
  }
}
