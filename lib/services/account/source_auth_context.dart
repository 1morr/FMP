import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_http_policy.dart';
import '../media/media_handoff.dart';
import 'bilibili_account_service.dart';
import 'netease_account_service.dart';
import 'youtube_account_service.dart';

typedef SourceSettingsLoader = Future<Settings> Function();

typedef PlaybackUrlResolver = Future<PlaybackUrlResolution> Function(
  String sourceType,
  String url,
  Map<String, String>? authHeaders,
);

abstract interface class SourceAccountAuthLoader {
  Future<Map<String, String>?> load(String sourceType);
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
  Future<Map<String, String>?> load(String sourceType) async {
    switch (sourceType) {
      case SourceIds.bilibili:
        final cookies = await _bilibiliAccountService?.getAuthCookieString();
        if (cookies == null) return null;
        return {'Cookie': cookies};
      case SourceIds.youtube:
        final youtubeAccountService = _youtubeAccountService;
        if (youtubeAccountService == null) return null;
        return youtubeAccountService.getAuthHeaders();
      case SourceIds.netease:
        final cookies = await _neteaseAccountService?.getAuthCookieString();
        if (cookies == null) return null;
        return SourceHttpPolicy.neteaseAuthHeaders(cookies);
      default:
        // 認不得的音源拿不到任何憑證。這裡若 fallback 到 B 站，等於把
        // SESSDATA 送給一個我們不認識的主機。
        return null;
    }
  }
}

abstract interface class SourcePlaybackAuthContext {
  /// Returns source-account headers for source adapter playback purposes.
  ///
  /// These raw headers are for source adapters, stream resolution, and track
  /// detail calls. They are not media request headers and must not be attached
  /// directly to byte requests.
  Future<Map<String, String>?> authForPlay(String sourceType);
}

abstract interface class PlaybackMediaRequestContext {
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  );
}

abstract interface class DownloadSourceAuthContext
    implements SourcePlaybackAuthContext {
  Map<String, String> imageHeaders(String sourceType);

  Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  });
}

abstract interface class PlaylistAuthContext {
  Future<Map<String, String>?> playlistImportAuth(
    String sourceType, {
    required bool useAuth,
  });

  Future<Map<String, String>?> playlistRefreshAuth(
    String sourceType, {
    required bool useAuthForRefresh,
  });
}

abstract interface class SourceAuthContext
    implements
        SourcePlaybackAuthContext,
        PlaybackMediaRequestContext,
        DownloadSourceAuthContext,
        PlaylistAuthContext {}

class PlaybackUrlResolution {
  const PlaybackUrlResolution({required this.url});

  final String url;
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
  })  : _settingsLoader = settingsLoader,
        _accountAuthLoader = accountAuthLoader,
        _mediaHandoff =
            mediaHandoff ?? _createMediaHandoff(playbackUrlResolver);

  factory DefaultSourceAuthContext.fromRepositories({
    required SettingsRepository settingsRepository,
    required SourceAccountAuthLoader accountAuthLoader,
    MediaHandoff? mediaHandoff,
    PlaybackUrlResolver? playbackUrlResolver,
  }) {
    return DefaultSourceAuthContext(
      settingsLoader: settingsRepository.get,
      accountAuthLoader: accountAuthLoader,
      mediaHandoff: mediaHandoff,
      playbackUrlResolver: playbackUrlResolver,
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
  Future<Map<String, String>?> authForPlay(String sourceType) async {
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
  Map<String, String> imageHeaders(String sourceType) {
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
    String sourceType, {
    required bool useAuth,
  }) async {
    if (!useAuth) return null;
    return _accountAuthLoader.load(sourceType);
  }

  @override
  Future<Map<String, String>?> playlistRefreshAuth(
    String sourceType, {
    required bool useAuthForRefresh,
  }) async {
    if (!useAuthForRefresh) return null;
    return _accountAuthLoader.load(sourceType);
  }

  static const String defaultPlaybackUserAgent =
      SourceHttpPolicy.mediaUserAgent;
}

MediaHandoff _createMediaHandoff(PlaybackUrlResolver? playbackUrlResolver) {
  if (playbackUrlResolver != null) {
    return _PlaybackUrlResolverMediaHandoff(playbackUrlResolver);
  }
  return const DefaultMediaHandoff();
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
    return MediaHandoffResult(
      url: Uri.parse(resolution.url),
      headers: SourceHttpPolicy.mediaHeaders(request.sourceType),
    );
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    throw UnsupportedError(
      'PlaybackUrlResolver compatibility adapter supports playback only',
    );
  }
}
