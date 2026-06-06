import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/bilibili_exception.dart';
import 'package:fmp/data/sources/netease_exception.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_exception.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_runtime_platform.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
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
    late ToastService toastService;
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
        [TrackSchema, PlayQueueSchema, SettingsSchema, LyricsMatchSchema],
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
      toastService = ToastService();
      mixTracksFetcher = _TestMixTracksFetcher();
      controller = AudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: toastService,
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

    test('stale lyrics auto-match cannot clear newer loading state', () async {
      final lyricsService = _GateableLyricsAutoMatchService(isar);
      controller.dispose();

      final settingsRepository = SettingsRepository(isar);
      final trackRepository = TrackRepository(isar);
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
        lyricsAutoMatchService: lyricsService,
        mixTracksFetcher: mixTracksFetcher.call,
      );

      final states = <bool>[];
      controller.onLyricsAutoMatchStateChanged = states.add;
      final settings = await settingsRepository.get();
      settings.autoMatchLyrics = true;
      await settingsRepository.save(settings);
      await controller.initialize();

      final firstGate = lyricsService.enqueuePendingResult(false);
      final secondGate = lyricsService.enqueuePendingResult(false);

      await controller.playTrack(_track('lyrics-a', title: 'Lyrics A'));
      await lyricsService.waitForCallCount(1);
      await controller.playTrack(_track('lyrics-b', title: 'Lyrics B'));
      await lyricsService.waitForCallCount(2);

      firstGate.complete();
      await pumpEventQueue(times: 10);

      expect(states, [true, true]);

      secondGate.complete();
      await pumpEventQueue(times: 10);

      expect(states, [true, true, false]);
    });

    test('lyrics auto-match preserves an explicitly empty enabled source list',
        () async {
      final lyricsService = _GateableLyricsAutoMatchService(isar);
      controller.dispose();

      final settingsRepository = SettingsRepository(isar);
      final trackRepository = TrackRepository(isar);
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
        lyricsAutoMatchService: lyricsService,
        mixTracksFetcher: mixTracksFetcher.call,
      );

      final settings = await settingsRepository.get();
      settings.autoMatchLyrics = true;
      settings.disabledLyricsSourcesSet = {
        'netease',
        'qqmusic',
        'lrclib',
      };
      await settingsRepository.save(settings);
      await controller.initialize();

      await controller.playTrack(_track('lyrics-disabled', title: 'Disabled'));
      await lyricsService.waitForCallCount(1);
      await pumpEventQueue(times: 10);

      expect(lyricsService.enabledSourceCalls.single, isEmpty);
    });

    tearDown(() async {
      controller.dispose();
      toastService.dispose();
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
      expect(audioService.setUrlCalls.single.url,
          'https://example.com/queue-b.m4a');
      expect(audioService.seekCalls.single, const Duration(seconds: 32));
    });

    test(
        'mobile notification stays on next track loading while queue navigation resolves stream',
        () async {
      final handler = FmpAudioHandler();
      controller.dispose();

      final settingsRepository = SettingsRepository(isar);
      final trackRepository = TrackRepository(isar);
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
        audioHandler: handler,
        windowsSmtcHandler: WindowsSmtcHandler(),
        settingsRepository: settingsRepository,
        mixTracksFetcher: mixTracksFetcher.call,
        runtimePlatform: AudioRuntimePlatform.mobile,
      );
      await controller.initialize();

      await queueManager.playAll([
        _track('notification-first', title: 'Notification First'),
        _track('notification-next', title: 'Notification Next'),
      ]);
      await controller.playAt(0);
      expect(handler.mediaItem.valueOrNull?.title, 'Notification First');

      final pendingNextLoad = audioService.enqueuePendingPlayUrl();
      final nextFuture = controller.next();
      await audioService.waitForPlayUrlCallCount(2);
      await pumpEventQueue(times: 5);

      expect(handler.mediaItem.valueOrNull?.title, 'Notification Next');
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.loading,
      );

      pendingNextLoad.complete();
      await nextFuture;
    });

    test('mobile notification exits loading when next-track stream fails',
        () async {
      final handler = FmpAudioHandler();
      controller.dispose();

      final settingsRepository = SettingsRepository(isar);
      final trackRepository = TrackRepository(isar);
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
        audioHandler: handler,
        windowsSmtcHandler: WindowsSmtcHandler(),
        settingsRepository: settingsRepository,
        mixTracksFetcher: mixTracksFetcher.call,
        runtimePlatform: AudioRuntimePlatform.mobile,
      );
      await controller.initialize();

      await queueManager.playAll([
        _track('notification-fail-first', title: 'Notification Fail First'),
        _track('notification-fail-next', title: 'Notification Fail Next'),
      ]);
      await controller.playAt(0);
      expect(handler.mediaItem.valueOrNull?.title, 'Notification Fail First');
      await pumpEventQueue(times: 20);

      sourceManager.throwGetAudioStreamOnce(
        const YouTubeApiException(
          code: 'rate_limited',
          message: 'rate limited',
        ),
      );

      await controller.next();
      await pumpEventQueue(times: 10);

      expect(handler.mediaItem.valueOrNull?.title, 'Notification Fail Next');
      expect(
        handler.playbackState.value.processingState,
        isNot(AudioProcessingState.loading),
      );
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

    test(
        'superseded playback-starting callback does not stop the newer request',
        () async {
      final firstTrack =
          _track('callback-first', title: 'Callback First Track');
      final secondTrack =
          _track('callback-second', title: 'Callback Second Track');
      final firstCallback = Completer<void>();
      final secondCallback = Completer<void>();
      var callbackCount = 0;
      controller.onPlaybackStarting = () {
        callbackCount++;
        return callbackCount == 1
            ? firstCallback.future
            : secondCallback.future;
      };
      final secondPlayGate = audioService.enqueuePendingPlayUrl();

      final firstPlay = controller.playTrack(firstTrack);
      await _pumpUntil(() => callbackCount == 1);
      expect(controller.state.playingTrack?.sourceId, 'callback-first');

      final secondPlay = controller.playTrack(secondTrack);
      await _pumpUntil(() => callbackCount == 2);
      expect(controller.state.playingTrack?.sourceId, 'callback-second');

      firstCallback.complete();
      await firstPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 0);
      expect(audioService.playUrlCalls, isEmpty);
      expect(controller.state.playingTrack?.sourceId, 'callback-second');
      expect(controller.state.currentTrack?.sourceId, 'callback-second');
      expect(controller.state.isLoading, isTrue);

      secondCallback.complete();
      await audioService.waitForPlayUrlCallCount(1);
      secondPlayGate.complete();
      await secondPlay;
      await pumpEventQueue(times: 5);

      expect(audioService.stopCallCount, 1);
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/callback-second.m4a');
      expect(controller.state.playingTrack?.sourceId, 'callback-second');
      expect(controller.state.currentTrack?.sourceId, 'callback-second');
      expect(controller.state.isLoading, isFalse);
      controller.onPlaybackStarting = null;
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

    test('source skip errors include semantic reason in toast', () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);
      sourceManager.throwGetAudioStreamAlways(
        const NeteaseApiException(
          numericCode: -10,
          message: 'VIP song, payment required',
        ),
      );

      await controller.playTrack(_track('locked-song', title: 'Locked Song'));
      await pumpEventQueue(times: 5);

      expect(toasts, isNotEmpty);
      expect(toasts.last.message, contains('Locked Song'));
      expect(toasts.last.message, contains('VIP'));
      expect(toasts.last.type, ToastType.error);
    });

    test('source skip errors prefer concrete source diagnostic text', () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);
      sourceManager.throwGetAudioStreamOnce(
        const YouTubeApiException(
          code: 'geo_restricted',
          message: 'This video is not available in your country',
        ),
      );

      await controller.playTrack(_track('geo-song', title: 'Geo Song'));
      await pumpEventQueue(times: 5);

      expect(toasts, isNotEmpty);
      expect(toasts.last.message, contains('Geo Song'));
      expect(
        toasts.last.message,
        contains('This video is not available in your country'),
      );
      expect(toasts.last.type, ToastType.error);
    });

    test('source skip errors clear stale stream metadata', () async {
      await controller.playTrack(_track('playable-song', title: 'Playable'));
      await pumpEventQueue(times: 5);

      expect(controller.state.currentContainer, 'm4a');
      expect(controller.state.currentCodec, 'aac');
      expect(controller.state.currentStreamType, StreamType.audioOnly);

      sourceManager.throwGetAudioStreamAlways(
        const YouTubeApiException(
          code: 'geo_restricted',
          message: 'This video is not available in your country',
        ),
      );

      await controller.playTrack(_track('blocked-song', title: 'Blocked Song'));
      await pumpEventQueue(times: 5);

      expect(controller.state.playingTrack?.sourceId, 'blocked-song');
      expect(controller.state.error, contains('Blocked Song'));
      expect(controller.state.currentBitrate, isNull);
      expect(controller.state.currentContainer, isNull);
      expect(controller.state.currentCodec, isNull);
      expect(controller.state.currentStreamType, isNull);
    });

    test('source skip errors hide synthesized fallback diagnostics', () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);
      sourceManager.throwGetAudioStreamOnce(
        const NeteaseApiException(
          numericCode: -110,
          message: 'No playback rights due to copyright or region restrictions',
        ),
      );

      await controller.playTrack(_track('flag-song', title: 'Flag Song'));
      await pumpEventQueue(times: 5);

      expect(toasts, isNotEmpty);
      expect(toasts.last.message, contains('Flag Song'));
      expect(
        toasts.last.message,
        isNot(contains('No playback rights')),
      );
      expect(
        toasts.last.message,
        anyOf(
          contains('copyright'),
          contains('版权'),
          contains('版權'),
        ),
      );
      expect(toasts.last.type, ToastType.error);
    });

    test('Bilibili permission error code uses friendly playback message',
        () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);
      sourceManager.throwGetAudioStreamOnce(
        const BilibiliApiException(
          numericCode: 62012,
          message: '62012',
        ),
      );

      await controller.playTrack(
        _track('private-bilibili-video', title: 'Private Bilibili Video'),
      );
      await pumpEventQueue(times: 5);

      expect(toasts, isNotEmpty);
      expect(toasts.last.message, isNot(contains('62012')));
      expect(
        toasts.last.message,
        contains('Bilibili'),
      );
      expect(
        toasts.last.message,
        anyOf(contains('logged-in'), contains('登录状态'), contains('登入狀態')),
      );
      expect(toasts.last.type, ToastType.error);
    });

    test('terminal media open error aborts the active play request', () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);

      final playGate = audioService.enqueuePendingPlayUrl();
      final playFuture = controller.playTrack(
        _track('media-open-failure', title: 'Media Open Failure'),
      );
      await audioService.waitForPlayUrlCallCount(1);

      audioService.emitError(
        'Failed to open https://example.com/media-open-failure.m4a.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(toasts, isNotEmpty);
      expect(toasts.last.type, ToastType.error);
      expect(toasts.last.message, contains('Media Open Failure'));
      expect(controller.state.error, contains('Media Open Failure'));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isFalse);

      playGate.complete();
      await playFuture;
      await pumpEventQueue(times: 5);

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isFalse);
      expect(controller.state.currentContainer, isNull);
      expect(controller.state.currentStreamType, isNull);
    });

    test('post-handoff media open error becomes visible terminal error',
        () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);

      await controller.playTrack(
        _track('media-open-post-handoff', title: 'Media Open Post Handoff'),
      );
      await pumpEventQueue(times: 5);

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.error, isNull);
      final stopCountBeforeError = audioService.stopCallCount;

      audioService.setPlayingValue(false);
      audioService.setPositionValue(Duration.zero);
      audioService.emitError(
        'Failed to open https://example.com/media-open-post-handoff.m4a.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await pumpEventQueue(times: 5);

      expect(toasts, isNotEmpty);
      expect(toasts.last.type, ToastType.error);
      expect(toasts.last.message, contains('Media Open Post Handoff'));
      expect(controller.state.error, contains('Media Open Post Handoff'));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isFalse);
      expect(audioService.stopCallCount, stopCountBeforeError + 1);
    });

    test('new playback cancels pending post-handoff media open stop', () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);

      await controller.playTrack(
        _track('media-open-old-pending', title: 'Media Open Old Pending'),
      );
      await pumpEventQueue(times: 5);

      audioService.setPlayingValue(false);
      audioService.setPositionValue(Duration.zero);
      audioService.emitError(
        'Failed to open https://example.com/media-open-old-pending.m4a.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));

      await controller.playTrack(
        _track('media-open-new-track', title: 'Media Open New Track'),
      );
      await pumpEventQueue(times: 5);
      final stopCountAfterNewPlayback = audioService.stopCallCount;

      await Future<void>.delayed(const Duration(milliseconds: 1800));
      await pumpEventQueue(times: 5);

      expect(
        toasts.map((toast) => toast.message),
        isNot(contains(contains('Media Open Old Pending'))),
      );
      expect(controller.state.error, isNull);
      expect(controller.state.currentTrack?.sourceId, 'media-open-new-track');
      expect(controller.state.playingTrack?.sourceId, 'media-open-new-track');
      expect(controller.state.isPlaying, isTrue);
      expect(audioService.stopCallCount, stopCountAfterNewPlayback);
    });

    test('pending media open blocks active play success path', () async {
      final playGate = audioService.enqueuePendingPlayUrl();
      var playCompleted = false;

      final playFuture = controller
          .playTrack(
            _track('media-open-active', title: 'Media Open Active'),
          )
          .then((_) => playCompleted = true);
      await audioService.waitForPlayUrlCallCount(1);

      audioService.emitError(
        'Failed to open https://example.com/media-open-active.m4a.',
      );

      playGate.complete();
      await pumpEventQueue(times: 5);

      expect(playCompleted, isFalse);
      expect(controller.state.isLoading, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await playFuture;
      await pumpEventQueue(times: 5);

      expect(playCompleted, isTrue);
      expect(controller.state.error, contains('Media Open Active'));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isFalse);
    });

    test('terminal media open ignores stale backend loading state', () async {
      final playGate = audioService.enqueuePendingPlayUrl();

      final playFuture = controller.playTrack(
        _track('media-open-stale-loading', title: 'Media Open Stale Loading'),
      );
      await audioService.waitForPlayUrlCallCount(1);

      audioService.emitError(
        'Failed to open https://example.com/media-open-stale-loading.m4a.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      playGate.complete();
      await playFuture;
      await pumpEventQueue(times: 5);

      expect(controller.state.error, contains('Media Open Stale Loading'));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isBuffering, isFalse);

      audioService.setPlayingValue(false);
      audioService.emitProcessingState(FmpAudioProcessingState.loading);
      await pumpEventQueue(times: 5);

      expect(controller.state.error, contains('Media Open Stale Loading'));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isBuffering, isFalse);
    });

    test('waits for pending media open cleanup when handoff is superseded',
        () async {
      final playGate = audioService.enqueuePendingPlayUrl();
      var playCompleted = false;

      final playFuture = controller
          .playTrack(
            _track('media-open-cleanup', title: 'Media Open Cleanup'),
          )
          .then((_) => playCompleted = true);
      await audioService.waitForPlayUrlCallCount(1);
      final stopGate = audioService.enqueuePendingStop();

      audioService.emitError(
        'Failed to open https://example.com/media-open-cleanup.m4a.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      playGate.complete();
      await pumpEventQueue(times: 5);

      expect(playCompleted, isFalse);

      stopGate.complete();
      await playFuture;
      await pumpEventQueue(times: 5);

      expect(playCompleted, isTrue);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isFalse);
    });

    test('active media open terminal cannot overwrite newer playback',
        () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);

      final oldPlayGate = audioService.enqueuePendingPlayUrl();
      final oldPlayFuture = controller.playTrack(
        _track('media-open-old-active', title: 'Media Open Old Active'),
      );
      await audioService.waitForPlayUrlCallCount(1);

      final terminalStopGate = audioService.enqueuePendingStop();
      audioService.emitError(
        'Failed to open https://example.com/media-open-old-active.m4a.',
      );
      oldPlayGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await pumpEventQueue(times: 5);

      final newPlayGate = audioService.enqueuePendingPlayUrl();
      final newPlayFuture = controller.playTrack(
        _track('media-open-new-active', title: 'Media Open New Active'),
      );
      await audioService.waitForPlayUrlCallCount(2);

      terminalStopGate.complete();
      await oldPlayFuture;
      await pumpEventQueue(times: 5);

      newPlayGate.complete();
      await newPlayFuture;
      await pumpEventQueue(times: 5);

      expect(
        toasts.map((toast) => toast.message),
        isNot(contains(contains('Media Open Old Active'))),
      );
      expect(controller.state.error, isNull);
      expect(controller.state.currentTrack?.sourceId, 'media-open-new-active');
      expect(controller.state.playingTrack?.sourceId, 'media-open-new-active');
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isPlaying, isTrue);
    });

    test('retry terminal media open clears loading and retry state', () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);

      await controller.playTrack(
        _track('retry-media-open-terminal', title: 'Retry Media Open Terminal'),
      );
      await pumpEventQueue(times: 10);

      audioService.emitPosition(const Duration(seconds: 19));
      audioService.emitError('network timeout during playback');
      await pumpEventQueue(times: 10);

      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);

      audioService.playUrlCalls.clear();
      final retryPlayGate = audioService.enqueuePendingPlayUrl();
      final retry = controller.retryManually();
      await audioService.waitForPlayUrlCallCount(1);

      audioService.emitError(
        'Failed to open https://example.com/retry-media-open-terminal.m4a.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      retryPlayGate.complete();
      await retry;
      await pumpEventQueue(times: 5);

      expect(toasts, isNotEmpty);
      expect(toasts.last.type, ToastType.error);
      expect(toasts.last.message, contains('Retry Media Open Terminal'));
      expect(controller.state.error, contains('Retry Media Open Terminal'));
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isBuffering, isFalse);
      expect(controller.state.isPlaying, isFalse);
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isNetworkError, isFalse);
      expect(controller.state.retryAttempt, 0);
      expect(controller.state.nextRetryAt, isNull);
    });

    test('rate-limited source error remains visible after loading resets',
        () async {
      sourceManager.throwGetAudioStreamOnce(
        const YouTubeApiException(
          code: 'rate_limited',
          message: 'Too many requests',
        ),
      );

      await controller.playTrack(
        _track('rate-limited-song', title: 'Rate Limited Song'),
      );
      await pumpEventQueue(times: 10);

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.error, 'Too many requests');
    });

    test('skipped queue track toast includes semantic reason', () async {
      final toasts = <ToastMessage>[];
      final subscription = toastService.messageStream.listen(toasts.add);
      addTearDown(subscription.cancel);
      sourceManager.throwGetAudioStreamAlways(
        const NeteaseApiException(
          numericCode: -10,
          message: 'VIP song, payment required',
        ),
      );

      try {
        await controller.playAll([
          _track('locked-queue-song', title: 'Locked Queue Song'),
          _track('next-after-locked', title: 'Next After Locked'),
        ]);
        await pumpEventQueue(times: 5);

        expect(toasts, isNotEmpty);
        expect(toasts.last.message, contains('Locked Queue Song'));
        expect(toasts.last.message, contains('VIP'));
        expect(toasts.last.type, ToastType.warning);
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await pumpEventQueue(times: 5);
      }
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
        'return from radio restores queue through the shared transition handoff',
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
      expect(audioService.setUrlCalls.single.url,
          'https://example.com/radio-b.m4a');
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

    test('playback prefetch uses a detached next-track copy', () async {
      final tracks = [
        _track('prefetch-play-current', title: 'Prefetch Play Current'),
        _track('prefetch-play-next', title: 'Prefetch Play Next')
          ..audioUrl = 'https://stale.example/prefetch-play-next.m4a'
          ..audioUrlExpiry =
              DateTime.now().subtract(const Duration(minutes: 1)),
      ];

      await controller.playAll(tracks, startIndex: 0);
      await pumpEventQueue(times: 20);

      expect(controller.state.queue.length, 2);
      final nextQueueTrack = controller.state.queue[1];
      expect(nextQueueTrack.sourceId, 'prefetch-play-next');
      expect(nextQueueTrack.audioUrl,
          'https://stale.example/prefetch-play-next.m4a');
    });

    test(
        'prepareCurrentTrack prefetch keeps queue-owned next track unchanged until explicit replacement',
        () async {
      final tracks = [
        _track('prefetch-current', title: 'Prefetch Current'),
        _track('prefetch-next', title: 'Prefetch Next')
          ..audioUrl = 'https://stale.example/prefetch-next.m4a'
          ..audioUrlExpiry =
              DateTime.now().subtract(const Duration(minutes: 1)),
      ];

      await controller.playAll(tracks, startIndex: 0);
      await pumpEventQueue(times: 20);

      final nextTrackBeforePrepare = controller.state.queue[1];
      expect(nextTrackBeforePrepare.audioUrl,
          'https://stale.example/prefetch-next.m4a');

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
      expect(nextTrackAfterPrepare.audioUrl,
          'https://stale.example/prefetch-next.m4a');

      final persistedNextTrack =
          await trackRepository.getById(nextTrackAfterPrepare.id);
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
      expect(playingTrackAfterPlay.audioUrl,
          'https://example.com/runtime-boundary.m4a');
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
      expect(audioService.playUrlCalls.single.track,
          isNot(same(queueTrackAfterPlay)));
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

  void throwGetAudioStreamAlways(Object error) {
    _source.throwGetAudioStreamAlways(error);
  }

  void setNextAudioExpiry(Duration? expiry) {
    _source.nextAudioExpiry = expiry;
  }

  @override
  BaseSource? getSource(SourceType type) => _source;

  @override
  void dispose() {}
}

class _GateableLyricsAutoMatchService extends LyricsAutoMatchService {
  _GateableLyricsAutoMatchService(Isar isar)
      : super(
          lrclib: LrclibSource(),
          netease: NeteaseSource(),
          qqmusic: QQMusicSource(),
          repo: LyricsRepository(isar),
          cache: LyricsCacheService(),
          parser: _PassThroughTitleParser(),
        );

  final List<_PendingLyricsMatch> _pending = [];
  final List<Track> calls = [];
  final List<List<String>?> enabledSourceCalls = [];
  final List<_CountWaiter> _waiters = [];

  Completer<void> enqueuePendingResult(bool result) {
    final completer = Completer<void>();
    _pending.add(_PendingLyricsMatch(completer, result));
    return completer;
  }

  Future<void> waitForCallCount(int count) {
    if (calls.length >= count) return Future.value();
    final completer = Completer<void>();
    _waiters.add(_CountWaiter(count, completer));
    return completer.future;
  }

  @override
  Future<bool> tryAutoMatch(
    Track track, {
    List<String>? enabledSources,
    bool? allowPlainLyricsAutoMatch,
  }) async {
    calls.add(track);
    enabledSourceCalls.add(enabledSources);
    for (final waiter in List<_CountWaiter>.from(_waiters)) {
      if (calls.length >= waiter.target && !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _waiters.remove(waiter);
      }
    }
    if (_pending.isEmpty) return false;
    final pending = _pending.removeAt(0);
    await pending.completer.future;
    return pending.result;
  }
}

class _PendingLyricsMatch {
  _PendingLyricsMatch(this.completer, this.result);

  final Completer<void> completer;
  final bool result;
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxPumps = 50,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) return;
    await pumpEventQueue();
  }
  throw StateError('Condition was not met after $maxPumps event pumps');
}

class _PassThroughTitleParser implements TitleParser {
  @override
  ParsedTitle parse(String title, {String? uploader}) {
    return ParsedTitle(
      trackName: title,
      artistName: uploader,
      cleanedTitle: title,
    );
  }
}

class _CountWaiter {
  _CountWaiter(this.target, this.completer);

  final int target;
  final Completer<void> completer;
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
  Object? _alwaysGetAudioStreamError;
  Duration? nextAudioExpiry;

  void throwGetAudioStreamOnce(Object error) {
    _nextGetAudioStreamError = error;
  }

  void throwGetAudioStreamAlways(Object error) {
    _alwaysGetAudioStreamError = error;
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
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    final error = _alwaysGetAudioStreamError ?? _nextGetAudioStreamError;
    if (error != null) {
      if (_alwaysGetAudioStreamError == null) {
        _nextGetAudioStreamError = null;
      }
      throw error;
    }

    final expiry = nextAudioExpiry;
    nextAudioExpiry = null;
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
      expiry: expiry,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async {
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}-fallback.m4a',
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
