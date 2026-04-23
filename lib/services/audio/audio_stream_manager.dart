import '../../core/extensions/track_extensions.dart';
import '../../core/logger.dart';
import '../../core/utils/auth_headers_utils.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/track_repository.dart';
import '../../data/sources/base_source.dart';
import '../../data/sources/source_provider.dart';
import '../account/bilibili_account_service.dart';
import '../account/netease_account_service.dart';
import '../account/youtube_account_service.dart';
import 'internal/audio_stream_delegate.dart';

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

  Future<Map<String, String>?> getPlaybackHeaders(Track track);

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

class AudioStreamManager with Logging implements PlaybackRequestStreamAccess {
  AudioStreamManager({
    AudioStreamDelegate? delegate,
    TrackRepository? trackRepository,
    SettingsRepository? settingsRepository,
    SourceManager? sourceManager,
    BilibiliAccountService? bilibiliAccountService,
    YouTubeAccountService? youtubeAccountService,
    NeteaseAccountService? neteaseAccountService,
  }) : _neteaseAccountService = neteaseAccountService {
    _delegate = delegate ??
        AudioStreamDelegate(
          trackRepository: trackRepository!,
          settingsRepository: settingsRepository!,
          sourceManager: sourceManager!,
          getAuthHeaders: (sourceType) => buildAuthHeaders(
            sourceType,
            bilibiliAccountService: bilibiliAccountService,
            youtubeAccountService: youtubeAccountService,
            neteaseAccountService: neteaseAccountService,
          ),
        );
  }

  late final AudioStreamDelegate _delegate;
  final NeteaseAccountService? _neteaseAccountService;
  final Set<int> _fetchingUrlTrackIds = {};

  @override
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) {
    return _delegate.ensureAudioStream(
      track,
      retryCount: retryCount,
      persist: persist,
    );
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

    return PlaybackSelection(
      track: trackWithUrl,
      url: url,
      localPath: localPath,
      headers: localPath == null ? await getPlaybackHeaders(trackWithUrl) : null,
      streamResult: streamResult,
    );
  }

  Future<AudioStreamResult?> getAlternativeAudioStream(
    Track track, {
    String? failedUrl,
  }) {
    return _delegate.getAlternativeAudioStream(track, failedUrl: failedUrl);
  }

  @override
  Future<PlaybackSelection?> selectFallbackPlayback(
    Track track, {
    String? failedUrl,
  }) async {
    final fallbackResult = await getAlternativeAudioStream(
      track,
      failedUrl: failedUrl,
    );
    if (fallbackResult == null) return null;

    track.audioUrl = fallbackResult.url;
    track.audioUrlExpiry = DateTime.now().add(
      fallbackResult.expiry ?? const Duration(hours: 1),
    );

    return PlaybackSelection(
      track: track,
      url: fallbackResult.url,
      localPath: null,
      headers: await getPlaybackHeaders(track),
      streamResult: fallbackResult,
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
  Future<Map<String, String>?> getPlaybackHeaders(Track track) async {
    switch (track.sourceType) {
      case SourceType.bilibili:
        return {
          'Referer': 'https://www.bilibili.com',
          'User-Agent': defaultPlaybackUserAgent,
        };
      case SourceType.youtube:
        return {
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
          'User-Agent': defaultPlaybackUserAgent,
        };
      case SourceType.netease:
        return await _neteaseAccountService?.getAuthHeaders() ??
            {
              'Origin': 'https://music.163.com',
              'Referer': 'https://music.163.com/',
              'User-Agent': defaultPlaybackUserAgent,
            };
    }
  }

  @override
  Future<void> prefetchTrack(Track track) async {
    if (track.hasLocalAudio ||
        track.hasValidAudioUrl ||
        _fetchingUrlTrackIds.contains(track.id)) {
      return;
    }

    _fetchingUrlTrackIds.add(track.id);
    try {
      await ensureAudioUrl(track, persist: false);
    } catch (error, stackTrace) {
      logError(
        'Failed to prefetch audio URL for ${track.sourceType.name}:${track.sourceId}',
        error,
        stackTrace,
      );
    } finally {
      _fetchingUrlTrackIds.remove(track.id);
    }
  }

  static const String defaultPlaybackUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}

