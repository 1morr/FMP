import 'dart:io';

import '../../core/constants/app_constants.dart';
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
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  });

  Future<Map<String, String>?> getPlaybackHeaders(Track track);

  Future<void> prefetchTrack(Track track);
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
    void Function(Track updatedTrack)? replaceTrack,
  })  : _trackRepository = trackRepository,
        _settingsRepository = settingsRepository,
        _sourceManager = sourceManager,
        _bilibiliAccountService = bilibiliAccountService,
        _youtubeAccountService = youtubeAccountService,
        _neteaseAccountService = neteaseAccountService {
    _queueTrackUpdater = replaceTrack;
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
          updateQueueTrack: (updatedTrack) =>
              _queueTrackUpdater?.call(updatedTrack),
        );
  }

  late final AudioStreamDelegate _delegate;
  final TrackRepository? _trackRepository;
  final SettingsRepository? _settingsRepository;
  final SourceManager? _sourceManager;
  final BilibiliAccountService? _bilibiliAccountService;
  final YouTubeAccountService? _youtubeAccountService;
  final NeteaseAccountService? _neteaseAccountService;
  final Set<int> _fetchingUrlTrackIds = {};
  void Function(Track updatedTrack)? _queueTrackUpdater;

  void attachQueueTrackUpdater(void Function(Track updatedTrack) replaceTrack) {
    _queueTrackUpdater = replaceTrack;
  }

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

  Future<AudioStreamResult?> getAlternativeAudioStream(
    Track track, {
    String? failedUrl,
  }) {
    return _delegate.getAlternativeAudioStream(track, failedUrl: failedUrl);
  }

  Future<(Track, String?)> ensureAudioUrl(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    final localFileState = _inspectLocalFiles(track);
    if (localFileState.localPath != null) {
      if (localFileState.invalidPaths.isNotEmpty && persist) {
        _clearInvalidPaths(track, localFileState.invalidPaths);
        await _requireTrackRepository().save(track);
        _queueTrackUpdater?.call(track);
      }
      return (track, localFileState.localPath);
    }

    if (localFileState.invalidPaths.isNotEmpty && persist) {
      track.clearAllDownloadPaths();
      await _requireTrackRepository().save(track);
      _queueTrackUpdater?.call(track);
    }

    if (track.hasValidAudioUrl) {
      return (track, null);
    }

    final source = _requireSourceManager().getSource(track.sourceType);
    if (source == null) {
      throw Exception('No source available for ${track.sourceType}');
    }

    try {
      Map<String, String>? authHeaders;
      final settings = await _requireSettingsRepository().get();
      if (settings.useAuthForPlay(track.sourceType)) {
        authHeaders = await buildAuthHeaders(
          track.sourceType,
          bilibiliAccountService: _bilibiliAccountService,
          youtubeAccountService: _youtubeAccountService,
          neteaseAccountService: _neteaseAccountService,
        );
      }

      final refreshedTrack = await source.refreshAudioUrl(
        track,
        authHeaders: authHeaders,
      );

      if (persist) {
        final freshTrack = await _requireTrackRepository().getById(track.id);
        if (freshTrack != null) {
          freshTrack.audioUrl = refreshedTrack.audioUrl;
          freshTrack.audioUrlExpiry = refreshedTrack.audioUrlExpiry;
          await _requireTrackRepository().save(freshTrack);
          refreshedTrack.playlistInfo = freshTrack.playlistInfo;
        } else {
          await _requireTrackRepository().save(refreshedTrack);
        }
      }

      _queueTrackUpdater?.call(refreshedTrack);
      return (refreshedTrack, null);
    } catch (_) {
      if (retryCount < 1) {
        await Future.delayed(AppConstants.queueSaveRetryDelay);
        return ensureAudioUrl(
          track,
          retryCount: retryCount + 1,
          persist: persist,
        );
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, String>?> getPlaybackHeaders(Track track) async {
    switch (track.sourceType) {
      case SourceType.bilibili:
        return {
          'Referer': 'https://www.bilibili.com',
          'User-Agent': _defaultPlaybackUserAgent,
        };
      case SourceType.youtube:
        return {
          'Origin': 'https://www.youtube.com',
          'Referer': 'https://www.youtube.com/',
          'User-Agent': _defaultPlaybackUserAgent,
        };
      case SourceType.netease:
        return await _neteaseAccountService?.getAuthHeaders() ??
            {
              'Origin': 'https://music.163.com',
              'Referer': 'https://music.163.com/',
              'User-Agent': _defaultPlaybackUserAgent,
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
      await ensureAudioUrl(track);
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

  _LocalFileState _inspectLocalFiles(Track track) {
    String? localPath;
    final invalidPaths = <String>[];

    for (final path in track.allDownloadPaths) {
      try {
        if (File(path).existsSync()) {
          localPath ??= path;
          continue;
        }
      } catch (_) {
        // Treat unreadable paths as invalid and clear them below.
      }
      invalidPaths.add(path);
    }

    return _LocalFileState(localPath: localPath, invalidPaths: invalidPaths);
  }

  void _clearInvalidPaths(Track track, List<String> invalidPaths) {
    track.playlistInfo = track.playlistInfo
        .map((info) => PlaylistDownloadInfo()
          ..playlistId = info.playlistId
          ..playlistName = info.playlistName
          ..downloadPath =
              invalidPaths.contains(info.downloadPath) ? '' : info.downloadPath)
        .toList();
  }

  TrackRepository _requireTrackRepository() =>
      _trackRepository ?? (throw StateError('TrackRepository is required'));

  SettingsRepository _requireSettingsRepository() =>
      _settingsRepository ??
      (throw StateError('SettingsRepository is required'));

  SourceManager _requireSourceManager() =>
      _sourceManager ?? (throw StateError('SourceManager is required'));

  static const String _defaultPlaybackUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}

class _LocalFileState {
  const _LocalFileState({required this.localPath, required this.invalidPaths});

  final String? localPath;
  final List<String> invalidPaths;
}
