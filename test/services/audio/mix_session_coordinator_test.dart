import 'dart:async';
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
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_session_coordinator.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
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

  /// `MixSessionCoordinator` 是 Phase 4 步驟 D 抽出來的第三個副作用協作者。
  ///
  /// 它吸收了原本的 `MixPlaylistHandler`（工作階段身分 + 載入旗標）與原本留在
  /// `AudioController` 的預取（觸發門檻、重試迴圈、in-flight future）。合併的理由
  /// 就是這裡第一條測試在守的東西：那兩組狀態過去是分開的欄位，每一條離開 Mix 的
  /// 路徑都得記得清兩次。
  group('MixSessionCoordinator', () {
    late Directory coordinatorTempDir;
    late Isar coordinatorIsar;
    late QueueManager coordinatorQueue;
    late _TestMixTracksFetcher fetcher;
    late List<bool> loadingStates;
    late int queueChangedCount;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      coordinatorTempDir = await Directory.systemTemp.createTemp(
        'mix_coordinator_',
      );
      coordinatorIsar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: coordinatorTempDir.path,
        name: 'mix_coordinator_test',
      );
      coordinatorQueue = _buildQueueManager(coordinatorIsar);
      await coordinatorQueue.initialize();
      fetcher = _TestMixTracksFetcher();
      loadingStates = [];
      queueChangedCount = 0;
    });

    tearDown(() async {
      coordinatorQueue.dispose();
      await coordinatorIsar.close(deleteFromDisk: true);
      if (await coordinatorTempDir.exists()) {
        await coordinatorTempDir.delete(recursive: true);
      }
    });

    MixSessionCoordinator build({bool withFetcher = true}) =>
        MixSessionCoordinator(
          queueManager: coordinatorQueue,
          toastService: ToastService(),
          fetcher: withFetcher ? fetcher.call : null,
          onLoadingChanged: loadingStates.add,
          onQueueChanged: () => queueChangedCount++,
        );

    Future<void> seedQueue(int count) async {
      await coordinatorQueue.playAll(
        List.generate(count, (i) => _track('seed-$i', title: 'Seed $i')),
        startIndex: count - 1,
      );
    }

    QueueRestoreState restoreState({
      required bool isMixMode,
      String? playlistId = 'RD-restored',
      String? seedVideoId = 'seed-restored',
      String? title = 'Restored Mix',
    }) {
      final queue = PlayQueue()..isMixMode = isMixMode;
      return QueueRestoreState(
        queue: queue,
        tracks: const [],
        currentIndex: 0,
        savedPosition: Duration.zero,
        savedVolume: 1,
        mixPlaylistId: playlistId,
        mixSeedVideoId: seedVideoId,
        mixTitle: title,
      );
    }

    test(
      'restoreFrom picks the session back up and marks the queue seen',
      () async {
        final coordinator = build();
        await seedQueue(2);

        final session = coordinator.restoreFrom(restoreState(isMixMode: true));

        expect(session, isNotNull);
        expect(session!.title, 'Restored Mix');
        expect(coordinator.current, same(session));
        // 佇列裡已經有的兩首不該再被抓一次。
        expect(session.seenVideoIds, containsAll(<String>['seed-0', 'seed-1']));
      },
    );

    test('restoreFrom refuses a mix whose metadata is incomplete', () {
      final coordinator = build();

      // 少了任何一個欄位，之後的預取都抓不到東西 —— 寧可退回一般佇列，也不要
      // 一個永遠加載不出下一批的假 Mix。
      expect(
        coordinator.restoreFrom(
          restoreState(isMixMode: true, playlistId: null),
        ),
        isNull,
      );
      expect(
        coordinator.restoreFrom(
          restoreState(isMixMode: true, seedVideoId: null),
        ),
        isNull,
      );
      expect(
        coordinator.restoreFrom(restoreState(isMixMode: true, title: null)),
        isNull,
      );
      expect(coordinator.current, isNull);
    });

    test('restoreFrom ignores a queue that was not in mix mode', () {
      final coordinator = build();

      expect(coordinator.restoreFrom(null), isNull);
      expect(coordinator.restoreFrom(restoreState(isMixMode: false)), isNull);
      expect(coordinator.current, isNull);
    });

    test(
      'exit clears the session and the in-flight prefetch together',
      () async {
        final coordinator = build();
        await seedQueue(2);
        final gate = fetcher.enqueuePendingResult(
          const MixFetchResult(title: 'Mix', tracks: []),
        );
        coordinator.start(
          playlistId: 'RD-1',
          seedVideoId: 'seed-0',
          title: 'Mix',
        );
        coordinator.onTrackStarted(PlayMode.mix);
        expect(coordinator.pendingLoad, isNotNull);

        coordinator.exit();

        // 過去這兩件事是兩個欄位，離開路徑要記得各清一次。
        expect(coordinator.current, isNull);
        expect(coordinator.pendingLoad, isNull);
        gate.complete();
        await drainEventQueue(
          reason: 'let the cancelled load unwind before teardown',
        );
      },
    );

    test('a stale session cannot append into the queue of a new one', () async {
      final coordinator = build();
      await seedQueue(2);
      final staleGate = fetcher.enqueuePendingResult(
        MixFetchResult(
          title: 'Stale',
          tracks: [_track('stale-0', title: 'Stale 0')],
        ),
      );
      coordinator.start(
        playlistId: 'RD-stale',
        seedVideoId: 'seed-0',
        title: 'Stale',
      );
      coordinator.onTrackStarted(PlayMode.mix);

      // 舊工作階段還在抓的時候換成新的。
      coordinator.start(
        playlistId: 'RD-active',
        seedVideoId: 'seed-1',
        title: 'Active',
      );
      staleGate.complete();
      await drainEventQueue(
        reason: 'the stale session must not append into the newer queue',
      );

      expect(
        coordinatorQueue.tracks.map((t) => t.sourceId),
        isNot(contains('stale-0')),
      );
      expect(queueChangedCount, 0);
    });

    test('only mix mode prefetches', () async {
      final coordinator = build();
      await seedQueue(2);
      coordinator.start(
        playlistId: 'RD-1',
        seedVideoId: 'seed-0',
        title: 'Mix',
      );

      coordinator.onTrackStarted(PlayMode.queue);

      expect(coordinator.pendingLoad, isNull);
      expect(fetcher.callCount, 0);
    });

    test(
      'a second trigger while one is in flight does not start another',
      () async {
        final coordinator = build();
        await seedQueue(2);
        final gate = fetcher.enqueuePendingResult(
          const MixFetchResult(title: 'Mix', tracks: []),
        );
        coordinator.start(
          playlistId: 'RD-1',
          seedVideoId: 'seed-0',
          title: 'Mix',
        );

        coordinator.onTrackStarted(PlayMode.mix);
        final first = coordinator.pendingLoad;
        coordinator.onTrackStarted(PlayMode.mix);

        expect(coordinator.pendingLoad, same(first));
        gate.complete();
        await drainEventQueue(
          reason: 'let the single pending load finish before teardown',
        );
      },
    );

    test(
      'reports loading back to the caller instead of touching state',
      () async {
        final coordinator = build();
        await seedQueue(2);
        final gate = fetcher.enqueuePendingResult(
          MixFetchResult(
            title: 'Mix',
            tracks: List.generate(10, (i) => _track('new-$i', title: 'New $i')),
          ),
        );
        coordinator.start(
          playlistId: 'RD-1',
          seedVideoId: 'seed-0',
          title: 'Mix',
        );

        coordinator.onTrackStarted(PlayMode.mix);
        await pumpUntil(
          () => loadingStates.isNotEmpty,
          reason: 'starting a mix track should report loading to the caller',
        );
        expect(loadingStates, [true]);

        gate.complete();
        // 佇列寫入是真的 Isar 交易，固定次數的 pump 不是可靠的同步點。
        await pumpUntil(
          () => loadingStates.length >= 2,
          reason: 'the load should report back when it finishes',
        );

        expect(loadingStates, [true, false]);
        expect(queueChangedCount, 1);
        expect(coordinatorQueue.tracks, hasLength(12));
      },
    );

    test('without a fetcher it gives up instead of hanging', () async {
      final coordinator = build(withFetcher: false);
      await seedQueue(2);
      coordinator.start(
        playlistId: 'RD-1',
        seedVideoId: 'seed-0',
        title: 'Mix',
      );

      coordinator.onTrackStarted(PlayMode.mix);
      await pumpUntil(
        () => loadingStates.length >= 2,
        reason: 'a missing fetcher should report loading and then give up',
      );

      expect(coordinator.canFetch, isFalse);
      expect(loadingStates, [true, false]);
      expect(coordinator.pendingLoad, isNull);
    });
  });
  group('Mix session Task 3 regression', () {
    late Directory tempDir;
    late Isar isar;
    late QueueRepository queueRepository;
    late QueueManager queueManager;
    late FakeAudioService audioService;
    late _FakeSourceManager sourceManager;
    late _TestMixTracksFetcher mixTracksFetcher;
    late DefaultStreamResolutionService streamResolutionService;
    late AudioController controller;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mix_session_handler_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'mix_session_handler_test',
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
      mixTracksFetcher = _TestMixTracksFetcher();
      controller = buildTestAudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        nowPlayingPublisher: testNowPlayingPublisher(),
        settingsRepository: settingsRepository,
        mixTracksFetcher: mixTracksFetcher.call,
      );

      await controller.initialize();
    });

    tearDown(() async {
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'clearing an active loading mix session removes ownership and visible loading state',
      () async {
        final loadMoreGate = mixTracksFetcher.enqueuePendingResult(
          const MixFetchResult(title: 'First Mix', tracks: []),
        );

        await controller.playMixPlaylist(
          playlistId: 'RDmix-1',
          seedVideoId: 'seed-1',
          title: 'First Mix',
          tracks: [
            _track('mix-1-a', title: 'Mix 1 A'),
            _track('mix-1-b', title: 'Mix 1 B'),
          ],
          startIndex: 1,
        );
        await pumpUntil(
          () =>
              controller.queueState.isMixMode &&
              controller.queueState.isLoadingMoreMix,
          reason: 'the mix should enter load-more before the queue is cleared',
        );

        expect(controller.queueState.isMixMode, isTrue);
        expect(controller.queueState.mixTitle, 'First Mix');
        expect(controller.queueState.isLoadingMoreMix, isTrue);

        await controller.clearQueue();
        await pumpUntil(
          () => !controller.queueState.isMixMode,
          reason: 'clearing the queue should leave mix mode',
        );

        loadMoreGate.complete();
        await drainEventQueue(
          reason: 'the stale load-more must not revive mix mode',
        );

        expect(controller.queueState.isMixMode, isFalse);
        expect(controller.queueState.mixTitle, isNull);
        expect(controller.queueState.isLoadingMoreMix, isFalse);
        expect(controller.queueState.upcomingTracks, isEmpty);
      },
    );

    test(
      'replacing a loading mix session keeps stale load-more work from affecting the new session',
      () async {
        final staleLoadGate = mixTracksFetcher.enqueuePendingResult(
          const MixFetchResult(title: 'Old Mix', tracks: []),
        );

        await controller.playMixPlaylist(
          playlistId: 'RDmix-old',
          seedVideoId: 'seed-old',
          title: 'Old Mix',
          tracks: [
            _track('old-a', title: 'Old A'),
            _track('old-b', title: 'Old B'),
          ],
          startIndex: 1,
        );
        await pumpUntil(
          () =>
              controller.queueState.mixTitle == 'Old Mix' &&
              controller.queueState.isLoadingMoreMix,
          reason: 'the old mix should be loading more before it is replaced',
        );

        expect(controller.queueState.isMixMode, isTrue);
        expect(controller.queueState.mixTitle, 'Old Mix');
        expect(controller.state.currentTrack?.sourceId, 'old-b');
        expect(controller.queueState.isLoadingMoreMix, isTrue);

        await controller.playMixPlaylist(
          playlistId: 'RDmix-new',
          seedVideoId: 'seed-new',
          title: 'New Mix',
          tracks: [
            _track('new-a', title: 'New A'),
            _track('new-b', title: 'New B'),
          ],
          startIndex: 0,
        );
        await pumpUntil(
          () =>
              controller.queueState.mixTitle == 'New Mix' &&
              controller.state.currentTrack?.sourceId == 'new-a',
          reason: 'the newer mix should take over the queue',
        );

        expect(controller.queueState.isMixMode, isTrue);
        expect(controller.queueState.mixTitle, 'New Mix');
        expect(controller.state.currentTrack?.sourceId, 'new-a');
        expect(controller.state.playingTrack?.sourceId, 'new-a');
        expect(controller.queueState.isLoadingMoreMix, isFalse);

        staleLoadGate.complete();
        await drainEventQueue(
          reason: 'the stale load must not overwrite the newer mix',
        );

        expect(controller.queueState.isMixMode, isTrue);
        expect(controller.queueState.mixTitle, 'New Mix');
        expect(controller.state.currentTrack?.sourceId, 'new-a');
        expect(controller.state.playingTrack?.sourceId, 'new-a');
        expect(controller.queueState.isLoadingMoreMix, isFalse);
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

class _TestMixTracksFetcher {
  final List<_PendingMixFetch> _pending = [];
  int callCount = 0;

  Completer<void> enqueuePendingResult(MixFetchResult result) {
    final completer = Completer<void>();
    _pending.add(_PendingMixFetch(completer, result));
    return completer;
  }

  Future<MixFetchResult> call({
    required String playlistId,
    required String currentVideoId,
  }) async {
    callCount++;
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
}

QueueManager _buildQueueManager(Isar isar) {
  final queueRepository = QueueRepository(isar);
  final trackRepository = TrackRepository(isar);
  return QueueManager(
    queueRepository: queueRepository,
    trackRepository: trackRepository,
    queuePersistenceManager: QueuePersistenceManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      settingsRepository: SettingsRepository(isar),
    ),
  );
}
