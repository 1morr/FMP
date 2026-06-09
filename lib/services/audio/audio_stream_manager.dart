import '../../data/models/track.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_http_policy.dart';
import '../account/source_auth_context.dart';
import 'stream_resolution_service.dart';

export '../account/source_auth_context.dart'
    show PlaybackNetworkRequest, PlaybackUrlResolution, PlaybackUrlResolver;

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

class AudioStreamManager implements PlaybackRequestStreamAccess {
  AudioStreamManager({
    required StreamResolutionService streamResolutionService,
    required SourceAuthContext sourceAuthContext,
  })  : _streamResolutionService = streamResolutionService,
        _sourceAuthContext = sourceAuthContext;

  final StreamResolutionService _streamResolutionService;
  final SourceAuthContext _sourceAuthContext;
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
    final prepared = await _sourceAuthContext.playbackNetworkRequest(
      track,
      requestUrl ?? track.audioUrl ?? '',
    );
    return prepared.headers;
  }

  @override
  Future<PlaybackNetworkRequest> prepareNetworkPlayback(
    Track track,
    String url,
  ) {
    return _sourceAuthContext.playbackNetworkRequest(track, url);
  }

  @override
  Future<void> prefetchTrack(Track track) async {
    return _streamResolutionService.prefetchTrack(track);
  }

  static const String defaultPlaybackUserAgent =
      SourceHttpPolicy.mediaUserAgent;
}
