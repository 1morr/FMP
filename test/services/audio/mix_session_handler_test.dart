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
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/mix_playlist_handler.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/fakes/fake_audio_service.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MixPlaylistHandler', () {
    test(
        'finishLoading ignores stale session and leaves active session loading',
        () {
      final handler = MixPlaylistHandler();
      final stale = handler.start(
        playlistId: 'RD-stale',
        seedVideoId: 'seed-stale',
        title: 'Stale Mix',
      );
      expect(handler.markLoading(stale), isTrue);

      final active = handler.start(
        playlistId: 'RD-active',
        seedVideoId: 'seed-active',
        title: 'Active Mix',
      );
      expect(handler.markLoading(active), isTrue);

      const fetchResult = MixFetchResult(title: 'Ignored Result', tracks: []);
      expect(fetchResult.title, 'Ignored Result');

      handler.finishLoading(stale);

      expect(handler.current, same(active));
      expect(handler.current?.isLoadingMore, isTrue);
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
      mixTracksFetcher = _TestMixTracksFetcher();
      controller = AudioController(
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
      controller.dispose();
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
      await pumpEventQueue(times: 5);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'First Mix');
      expect(controller.state.isLoadingMoreMix, isTrue);

      await controller.clearQueue();
      await pumpEventQueue(times: 5);

      loadMoreGate.complete();
      await pumpEventQueue(times: 20);

      expect(controller.state.isMixMode, isFalse);
      expect(controller.state.mixTitle, isNull);
      expect(controller.state.isLoadingMoreMix, isFalse);
      expect(controller.state.upcomingTracks, isEmpty);
    });

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
      await pumpEventQueue(times: 5);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'Old Mix');
      expect(controller.state.currentTrack?.sourceId, 'old-b');
      expect(controller.state.isLoadingMoreMix, isTrue);

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
      await pumpEventQueue(times: 5);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'New Mix');
      expect(controller.state.currentTrack?.sourceId, 'new-a');
      expect(controller.state.playingTrack?.sourceId, 'new-a');
      expect(controller.state.isLoadingMoreMix, isFalse);

      staleLoadGate.complete();
      await pumpEventQueue(times: 20);

      expect(controller.state.isMixMode, isTrue);
      expect(controller.state.mixTitle, 'New Mix');
      expect(controller.state.currentTrack?.sourceId, 'new-a');
      expect(controller.state.playingTrack?.sourceId, 'new-a');
      expect(controller.state.isLoadingMoreMix, isFalse);
    });
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
