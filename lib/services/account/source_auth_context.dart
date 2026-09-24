import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/media/media_handoff.dart';
import 'package:fmp/services/account/account_service.dart';

typedef SourceSettingsLoader = Future<Settings> Function();

typedef PlaybackUrlResolver =
    Future<PlaybackUrlResolution> Function(
      String sourceType,
      String url,
      Map<String, String>? authHeaders,
    );

abstract interface class SourceAccountAuthLoader {
  Future<Map<String, String>?> load(String sourceType);
}

/// 依音源 id 找到它的帳號服務，由服務自己組 headers。
class AccountServiceAuthLoader implements SourceAccountAuthLoader {
  AccountServiceAuthLoader([
    Iterable<AccountService> accountServices = const [],
  ]) : _servicesBySource = {
         for (final service in accountServices) service.platform: service,
       };

  final Map<String, AccountService> _servicesBySource;

  /// 沒有帳號服務的音源拿不到任何憑證。這裡若 fallback 到別的服務，等於把
  /// 那個平台的 Cookie 送給一個我們不認識的主機。
  @override
  Future<Map<String, String>?> load(String sourceType) async =>
      _servicesBySource[sourceType]?.getAuthHeaders();
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
  const PlaybackNetworkRequest({required this.url, required this.headers});

  final String url;
  final Map<String, String>? headers;
}

class DefaultSourceAuthContext implements SourceAuthContext {
  DefaultSourceAuthContext({
    required SourceSettingsLoader settingsLoader,
    required SourceAccountAuthLoader accountAuthLoader,
    MediaHandoff? mediaHandoff,
    PlaybackUrlResolver? playbackUrlResolver,
  }) : _settingsLoader = settingsLoader,
       _accountAuthLoader = accountAuthLoader,
       _mediaHandoff = mediaHandoff ?? _createMediaHandoff(playbackUrlResolver);

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
