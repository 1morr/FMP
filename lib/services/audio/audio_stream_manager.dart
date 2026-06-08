import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../core/utils/auth_headers_utils.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_http_policy.dart';
import '../account/bilibili_account_service.dart';
import '../account/netease_account_service.dart';
import '../account/youtube_account_service.dart';
import 'stream_resolution_service.dart';

abstract class PlaybackRequestStreamAccess {
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  });

  Future<PlaybackSelection?> selectFallbackPlayback(
    Track track, {
    String? failedUrl,
  });

  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  });

  Future<Map<String, String>?> getPlaybackHeaders(
    Track track, {
    String? requestUrl,
  });

  Future<PlaybackNetworkRequest> prepareNetworkPlayback(
    Track track,
    String url,
  );

  Future<void> prefetchTrack(Track track);
}

typedef PlaybackUrlResolver = Future<PlaybackUrlResolution> Function(
  SourceType sourceType,
  String url,
  Map<String, String>? authHeaders,
);

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

class PlaybackSelection {
  const PlaybackSelection({
    required this.track,
    required this.url,
    required this.localPath,
    required this.headers,
    required this.streamResult,
  });

  final Track track;
  final String url;
  final String? localPath;
  final Map<String, String>? headers;
  final AudioStreamResult? streamResult;
}

class AudioStreamManager with Logging implements PlaybackRequestStreamAccess {
  AudioStreamManager({
    required StreamResolutionService streamResolutionService,
    SettingsRepository? settingsRepository,
    BilibiliAccountService? bilibiliAccountService,
    YouTubeAccountService? youtubeAccountService,
    NeteaseAccountService? neteaseAccountService,
    PlaybackUrlResolver? playbackUrlResolver,
  })  : _settingsRepository = settingsRepository,
        _streamResolutionService = streamResolutionService,
        _playbackUrlResolver = playbackUrlResolver,
        _getAuthHeaders = ((sourceType) => buildAuthHeaders(
              sourceType,
              bilibiliAccountService: bilibiliAccountService,
              youtubeAccountService: youtubeAccountService,
              neteaseAccountService: neteaseAccountService,
            ));

  final StreamResolutionService _streamResolutionService;
  final SettingsRepository? _settingsRepository;
  final PlaybackUrlResolver? _playbackUrlResolver;
  final Future<Map<String, String>?> Function(SourceType sourceType)
      _getAuthHeaders;
  Stream<DownloadPathsChangedEvent> get downloadPathsChangedStream =>
      _streamResolutionService.downloadPathsChangedStream;

  void dispose() {}

  @override
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    final result = await _streamResolutionService.resolvePrimary(
      track,
      purpose: StreamResolutionPurpose.playback,
      persist: persist,
    );
    return switch (result) {
      LocalStreamResolution(:final track, :final path) => (track, path, null),
      RemoteStreamResolution(:final track, :final stream) => (
          track,
          null,
          stream
        ),
    };
  }

  @override
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  }) async {
    final (trackWithUrl, localPath, streamResult) =
        await ensureAudioStream(track, persist: persist);
    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw Exception('No audio URL available for: ${track.title}');
    }

    final networkRequest = localPath == null
        ? await prepareNetworkPlayback(trackWithUrl, url)
        : null;
    return PlaybackSelection(
      track: trackWithUrl,
      url: networkRequest?.url ?? url,
      localPath: localPath,
      headers: networkRequest?.headers,
      streamResult: streamResult,
    );
  }

  Future<AudioStreamResult?> getAlternativeAudioStream(
    Track track, {
    String? failedUrl,
  }) async {
    final result = await _streamResolutionService.resolveFallback(
      track,
      purpose: StreamResolutionPurpose.playback,
      failedUrl: failedUrl ?? '',
    );
    return result?.stream;
  }

  @override
  Future<PlaybackSelection?> selectFallbackPlayback(
    Track track, {
    String? failedUrl,
  }) async {
    final fallback = await _streamResolutionService.resolveFallback(
      track,
      purpose: StreamResolutionPurpose.playback,
      failedUrl: failedUrl ?? '',
    );
    if (fallback == null) return null;

    final networkRequest =
        await prepareNetworkPlayback(fallback.track, fallback.stream.url);
    return PlaybackSelection(
      track: fallback.track,
      url: networkRequest.url,
      localPath: null,
      headers: networkRequest.headers,
      streamResult: fallback.stream,
    );
  }

  Future<(Track, String?)> ensureAudioUrl(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    final (trackWithStream, localPath, _) = await ensureAudioStream(
      track,
      retryCount: retryCount,
      persist: persist,
    );
    return (trackWithStream, localPath);
  }

  @override
  Future<Map<String, String>?> getPlaybackHeaders(
    Track track, {
    String? requestUrl,
  }) async {
    final authHeaders = await _getPlaybackAuthHeaders(track);
    return SourceHttpPolicy.mediaHeaders(
      track.sourceType,
      authHeaders: authHeaders,
      requestUrl: requestUrl ?? track.audioUrl,
    );
  }

  @override
  Future<PlaybackNetworkRequest> prepareNetworkPlayback(
    Track track,
    String url,
  ) async {
    final authHeaders = await _getPlaybackAuthHeaders(track);
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
  Future<void> prefetchTrack(Track track) async {
    return _streamResolutionService.prefetchTrack(track);
  }

  bool _defaultUseAuthForPlay(SourceType sourceType) {
    return switch (sourceType) {
      SourceType.bilibili => false,
      SourceType.youtube => false,
      SourceType.netease => true,
    };
  }

  Future<Map<String, String>?> _getPlaybackAuthHeaders(Track track) async {
    final settingsRepository = _settingsRepository;
    final useAuthForPlay = settingsRepository == null
        ? _defaultUseAuthForPlay(track.sourceType)
        : (await settingsRepository.get()).useAuthForPlay(track.sourceType);
    return useAuthForPlay ? _getAuthHeaders(track.sourceType) : null;
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
      return await _resolveNeteasePlaybackRedirects(url, authHeaders);
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
