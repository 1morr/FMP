import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_exception.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/main.dart' as app_main;
import 'package:fmp/providers/lyrics_provider.dart';
import 'package:fmp/providers/repository_providers.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/audio_provider.dart'
    hide MixTracksFetcher, PlayMode;
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
import 'package:fmp/services/network/connectivity_service.dart';
import 'package:fmp/services/radio/radio_controller.dart';
import 'package:fmp/services/radio/radio_refresh_service.dart';
import 'package:fmp/services/radio/radio_source.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioController phase 1 regressions', () {
    test('shared playback boundary types remain importable', () {
      expect(PlayMode.queue, isNotNull);
      MixTracksFetcher? fetcher;
      expect(fetcher, isNull);
    });

    late Directory tempDir;
    late Isar isar;
    late QueueRepository queueRepository;
    late QueueManager queueManager;
    late FakeAudioService audioService;
    late _FakeSourceManager sourceManager;
    late _TestMixTracksFetcher mixTracksFetcher;
    late AudioController controller;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
      RadioRefreshService.instance = RadioRefreshService(
        radioSource: _FakeRadioSource(),
        refreshInterval: const Duration(days: 1),
      );
    });

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('audio_controller_phase1_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema, RadioStationSchema],
        directory: tempDir.path,
        name: 'audio_controller_phase1_test',
      );

      queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      final settingsRepository = SettingsRepository(isar);
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
        audioStreamManager: audioStreamManager,
      );

      app_main.audioHandler = FmpAudioHandler();
      app_main.windowsSmtcHandler = WindowsSmtcHandler();

      audioService = FakeAudioService();
      mixTracksFetcher = _TestMixTracksFetcher();
      controller = AudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        audioHandler: app_main.audioHandler,
        windowsSmtcHandler: app_main.windowsSmtcHandler,
        settingsRepository: settingsRepository,
        mixTracksFetcher: mixTracksFetcher.call,
      );

      final settings = await settingsRepository.get();
      settings.rememberPlaybackPosition = true;
      settings.tempPlayRewindSeconds = 10;
      await settingsRepository.save(settings);

      await controller.initialize();
    });

    tearDownAll(() {
      RadioRefreshService.instance.dispose();
    });

    tearDown(() async {
      controller.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'second temporary play restores the original queue target instead of the first temporary track',
        () async {
      final queueTracks = [
        _track('queue-a', title: 'Queue A'),
        _track('queue-b', title: 'Queue B'),
        _track('queue-c', title: 'Queue C'),
      ];
      await controller.playAll(queueTracks, startIndex: 1);
      await controller.seekTo(const Duration(seconds: 42));
      audioService.setPositionValue(const Duration(seconds: 42));
      audioService.setPlayingValue(true);

      final tempOne = _track('temp-1', title: 'Temp One');
      final tempTwo = _track('temp-2', title: 'Temp Two');

      await controller.playTemporary(tempOne);
      await controller.playTemporary(tempTwo);

      expect(controller.state.upcomingTracks.map((track) => track.sourceId),
          orderedEquals(['queue-b', 'queue-c']));

      audioService.emitCompleted();
      await pumpEventQueue(times: 20);

      expect(controller.state.playingTrack?.sourceId, 'queue-b');
      expect(controller.state.currentTrack?.sourceId, 'queue-b');
      expect(
          audioService.setUrlCalls.last.url, 'https://example.com/queue-b.m4a');
      expect(audioService.seekCalls.last, const Duration(seconds: 32));
    });

    test('superseded request stays loading until the latest request finishes',
        () async {
      final firstTrack = _track('first', title: 'First Track');
      final secondTrack = _track('second', title: 'Second Track');
      final firstPlayGate = audioService.enqueuePendingPlayUrl();
      final secondPlayGate = audioService.enqueuePendingPlayUrl();

      final firstPlay = controller.playTrack(firstTrack);
      await audioService.waitForPlayUrlCallCount(1);

      final secondPlay = controller.playTrack(secondTrack);
      await audioService.waitForPlayUrlCallCount(2);

      firstPlayGate.complete();
      await firstPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 2);
      expect(controller.state.playingTrack?.sourceId, 'second');
      expect(controller.state.currentTrack?.sourceId, 'second');
      expect(controller.state.isLoading, isTrue);

      secondPlayGate.complete();
      await secondPlay;

      expect(controller.state.playingTrack?.sourceId, 'second');
      expect(controller.state.currentTrack?.sourceId, 'second');
      expect(controller.state.isLoading, isFalse);
    });

    test('superseded failing request does not stop or error the newer request',
        () async {
      final firstTrack = _track('first-error', title: 'First Error Track');
      final secondTrack = _track('second-ok', title: 'Second Ok Track');
      final firstPlayGate = audioService.enqueuePendingPlayUrl();
      final secondPlayGate = audioService.enqueuePendingPlayUrl();
      audioService.enqueuePlayUrlError(Exception('stale request failed'));

      final firstPlay = controller.playTrack(firstTrack);
      await audioService.waitForPlayUrlCallCount(1);

      final secondPlay = controller.playTrack(secondTrack);
      await audioService.waitForPlayUrlCallCount(2);

      firstPlayGate.complete();
      await firstPlay;
      await pumpEventQueue(times: 5);

      expect(controller.state.playingTrack?.sourceId, 'second-ok');
      expect(controller.state.currentTrack?.sourceId, 'second-ok');
      expect(controller.state.error, isNull);
      expect(controller.state.isLoading, isTrue);
      expect(controller.state.isRetrying, isFalse);

      secondPlayGate.complete();
      await secondPlay;

      expect(controller.state.playingTrack?.sourceId, 'second-ok');
      expect(controller.state.currentTrack?.sourceId, 'second-ok');
      expect(controller.state.error, isNull);
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isLoading, isFalse);
    });

    test('superseded restore does not stop or overwrite the newer request',
        () async {
      final queueTracks = [
        _track('queue-a', title: 'Queue A'),
        _track('queue-b', title: 'Queue B'),
      ];
      final newerTrack = _track('newer', title: 'Newer Track');

      await controller.playAll(queueTracks, startIndex: 1);
      await controller.seekTo(const Duration(seconds: 42));
      audioService.setPositionValue(const Duration(seconds: 42));
      audioService.setPlayingValue(true);

      final tempTrack = _track('temp-restore', title: 'Temp Restore');
      await controller.playTemporary(tempTrack);

      final blockedSeek = audioService.enqueuePendingSeek();
      final restoreSeekCount = audioService.seekCalls.length + 1;

      audioService.emitCompleted();
      await audioService.waitForSetUrlCallCount(1);
      await audioService.waitForSeekCallCount(restoreSeekCount);
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 3);
      expect(controller.state.playingTrack?.sourceId, 'queue-b');

      final newerPlay = controller.playTrack(newerTrack);
      await newerPlay;
      expect(audioService.stopCallCount, 4);
      expect(controller.state.playingTrack?.sourceId, 'newer');
      expect(controller.state.currentTrack?.sourceId, 'newer');

      blockedSeek.complete();
      await pumpEventQueue(times: 20);

      expect(audioService.stopCallCount, 4);
      expect(controller.state.playingTrack?.sourceId, 'newer');
      expect(controller.state.currentTrack?.sourceId, 'newer');
      expect(
          audioService.playUrlCalls.last.url, 'https://example.com/newer.m4a');
    });

    test(
        'superseded fallback playback does not start while newer request is loading',
        () async {
      final firstTrack =
          _track('first-fallback', title: 'First Fallback Track');
      final secondTrack =
          _track('second-fallback', title: 'Second Fallback Track');
      final firstPlayGate = audioService.enqueuePendingPlayUrl();
      final fallbackPlayGate = audioService.enqueuePendingPlayUrl();
      final secondPlayGate = audioService.enqueuePendingPlayUrl();
      audioService.enqueuePlayUrlError(Exception('force fallback'));

      final firstPlay = controller.playTrack(firstTrack);
      await audioService.waitForPlayUrlCallCount(1);

      firstPlayGate.complete();
      await audioService.waitForPlayUrlCallCount(2);

      final secondPlay = controller.playTrack(secondTrack);
      await audioService.waitForPlayUrlCallCount(3);

      fallbackPlayGate.complete();
      await firstPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 2);
      expect(audioService.playUrlCalls[0].url,
          'https://example.com/first-fallback.m4a');
      expect(audioService.playUrlCalls[1].url,
          'https://example.com/first-fallback-fallback.m4a');
      expect(audioService.playUrlCalls[2].url,
          'https://example.com/second-fallback.m4a');
      expect(controller.state.playingTrack?.sourceId, 'second-fallback');
      expect(controller.state.currentTrack?.sourceId, 'second-fallback');
      expect(controller.state.isLoading, isTrue);
      expect(controller.state.error, isNull);

      secondPlayGate.complete();
      await secondPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 2);
      expect(controller.state.playingTrack?.sourceId, 'second-fallback');
      expect(controller.state.currentTrack?.sourceId, 'second-fallback');
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isTrue);
    });

    test(
        'superseded source error without next track does not stop newer request',
        () async {
      final firstTrack =
          _track('stale-source-error', title: 'Stale Source Error');
      final secondTrack =
          _track('fresh-after-error', title: 'Fresh After Error');
      final secondPlayGate = audioService.enqueuePendingPlayUrl();
      sourceManager.throwGetAudioStreamOnce(
        const YouTubeApiException(code: 'unavailable', message: 'gone'),
      );

      final firstPlay = controller.playTrack(firstTrack);
      await pumpEventQueue(times: 1);

      final secondPlay = controller.playTrack(secondTrack);
      await audioService.waitForPlayUrlCallCount(1);
      await firstPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 2);
      expect(controller.state.playingTrack?.sourceId, 'fresh-after-error');
      expect(controller.state.currentTrack?.sourceId, 'fresh-after-error');
      expect(controller.state.error, isNull);
      expect(controller.state.isLoading, isTrue);

      secondPlayGate.complete();
      await secondPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 2);
      expect(controller.state.playingTrack?.sourceId, 'fresh-after-error');
      expect(controller.state.currentTrack?.sourceId, 'fresh-after-error');
      expect(controller.state.error, isNull);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isTrue);
    });

    test(
        'clearing queue while mix load-more is active exits safely and clears persisted mix metadata',
        () async {
      final mixTracks = [
        _track('mix-a', title: 'Mix A'),
        _track('mix-b', title: 'Mix B'),
      ];
      final loadMoreGate = mixTracksFetcher.enqueuePendingResult(
        const MixFetchResult(title: 'My Mix', tracks: []),
      );

      await controller.playMixPlaylist(
        playlistId: 'RDmix123',
        seedVideoId: 'seed123',
        title: 'My Mix',
        tracks: mixTracks,
        startIndex: 1,
      );
      await pumpEventQueue(times: 5);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'My Mix');
      expect(controller.state.isLoadingMoreMix, isTrue);

      await controller.clearQueue();
      await pumpEventQueue(times: 5);

      loadMoreGate.complete();
      await pumpEventQueue(times: 20);

      final persistedQueue = await queueRepository.getOrCreate();

      expect(controller.state.isMixMode, isFalse);
      expect(controller.state.mixTitle, isNull);
      expect(controller.state.isLoadingMoreMix, isFalse);
      expect(persistedQueue.trackIds, isEmpty);
      expect(persistedQueue.isMixMode, isFalse);
      expect(persistedQueue.mixPlaylistId, isNull);
      expect(persistedQueue.mixSeedVideoId, isNull);
      expect(persistedQueue.mixTitle, isNull);
    });

    test(
        'replacing a loading mix session resets visible load-more state for the new session',
        () async {
      final oldMixTracks = [
        _track('old-mix-a', title: 'Old Mix A'),
        _track('old-mix-b', title: 'Old Mix B'),
      ];
      final newMixTracks = [
        _track('new-mix-a', title: 'New Mix A'),
        _track('new-mix-b', title: 'New Mix B'),
      ];
      final oldLoadMoreGate = mixTracksFetcher.enqueuePendingResult(
        const MixFetchResult(title: 'Old Mix', tracks: []),
      );

      await controller.playMixPlaylist(
        playlistId: 'RDoldmix',
        seedVideoId: 'seed-old',
        title: 'Old Mix',
        tracks: oldMixTracks,
        startIndex: 1,
      );
      await pumpEventQueue(times: 5);

      expect(controller.state.mixTitle, 'Old Mix');
      expect(controller.state.isLoadingMoreMix, isTrue);

      await controller.playMixPlaylist(
        playlistId: 'RDnewmix',
        seedVideoId: 'seed-new',
        title: 'New Mix',
        tracks: newMixTracks,
        startIndex: 0,
      );
      await pumpEventQueue(times: 5);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'New Mix');
      expect(controller.state.currentTrack?.sourceId, 'new-mix-a');
      expect(controller.state.playingTrack?.sourceId, 'new-mix-a');
      expect(controller.state.isLoadingMoreMix, isFalse);

      oldLoadMoreGate.complete();
      await pumpEventQueue(times: 20);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'New Mix');
      expect(controller.state.currentTrack?.sourceId, 'new-mix-a');
      expect(controller.state.playingTrack?.sourceId, 'new-mix-a');
      expect(controller.state.isLoadingMoreMix, isFalse);
    });

    test('queue manager stops state notifications after dispose', () async {
      await queueManager.playAll([
        _track('dispose-a', title: 'Dispose A'),
        _track('dispose-b', title: 'Dispose B'),
      ]);

      final stateEvents = <void>[];
      final subscription = queueManager.stateStream.listen(stateEvents.add);

      queueManager.dispose();
      queueManager.setCurrentIndex(1);
      await pumpEventQueue(times: 5);

      expect(stateEvents, isEmpty);
      await subscription.cancel();
    });

    test('radio stop restores shared media-control callbacks to music ownership',
        () async {
      if (!Platform.isAndroid && !Platform.isWindows) {
        return;
      }

      app_main.audioHandler = FmpAudioHandler();
      app_main.windowsSmtcHandler = WindowsSmtcHandler();

      final radioStation = RadioStation()
        ..id = 1
        ..url = 'https://live.bilibili.com/1'
        ..title = 'Radio One'
        ..sourceType = SourceType.bilibili
        ..sourceId = '1';
      final radioRepository = RadioRepository(isar);
      await radioRepository.save(radioStation);

      final settingsRepository = SettingsRepository(isar);
      await settingsRepository.get();
      final trackRepository = TrackRepository(isar);
      final queueRepository = QueueRepository(isar);
      final sharedAudioService = FakeAudioService();
      final sourceManager = _FakeSourceManager();
      final audioStreamManager = AudioStreamManager(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
      );
      final queueManager = QueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        ),
        audioStreamManager: audioStreamManager,
      );
      final radioSource = _FakeRadioSource();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => sharedAudioService),
          audioStreamManagerProvider.overrideWith((ref) => audioStreamManager),
          queueManagerProvider.overrideWith((ref) => queueManager),
          radioRepositoryProvider.overrideWith((ref) => radioRepository),
          radioSourceProvider.overrideWith((ref) => radioSource),
          connectivityProvider.overrideWith((ref) => _TestConnectivityNotifier()),
          settingsRepositoryProvider.overrideWith((ref) => settingsRepository),
          playHistoryRepositoryProvider.overrideWith(
            (ref) => PlayHistoryRepository(isar),
          ),
          lyricsAutoMatchServiceProvider.overrideWith(
            (ref) => LyricsAutoMatchService(
              lrclib: LrclibSource(),
              netease: NeteaseSource(),
              qqmusic: QQMusicSource(),
              repo: LyricsRepository(isar),
              cache: LyricsCacheService(),
              parser: RegexTitleParser(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final invokePlayControl = () async {
        if (Platform.isWindows) {
          await app_main.windowsSmtcHandler.onPlay?.call();
          return;
        }
        await app_main.audioHandler.play();
      };
      final invokePauseControl = () async {
        if (Platform.isWindows) {
          await app_main.windowsSmtcHandler.onPause?.call();
          return;
        }
        await app_main.audioHandler.pause();
      };
      final invokeStopControl = () async {
        if (Platform.isWindows) {
          await app_main.windowsSmtcHandler.onStop?.call();
          return;
        }
        await app_main.audioHandler.stop();
      };

      container.read(audioControllerProvider.notifier);
      await pumpEventQueue(times: 10);

      expect(
        Platform.isWindows
            ? app_main.windowsSmtcHandler.onPlay
            : app_main.audioHandler.onPlay,
        isNotNull,
      );
      expect(
        Platform.isWindows
            ? app_main.windowsSmtcHandler.onPause
            : app_main.audioHandler.onPause,
        isNotNull,
      );
      expect(
        Platform.isWindows
            ? app_main.windowsSmtcHandler.onStop
            : app_main.audioHandler.onStop,
        isNotNull,
      );

      await invokePlayControl();
      expect(sharedAudioService.playUrlCalls, isEmpty);
      expect(sharedAudioService.isPlaying, isTrue);

      await invokePauseControl();
      expect(sharedAudioService.stopCallCount, 0);
      expect(sharedAudioService.isPlaying, isFalse);

      final radioController = container.read(radioControllerProvider.notifier);
      await pumpEventQueue(times: 5);
      await radioController.play(radioStation);

      expect(sharedAudioService.playUrlCalls, hasLength(1));
      expect(
        sharedAudioService.playUrlCalls.single.url,
        'https://example.com/radio-stream.m3u8',
      );
      expect(radioController.state.currentStation?.id, radioStation.id);
      expect(radioController.state.isPlaying, isTrue);

      await invokePauseControl();
      expect(sharedAudioService.stopCallCount, 1);
      expect(radioController.state.currentStation?.id, radioStation.id);
      expect(radioController.state.isPlaying, isFalse);

      await invokePlayControl();
      expect(sharedAudioService.playUrlCalls, hasLength(2));
      expect(
        sharedAudioService.playUrlCalls.last.url,
        'https://example.com/radio-stream.m3u8',
      );
      expect(radioController.state.currentStation?.id, radioStation.id);
      expect(radioController.state.isPlaying, isTrue);

      await invokeStopControl();
      expect(sharedAudioService.stopCallCount, 2);
      expect(radioController.state.currentStation, isNull);
      expect(radioController.state.isPlaying, isFalse);

      final playUrlCallCountAfterRadioStop = sharedAudioService.playUrlCalls.length;
      final stopCallCountAfterRadioStop = sharedAudioService.stopCallCount;

      await invokePlayControl();
      expect(
        sharedAudioService.playUrlCalls.length,
        playUrlCallCountAfterRadioStop,
      );
      expect(sharedAudioService.stopCallCount, stopCallCountAfterRadioStop);
      expect(sharedAudioService.isPlaying, isTrue);

      await invokePauseControl();
      expect(sharedAudioService.stopCallCount, stopCallCountAfterRadioStop);
      expect(sharedAudioService.isPlaying, isFalse);
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
  if (!await packageConfigFile.exists()) {
    throw StateError(
      'Could not find .dart_tool/package_config.json for test package resolution',
    );
  }

  return jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
}

Directory _resolvePackageDirectory(
  Map<String, dynamic> packageConfig,
  String packageName,
) {
  final packages = packageConfig['packages'];
  if (packages is! List) {
    throw StateError('Invalid package_config.json format');
  }

  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');
  for (final package in packages) {
    if (package is! Map<String, dynamic>) continue;
    if (package['name'] != packageName) continue;

    final rootUri = package['rootUri'];
    if (rootUri is! String) break;

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

class _TestConnectivityNotifier extends StateNotifier<ConnectivityState>
    with Logging
    implements ConnectivityNotifier {
  _TestConnectivityNotifier() : super(ConnectivityState.initial);

  final _networkRecoveredController = StreamController<void>.broadcast();

  @override
  Stream<void> get onNetworkRecovered => _networkRecoveredController.stream;

  @override
  void dispose() {
    _networkRecoveredController.close();
    super.dispose();
  }
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super();

  final _source = _FakeSource();

  void throwGetAudioStreamOnce(Object error) {
    _source.throwGetAudioStreamOnce(error);
  }

  @override
  BaseSource? getSource(SourceType type) => _source;

  @override
  void dispose() {}
}

class _TestMixTracksFetcher {
  final List<_PendingMixFetch> _pending = [];

  Completer<void> enqueuePendingResult(MixFetchResult result) {
    final completer = Completer<void>();
    _pending.add(_PendingMixFetch(completer, result));
    return completer;
  }

  Future<MixFetchResult> call({
    required String playlistId,
    required String currentVideoId,
  }) async {
    if (_pending.isEmpty) {
      return const MixFetchResult(title: 'My Mix', tracks: []);
    }

    final pending = _pending.removeAt(0);
    await pending.completer.future;
    return pending.result;
  }
}

class _PendingMixFetch {
  _PendingMixFetch(this.completer, this.result);

  final Completer<void> completer;
  final MixFetchResult result;
}

class _FakeRadioSource extends RadioSource {
  @override
  Future<LiveStreamInfo> getStreamUrl(RadioStation station) async {
    return const LiveStreamInfo(url: 'https://example.com/radio-stream.m3u8');
  }

  @override
  Future<LiveRoomInfo> getLiveInfo(RadioStation station) async {
    return const LiveRoomInfo(
      title: 'Radio One',
      isLive: true,
    );
  }

  @override
  Future<int?> getHighEnergyUserCount(RadioStation station) async => 123;

  @override
  void dispose() {}
}

class _FakeSource extends BaseSource {
  Object? _nextGetAudioStreamError;

  void throwGetAudioStreamOnce(Object error) {
    _nextGetAudioStreamError = error;
  }

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
    final error = _nextGetAudioStreamError;
    if (error != null) {
      _nextGetAudioStreamError = null;
      throw error;
    }

    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    String sourceId, {
    String? failedUrl,
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  }) async {
    return AudioStreamResult(
      url: 'https://example.com/$sourceId-fallback.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.muxed,
    );
  }

  @override
  Future<Track> refreshAudioUrl(Track track,
      {Map<String, String>? authHeaders}) async {
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
