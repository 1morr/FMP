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
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_playback_types.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/temporary_play_handler.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TemporaryPlayStateHelper Task 2 regression', () {
    late Directory tempDir;
    late Isar isar;
    late QueueManager queueManager;
    late FakeAudioService audioService;
    late _FakeSourceManager sourceManager;
    late AudioController controller;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
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

      audioService = FakeAudioService();
      controller = AudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        audioHandler: FmpAudioHandler(),
        windowsSmtcHandler: WindowsSmtcHandler(),
        settingsRepository: settingsRepository,
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
      'buildRestorePlan keeps original queue target across chained temporary play',
      () {
        const handler = TemporaryPlayHandler();
        const originalState = TemporaryPlaybackState(
          savedQueueIndex: null,
          savedPosition: null,
          savedWasPlaying: null,
        );

        final firstTemporary = handler.enterTemporary(
          currentMode: PlayMode.queue,
          currentState: originalState,
          hasQueueTrack: true,
          currentIndex: 1,
          currentPosition: const Duration(seconds: 45),
          currentWasPlaying: false,
        );

        final secondTemporary = handler.enterTemporary(
          currentMode: PlayMode.temporary,
          currentState: firstTemporary,
          hasQueueTrack: true,
          currentIndex: 2,
          currentPosition: const Duration(seconds: 7),
          currentWasPlaying: true,
        );

        final restorePlan = handler.buildRestorePlan(
          state: secondTemporary,
          rememberPosition: true,
          rewindSeconds: 10,
        );

        expect(secondTemporary.savedQueueIndex, 1);
        expect(restorePlan, isNotNull);
        expect(restorePlan!.savedIndex, 1);
        expect(restorePlan.savedPosition, const Duration(seconds: 45));
        expect(restorePlan.savedWasPlaying, isFalse);
        expect(restorePlan.rewindSeconds, 10);
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
        await pumpEventQueue(times: 5);
        audioService.setPositionValue(const Duration(seconds: 7));
        audioService.setPlayingValue(true);

        await controller.playTemporary(tempTwo);

        expect(controller.state.currentIndex, 2);
        expect(
          controller.state.upcomingTracks.map((track) => track.sourceId),
          orderedEquals(['queue-b', 'queue-c']),
        );

        audioService.emitCompleted();
        await pumpEventQueue(times: 20);

        expect(controller.state.currentIndex, 1);
        expect(controller.state.playingTrack?.sourceId, 'queue-b');
        expect(controller.state.currentTrack?.sourceId, 'queue-b');
        expect(audioService.setUrlCalls.last.url,
            'https://example.com/queue-b.m4a');
        expect(audioService.seekCalls.last, const Duration(seconds: 35));
        expect(controller.state.isPlaying, isFalse);
      },
    );
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
    'Unsupported platform for Isar test setup: ${Platform.operatingSystem}',
  );
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

  @override
  BaseSource? getSource(SourceType type) => _source;

  @override
  void dispose() {}
}

class _FakeSource extends BaseSource {
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
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Track> getTrackInfo(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    return _track(sourceId, title: sourceId);
  }

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
