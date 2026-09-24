import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/lyrics_auto_match_coordinator.dart';
import 'package:fmp/services/audio/now_playing_publisher.dart';
import 'package:fmp/services/audio/play_history_recorder.dart';
import 'package:fmp/services/audio/playback_capabilities.dart';
import 'package:fmp/services/audio/playback_side_effects.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/just_audio_service.dart';
import 'package:fmp/services/audio/media_kit_audio_service.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_auto_match_service.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:fmp/services/lyrics/title_parser.dart';
import 'package:fmp/services/network/connectivity_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/fakes/fake_audio_service.dart';
import '../../support/fakes/fake_source_auth_context.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';
import '../../support/pump_until.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('audio disposal safety', () {
    late Directory tempDir;
    late Isar isar;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_dispose_test_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'audio_service_dispose_test',
      );

      final settingsRepository = SettingsRepository(isar);
      await settingsRepository.get();
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'provider disposal does not double-dispose owned dependencies',
      () async {
        final audioService = _ThrowOnSecondDisposeAudioService();
        final queueRepository = QueueRepository(isar);
        final trackRepository = TrackRepository(isar);
        final settingsRepository = SettingsRepository(isar);
        final queuePersistenceManager = QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        );
        final queueManager = _ThrowOnSecondDisposeQueueManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          queuePersistenceManager: queuePersistenceManager,
        );
        final container = _createContainer(
          isar: isar,
          audioService: audioService,
          queueManager: queueManager,
          queuePersistenceManager: queuePersistenceManager,
        );

        final controller = container.read(audioControllerProvider.notifier);
        await controller.initialize();
        await drainEventQueue(
          reason: 'let initialization settle before the container is disposed',
        );

        expect(container.dispose, returnsNormally);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(audioService.initializeAfterDisposeCallCount, 0);
        expect(queueManager.initializeAfterDisposeCallCount, 0);
        expect(audioService.disposeCallCount, 1);
        expect(queueManager.disposeCallCount, 1);
      },
    );

    test(
      'provider disposal is safe when container is disposed before scheduled initialization runs',
      () async {
        final audioService = _ThrowOnSecondDisposeAudioService();
        final queueRepository = QueueRepository(isar);
        final trackRepository = TrackRepository(isar);
        final settingsRepository = SettingsRepository(isar);
        final queuePersistenceManager = QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        );
        final queueManager = _ThrowOnSecondDisposeQueueManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          queuePersistenceManager: queuePersistenceManager,
        );
        final container = _createContainer(
          isar: isar,
          audioService: audioService,
          queueManager: queueManager,
          queuePersistenceManager: queuePersistenceManager,
        );

        container.read(audioControllerProvider.notifier);
        expect(container.dispose, returnsNormally);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(audioService.initializeAfterDisposeCallCount, 0);
        expect(queueManager.initializeAfterDisposeCallCount, 0);
        expect(audioService.disposeCallCount, 1);
        expect(queueManager.disposeCallCount, 1);
      },
    );

    test(
      'lyrics setting changes do not dispose the audio controller',
      () async {
        final audioService = _RecordingLifecycleAudioService();
        final queueRepository = QueueRepository(isar);
        final trackRepository = TrackRepository(isar);
        final settingsRepository = SettingsRepository(isar);
        final queuePersistenceManager = QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        );
        final queueManager = _RecordingLifecycleQueueManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          queuePersistenceManager: queuePersistenceManager,
        );
        final plainLyricsSettingProvider = NotifierProvider<_Flag, bool>(
          _Flag.new,
        );
        final container = _createContainer(
          isar: isar,
          audioService: audioService,
          queueManager: queueManager,
          queuePersistenceManager: queuePersistenceManager,
          lyricsAutoMatchServiceFactory: (ref) {
            ref.watch(plainLyricsSettingProvider);
            return LyricsAutoMatchService(
              lrclib: LrclibSource(),
              netease: NeteaseSource(),
              qqmusic: QQMusicSource(),
              repo: LyricsRepository(isar),
              cache: LyricsCacheService(),
              parser: RegexTitleParser(),
            );
          },
        );
        final subscription = container.listen(
          audioControllerProvider,
          (_, _) {},
          fireImmediately: true,
        );

        try {
          final controller = container.read(audioControllerProvider.notifier);
          await controller.initialize();
          await drainEventQueue(
            reason: 'let initialization settle before the setting changes',
          );

          container.read(plainLyricsSettingProvider.notifier).set(true);
          await drainEventQueue(
            reason: 'an unrelated setting must not rebuild the controller',
          );

          expect(
            container.read(audioControllerProvider.notifier),
            same(controller),
          );
          expect(audioService.disposeCallCount, 0);
          expect(queueManager.disposeCallCount, 0);
          expect(audioService.initializeAfterDisposeCallCount, 0);
          expect(queueManager.initializeAfterDisposeCallCount, 0);
        } finally {
          subscription.close();
          container.dispose();
        }
      },
    );

    test(
      'teardown disposes every side effect once, in reverse order',
      () async {
        final audioService = _RecordingLifecycleAudioService();
        final queueRepository = QueueRepository(isar);
        final trackRepository = TrackRepository(isar);
        final settingsRepository = SettingsRepository(isar);
        final queuePersistenceManager = QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        );
        final queueManager = _RecordingLifecycleQueueManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          queuePersistenceManager: queuePersistenceManager,
        );
        // 真的那三個 adapter，外面各包一層只負責記名字的裝飾 —— 順序要守的是
        // registry 的行為，而通知欄那一格還要真的把系統媒體控制交還回去。
        final publisher = testNowPlayingPublisher();
        final disposeOrder = <String>[];
        final effects = [
          _NamedSideEffect(
            'nowPlaying',
            NowPlayingSideEffect(publisher),
            disposeOrder,
          ),
          _NamedSideEffect(
            'history',
            PlayHistorySideEffect(PlayHistoryRecorder()),
            disposeOrder,
          ),
          _NamedSideEffect(
            'lyrics',
            LyricsAutoMatchSideEffect(LyricsAutoMatchCoordinator()),
            disposeOrder,
          ),
        ];
        final registry = PlaybackSideEffectRegistry(effects);
        final container = _createContainer(
          isar: isar,
          audioService: audioService,
          queueManager: queueManager,
          queuePersistenceManager: queuePersistenceManager,
          nowPlayingPublisher: publisher,
          playbackSideEffects: registry,
        );

        final controller = container.read(audioControllerProvider.notifier);
        await controller.initialize();
        await drainEventQueue(
          reason: 'let initialization settle before the container is disposed',
        );
        expect(
          publisher.capabilities,
          PlaybackCapabilities.music,
          reason: 'the controller claims the system media controls on startup',
        );
        final notifiedBefore = effects.map((e) => e.notifications).toList();

        container.dispose();
        await drainEventQueue(reason: 'let the teardown microtasks run out');

        expect(disposeOrder, ['lyrics', 'history', 'nowPlaying']);
        expect(
          publisher.capabilities,
          PlaybackCapabilities.none,
          reason: 'the media control binding is released with the controller',
        );

        // 閂住之後的呼叫既不拋也不記帳。
        expect(
          () => registry
            ..onTrackStarted(_track(), countsAsNewPlay: true)
            ..onPlaybackStateChanged(
              const PlaybackStateSnapshot(
                isPlaying: false,
                position: Duration.zero,
                bufferedPosition: Duration.zero,
                processingState: FmpAudioProcessingState.idle,
              ),
            )
            ..onStopped()
            ..dispose(),
          returnsNormally,
        );
        expect(disposeOrder, ['lyrics', 'history', 'nowPlaying']);
        expect(effects.map((e) => e.notifications), notifiedBefore);
      },
    );

    test(
      'teardown finishes and logs when the backend fails to dispose',
      () async {
        final audioService = _FailingDisposeAudioService();
        final queueRepository = QueueRepository(isar);
        final trackRepository = TrackRepository(isar);
        final settingsRepository = SettingsRepository(isar);
        final queuePersistenceManager = QueuePersistenceManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          settingsRepository: settingsRepository,
        );
        final queueManager = _RecordingLifecycleQueueManager(
          queueRepository: queueRepository,
          trackRepository: trackRepository,
          queuePersistenceManager: queuePersistenceManager,
        );
        final container = _createContainer(
          isar: isar,
          audioService: audioService,
          queueManager: queueManager,
          queuePersistenceManager: queuePersistenceManager,
        );
        final logged = <LogEntry>[];
        final logSubscription = AppLogger.logStream.listen(logged.add);
        addTearDown(logSubscription.cancel);

        final controller = container.read(audioControllerProvider.notifier);
        await controller.initialize();
        await drainEventQueue(
          reason: 'let initialization settle before the container is disposed',
        );

        // 後端的釋放是非同步的，失敗只會出現在它回傳的 future 上。沒人接住的話
        // 那是一個未處理的 async error —— 在 app 裡直接進 zone 的錯誤處理，
        // 在這裡會讓測試失敗。
        expect(container.dispose, returnsNormally);
        // 日誌裡的 error 是 redact 過的字串，不是原物件。
        bool isDisposeFailure(LogEntry entry) =>
            entry.level == LogLevel.error &&
            entry.error == audioService.failure.toString();
        await pumpUntil(
          () => logged.any(isDisposeFailure),
          reason: 'the backend dispose failure is logged',
        );

        expect(audioService.disposeCallCount, 1);
        expect(queueManager.disposeCallCount, 1);
      },
    );

    test(
      'just audio dispose is safe before initialization and on repeat calls',
      () async {
        final service = JustAudioService();

        await service.dispose();
        await service.dispose();
      },
    );

    test(
      'media kit dispose is safe before initialization and on repeat calls',
      () async {
        final service = MediaKitAudioService();

        await service.dispose();
        await service.dispose();
      },
    );
  });
}

ProviderContainer _createContainer({
  required Isar isar,
  required FakeAudioService audioService,
  required QueueManager queueManager,
  required QueuePersistenceManager queuePersistenceManager,
  LyricsAutoMatchService Function(Ref ref)? lyricsAutoMatchServiceFactory,
  NowPlayingPublisher? nowPlayingPublisher,
  PlaybackSideEffect? playbackSideEffects,
}) {
  return ProviderContainer(
    overrides: [
      audioServiceProvider.overrideWith((ref) => audioService),
      nowPlayingPublisherProvider.overrideWithValue(
        nowPlayingPublisher ?? testNowPlayingPublisher(),
      ),
      if (playbackSideEffects != null)
        playbackSideEffectsProvider.overrideWithValue(playbackSideEffects),
      queueManagerProvider.overrideWith((ref) => queueManager),
      queuePersistenceManagerProvider.overrideWith(
        (ref) => queuePersistenceManager,
      ),
      audioStreamManagerProvider.overrideWith((ref) {
        final settingsRepository = SettingsRepository(isar);
        final sourceManager = SourceManager();
        final sourceAuthContext = FakeSourceAuthContext();
        final streamResolutionService = DefaultStreamResolutionService(
          trackRepository: TrackRepository(isar),
          settingsRepository: settingsRepository,
          sourceManager: sourceManager,
          sourceAuthContext: sourceAuthContext,
        );
        ref.onDispose(streamResolutionService.dispose);
        ref.onDispose(sourceManager.dispose);
        return AudioStreamManager(
          streamResolutionService: streamResolutionService,
          sourceAuthContext: sourceAuthContext,
        );
      }),
      connectivityProvider.overrideWith(_TestConnectivityNotifier.new),
      settingsRepositoryProvider.overrideWith(
        (ref) => SettingsRepository(isar),
      ),
      playHistoryRepositoryProvider.overrideWith(
        (ref) => PlayHistoryRepository(isar),
      ),
      neteaseAccountServiceProvider.overrideWith(
        (ref) => _FakeNeteaseAccountService(isar: isar),
      ),
      lyricsAutoMatchServiceProvider.overrideWith(
        lyricsAutoMatchServiceFactory ??
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
}

class _ThrowOnSecondDisposeAudioService extends FakeAudioService {
  int disposeCallCount = 0;
  int initializeAfterDisposeCallCount = 0;
  bool _disposed = false;

  @override
  Future<void> initialize() {
    if (_disposed) {
      initializeAfterDisposeCallCount++;
      throw StateError('audio service initialized after dispose');
    }
    return super.initialize();
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    disposeCallCount++;
    if (disposeCallCount > 1) {
      throw StateError('audio service disposed more than once');
    }
    return super.dispose();
  }
}

/// 釋放時照常收掉假替身自己的資源，然後以非同步錯誤結束 —— 真後端的原生
/// 播放器釋放失敗就是這個形狀。
class _FailingDisposeAudioService extends FakeAudioService {
  final failure = StateError('native player refused to dispose');
  int disposeCallCount = 0;

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    await super.dispose();
    throw failure;
  }
}

class _RecordingLifecycleAudioService extends FakeAudioService {
  int disposeCallCount = 0;
  int initializeAfterDisposeCallCount = 0;
  bool _disposed = false;

  @override
  Future<void> initialize() {
    if (_disposed) {
      initializeAfterDisposeCallCount++;
      return Future.value();
    }
    return super.initialize();
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    if (_disposed) return;
    _disposed = true;
    await super.dispose();
  }
}

class _ThrowOnSecondDisposeQueueManager extends QueueManager {
  _ThrowOnSecondDisposeQueueManager({
    required super.queueRepository,
    required super.trackRepository,
    required super.queuePersistenceManager,
  });

  int disposeCallCount = 0;
  int initializeAfterDisposeCallCount = 0;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      initializeAfterDisposeCallCount++;
      throw StateError('queue manager initialized after dispose');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    disposeCallCount++;
    if (disposeCallCount > 1) {
      throw StateError('queue manager disposed more than once');
    }
  }
}

class _RecordingLifecycleQueueManager extends QueueManager {
  _RecordingLifecycleQueueManager({
    required super.queueRepository,
    required super.trackRepository,
    required super.queuePersistenceManager,
  });

  int disposeCallCount = 0;
  int initializeAfterDisposeCallCount = 0;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      initializeAfterDisposeCallCount++;
    }
  }

  @override
  void dispose() {
    disposeCallCount++;
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

/// 不呼叫 `super.build()`：真的那個會做 DNS 查詢並開一個輪詢計時器。
class _TestConnectivityNotifier extends ConnectivityNotifier {
  final _networkRecoveredController = StreamController<void>.broadcast();

  @override
  ConnectivityState build() {
    ref.onDispose(_networkRecoveredController.close);
    return ConnectivityState.initial;
  }

  @override
  Stream<void> get onNetworkRecovered => _networkRecoveredController.stream;
}

class _FakeNeteaseAccountService extends NeteaseAccountService {
  _FakeNeteaseAccountService({required super.isar});
}

/// 觸發用的旗標 provider。這條測試要看的是「設定變了，控制器不該被重建」。
class _Flag extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// 只記名字的裝飾，其餘原樣轉發給真的 adapter。
class _NamedSideEffect implements PlaybackSideEffect {
  _NamedSideEffect(this.name, this._delegate, this._disposeOrder);

  final String name;
  final PlaybackSideEffect _delegate;
  final List<String> _disposeOrder;

  int notifications = 0;

  @override
  void onTrackStarted(Track track, {required bool countsAsNewPlay}) {
    notifications++;
    _delegate.onTrackStarted(track, countsAsNewPlay: countsAsNewPlay);
  }

  @override
  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot) {
    notifications++;
    _delegate.onPlaybackStateChanged(snapshot);
  }

  @override
  void onStopped() {
    notifications++;
    _delegate.onStopped();
  }

  @override
  void dispose() {
    _disposeOrder.add(name);
    _delegate.dispose();
  }
}

Track _track() => Track()
  ..sourceId = 'after-dispose'
  ..sourceType = 'youtube'
  ..title = 'After Dispose';
