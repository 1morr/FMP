import 'dart:async';
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
import 'package:fmp/data/sources/youtube_exception.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/audio_provider.dart'
    hide MixTracksFetcher, PlayMode;
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
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
    });

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('audio_controller_phase1_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
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
      );

      audioService = FakeAudioService();
      mixTracksFetcher = _TestMixTracksFetcher();
      controller = AudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        audioHandler: FmpAudioHandler(),
        windowsSmtcHandler: WindowsSmtcHandler(),
        settingsRepository: settingsRepository,
        mixTracksFetcher: mixTracksFetcher.call,
      );

      final settings = await settingsRepository.get();
      settings.rememberPlaybackPosition = true;
      settings.tempPlayRewindSeconds = 10;
      await settingsRepository.save(settings);

      await controller.initialize();
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

      audioService.setUrlCalls.clear();
      audioService.seekCalls.clear();
      final restoreSetUrl = audioService.waitForSetUrlCallCount(1);
      final restoreSeek = audioService.waitForSeekCallCount(1);

      audioService.emitCompleted();
      await restoreSetUrl;
      await restoreSeek;
      await pumpEventQueue(times: 20);

      expect(controller.state.playingTrack?.sourceId, 'queue-b');
      expect(controller.state.currentTrack?.sourceId, 'queue-b');
      expect(
          audioService.setUrlCalls.single.url, 'https://example.com/queue-b.m4a');
      expect(audioService.seekCalls.single, const Duration(seconds: 32));
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

    test('togglePlayPause refreshes expired remote URL and restores position',
        () async {
      sourceManager.setNextAudioExpiry(const Duration(milliseconds: 1));
      await controller
          .playTrack(_track('expired-resume', title: 'Expired Resume'));
      await controller.seekTo(const Duration(seconds: 42));
      audioService.setPositionValue(const Duration(seconds: 42));
      await controller.pause();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      await controller.togglePlayPause();
      await pumpEventQueue(times: 20);

      expect(audioService.playUrlCalls.single.url,
          'https://example.com/expired-resume.m4a');
      expect(audioService.seekCalls.single, const Duration(seconds: 42));
      expect(controller.state.playingTrack?.sourceId, 'expired-resume');
      expect(controller.state.isPlaying, isTrue);
    });

    test('togglePlayPause does not refresh expired URL when local file exists',
        () async {
      final localFile = File('${tempDir.path}/local-expired.m4a');
      await localFile.writeAsString('audio-bytes');
      final track = _track('local-expired', title: 'Local Expired')
        ..audioUrl = 'https://stale.example/local-expired.m4a'
        ..audioUrlExpiry = DateTime.now().subtract(const Duration(minutes: 1))
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 1
            ..playlistName = 'Downloaded'
            ..downloadPath = localFile.path,
        ];

      await controller.playTrack(track);
      await controller.pause();
      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      await controller.togglePlayPause();
      await pumpEventQueue(times: 10);

      expect(audioService.playUrlCalls, isEmpty);
      expect(audioService.seekCalls, isEmpty);
      expect(controller.state.isPlaying, isTrue);
    });

    test('superseded expired URL resume does not seek the newer track',
        () async {
      sourceManager.setNextAudioExpiry(const Duration(milliseconds: 1));
      await controller.playTrack(_track('old-expired', title: 'Old Expired'));
      await controller.seekTo(const Duration(seconds: 42));
      audioService.setPositionValue(const Duration(seconds: 42));
      await controller.pause();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();
      final oldResume = controller.togglePlayPause();
      await audioService.waitForPlayUrlCallCount(1);

      final newerTrack =
          _track('new-after-expired', title: 'New After Expired');
      await controller.playTrack(newerTrack);
      await oldResume;
      await pumpEventQueue(times: 20);

      expect(controller.state.playingTrack?.sourceId, 'new-after-expired');
      expect(controller.state.currentTrack?.sourceId, 'new-after-expired');
      expect(
          audioService.playUrlCalls.map((call) => call.url),
          containsAllInOrder([
            'https://example.com/old-expired.m4a',
            'https://example.com/new-after-expired.m4a',
          ]));
      expect(audioService.seekCalls, isEmpty);
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

    test('return from radio restores queue through the shared transition handoff',
        () async {
      final queueTracks = [
        _track('radio-a', title: 'Radio A'),
        _track('radio-b', title: 'Radio B'),
      ];

      await controller.playAll(queueTracks, startIndex: 1);
      audioService.setUrlCalls.clear();
      audioService.seekCalls.clear();
      final restoreSetUrl = audioService.waitForSetUrlCallCount(1);
      final restoreSeek = audioService.waitForSeekCallCount(1);

      await controller.returnFromRadio(
        savedQueueIndex: 1,
        savedPosition: const Duration(seconds: 18),
        savedWasPlaying: true,
      );
      await restoreSetUrl;
      await restoreSeek;
      await pumpEventQueue(times: 10);

      expect(controller.state.currentTrack?.sourceId, 'radio-b');
      expect(controller.state.playingTrack?.sourceId, 'radio-b');
      expect(audioService.setUrlCalls.single.url, 'https://example.com/radio-b.m4a');
      expect(audioService.seekCalls.single, const Duration(seconds: 18));
      expect(controller.state.isPlaying, isTrue);
    });

    test(
        'temporary restore replaces the queue copy instead of mutating the existing queue track in place',
        () async {
      final queueTracks = [
        _track('restore-a', title: 'Restore A'),
        _track('restore-b', title: 'Restore B'),
      ];
      final tempTrack = _track('restore-temp', title: 'Restore Temp');

      await controller.playAll(queueTracks, startIndex: 1);
      final queueTrackBeforeTemporary = controller.state.queueTrack;
      expect(queueTrackBeforeTemporary, isNotNull);

      await controller.playTemporary(tempTrack);
      audioService.setUrlCalls.clear();
      final restoreSetUrl = audioService.waitForSetUrlCallCount(1);

      audioService.emitCompleted();
      await restoreSetUrl;
      await pumpEventQueue(times: 20);

      final queueTrackAfterRestore = controller.state.queueTrack;
      final playingTrackAfterRestore = controller.state.playingTrack;
      expect(queueTrackAfterRestore, isNotNull);
      expect(playingTrackAfterRestore, isNotNull);
      expect(queueTrackAfterRestore!.sourceId, 'restore-b');
      expect(playingTrackAfterRestore!.sourceId, 'restore-b');
      expect(queueTrackAfterRestore, isNot(same(queueTrackBeforeTemporary)));
      expect(queueTrackAfterRestore, isNot(same(playingTrackAfterRestore)));
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

    test(
        'playback prefetch uses a detached next-track copy',
        () async {
      final tracks = [
        _track('prefetch-play-current', title: 'Prefetch Play Current'),
        _track('prefetch-play-next', title: 'Prefetch Play Next')
          ..audioUrl = 'https://stale.example/prefetch-play-next.m4a'
          ..audioUrlExpiry = DateTime.now().subtract(const Duration(minutes: 1)),
      ];

      await controller.playAll(tracks, startIndex: 0);
      await pumpEventQueue(times: 20);

      expect(controller.state.queue.length, 2);
      final nextQueueTrack = controller.state.queue[1];
      expect(nextQueueTrack.sourceId, 'prefetch-play-next');
      expect(nextQueueTrack.audioUrl, 'https://stale.example/prefetch-play-next.m4a');
    });

    test(
        'prepareCurrentTrack prefetch keeps queue-owned next track unchanged until explicit replacement',
        () async {
      final tracks = [
        _track('prefetch-current', title: 'Prefetch Current'),
        _track('prefetch-next', title: 'Prefetch Next')
          ..audioUrl = 'https://stale.example/prefetch-next.m4a'
          ..audioUrlExpiry = DateTime.now().subtract(const Duration(minutes: 1)),
      ];

      await controller.playAll(tracks, startIndex: 0);
      await pumpEventQueue(times: 20);

      final nextTrackBeforePrepare = controller.state.queue[1];
      expect(nextTrackBeforePrepare.audioUrl, 'https://stale.example/prefetch-next.m4a');

      controller.dispose();

      final trackRepository = TrackRepository(isar);
      final settingsRepository = SettingsRepository(isar);
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
        mixTracksFetcher: mixTracksFetcher.call,
      );
      await controller.initialize();
      await pumpEventQueue(times: 20);

      expect(controller.state.queue.length, 2);
      final nextTrackAfterPrepare = controller.state.queue[1];
      expect(nextTrackAfterPrepare.id, nextTrackBeforePrepare.id);
      expect(nextTrackAfterPrepare.audioUrl, 'https://stale.example/prefetch-next.m4a');

      final persistedNextTrack = await trackRepository.getById(nextTrackAfterPrepare.id);
      expect(persistedNextTrack, isNotNull);
      expect(persistedNextTrack!.audioUrl,
          'https://stale.example/prefetch-next.m4a');
    });

    test(
        'controller playback keeps queue stale until explicit replacement and then notifies UI',
        () async {
      final track = _track('runtime-boundary', title: 'Runtime Boundary');

      await controller.playSingle(track);
      await pumpEventQueue(times: 20);

      final queueTrackAfterPlay = controller.state.queueTrack;
      final playingTrackAfterPlay = controller.state.playingTrack;
      final queueVersionAfterPlay = controller.state.queueVersion;
      expect(queueTrackAfterPlay, isNotNull);
      expect(playingTrackAfterPlay, isNotNull);
      expect(queueTrackAfterPlay!.id, playingTrackAfterPlay!.id);
      expect(queueTrackAfterPlay.audioUrl,
          'https://example.com/runtime-boundary.m4a');
      expect(playingTrackAfterPlay.audioUrl, 'https://example.com/runtime-boundary.m4a');
      expect(queueTrackAfterPlay, isNot(same(playingTrackAfterPlay)));

      final replacementNotified = Completer<void>();
      late final StreamSubscription<void> queueSub;
      queueSub = queueManager.stateStream.listen((_) {
        if (controller.state.queueTrack?.audioUrl ==
                'https://manual.example/runtime-boundary.m4a' &&
            !replacementNotified.isCompleted) {
          replacementNotified.complete();
        }
      });

      final replacement = queueTrackAfterPlay.copy()
        ..audioUrl = 'https://manual.example/runtime-boundary.m4a'
        ..audioUrlExpiry = DateTime.utc(2031, 1, 1);
      queueManager.replaceTrack(replacement);
      await replacementNotified.future;
      await pumpEventQueue(times: 5);
      await queueSub.cancel();

      expect(controller.state.queueTrack?.audioUrl,
          'https://manual.example/runtime-boundary.m4a');
      expect(controller.state.queueTrack?.audioUrlExpiry,
          DateTime.utc(2031, 1, 1));
      expect(controller.state.playingTrack?.audioUrl,
          'https://example.com/runtime-boundary.m4a');
      expect(controller.state.queueVersion, greaterThan(queueVersionAfterPlay));
      expect(audioService.playUrlCalls.single.track, isNotNull);
      expect(audioService.playUrlCalls.single.track, isNot(same(queueTrackAfterPlay)));
      expect(audioService.playUrlCalls.single.track!.audioUrl,
          'https://example.com/runtime-boundary.m4a');
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

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super();

  final _source = _FakeSource();

  void throwGetAudioStreamOnce(Object error) {
    _source.throwGetAudioStreamOnce(error);
  }

  void setNextAudioExpiry(Duration? expiry) {
    _source.nextAudioExpiry = expiry;
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

class _FakeSource extends BaseSource {
  Object? _nextGetAudioStreamError;
  Duration? nextAudioExpiry;

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

    final expiry = nextAudioExpiry;
    nextAudioExpiry = null;
    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
      expiry: expiry,
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
