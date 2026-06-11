import '../../data/models/track.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_http_policy.dart';
import '../account/source_auth_context.dart';
import 'playback_media.dart';
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

  Future<void> prefetchTrack(Track track);
}

class PlaybackSelection {
  const PlaybackSelection({
    required this.media,
    required this.streamResult,
  });

  final PreparedPlaybackMedia media;
  final AudioStreamResult? streamResult;
}

class AudioStreamManager implements PlaybackRequestStreamAccess {
  AudioStreamManager({
    required StreamResolutionService streamResolutionService,
    required PlaybackMediaRequestContext sourceAuthContext,
  })  : _streamResolutionService = streamResolutionService,
        _sourceAuthContext = sourceAuthContext;

  final StreamResolutionService _streamResolutionService;
  final PlaybackMediaRequestContext _sourceAuthContext;
  Stream<DownloadPathsChangedEvent> get downloadPathsChangedStream =>
      _streamResolutionService.downloadPathsChangedStream;

  void dispose() {}

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

    final media = localPath == null
        ? await prepareNetworkPlayback(trackWithUrl, url)
        : LocalPlaybackMedia(path: localPath, track: trackWithUrl);
    return PlaybackSelection(
      media: media,
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

    final media =
        await prepareNetworkPlayback(fallback.track, fallback.stream.url);
    return PlaybackSelection(
      media: media,
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

  Future<RemotePlaybackMedia> prepareNetworkPlayback(
    Track track,
    String url,
  ) async {
    final prepared = await _sourceAuthContext.playbackNetworkRequest(
      track,
      url,
    );
    return RemotePlaybackMedia(
      url: Uri.parse(prepared.url),
      headers: prepared.headers,
      track: track,
    );
  }

  @override
  Future<void> prefetchTrack(Track track) async {
    return _streamResolutionService.prefetchTrack(track);
  }

  static const String defaultPlaybackUserAgent =
      SourceHttpPolicy.mediaUserAgent;
}
