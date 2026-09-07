import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/providers/database/repository_providers.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/services/audio/now_playing_publisher.dart';
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
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';

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

    test('provider disposal does not double-dispose owned dependencies',
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
      await pumpEventQueue(times: 5);

      expect(container.dispose, returnsNormally);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(audioService.initializeAfterDisposeCallCount, 0);
      expect(queueManager.initializeAfterDisposeCallCount, 0);
      expect(audioService.disposeCallCount, 1);
      expect(queueManager.disposeCallCount, 1);
    });

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
    });

    test('lyrics setting changes do not dispose the audio controller',
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
      final plainLyricsSettingProvider = StateProvider<bool>((ref) => false);
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
        (_, __) {},
        fireImmediately: true,
      );

      try {
        final controller = container.read(audioControllerProvider.notifier);
        await controller.initialize();
        await pumpEventQueue(times: 5);

        container.read(plainLyricsSettingProvider.notifier).state = true;
        await pumpEventQueue(times: 10);

        expect(
            container.read(audioControllerProvider.notifier), same(controller));
        expect(audioService.disposeCallCount, 0);
        expect(queueManager.disposeCallCount, 0);
        expect(audioService.initializeAfterDisposeCallCount, 0);
        expect(queueManager.initializeAfterDisposeCallCount, 0);
      } finally {
        subscription.close();
        container.dispose();
      }
    });

    test('just audio dispose is safe before initialization and on repeat calls',
        () async {
      final service = JustAudioService();

      await service.dispose();
      await service.dispose();
    });

    test('media kit dispose is safe before initialization and on repeat calls',
        () async {
      final service = MediaKitAudioService();

      await service.dispose();
      await service.dispose();
    });
  });
}

ProviderContainer _createContainer({
  required Isar isar,
  required FakeAudioService audioService,
  required QueueManager queueManager,
  required QueuePersistenceManager queuePersistenceManager,
  LyricsAutoMatchService Function(Ref ref)? lyricsAutoMatchServiceFactory,
}) {
  return ProviderContainer(
    overrides: [
      audioServiceProvider.overrideWith((ref) => audioService),
      nowPlayingPublisherProvider.overrideWithValue(testNowPlayingPublisher()),
      queueManagerProvider.overrideWith((ref) => queueManager),
      queuePersistenceManagerProvider
          .overrideWith((ref) => queuePersistenceManager),
      audioStreamManagerProvider.overrideWith(
        (ref) {
          final settingsRepository = SettingsRepository(isar);
          final sourceManager = SourceManager();
          final sourceAuthContext = _FakeSourceAuthContext();
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
        },
      ),
      connectivityProvider.overrideWith(_TestConnectivityNotifier.new),
      settingsRepositoryProvider
          .overrideWith((ref) => SettingsRepository(isar)),
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

class _FakeSourceAuthContext implements SourceAuthContext {
  @override
  Future<Map<String, String>?> authForPlay(String sourceType) async => null;

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    return PlaybackNetworkRequest(
      url: url,
      headers: SourceHttpPolicy.mediaHeaders(track.sourceType),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNeteaseAccountService extends NeteaseAccountService {
  _FakeNeteaseAccountService({required super.isar});
}
