import 'dart:async';
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
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/providers/audio/audio_controller_provider.dart';
import 'package:fmp/providers/audio/audio_player_selectors.dart';
import 'package:fmp/services/audio/queue_state.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_playlist_types.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/audio_controller_harness.dart';
import '../../support/fakes/fake_audio_service.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('queueStateProvider', () {
    setUpAll(() async {
      await initializeIsarForTests();
    });

    late _AudioControllerHarness harness;

    setUp(() async {
      harness = await _AudioControllerHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('queueProvider reads the queue projection', () async {
      final firstQueue = [_track('one')];

      harness.container
          .read(queueStateProvider.notifier)
          .publish(QueueState(queue: firstQueue, queueVersion: 1));
      expect(harness.container.read(queueProvider), firstQueue);

      // 位置每秒更新一次，佇列不該跟著動。
      harness.container.read(audioControllerProvider.notifier).state = harness
          .container
          .read(audioControllerProvider)
          .copyWith(position: const Duration(seconds: 30));

      expect(harness.container.read(queueProvider), firstQueue);
    });

    test('PlayerState declares none of the queue fields', () {
      // 這兩個型別曾經各存一份同樣的 12 個欄位，靠 controller 每次逐欄位抄過去
      // 維持一致。抄漏一個就是一個看不見的 bug，而消費端會因為問了不同的
      // provider 拿到不同的答案。長回來的話這條會先掛。
      final source = File(
        'lib/services/audio/player_state.dart',
      ).readAsStringSync();

      for (final field in const [
        'queue',
        'upcomingTracks',
        'currentIndex',
        'queueTrack',
        'canPlayPrevious',
        'canPlayNext',
        'isShuffleEnabled',
        'loopMode',
        'queueVersion',
        'isMixMode',
        'mixTitle',
        'isLoadingMoreMix',
      ]) {
        expect(
          source.contains(
            RegExp('^' + r'\s+final .* ' + field + ';', multiLine: true),
          ),
          isFalse,
          reason: 'PlayerState.$field belongs to QueueState',
        );
      }
    });

    test(
      'controller queue updates publish through queueStateProvider wiring',
      () async {
        await harness.container
            .read(audioControllerProvider.notifier)
            .addToQueue(_track('wired'));

        final queueState = harness.container.read(queueStateProvider);
        expect(
          harness.container.read(queueProvider).map((track) => track.sourceId),
          ['wired'],
        );
        expect(queueState.queue.map((track) => track.sourceId), ['wired']);
        expect(queueState.queueVersion, greaterThan(0));
      },
    );

    test(
      'mix load-more flag stays synchronized in queueStateProvider',
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
              tracks: [_track('mix-a'), _track('mix-b')],
              startIndex: 1,
            );
        await pumpEventQueue(times: 5);

        expect(harness.container.read(queueStateProvider).isMixMode, isTrue);
        expect(harness.container.read(queueStateProvider).mixTitle, 'My Mix');
        expect(
          harness.container.read(queueStateProvider).isLoadingMoreMix,
          isTrue,
        );

        loadMoreGate.complete();
        await _waitUntil(
          () => !harness.container.read(queueStateProvider).isLoadingMoreMix,
        );

        expect(harness.container.read(queueStateProvider).isMixMode, isTrue);
        expect(harness.container.read(queueStateProvider).mixTitle, 'My Mix');
        expect(
          harness.container.read(queueStateProvider).isLoadingMoreMix,
          isFalse,
        );
      },
    );
  });
}

Track _track(String sourceId) => Track()
  ..sourceId = sourceId
  ..sourceType = SourceIds.youtube
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
    required this.streamResolutionService,
  });

  final Directory tempDir;
  final Isar isar;
  final AudioController controller;
  final ProviderContainer container;
  final _TestMixTracksFetcher mixTracksFetcher;
  final DefaultStreamResolutionService streamResolutionService;

  static Future<_AudioControllerHarness> create() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'audio_queue_state_provider_',
    );
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
    final streamResolutionService = DefaultStreamResolutionService(
      trackRepository: trackRepository,
      settingsRepository: settingsRepository,
      sourceManager: sourceManager,
      sourceAuthContext: _FakeSourceAuthContext(),
    );
    final audioStreamManager = AudioStreamManager(
      streamResolutionService: streamResolutionService,
      sourceAuthContext: _FakeSourceAuthContext(),
    );
    final mixTracksFetcher = _TestMixTracksFetcher();
    final built = buildTestAudioControllerIn(
      audioService: FakeAudioService(),
      queueManager: queueManager,
      audioStreamManager: audioStreamManager,
      toastService: ToastService(),
      nowPlayingPublisher: testNowPlayingPublisher(),
      settingsRepository: settingsRepository,
      mixTracksFetcher: mixTracksFetcher.call,
    );
    // 控制器與 `queueStateProvider` 現在住在同一個 container，投影的接線由
    // `AudioController.build()` 自己完成，測試不必再手動接一次。
    final controller = built.controller;
    final container = built.container;
    await controller.initialize();

    return _AudioControllerHarness(
      tempDir: tempDir,
      isar: isar,
      controller: controller,
      container: container,
      mixTracksFetcher: mixTracksFetcher,
      streamResolutionService: streamResolutionService,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    streamResolutionService.dispose();
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
}
