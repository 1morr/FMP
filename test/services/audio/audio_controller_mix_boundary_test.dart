import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';
import 'package:isar/isar.dart';

import '../../support/fakes/fake_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioController mix boundary', () {
    late Directory tempDir;
    late Isar isar;
    late QueueRepository queueRepository;
    late QueueManager queueManager;
    late FakeAudioService audioService;
    late _FakeSourceManager sourceManager;
    late SettingsRepository settingsRepository;
    late DefaultStreamResolutionService streamResolutionService;
    late AudioController controller;
    late _RecordingMixTracksFetcher mixTracksFetcher;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_controller_mix_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema, PlaylistSchema],
        directory: tempDir.path,
        name: 'audio_controller_mix_boundary_test',
      );

      queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
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
        sourceAuthContext: _FakeSourceAuthContext(),
      );
      final audioStreamManager = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: _FakeSourceAuthContext(),
      );
      queueManager = QueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: queuePersistenceManager,
      );

      audioService = FakeAudioService();
      mixTracksFetcher = _RecordingMixTracksFetcher();
      controller = AudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: audioStreamManager,
        toastService: ToastService(),
        audioHandler: FmpAudioHandler(),
        windowsSmtcHandler: WindowsSmtcHandler(),
        settingsRepository: settingsRepository,
        queuePersistenceManager: queuePersistenceManager,
        mixTracksFetcher: mixTracksFetcher.call,
      );

      await controller.initialize();
    });

    tearDown(() async {
      controller.dispose();
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'restoring a persisted mix session at queue end schedules load-more runtime state',
        () async {
      controller.dispose();

      final trackRepository = TrackRepository(isar);
      final queuePersistenceManager = QueuePersistenceManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
      );
      final persistedTracks = await trackRepository.getOrCreateAll([
        _track('restored-a', title: 'Restored A'),
        _track('restored-b', title: 'Restored B'),
      ]);
      final persistedQueue = await queueRepository.getOrCreate();
      persistedQueue.trackIds =
          persistedTracks.map((track) => track.id).toList();
      persistedQueue.currentIndex = 1;
      persistedQueue.isMixMode = true;
      persistedQueue.mixPlaylistId = 'RDrestore123';
      persistedQueue.mixSeedVideoId = 'seed-restore';
      persistedQueue.mixTitle = 'Restored Mix';
      await queueRepository.save(persistedQueue);

      final source = await File(
        '${Directory.current.path}/lib/services/audio/audio_provider.dart',
      ).readAsString();
      expect(source.contains('_queueManager.isMixMode'), isFalse);
      expect(source.contains('_queueManager.mixPlaylistId'), isFalse);
      expect(source.contains('_queueManager.mixSeedVideoId'), isFalse);
      expect(source.contains('_queueManager.mixTitle'), isFalse);

      final loadMoreTracks = List.generate(
        10,
        (index) => _track('restored-new-$index', title: 'Restored New $index'),
      );
      final loadMoreGate = mixTracksFetcher.enqueuePendingResult(
        MixFetchResult(title: 'Restored Mix', tracks: loadMoreTracks),
      );
      streamResolutionService.dispose();
      streamResolutionService = DefaultStreamResolutionService(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: sourceManager,
        sourceAuthContext: _FakeSourceAuthContext(),
      );
      final audioStreamManager = AudioStreamManager(
        streamResolutionService: streamResolutionService,
        sourceAuthContext: _FakeSourceAuthContext(),
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
        queuePersistenceManager: queuePersistenceManager,
        mixTracksFetcher: mixTracksFetcher.call,
      );

      await controller.initialize();
      await pumpEventQueue(times: 10);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'Restored Mix');
      expect(controller.state.currentTrack?.sourceId, 'restored-b');
      expect(controller.state.playingTrack?.sourceId, 'restored-b');
      expect(controller.state.isLoadingMoreMix, isTrue);

      final loadMoreApplied = Completer<void>();
      late final StreamSubscription<void> queueSub;
      queueSub = queueManager.stateStream.listen((_) {
        final hasNewTrack = controller.state.queue
            .any((track) => track.sourceId == 'restored-new-0');
        if (hasNewTrack &&
            !controller.state.isLoadingMoreMix &&
            !loadMoreApplied.isCompleted) {
          loadMoreApplied.complete();
        }
      });

      loadMoreGate.complete();
      await loadMoreApplied.future;
      await queueSub.cancel();
      await pumpEventQueue(times: 5);

      expect(controller.state.isLoadingMoreMix, isFalse);
      expect(
        controller.state.queue.map((track) => track.sourceId),
        contains('restored-new-0'),
      );
    });

    test('startMixFromPlaylist loads mix tracks and starts mix playback',
        () async {
      final playlist = Playlist()
        ..name = 'Focus Mix'
        ..mixPlaylistId = 'RDfocus123'
        ..mixSeedVideoId = 'seed-video';
      final firstTrack = _track('mix-a', title: 'Mix A');
      final secondTrack = _track('mix-b', title: 'Mix B');

      mixTracksFetcher.result = MixFetchResult(
        title: 'Ignored source title',
        tracks: [firstTrack, secondTrack],
      );

      await controller.startMixFromPlaylist(playlist);

      expect(
        mixTracksFetcher.calls,
        [
          const _MixFetchCall(
            playlistId: 'RDfocus123',
            currentVideoId: 'seed-video',
          ),
        ],
      );
      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'Focus Mix');
      expect(controller.state.currentTrack?.sourceId, 'mix-a');
      expect(
        controller.state.queue.map((track) => track.sourceId),
        orderedEquals(['mix-a', 'mix-b']),
      );
      expect(audioService.playUrlCalls.single.url,
          'https://example.com/mix-a.m4a');
    });

    test('delayed startMixFromPlaylist result does not override newer playback',
        () async {
      final playlist = Playlist()
        ..name = 'Slow Mix'
        ..mixPlaylistId = 'RDslow123'
        ..mixSeedVideoId = 'seed-video';
      final mixGate = mixTracksFetcher.enqueuePendingResult(
        MixFetchResult(
          title: 'Slow Mix',
          tracks: [_track('slow-mix-a', title: 'Slow Mix A')],
        ),
      );

      final mixFuture = controller.startMixFromPlaylist(playlist);
      await pumpEventQueue(times: 2);

      await controller.playTrack(_track('new-direct-track', title: 'Direct'));
      await pumpEventQueue(times: 10);
      expect(controller.state.currentTrack?.sourceId, 'new-direct-track');

      mixGate.complete();
      await mixFuture;
      await pumpEventQueue(times: 10);

      expect(controller.state.currentTrack?.sourceId, 'new-direct-track');
      expect(controller.state.isMixMode, isFalse);
      expect(
        audioService.playUrlCalls.map((call) => call.url),
        isNot(contains('https://example.com/slow-mix-a.m4a')),
      );
    });

    test('completion at mix queue end waits for pending load-more tracks',
        () async {
      final playlist = Playlist()
        ..name = 'Continuous Mix'
        ..mixPlaylistId = 'RDcontinuous123'
        ..mixSeedVideoId = 'seed-video';

      mixTracksFetcher.result = MixFetchResult(
        title: 'Continuous Mix',
        tracks: [
          _track('mix-a', title: 'Mix A'),
          _track('mix-b', title: 'Mix B'),
        ],
      );

      await controller.startMixFromPlaylist(playlist);

      final loadMoreGate = mixTracksFetcher.enqueuePendingResult(
        MixFetchResult(
          title: 'Continuous Mix',
          tracks: List.generate(
            10,
            (index) => _track('mix-new-$index', title: 'Mix New $index'),
          ),
        ),
      );

      await controller.next();
      await pumpEventQueue(times: 5);

      expect(controller.state.currentTrack?.sourceId, 'mix-b');
      expect(controller.state.isLoadingMoreMix, isTrue);

      final nextTrackPlayed = _waitForPlayUrlCallCount(
        audioService,
        controller,
        3,
      );
      audioService.emitCompleted();
      await pumpEventQueue(times: 5);
      loadMoreGate.complete();

      await nextTrackPlayed;
      expect(controller.state.currentTrack?.sourceId, 'mix-new-0');
      expect(audioService.playUrlCalls.last.url,
          'https://example.com/mix-new-0.m4a');
    });
  });
}

Future<void> _waitForPlayUrlCallCount(
  FakeAudioService audioService,
  AudioController controller,
  int count, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  var waitComplete = audioService.playUrlCalls.length >= count;
  Object? waitError;
  StackTrace? waitStackTrace;
  if (!waitComplete) {
    unawaited(audioService.waitForPlayUrlCallCount(count).then((_) {
      waitComplete = true;
    }).catchError((Object error, StackTrace stackTrace) {
      waitError = error;
      waitStackTrace = stackTrace;
    }));
  }

  final stopwatch = Stopwatch()..start();
  while (!waitComplete && audioService.playUrlCalls.length < count) {
    if (waitError != null) {
      Error.throwWithStackTrace(waitError!, waitStackTrace!);
    }
    if (stopwatch.elapsed >= timeout) {
      final playUrlCalls = audioService.playUrlCalls
          .map((call) => '${call.track?.sourceId ?? 'unknown'} => ${call.url}')
          .toList();
      fail(
        'Timed out waiting for $count playUrl calls after $timeout. '
        'playUrlCalls=$playUrlCalls, '
        'currentTrack=${controller.state.currentTrack?.sourceId}',
      );
    }
    await pumpEventQueue();
  }
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
  _FakeSourceManager() : super(sources: const []);

  final _source = _FakeSource();

  @override
  AudioStreamSource? audioStreamSource(SourceType type) => _source;

  @override
  void dispose() {}
}

class _RecordingMixTracksFetcher {
  final List<_MixFetchCall> calls = [];
  final List<_PendingMixFetch> _pending = [];
  MixFetchResult result = const MixFetchResult(title: 'Empty', tracks: []);

  Completer<void> enqueuePendingResult(MixFetchResult result) {
    final completer = Completer<void>();
    _pending.add(_PendingMixFetch(completer, result));
    return completer;
  }

  Future<MixFetchResult> call({
    required String playlistId,
    required String currentVideoId,
  }) async {
    calls.add(
      _MixFetchCall(
        playlistId: playlistId,
        currentVideoId: currentVideoId,
      ),
    );
    if (_pending.isNotEmpty) {
      final pending = _pending.removeAt(0);
      await pending.completer.future;
      return pending.result;
    }
    return result;
  }
}

class _PendingMixFetch {
  _PendingMixFetch(this.completer, this.result);

  final Completer<void> completer;
  final MixFetchResult result;
}

class _MixFetchCall {
  const _MixFetchCall({
    required this.playlistId,
    required this.currentVideoId,
  });

  final String playlistId;
  final String currentVideoId;

  @override
  bool operator ==(Object other) {
    return other is _MixFetchCall &&
        other.playlistId == playlistId &&
        other.currentVideoId == currentVideoId;
  }

  @override
  int get hashCode => Object.hash(playlistId, currentVideoId);
}

class _FakeSourceAuthContext implements SourceAuthContext {
  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async => null;

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    return PlaybackNetworkRequest(
      url: url,
      headers: SourceHttpPolicy.mediaHeaders(
        track.sourceType,
        requestUrl: url,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSource implements AudioStreamSource {
  @override
  SourceType get sourceType => SourceType.youtube;

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
    return null;
  }
}
