import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/playback_request_executor.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:isar/isar.dart';

import 'dart:async';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackRequestExecutor Task 1 regression', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;
    late _FakeSourceManager sourceManager;
    late FakeAudioService audioService;
    late QueueManager queueManager;
    late AudioController controller;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'playback_request_executor_',
      );
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'playback_request_executor_test',
      );

      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
      sourceManager = _FakeSourceManager();
      final queuePersistenceManager = QueuePersistenceManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
      );
      final audioStreamManager = AudioStreamManager(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
      );
      queueManager = QueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: queuePersistenceManager,
      );
      audioService = FakeAudioService();
      controller = AudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        audioHandler: FmpAudioHandler(),
        windowsSmtcHandler: WindowsSmtcHandler(),
        settingsRepository: settingsRepository,
      );

      await controller.initialize();
    });

    tearDown(() async {
      controller.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });


    test('executeQueueRestore uses playback handoff and seek playback state',
        () async {
      final restoreTrack = _track('queue-restore', title: 'Queue Restore');
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {restoreTrack.sourceId: restoreTrack},
      );
      final audioService = FakeAudioService();
      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (_) => false,
      );

      final result = await executor.executeQueueRestore(
        requestId: 7,
        track: restoreTrack,
        position: const Duration(seconds: 35),
        shouldResume: true,
      );

      expect(result, isNotNull);
      expect(result!.track.sourceId, 'queue-restore');
      expect(result.attemptedUrl, 'https://example.com/queue-restore.m4a');
      expect(audioService.playUrlCalls, isEmpty);
      expect(audioService.setUrlCalls.single.url,
          'https://example.com/queue-restore.m4a');
      expect(audioService.seekCalls, [const Duration(seconds: 35)]);
      expect(audioService.isPlaying, isTrue);
      expect(streamManager.ensureAudioStreamRequests, ['queue-restore']);
      expect(streamManager.headerRequests, ['queue-restore']);
    });

    test('executeQueueRestore skips seek and play when restore state is idle',
        () async {
      final restoreTrack = _track('queue-idle', title: 'Queue Idle');
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {restoreTrack.sourceId: restoreTrack},
      );
      final audioService = FakeAudioService();
      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (_) => false,
      );

      final result = await executor.executeQueueRestore(
        requestId: 8,
        track: restoreTrack,
        position: Duration.zero,
        shouldResume: false,
      );

      expect(result, isNotNull);
      expect(audioService.playUrlCalls, isEmpty);
      expect(audioService.setUrlCalls.single.url,
          'https://example.com/queue-idle.m4a');
      expect(audioService.seekCalls, isEmpty);
      expect(audioService.isPlaying, isFalse);
    });

    test('execute uses stream manager selection headers directly', () async {
      final track = _track('headers-owned', title: 'Headers Owned');
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {track.sourceId: track},
      );
      streamManager.onGetPlaybackHeaders = (_) async => {
            'X-Test-Header': 'owned-by-manager',
          };
      final audioService = FakeAudioService();

      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (_) => false,
      );

      final result = await executor.execute(
        requestId: 1,
        track: track,
        persist: true,
        prefetchNext: false,
      );

      expect(result, isNotNull);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/headers-owned.m4a');
      expect(audioService.playUrlCalls.single.headers, {
        'X-Test-Header': 'owned-by-manager',
      });
      expect(streamManager.selectionRequests, ['headers-owned']);
      expect(streamManager.headerRequests, ['headers-owned']);
    });

    test(
        'execute retries with manager-owned fallback selection regardless of source type',
        () async {
      final track = _track(
        'source-agnostic-fallback',
        title: 'Source Agnostic Fallback',
      )..sourceType = SourceType.bilibili;
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {track.sourceId: track},
      );
      streamManager.onGetPlaybackHeaders = (_) async => {
            'X-Primary-Header': 'primary',
          };
      streamManager.onSelectFallbackPlayback = (track, failedUrl) async {
        return PlaybackSelection(
          track: track
            ..audioUrl = 'https://example.com/${track.sourceId}-fallback.m3u8',
          url: 'https://example.com/${track.sourceId}-fallback.m3u8',
          localPath: null,
          headers: {
            'X-Fallback-Header': 'fallback',
          },
          streamResult: AudioStreamResult(
            url: 'https://example.com/${track.sourceId}-fallback.m3u8',
            container: 'm3u8',
            codec: 'aac',
            streamType: StreamType.muxed,
          ),
        );
      };
      final audioService = FakeAudioService();
      audioService.enqueuePlayUrlError(Exception('audio-only proxy failed'));

      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (_) => false,
      );

      final result = await executor.execute(
        requestId: 1,
        track: track,
        persist: true,
        prefetchNext: false,
      );

      expect(result, isNotNull);
      expect(result!.attemptedUrl,
          'https://example.com/source-agnostic-fallback-fallback.m3u8');
      expect(result.streamResult?.streamType, StreamType.muxed);
      expect(audioService.playUrlCalls.map((call) => call.url).toList(), [
        'https://example.com/source-agnostic-fallback.m4a',
        'https://example.com/source-agnostic-fallback-fallback.m3u8',
      ]);
      expect(audioService.playUrlCalls.first.headers, {
        'X-Primary-Header': 'primary',
      });
      expect(audioService.playUrlCalls.last.headers, {
        'X-Fallback-Header': 'fallback',
      });
      expect(streamManager.selectionRequests, ['source-agnostic-fallback']);
      expect(streamManager.fallbackSelectionTracks, ['source-agnostic-fallback']);
      expect(streamManager.fallbackSelectionFailedUrls,
          ['https://example.com/source-agnostic-fallback.m4a']);
    });

    test('execute rethrows original error when manager has no fallback', () async {
      final track = _track('no-fallback', title: 'No Fallback')
        ..sourceType = SourceType.bilibili;
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {track.sourceId: track},
      );
      final audioService = FakeAudioService();
      final playbackError = Exception('playback handoff failed');
      audioService.enqueuePlayUrlError(playbackError);

      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (_) => false,
      );

      await expectLater(
        () => executor.execute(
          requestId: 1,
          track: track,
          persist: true,
          prefetchNext: false,
        ),
        throwsA(same(playbackError)),
      );

      expect(streamManager.selectionRequests, ['no-fallback']);
      expect(streamManager.fallbackSelectionTracks, ['no-fallback']);
      expect(streamManager.fallbackSelectionFailedUrls,
          ['https://example.com/no-fallback.m4a']);
      expect(audioService.playUrlCalls.map((call) => call.url).toList(), [
        'https://example.com/no-fallback.m4a',
      ]);
    });

    test(
        'execute preserves original playback error when fallback selection throws',
        () async {
      final track = _track('fallback-throws', title: 'Fallback Throws')
        ..sourceType = SourceType.bilibili;
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {track.sourceId: track},
      );
      final audioService = FakeAudioService();
      final playbackError = Exception('primary playback failed');
      final fallbackError = Exception('fallback selection failed');
      audioService.enqueuePlayUrlError(playbackError);
      streamManager.onSelectFallbackPlayback = (_, __) async {
        throw fallbackError;
      };

      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (_) => false,
      );

      await expectLater(
        () => executor.execute(
          requestId: 1,
          track: track,
          persist: true,
          prefetchNext: false,
        ),
        throwsA(same(playbackError)),
      );

      expect(streamManager.selectionRequests, ['fallback-throws']);
      expect(streamManager.fallbackSelectionTracks, ['fallback-throws']);
      expect(streamManager.fallbackSelectionFailedUrls,
          ['https://example.com/fallback-throws.m4a']);
      expect(audioService.playUrlCalls.map((call) => call.url).toList(), [
        'https://example.com/fallback-throws.m4a',
      ]);
    });

    test('execute aborts after async header resolution when superseded',
        () async {
      final firstTrack = _track('first-netease', title: 'First Netease')
        ..sourceType = SourceType.netease;
      final secondTrack = _track('second-youtube', title: 'Second Youtube');
      final streamManager = _HarnessPlaybackRequestStreamAccess(
        trackBySourceId: {
          firstTrack.sourceId: firstTrack,
          secondTrack.sourceId: secondTrack,
        },
      );
      final audioService = FakeAudioService();
      final secondPlayGate = audioService.enqueuePendingPlayUrl();
      final headerGate = Completer<void>();
      var activeRequestId = 1;
      streamManager.onGetPlaybackHeaders = (track) async {
        if (track.sourceId == firstTrack.sourceId) {
          await headerGate.future;
        }
        return {'Referer': 'https://example.com/${track.sourceId}'};
      };

      final executor = PlaybackRequestExecutor(
        audioService: audioService,
        audioStreamManager: streamManager,
        getNextTrack: () => null,
        isSuperseded: (requestId) => requestId != activeRequestId,
      );

      final firstExecution = executor.execute(
        requestId: 1,
        track: firstTrack,
        persist: true,
        prefetchNext: false,
      );
      await streamManager.waitForHeaderRequest(firstTrack.sourceId);

      activeRequestId = 2;
      final secondExecution = executor.execute(
        requestId: 2,
        track: secondTrack,
        persist: true,
        prefetchNext: false,
      );
      await audioService.waitForPlayUrlCallCount(1);

      headerGate.complete();
      expect(await firstExecution, isNull);

      expect(audioService.playUrlCalls.length, 1);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/second-youtube.m4a');

      secondPlayGate.complete();
      final secondResult = await secondExecution;
      expect(secondResult, isNotNull);
      expect(secondResult!.track.sourceId, 'second-youtube');
      expect(secondResult.attemptedUrl, 'https://example.com/second-youtube.m4a');
      expect(streamManager.ensureAudioStreamRequests,
          ['first-netease', 'second-youtube']);
      expect(streamManager.headerRequests, ['first-netease', 'second-youtube']);
    });

    test(
        'happy path delegates playback handoff and prefetches next track through stream manager',
        () async {
      final queueTracks = [
        _track('first', title: 'First Track'),
        _track('next', title: 'Next Track'),
      ];

      await controller.playAll(queueTracks, startIndex: 0);
      await pumpEventQueue(times: 20);

      expect(audioService.stopCallCount, 1);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/first.m4a');
      expect(controller.state.playingTrack?.sourceId, 'first');
      expect(controller.state.currentTrack?.sourceId, 'first');
      expect(controller.state.isLoading, isFalse);
      expect(sourceManager.audioStreamRequests, ['first', 'next']);
      expect(sourceManager.refreshAudioUrlRequests, isEmpty);
    });

    test('stop failure stays outside playback fallback handling', () async {
      final track = _track('stop-fails', title: 'Stop Fails');
      audioService.enqueueStopError(Exception('stop failed before playback'));

      await controller.playTrack(track);
      await pumpEventQueue(times: 10);

      expect(audioService.stopCallCount, 1);
      expect(audioService.playUrlCalls, isEmpty);
      expect(sourceManager.audioStreamRequests, isEmpty);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.error, contains('stop failed before playback'));
    });

    test('superseded request aborts after async header resolution', () async {
      final firstTrack = _track('first-netease', title: 'First Netease')
        ..sourceType = SourceType.netease;
      final secondTrack = _track('second-youtube', title: 'Second Youtube');
      final headerGate = Completer<void>();
      final blockingAccountService = _BlockingNeteaseAccountService(
        isar,
        headerGate.future,
      );

      controller.dispose();
      audioService = FakeAudioService();
      final secondPlayGate = audioService.enqueuePendingPlayUrl();
      final audioStreamManager = AudioStreamManager(
        trackRepository: TrackRepository(isar),
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
        neteaseAccountService: blockingAccountService,
      );
      queueManager = QueueManager(
        queueRepository: QueueRepository(isar),
        trackRepository: TrackRepository(isar),
        queuePersistenceManager: QueuePersistenceManager(
          queueRepository: QueueRepository(isar),
          trackRepository: TrackRepository(isar),
          settingsRepository: settingsRepository,
        ),
      );
      controller = AudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        audioHandler: FmpAudioHandler(),
        windowsSmtcHandler: WindowsSmtcHandler(),
        settingsRepository: settingsRepository,
      );
      await controller.initialize();

      final firstPlay = controller.playTrack(firstTrack);
      await blockingAccountService.waitForHeaderRequest();

      final secondPlay = controller.playTrack(secondTrack);
      await audioService.waitForPlayUrlCallCount(1);

      headerGate.complete();
      await firstPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 2);
      expect(audioService.playUrlCalls.length, 1);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/second-youtube.m4a');
      expect(controller.state.playingTrack?.sourceId, 'second-youtube');
      expect(controller.state.currentTrack?.sourceId, 'second-youtube');
      expect(controller.state.isLoading, isTrue);

      secondPlayGate.complete();
      await secondPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.playUrlCalls.length, 1);
      expect(controller.state.playingTrack?.sourceId, 'second-youtube');
      expect(controller.state.currentTrack?.sourceId, 'second-youtube');
      expect(controller.state.isLoading, isFalse);
    });
  });
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfig = await _loadPackageConfig();
  final packageDir =
      _resolvePackageDirectory(packageConfig, 'isar_flutter_libs');

  if (Platform.isWindows) {
    return '${packageDir.path}/windows/isar.dll';
  }
  if (Platform.isLinux) {
    return '${packageDir.path}/linux/libisar.so';
  }
  if (Platform.isMacOS) {
    return '${packageDir.path}/macos/libisar.dylib';
  }
  throw UnsupportedError(
      'Unsupported platform for Isar test setup: ${Platform.operatingSystem}');
}

Future<Map<String, dynamic>> _loadPackageConfig() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  return jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
}

Directory _resolvePackageDirectory(
  Map<String, dynamic> packageConfig,
  String packageName,
) {
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages.whereType<Map<String, dynamic>>()) {
    if (package['name'] != packageName) continue;
    final rootUri = package['rootUri'] as String;
    return Directory(packageConfigDir.uri.resolve(rootUri).toFilePath());
  }

  throw StateError('Package not found in package_config.json: $packageName');
}

Track _track(String sourceId, {required String title}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = title
    ..artist = 'Tester';
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super();

  final _source = _FakeSource();

  List<String> get audioStreamRequests => _source.audioStreamRequests;
  List<String> get refreshAudioUrlRequests => _source.refreshAudioUrlRequests;

  @override
  BaseSource? getSource(SourceType type) => _source;

  @override
  void dispose() {}
}

class _BlockingNeteaseAccountService extends NeteaseAccountService {
  _BlockingNeteaseAccountService(Isar isar, this._headerFuture)
      : super(isar: isar);

  final Future<void> _headerFuture;
  final Completer<void> _headerRequested = Completer<void>();

  Future<void> waitForHeaderRequest() => _headerRequested.future;

  @override
  Future<String?> getAuthCookieString() async {
    if (!_headerRequested.isCompleted) {
      _headerRequested.complete();
    }
    await _headerFuture;
    return 'MUSIC_U=test';
  }

  @override
  Future<Map<String, String>?> getAuthHeaders() async {
    final cookie = await getAuthCookieString();
    if (cookie == null) return null;
    return {
      'Cookie': cookie,
      'Origin': 'https://music.163.com',
      'Referer': 'https://music.163.com/',
      'User-Agent': NeteaseAccountService.userAgent,
    };
  }
}

class _HarnessPlaybackRequestStreamAccess
    implements PlaybackRequestStreamAccess {
  _HarnessPlaybackRequestStreamAccess({required this.trackBySourceId});

  final Map<String, Track> trackBySourceId;
  final List<String> selectionRequests = [];
  final List<String> fallbackSelectionTracks = [];
  final List<String?> fallbackSelectionFailedUrls = [];
  final List<String> ensureAudioStreamRequests = [];
  final List<String> headerRequests = [];
  final Map<String, Completer<void>> _headerRequestWaiters = {};
  Future<Map<String, String>?> Function(Track track)? onGetPlaybackHeaders;
  Future<PlaybackSelection?> Function(Track track, String? failedUrl)?
      onSelectFallbackPlayback;

  Future<void> waitForHeaderRequest(String sourceId) {
    return (_headerRequestWaiters[sourceId] ??= Completer<void>()).future;
  }

  @override
  Future<PlaybackSelection> selectPlayback(
    Track track, {
    bool persist = true,
  }) async {
    selectionRequests.add(track.sourceId);
    final (trackWithUrl, localPath, streamResult) =
        await ensureAudioStream(track, persist: persist);
    final url = localPath ?? trackWithUrl.audioUrl;
    if (url == null) {
      throw StateError('No playback URL available for ${track.sourceId}');
    }
    return PlaybackSelection(
      track: trackWithUrl,
      url: url,
      localPath: localPath,
      headers: localPath == null ? await getPlaybackHeaders(trackWithUrl) : null,
      streamResult: streamResult,
    );
  }

  @override
  Future<PlaybackSelection?> selectFallbackPlayback(
    Track track, {
    String? failedUrl,
  }) async {
    fallbackSelectionTracks.add(track.sourceId);
    fallbackSelectionFailedUrls.add(failedUrl);
    return onSelectFallbackPlayback?.call(track, failedUrl);
  }

  @override
  Future<(Track, String?, AudioStreamResult?)> ensureAudioStream(
    Track track, {
    int retryCount = 0,
    bool persist = true,
  }) async {
    ensureAudioStreamRequests.add(track.sourceId);
    final trackWithUrl = trackBySourceId[track.sourceId] ?? track;
    trackWithUrl.audioUrl = 'https://example.com/${track.sourceId}.m4a';
    trackWithUrl.audioUrlExpiry = DateTime.now().add(const Duration(minutes: 30));
    return (
      trackWithUrl,
      null,
      AudioStreamResult(
        url: trackWithUrl.audioUrl!,
        container: 'm4a',
        codec: 'aac',
        streamType: StreamType.audioOnly,
      ),
    );
  }

  @override
  Future<Map<String, String>?> getPlaybackHeaders(Track track) async {
    headerRequests.add(track.sourceId);
    final waiter = _headerRequestWaiters[track.sourceId];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
    return onGetPlaybackHeaders?.call(track);
  }

  @override
  Future<void> prefetchTrack(Track track) async {}
}

class _FakeSource extends BaseSource {
  final audioStreamRequests = <String>[];
  final refreshAudioUrlRequests = <String>[];

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;

  @override
  bool isPlaylistUrl(String url) => false;

  @override
  bool isValidId(String id) => true;

  @override
  String? parseId(String url) => url;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1, int pageSize = 20, Map<String, String>? authHeaders}) {
    throw UnimplementedError();
  }

  @override
  Future<Track> getTrackInfo(String sourceId,
      {Map<String, String>? authHeaders}) async {
    return _track(sourceId, title: sourceId);
  }

  @override
  Future<AudioStreamResult> getAudioStream(String sourceId,
      {AudioStreamConfig config = AudioStreamConfig.defaultConfig,
      Map<String, String>? authHeaders}) async {
    audioStreamRequests.add(sourceId);
    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<Track> refreshAudioUrl(Track track,
      {Map<String, String>? authHeaders}) async {
    refreshAudioUrlRequests.add(track.sourceId);
    track.audioUrl = 'https://example.com/${track.sourceId}.m4a';
    track.audioUrlExpiry = DateTime.now().add(const Duration(minutes: 30));
    return track;
  }

  @override
  Future<SearchResult> search(String query,
      {int page = 1,
      int pageSize = 20,
      SearchOrder order = SearchOrder.relevance}) async {
    return SearchResult.empty();
  }

  @override
  void dispose() {}
}
