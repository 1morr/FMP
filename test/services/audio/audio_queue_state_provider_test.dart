import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/constants/app_constants.dart';
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
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('queueStateProvider', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    late _AudioControllerHarness harness;

    setUp(() async {
      harness = await _AudioControllerHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test(
        'queueProvider follows queueStateProvider instead of PlayerState queue',
        () async {
      final firstQueue = [_track('one')];
      final secondQueue = [_track('two')];

      harness.container.read(queueStateProvider.notifier).state =
          QueueState(queue: firstQueue, queueVersion: 1);
      expect(harness.container.read(queueProvider), firstQueue);

      harness.container.read(audioControllerProvider.notifier).state =
          harness.container.read(audioControllerProvider).copyWith(
                queue: secondQueue,
                position: const Duration(seconds: 30),
              );

      expect(harness.container.read(queueProvider), firstQueue);
    });

    test('controller queue updates publish through queueStateProvider wiring',
        () async {
      await harness.container.read(audioControllerProvider.notifier).addToQueue(
            _track('wired'),
          );

      final queueState = harness.container.read(queueStateProvider);
      expect(
          harness.container.read(queueProvider).map((track) => track.sourceId),
          ['wired']);
      expect(queueState.queue.map((track) => track.sourceId), ['wired']);
      expect(queueState.queueVersion, greaterThan(0));
    });

    test('mix load-more flag stays synchronized in queueStateProvider',
        () async {
      final loadMoreGate = harness.mixTracksFetcher.enqueuePendingResult(
        MixFetchResult(
          title: 'My Mix',
          tracks: List.generate(
            AppConstants.mixMinNewTracksRequired,
            (index) => _track('mix-new-$index'),
          ),
        ),
      );

      await harness.container
          .read(audioControllerProvider.notifier)
          .playMixPlaylist(
            playlistId: 'RDqueue-state-mix',
            seedVideoId: 'seed',
            title: 'My Mix',
            tracks: [
              _track('mix-a'),
              _track('mix-b'),
            ],
            startIndex: 1,
          );
      await pumpEventQueue(times: 5);

      expect(harness.container.read(queueStateProvider).isMixMode, isTrue);
      expect(harness.container.read(queueStateProvider).mixTitle, 'My Mix');
      expect(
          harness.container.read(queueStateProvider).isLoadingMoreMix, isTrue);

      loadMoreGate.complete();
      await _waitUntil(
        () => !harness.container.read(queueStateProvider).isLoadingMoreMix,
      );

      expect(harness.container.read(queueStateProvider).isMixMode, isTrue);
      expect(harness.container.read(queueStateProvider).mixTitle, 'My Mix');
      expect(
          harness.container.read(queueStateProvider).isLoadingMoreMix, isFalse);
    });
  });
}

Track _track(String sourceId) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceType.youtube
  ..title = sourceId;

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _AudioControllerHarness {
  _AudioControllerHarness({
    required this.tempDir,
    required this.isar,
    required this.controller,
    required this.container,
    required this.mixTracksFetcher,
  });

  final Directory tempDir;
  final Isar isar;
  final AudioController controller;
  final ProviderContainer container;
  final _TestMixTracksFetcher mixTracksFetcher;

  static Future<_AudioControllerHarness> create() async {
    final tempDir =
        await Directory.systemTemp.createTemp('audio_queue_state_provider_');
    final isar = await Isar.open(
      [TrackSchema, PlayQueueSchema, SettingsSchema],
      directory: tempDir.path,
      name: 'audio_queue_state_provider_test',
    );
    final queueRepository = QueueRepository(isar);
    final trackRepository = TrackRepository(isar);
    final settingsRepository = SettingsRepository(isar);
    final sourceManager = _FakeSourceManager();
    final queuePersistenceManager = QueuePersistenceManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
    );
    final queueManager = QueueManager(
      queueRepository: queueRepository,
      trackRepository: trackRepository,
      queuePersistenceManager: queuePersistenceManager,
    );
    final audioStreamManager = AudioStreamManager(
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
      sourceManager: sourceManager,
    );
    final mixTracksFetcher = _TestMixTracksFetcher();
    final controller = AudioController(
      audioService: FakeAudioService(),
      queueManager: queueManager,
      audioStreamManager: audioStreamManager,
      toastService: ToastService(),
      audioHandler: FmpAudioHandler(),
      windowsSmtcHandler: WindowsSmtcHandler(),
      settingsRepository: settingsRepository,
      mixTracksFetcher: mixTracksFetcher.call,
    );
    final container = ProviderContainer(
      overrides: [
        audioControllerProvider.overrideWith((ref) => controller),
      ],
    );
    controller.onQueueStateChanged = (queueState) {
      container.read(queueStateProvider.notifier).state = queueState;
    };
    await controller.initialize();

    return _AudioControllerHarness(
      tempDir: tempDir,
      isar: isar,
      controller: controller,
      container: container,
      mixTracksFetcher: mixTracksFetcher,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    controller.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
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
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1, int pageSize = 20, Map<String, String>? authHeaders}) {
    throw UnimplementedError();
  }

  @override
  Future<Track> getTrackInfo(String sourceId,
      {Map<String, String>? authHeaders}) async {
    return _track(sourceId);
  }

  @override
  Future<AudioStreamResult> getAudioStream(String sourceId,
      {AudioStreamConfig config = AudioStreamConfig.defaultConfig,
      Map<String, String>? authHeaders}) async {
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

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic>) continue;
    if (package['name'] != 'isar_flutter_libs') continue;

    final rootUri = package['rootUri'] as String;
    final packageDir =
        Directory(packageConfigDir.uri.resolve(rootUri).toFilePath());

    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
