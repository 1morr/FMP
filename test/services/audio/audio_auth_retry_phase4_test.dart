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
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_exception.dart';
import 'package:fmp/core/utils/auth_headers_utils.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

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
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
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
        getAuthHeaders: (_) async => null,
      );
      final audioStreamManager = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        settingsRepository: settingsRepository,
      );
      queueManager = QueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: queuePersistenceManager,
      );
      audioService = FakeAudioService();
      networkRecoveryController = StreamController<void>.broadcast();
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
      controller.setupNetworkRecoveryListener(networkRecoveryController.stream);
    });

    tearDown(() async {
      await networkRecoveryController.close();
      controller.dispose();
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('network recovery manual retry restores saved playback position',
        () async {
      final track = _track('retry-track');

      await controller.playTrack(track);
      await pumpEventQueue(times: 10);

      audioService.emitPosition(const Duration(seconds: 47));
      audioService.emitError('network timeout during playback');
      await pumpEventQueue(times: 10);

      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);
      expect(audioService.stopCallCount, 2);

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      await controller.retryManually();
      await pumpEventQueue(times: 20);

      expect(audioService.playUrlCalls.single.url,
          'https://example.com/retry-track.m4a');
      expect(audioService.seekCalls.single, const Duration(seconds: 47));
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isNetworkError, isFalse);
    });

    test('automatic network recovery resumes playback and clears retry state',
        () async {
      final track = _track('auto-recovery-track');

      await controller.playTrack(track);
      await pumpEventQueue(times: 10);

      audioService.emitPosition(const Duration(seconds: 31));
      audioService.emitError('network timeout during playback');
      await pumpEventQueue(times: 10);

      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);
      expect(controller.state.nextRetryAt, isNotNull);
      expect(controller.state.currentTrack?.sourceId, 'auto-recovery-track');

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      networkRecoveryController.add(null);
      await audioService.waitForPlayUrlCallCount(1);
      await audioService.waitForSeekCallCount(1);
      await pumpEventQueue(times: 20);

      expect(audioService.playUrlCalls.single.url,
          'https://example.com/auto-recovery-track.m4a');
      expect(audioService.seekCalls.single, const Duration(seconds: 31));
      expect(controller.state.currentTrack?.sourceId, 'auto-recovery-track');
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isNetworkError, isFalse);
      expect(controller.state.retryAttempt, 0);
      expect(controller.state.nextRetryAt, isNull);
      expect(controller.state.error, isNull);
    });

    test('network error during retry handoff schedules a fresh retry',
        () async {
      final track = _track('handoff-network-error-track');

      await controller.playTrack(track);
      await pumpEventQueue(times: 10);

      audioService.emitPosition(const Duration(seconds: 29));
      audioService.emitError('network timeout during playback');
      await pumpEventQueue(times: 10);

      expect(controller.state.currentTrack?.sourceId, track.sourceId);
      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);
      expect(controller.state.nextRetryAt, isNotNull);

      audioService.playUrlCalls.clear();
      final retryHandoff = audioService.enqueuePendingPlayUrl();

      final manualRetry = controller.retryManually();
      await audioService.waitForPlayUrlCallCount(1);
      await pumpEventQueue(times: 2);

      audioService.emitError('tcp: ffurl_read returned 0xffffd8ba');
      await pumpEventQueue(times: 10);

      retryHandoff.complete();
      await manualRetry;
      await pumpEventQueue(times: 20);

      expect(controller.state.currentTrack?.sourceId, track.sourceId);
      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);
      expect(controller.state.nextRetryAt, isNotNull);
      expect(controller.state.retryAttempt, 0);
    });

    test('mid-track network error completion event does not advance queue',
        () async {
      final firstTrack = _track('network-error-current');
      final secondTrack = _track('network-error-next');

      await controller.playAll([firstTrack, secondTrack]);
      await pumpEventQueue(times: 10);

      audioService.playUrlCalls.clear();
      audioService.setDurationValue(const Duration(minutes: 4));
      audioService.emitPosition(const Duration(minutes: 1));

      audioService.emitCompleted();
      audioService.emitError('tcp: ffurl_read returned 0xffffd8ba');
      await pumpEventQueue(times: 20);

      expect(controller.state.currentTrack?.sourceId, 'network-error-current');
      expect(controller.state.playingTrack?.sourceId, 'network-error-current');
      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);
      expect(audioService.playUrlCalls, isEmpty);
    });

    test('premature completion without error schedules current-track retry',
        () async {
      final firstTrack = _track('premature-complete-current');
      final secondTrack = _track('premature-complete-next');

      await controller.playAll([firstTrack, secondTrack]);
      await pumpEventQueue(times: 10);

      audioService.playUrlCalls.clear();
      audioService.setDurationValue(const Duration(minutes: 5));
      audioService.emitPosition(const Duration(minutes: 4));

      audioService.emitCompleted();
      await pumpEventQueue(times: 20);

      expect(controller.state.currentTrack?.sourceId,
          'premature-complete-current');
      expect(controller.state.playingTrack?.sourceId,
          'premature-complete-current');
      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);
      expect(audioService.playUrlCalls, isEmpty);
    });

    test(
        'network recovery does not restart old track after switch during stabilization',
        () async {
      final oldTrack = _track('old-network-track');
      final newTrack = _track('new-user-track');

      await controller.playTrack(oldTrack);
      await pumpEventQueue(times: 10);

      audioService.emitPosition(const Duration(seconds: 19));
      audioService.emitError('network timeout during playback');
      await pumpEventQueue(times: 10);

      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.currentTrack?.sourceId, 'old-network-track');

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      networkRecoveryController.add(null);
      await pumpEventQueue(times: 2);

      await controller.playTrack(newTrack);
      await pumpEventQueue(times: 10);
      expect(controller.state.currentTrack?.sourceId, 'new-user-track');

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      await Future<void>.delayed(const Duration(milliseconds: 600));
      await pumpEventQueue(times: 20);

      expect(audioService.playUrlCalls, isEmpty);
      expect(audioService.seekCalls, isEmpty);
      expect(controller.state.currentTrack?.sourceId, 'new-user-track');
    });

    test('delayed backend stop from old network error does not retry new track',
        () async {
      final oldTrack = _track('old-delayed-stop-track');
      final newTrack = _track('new-delayed-stop-track');

      await controller.playTrack(oldTrack);
      await pumpEventQueue(times: 10);

      audioService.emitPosition(const Duration(seconds: 21));
      final delayedStop = audioService.enqueuePendingStop();
      audioService.emitError('network timeout during playback');
      await pumpEventQueue(times: 2);

      expect(controller.state.currentTrack?.sourceId, 'old-delayed-stop-track');

      final newPlayback = controller.playTrack(newTrack);

      delayedStop.complete();
      await newPlayback;
      await pumpEventQueue(times: 20);

      expect(controller.state.currentTrack?.sourceId, 'new-delayed-stop-track');
      expect(controller.state.playingTrack?.sourceId, 'new-delayed-stop-track');
      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isNetworkError, isFalse);
      expect(
        audioService.playUrlCalls.where(
          (call) => call.track?.sourceId == 'old-delayed-stop-track',
        ),
        hasLength(1),
      );
    });

    test('typed source network kind schedules retry without string matching',
        () async {
      final track = _track('typed-network-kind');
      const sourceError = _KindOnlySourceException(SourceErrorKind.network);
      sourceManager.source.nextStreamError = sourceError;

      expect(sourceError.kind, SourceErrorKind.network);

      await controller.playTrack(track);
      await pumpEventQueue(times: 20);

      expect(controller.state.isRetrying, isTrue);
      expect(controller.state.isNetworkError, isTrue);
      expect(controller.state.nextRetryAt, isNotNull);
      expect(audioService.playUrlCalls, isEmpty);
    });

    test('typed source permission kind does not schedule network retry',
        () async {
      final track = _track('typed-permission-kind');
      sourceManager.source.nextStreamError = const YouTubeApiException(
        code: 'private_or_inaccessible',
        message: 'private video',
      );

      await controller.playTrack(track);
      await pumpEventQueue(times: 20);

      expect(controller.state.isRetrying, isFalse);
      expect(controller.state.isNetworkError, isFalse);
      expect(controller.state.error, isNotNull);
    });

    test('shared auth header builder keeps netease desktop playback headers',
        () async {
      final headers = await buildAuthHeaders(
        SourceType.netease,
        neteaseAccountService: _HeaderOnlyNeteaseAccountService(isar),
      );

      expect(headers, {
        'Cookie': 'MUSIC_U=music-u; __csrf=csrf',
        'Origin': 'https://music.163.com',
        'Referer': 'https://music.163.com/',
        'User-Agent': NeteaseAccountService.userAgent,
      });
    });
  });
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Tester';
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}

class _RetryAwareSourceManager extends SourceManager {
  _RetryAwareSourceManager() : super(sources: const []);

  final source = _RetryAwareSource();

  @override
  AudioStreamSource? audioStreamSource(SourceType type) => source;

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
  SourceType get sourceType => SourceType.youtube;

  @override
  String toString() => 'semantic source failure';
}

class _RetryAwareSource implements AudioStreamSource {
  Object? nextStreamError;

  @override
  SourceType get sourceType => SourceType.youtube;

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
