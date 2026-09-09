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
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_exception.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
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

  group('Audio auth retry phase 4', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;
    late _RetryAwareSourceManager sourceManager;
    late FakeAudioService audioService;
    late QueueManager queueManager;
    late DefaultStreamResolutionService streamResolutionService;
    late AudioController controller;
    late StreamController<void> networkRecoveryController;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'audio_auth_retry_phase4_',
      );
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema],
        directory: tempDir.path,
        name: 'audio_auth_retry_phase4_test',
      );

      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
      sourceManager = _RetryAwareSourceManager();
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
      networkRecoveryController = StreamController<void>.broadcast();
      controller = buildTestAudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        nowPlayingPublisher: testNowPlayingPublisher(),
        settingsRepository: settingsRepository,
      );

      await controller.initialize();
      controller.setupNetworkRecoveryListener(networkRecoveryController.stream);
    });

    tearDown(() async {
      await networkRecoveryController.close();
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'network recovery manual retry restores saved playback position',
      () async {
        final track = _track('retry-track');

        await controller.playTrack(track);
        await pumpUntil(
          () => controller.state.isPlaying,
          reason: 'the track should be playing before the transport fails',
        );

        audioService.emitPosition(const Duration(seconds: 47));
        audioService.emitTransportFailure('network timeout during playback');
        await pumpUntil(
          () => controller.state.isRetrying,
          reason: 'a transport failure should start a retry',
        );

        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.isNetworkError, isTrue);
        expect(audioService.stopCallCount, 2);

        audioService.playUrlCalls.clear();
        audioService.seekCalls.clear();

        await controller.retryManually();
        await pumpUntil(
          () =>
              audioService.playUrlCalls.isNotEmpty &&
              audioService.seekCalls.isNotEmpty,
          reason: 'a manual retry should replay and restore the position',
        );

        expect(
          audioService.playUrlCalls.single.url,
          'https://example.com/retry-track.m4a',
        );
        expect(audioService.seekCalls.single, const Duration(seconds: 47));
        expect(controller.state.isRetrying, isFalse);
        expect(controller.state.isNetworkError, isFalse);
      },
    );

    test(
      'automatic network recovery resumes playback and clears retry state',
      () async {
        final track = _track('auto-recovery-track');

        await controller.playTrack(track);
        await pumpUntil(
          () => controller.state.isPlaying,
          reason: 'the track should be playing before the transport fails',
        );

        audioService.emitPosition(const Duration(seconds: 31));
        audioService.emitTransportFailure('network timeout during playback');
        await pumpUntil(
          () => controller.state.isRetrying,
          reason: 'a transport failure should start a retry',
        );

        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.isNetworkError, isTrue);
        expect(controller.state.nextRetryAt, isNotNull);
        expect(controller.state.currentTrack?.sourceId, 'auto-recovery-track');

        audioService.playUrlCalls.clear();
        audioService.seekCalls.clear();

        networkRecoveryController.add(null);
        await audioService.waitForPlayUrlCallCount(1);
        await audioService.waitForSeekCallCount(1);
        await drainEventQueue(
          reason: 'let the recovery finish before the state is judged',
        );

        expect(
          audioService.playUrlCalls.single.url,
          'https://example.com/auto-recovery-track.m4a',
        );
        expect(audioService.seekCalls.single, const Duration(seconds: 31));
        expect(controller.state.currentTrack?.sourceId, 'auto-recovery-track');
        expect(controller.state.isRetrying, isFalse);
        expect(controller.state.isNetworkError, isFalse);
        expect(controller.state.retryAttempt, 0);
        expect(controller.state.nextRetryAt, isNull);
        expect(controller.state.error, isNull);
      },
    );

    test(
      'network error during retry handoff schedules a fresh retry',
      () async {
        final track = _track('handoff-network-error-track');

        await controller.playTrack(track);
        await pumpUntil(
          () => controller.state.isPlaying,
          reason: 'the track should be playing before the transport fails',
        );

        audioService.emitPosition(const Duration(seconds: 29));
        audioService.emitTransportFailure('network timeout during playback');
        await pumpUntil(
          () => controller.state.isRetrying,
          reason: 'a transport failure should start a retry',
        );

        expect(controller.state.currentTrack?.sourceId, track.sourceId);
        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.isNetworkError, isTrue);
        expect(controller.state.nextRetryAt, isNotNull);

        audioService.playUrlCalls.clear();
        final retryHandoff = audioService.enqueuePendingPlayUrl();

        final manualRetry = controller.retryManually();
        await audioService.waitForPlayUrlCallCount(1);
        await drainEventQueue(
          reason: 'let the retry request reach the gated backend call',
        );

        audioService.emitTransportFailure(
          'tcp: ffurl_read returned 0xffffd8ba',
        );
        await drainEventQueue(
          reason: 'let the second failure reach the controller',
        );

        retryHandoff.complete();
        await manualRetry;
        await pumpUntil(
          () => controller.state.nextRetryAt != null,
          reason: 'a failure during the handoff should schedule a fresh retry',
        );

        expect(controller.state.currentTrack?.sourceId, track.sourceId);
        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.isNetworkError, isTrue);
        expect(controller.state.nextRetryAt, isNotNull);
        expect(controller.state.retryAttempt, 0);
      },
    );

    test(
      'mid-track network error completion event does not advance queue',
      () async {
        final firstTrack = _track('network-error-current');
        final secondTrack = _track('network-error-next');

        await controller.playAll([firstTrack, secondTrack]);
        await pumpUntil(
          () => controller.state.isPlaying,
          reason: 'the first track should be playing before it fails',
        );

        audioService.playUrlCalls.clear();
        audioService.setDurationValue(const Duration(minutes: 4));
        audioService.emitPosition(const Duration(minutes: 1));

        audioService.emitCompleted();
        audioService.emitTransportFailure(
          'tcp: ffurl_read returned 0xffffd8ba',
        );
        await pumpUntil(
          () => controller.state.isRetrying,
          reason: 'a mid-track network error should retry, not advance',
        );

        expect(
          controller.state.currentTrack?.sourceId,
          'network-error-current',
        );
        expect(
          controller.state.playingTrack?.sourceId,
          'network-error-current',
        );
        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.isNetworkError, isTrue);
        expect(audioService.playUrlCalls, isEmpty);
      },
    );

    test(
      'premature completion without error schedules current-track retry',
      () async {
        final firstTrack = _track('premature-complete-current');
        final secondTrack = _track('premature-complete-next');

        await controller.playAll([firstTrack, secondTrack]);
        await pumpUntil(
          () => controller.state.isPlaying,
          reason: 'the first track should be playing before it completes',
        );

        audioService.playUrlCalls.clear();
        audioService.setDurationValue(const Duration(minutes: 5));
        audioService.emitPosition(const Duration(minutes: 4));

        audioService.emitCompleted();
        await pumpUntil(
          () => controller.state.isRetrying,
          reason: 'a premature completion should retry the current track',
        );

        expect(
          controller.state.currentTrack?.sourceId,
          'premature-complete-current',
        );
        expect(
          controller.state.playingTrack?.sourceId,
          'premature-complete-current',
        );
        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.isNetworkError, isTrue);
        expect(audioService.playUrlCalls, isEmpty);
      },
    );

    test(
      'network recovery does not restart old track after switch during stabilization',
      () async {
        final oldTrack = _track('old-network-track');
        final newTrack = _track('new-user-track');

        await controller.playTrack(oldTrack);
        await pumpUntil(
          () => controller.state.isPlaying,
          reason: 'the old track should be playing before the transport fails',
        );

        audioService.emitPosition(const Duration(seconds: 19));
        audioService.emitTransportFailure('network timeout during playback');
        await pumpUntil(
          () => controller.state.isRetrying,
          reason: 'a transport failure should start a retry',
        );

        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.currentTrack?.sourceId, 'old-network-track');

        audioService.playUrlCalls.clear();
        audioService.seekCalls.clear();

        networkRecoveryController.add(null);
        await drainEventQueue(
          reason: 'let recovery start while the user switches tracks',
        );

        await controller.playTrack(newTrack);
        await pumpUntil(
          () => controller.state.currentTrack?.sourceId == 'new-user-track',
          reason: 'the user switch should take over the current track',
        );
        expect(controller.state.currentTrack?.sourceId, 'new-user-track');

        audioService.playUrlCalls.clear();
        audioService.seekCalls.clear();

        // 舊軌的穩定化視窗排在 500ms 後；睡過那個時點才有資格說它沒有重啟。
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await drainEventQueue(
          reason:
              'the old track must not restart after the stabilization window',
        );

        expect(audioService.playUrlCalls, isEmpty);
        expect(audioService.seekCalls, isEmpty);
        expect(controller.state.currentTrack?.sourceId, 'new-user-track');
      },
    );

    test(
      'delayed backend stop from old network error does not retry new track',
      () async {
        final oldTrack = _track('old-delayed-stop-track');
        final newTrack = _track('new-delayed-stop-track');

        await controller.playTrack(oldTrack);
        await pumpUntil(
          () => controller.state.isPlaying,
          reason: 'the old track should be playing before the transport fails',
        );

        audioService.emitPosition(const Duration(seconds: 21));
        final delayedStop = audioService.enqueuePendingStop();
        audioService.emitTransportFailure('network timeout during playback');
        await drainEventQueue(
          reason:
              'let the failure reach the controller while the stop is gated',
        );

        expect(
          controller.state.currentTrack?.sourceId,
          'old-delayed-stop-track',
        );

        final newPlayback = controller.playTrack(newTrack);

        delayedStop.complete();
        await newPlayback;
        await pumpUntil(
          () =>
              controller.state.currentTrack?.sourceId ==
              'new-delayed-stop-track',
          reason: 'the newer track should survive the delayed backend stop',
        );

        expect(
          controller.state.currentTrack?.sourceId,
          'new-delayed-stop-track',
        );
        expect(
          controller.state.playingTrack?.sourceId,
          'new-delayed-stop-track',
        );
        expect(controller.state.isRetrying, isFalse);
        expect(controller.state.isNetworkError, isFalse);
        expect(
          audioService.playUrlCalls.where(
            (call) => call.track?.sourceId == 'old-delayed-stop-track',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'typed source network kind schedules retry without string matching',
      () async {
        final track = _track('typed-network-kind');
        const sourceError = _KindOnlySourceException(SourceErrorKind.network);
        sourceManager.source.nextStreamError = sourceError;

        expect(sourceError.kind, SourceErrorKind.network);

        await controller.playTrack(track);
        await pumpUntil(
          () => controller.state.isRetrying,
          reason: 'a typed network error should schedule a retry',
        );

        expect(controller.state.isRetrying, isTrue);
        expect(controller.state.isNetworkError, isTrue);
        expect(controller.state.nextRetryAt, isNotNull);
        expect(audioService.playUrlCalls, isEmpty);
      },
    );

    test(
      'typed source permission kind does not schedule network retry',
      () async {
        final track = _track('typed-permission-kind');
        sourceManager.source.nextStreamError = const YouTubeApiException(
          code: 'private_or_inaccessible',
          message: 'private video',
        );

        await controller.playTrack(track);
        await pumpUntil(
          () => controller.state.error != null,
          reason: 'a permission error should surface instead of retrying',
        );

        expect(controller.state.isRetrying, isFalse);
        expect(controller.state.isNetworkError, isFalse);
        expect(controller.state.error, isNotNull);
      },
    );

    test(
      'account auth loader keeps netease desktop playback headers',
      () async {
        final headers = await AccountServiceAuthLoader(
          neteaseAccountService: _HeaderOnlyNeteaseAccountService(isar),
        ).load(SourceIds.netease);

        expect(headers, {
          'Cookie': 'MUSIC_U=music-u; __csrf=csrf',
          'Origin': 'https://music.163.com',
          'Referer': 'https://music.163.com/',
          'User-Agent': NeteaseAccountService.userAgent,
        });
      },
    );
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceIds.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Tester';
}

class _RetryAwareSourceManager extends SourceManager {
  _RetryAwareSourceManager() : super(sources: const []);

  final source = _RetryAwareSource();

  @override
  AudioStreamSource? audioStreamSource(String type) => source;

  @override
  void dispose() {}
}

class _HeaderOnlyNeteaseAccountService extends NeteaseAccountService {
  _HeaderOnlyNeteaseAccountService(Isar isar) : super(isar: isar);

  @override
  Future<String?> getAuthCookieString() async => 'MUSIC_U=music-u; __csrf=csrf';
}

class _KindOnlySourceException extends SourceApiException {
  const _KindOnlySourceException(this.kind);

  @override
  final SourceErrorKind kind;

  @override
  String get code => 'kind_only';

  @override
  String get message => 'semantic only';

  @override
  String get sourceType => SourceIds.youtube;

  @override
  String toString() => 'semantic source failure';
}

class _RetryAwareSource implements AudioStreamSource {
  Object? nextStreamError;

  @override
  String get sourceType => SourceIds.youtube;

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    final error = nextStreamError;
    if (error != null) {
      nextStreamError = null;
      throw error;
    }

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
    return null;
  }
}
