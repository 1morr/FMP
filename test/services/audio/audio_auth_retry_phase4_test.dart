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
import 'package:fmp/core/utils/auth_headers_utils.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
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

    test('network recovery does not restart old track after switch during stabilization',
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
  _RetryAwareSourceManager() : super();

  final source = _RetryAwareSource();

  @override
  BaseSource? getSource(SourceType type) => source;

  @override
  void dispose() {}
}

class _HeaderOnlyNeteaseAccountService extends NeteaseAccountService {
  _HeaderOnlyNeteaseAccountService(Isar isar) : super(isar: isar);

  @override
  Future<String?> getAuthCookieString() async => 'MUSIC_U=music-u; __csrf=csrf';
}

class _RetryAwareSource extends BaseSource {
  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;

  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<Track> getTrackInfo(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    return _track(sourceId);
  }

  @override
  bool isPlaylistUrl(String url) => false;

  @override
  bool isValidId(String id) => true;

  @override
  String? parseId(String url) => url;

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) {
    throw UnimplementedError();
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
}
