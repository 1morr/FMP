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
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/temporary_play_handler.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/audio_controller_harness.dart';
import '../../support/fakes/fake_audio_service.dart';
import '../../support/fakes/fake_source_auth_context.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';
import '../../support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TemporaryPlayStateHelper Task 2 regression', () {
    late Directory tempDir;
    late Isar isar;
    late QueueManager queueManager;
    late FakeAudioService audioService;
    late _FakeSourceManager sourceManager;
    late DefaultStreamResolutionService streamResolutionService;
    late AudioController controller;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'temporary_play_handler_',
      );
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'temporary_play_handler_test',
      );

      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      final settingsRepository = SettingsRepository(isar);
      sourceManager = _FakeSourceManager();
      final queuePersistenceManager = QueuePersistenceManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
      );
      streamResolutionService = DefaultStreamResolutionService(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
        sourceAuthContext: FakeSourceAuthContext(),
      );
      final audioStreamManager = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: FakeSourceAuthContext(),
      );
      queueManager = QueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: queuePersistenceManager,
      );

      audioService = FakeAudioService();
      controller = buildTestAudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        nowPlayingPublisher: testNowPlayingPublisher(),
        settingsRepository: settingsRepository,
      );

      final settings = await settingsRepository.get();
      settings.rememberPlaybackPosition = true;
      settings.tempPlayRewindSeconds = 10;
      await settingsRepository.save(settings);

      await controller.initialize();
    });

    tearDown(() async {
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('buildQueueRestorePlan keeps queue restore shape inside handler', () {
      final handler = TemporaryPlayHandler();

      final restorePlan = handler.buildQueueRestorePlan(
        savedQueueIndex: 2,
        savedPosition: const Duration(seconds: 28),
        savedWasPlaying: true,
      );

      expect(restorePlan, isNotNull);
      expect(restorePlan!.savedIndex, 2);
      expect(restorePlan.savedPosition, const Duration(seconds: 28));
      expect(restorePlan.savedWasPlaying, isTrue);
      expect(restorePlan.rewindSeconds, 0);
    });

    test(
      'buildRestorePlan keeps original queue target across chained temporary play',
      () {
        final handler = TemporaryPlayHandler();

        handler.enterTemporary(
          currentMode: PlayMode.queue,
          hasQueueTrack: true,
          currentIndex: 1,
          currentPosition: const Duration(seconds: 45),
          currentWasPlaying: false,
        );

        // 已經在臨時播放中：第二次進來必須保留最早那份快照。
        handler.enterTemporary(
          currentMode: PlayMode.temporary,
          hasQueueTrack: true,
          currentIndex: 2,
          currentPosition: const Duration(seconds: 7),
          currentWasPlaying: true,
        );

        final restorePlan = handler.buildRestorePlan(
          rememberPosition: true,
          rewindSeconds: 10,
        );

        expect(handler.savedQueueIndex, 1);
        expect(restorePlan, isNotNull);
        expect(restorePlan!.savedIndex, 1);
        expect(restorePlan.savedPosition, const Duration(seconds: 45));
        expect(restorePlan.savedWasPlaying, isFalse);
        expect(restorePlan.rewindSeconds, 10);
      },
    );

    test('entering with no queue track leaves nothing to restore', () {
      final handler = TemporaryPlayHandler();

      handler.enterTemporary(
        currentMode: PlayMode.queue,
        hasQueueTrack: false,
        currentIndex: 3,
        currentPosition: const Duration(seconds: 12),
        currentWasPlaying: true,
      );

      expect(handler.hasSavedState, isFalse);
      expect(
        handler.buildRestorePlan(rememberPosition: true, rewindSeconds: 10),
        isNull,
      );
    });

    test('clear drops the snapshot so nothing can be restored from it', () {
      final handler = TemporaryPlayHandler();

      handler.enterTemporary(
        currentMode: PlayMode.queue,
        hasQueueTrack: true,
        currentIndex: 4,
        currentPosition: const Duration(seconds: 33),
        currentWasPlaying: true,
      );
      expect(handler.hasSavedState, isTrue);

      handler.clear();

      expect(handler.hasSavedState, isFalse);
      expect(handler.savedQueueIndex, isNull);
      expect(
        handler.buildRestorePlan(rememberPosition: true, rewindSeconds: 10),
        isNull,
      );
    });

    test('buildQueueRestorePlan ignores the handler own snapshot', () {
      final handler = TemporaryPlayHandler();

      handler.enterTemporary(
        currentMode: PlayMode.queue,
        hasQueueTrack: true,
        currentIndex: 1,
        currentPosition: const Duration(seconds: 45),
        currentWasPlaying: false,
      );

      // 電台返回帶的是 RadioController 存的快照，不是這個 handler 存的。
      final restorePlan = handler.buildQueueRestorePlan(
        savedQueueIndex: 7,
        savedPosition: const Duration(seconds: 5),
        savedWasPlaying: true,
      );

      expect(restorePlan!.savedIndex, 7);
      expect(restorePlan.savedPosition, const Duration(seconds: 5));
      expect(restorePlan.savedWasPlaying, isTrue);
    });

    test(
      'forgetting position restores from the queue start without rewind',
      () {
        final handler = TemporaryPlayHandler();

        handler.enterTemporary(
          currentMode: PlayMode.queue,
          hasQueueTrack: true,
          currentIndex: 2,
          currentPosition: const Duration(seconds: 45),
          currentWasPlaying: true,
        );

        final restorePlan = handler.buildRestorePlan(
          rememberPosition: false,
          rewindSeconds: 10,
        );

        expect(restorePlan!.savedIndex, 2);
        expect(restorePlan.savedPosition, Duration.zero);
        expect(restorePlan.savedWasPlaying, isTrue);
        expect(restorePlan.rewindSeconds, 0);
      },
    );

    test(
      'second temporary play preserves the original queue index position and play state',
      () async {
        final queueTracks = [
          _track('queue-a', title: 'Queue A'),
          _track('queue-b', title: 'Queue B'),
          _track('queue-c', title: 'Queue C'),
        ];
        final tempOne = _track('temp-1', title: 'Temp One');
        final tempTwo = _track('temp-2', title: 'Temp Two');

        await controller.playAll(queueTracks, startIndex: 1);
        await controller.seekTo(const Duration(seconds: 45));
        audioService.setPositionValue(const Duration(seconds: 45));
        audioService.setPlayingValue(false);

        await controller.playTemporary(tempOne);

        queueManager.setCurrentIndex(2);
        await pumpUntil(
          () => controller.queueState.currentIndex == 2,
          reason: 'the queue index move should reach the controller state',
        );
        audioService.setPositionValue(const Duration(seconds: 7));
        audioService.setPlayingValue(true);

        await controller.playTemporary(tempTwo);

        expect(controller.queueState.currentIndex, 2);
        expect(
          controller.queueState.upcomingTracks.map((track) => track.sourceId),
          orderedEquals(['queue-b', 'queue-c']),
        );

        audioService.setUrlCalls.clear();
        audioService.seekCalls.clear();
        final restoreSetUrl = audioService.waitForSetUrlCallCount(1);
        final restoreSeek = audioService.waitForSeekCallCount(1);

        audioService.emitNaturalCompletion();
        await restoreSetUrl;
        await restoreSeek;
        await pumpUntil(
          () => controller.state.playingTrack?.sourceId == 'queue-b',
          reason: 'the temporary track should restore the saved queue entry',
        );

        expect(controller.queueState.currentIndex, 1);
        expect(controller.state.playingTrack?.sourceId, 'queue-b');
        expect(controller.state.currentTrack?.sourceId, 'queue-b');
        expect(
          audioService.setUrlCalls.single.url,
          'https://example.com/queue-b.m4a',
        );
        expect(audioService.seekCalls.single, const Duration(seconds: 35));
        expect(controller.state.isPlaying, isFalse);
      },
    );
  });
}

Track _track(String sourceId, {required String title}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceIds.youtube
    ..title = title
    ..artist = 'Tester';
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super(sources: const []);

  final _source = _FakeSource();

  @override
  AudioStreamSource? audioStreamSource(String type) => _source;

  @override
  void dispose() {}
}

class _FakeSource implements AudioStreamSource {
  @override
  String get sourceType => SourceIds.youtube;

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
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
  Future<Track> refreshAudioUrl(
    Track track, {
    Map<String, String>? authHeaders,
  }) async {
    track.audioUrl = 'https://example.com/${track.sourceId}.m4a';
    track.audioUrlExpiry = DateTime.now().add(const Duration(minutes: 30));
    return track;
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    return SearchResult.empty();
  }

  @override
  void dispose() {}
}
