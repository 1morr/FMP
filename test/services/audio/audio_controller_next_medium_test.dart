import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/source_ids.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/account/source_auth_context.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/playback_media.dart';
import 'package:fmp/services/audio/queue_manager.dart';
import 'package:fmp/services/audio/queue_persistence_manager.dart';
import 'package:fmp/services/audio/stream_resolution_service.dart';
import 'package:isar_community/isar.dart';

import '../../support/audio_controller_harness.dart';
import '../../support/fakes/fake_audio_service.dart';
import '../../support/isar_test_harness.dart';
import '../../support/now_playing.dart';

/// 把「下一首」交給後端之後，推進權在後端手上：交界不會有 `EndedNaturally`，
/// 控制器改成跟隨 `advancedToNext`。
///
/// 這裡守的是 arm/disarm 的條件表 —— 每一條都是「下一首是什麼由別的規則決定」
/// 的情況，錯一條就是安靜地播錯歌。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioController next medium', () {
    late Directory tempDir;
    late Isar isar;
    late QueueManager queueManager;
    late FakeAudioService audioService;
    late DefaultStreamResolutionService streamResolutionService;
    late _CountingSourceManager sourceManager;
    late AudioController controller;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_next_medium_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema, PlaylistSchema],
        directory: tempDir.path,
        name: 'audio_controller_next_medium_test',
      );

      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      final settingsRepository = SettingsRepository(isar);
      sourceManager = _CountingSourceManager();
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
      queueManager = QueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: queuePersistenceManager,
      );
      audioService = FakeAudioService();
      controller = buildTestAudioController(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: AudioStreamManager(
          streamResolutionService: streamResolutionService,
          sourceAuthContext: _FakeSourceAuthContext(),
        ),
        toastService: ToastService(),
        nowPlayingPublisher: testNowPlayingPublisher(),
        settingsRepository: settingsRepository,
        queuePersistenceManager: queuePersistenceManager,
      );
      await controller.initialize();
    });

    tearDown(() async {
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// 條件式等待。固定圈數的 `pumpEventQueue` 在滿載的套件裡會變成計時競態
    /// （issue #43、#55 都是那個形狀）。
    Future<void> waitFor(bool Function() done, String what) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) fail('timed out waiting: $what');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    Future<void> playPair() async {
      await controller.playAll([
        _track('alpha', title: 'Alpha'),
        _track('beta', title: 'Beta'),
      ]);
    }

    test('playing a queue hands the next medium to the backend', () async {
      await playPair();
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the next medium to be armed');

      final armed = audioService.setNextMediaCalls.single;
      expect(armed, isA<RemotePlaybackMedia>());
      expect(armed!.track.sourceId, 'beta');
      // 預取解析過一次，arm 走的是那一次留下的行程內快取，不再打第二次。
      expect(sourceManager.resolveCount['beta'], 1);
    });

    test('loop-one never arms', () async {
      // `QueueManager.getNextIndex()` 根本不看 loop-one，所以預取還是會跑到
      // 「再下一首」。照著它 arm 就是直接播錯歌。
      await controller.setLoopMode(LoopMode.one);
      await playPair();

      // 等預取真的跑完再做否定斷言，否則只是在賭時序。
      await waitFor(() => sourceManager.resolveCount['beta'] != null,
          'the next track to be prefetched');
      expect(audioService.setNextMediaCalls, isEmpty);
    });

    test('a queue mutation takes the next medium back', () async {
      await playPair();
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the next medium to be armed');

      await controller.addNext(_track('gamma', title: 'Gamma'));

      await waitFor(() => audioService.setNextMediaCalls.contains(null),
          'the arm to be cleared');
    });

    test('switching to loop-one takes the next medium back', () async {
      await playPair();
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the next medium to be armed');

      await controller.setLoopMode(LoopMode.one);

      await waitFor(() => audioService.setNextMediaCalls.contains(null),
          'the arm to be cleared');
    });

    test('shuffle never leaves a stale medium armed', () async {
      await controller.playAll([
        _track('alpha', title: 'Alpha'),
        _track('beta', title: 'Beta'),
        _track('gamma', title: 'Gamma'),
        _track('delta', title: 'Delta'),
      ]);
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the next medium to be armed');

      final versionBefore = controller.queueState.queueVersion;
      await controller.toggleShuffle();
      // `queueVersion` 只在 `_updateQueueState` 裡前進，而 disarm 的網就掛在
      // 那裡 —— 等它跑過一輪才有東西可以斷言。
      await waitFor(() => controller.queueState.queueVersion > versionBefore,
          'the queue state to be recomputed');

      // 打亂之後「下一首」有機會剛好還是同一首，所以不能斷言一定 disarm ——
      // 真正的不變量是「還 armed 著的話，它必須就是現在的下一首」。
      final armed = audioService.setNextMediaCalls.last;
      if (armed == null) return;
      final nextIndex = queueManager.getNextIndex();
      expect(nextIndex, isNotNull);
      expect(armed.track.sourceId, queueManager.tracks[nextIndex!].sourceId);
    });

    test('the controller follows the backend across the boundary', () async {
      await playPair();
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the next medium to be armed');
      final armed = audioService.setNextMediaCalls.single!;

      expect(queueManager.currentIndex, 0);
      final playedBefore = audioService.playMediaCalls.length;
      final stoppedBefore = audioService.stopCallCount;

      audioService.emitAdvancedToNext(armed);
      await waitFor(() => controller.state.playingTrack?.sourceId == 'beta',
          'the controller to follow the backend');

      expect(queueManager.currentIndex, 1, reason: 'exactly one step');
      expect(audioService.playMediaCalls.length, playedBefore,
          reason: 'following must not start a new playback request');
      expect(audioService.stopCallCount, stoppedBefore,
          reason: 'a gapless boundary must never stop the backend');
      expect(controller.queueState.currentIndex, 1);
    });

    test('following one boundary arms the boundary after it', () async {
      // 平常的 arm 掛在播放請求的預取上，而跟隨路徑刻意不發請求 —— 不補這一步
      // 的話一條佇列只有第一個交界是 gapless。
      await controller.playAll([
        _track('alpha', title: 'Alpha'),
        _track('beta', title: 'Beta'),
        _track('gamma', title: 'Gamma'),
      ]);
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the first medium to be armed');
      final first = audioService.setNextMediaCalls.single!;
      expect(first.track.sourceId, 'beta');

      audioService.emitAdvancedToNext(first);

      await waitFor(
          () => audioService.setNextMediaCalls.last?.track.sourceId == 'gamma',
          'the next boundary to be armed');
    });

    test('the boundary replaces the stream metadata', () async {
      await playPair();
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the next medium to be armed');
      expect(controller.state.currentContainer, 'alpha-m4a');

      audioService.emitAdvancedToNext(audioService.setNextMediaCalls.single!);
      await waitFor(() => controller.state.playingTrack?.sourceId == 'beta',
          'the controller to follow the backend');

      // 這四個值屬於當前播放請求。跟隨路徑不經過 `_exitLoadingState`，忘了補
      // 就會一直顯示上一首的碼率與格式。
      expect(controller.state.currentContainer, 'beta-m4a');
      expect(controller.state.isLoading, isFalse,
          reason: 'a gapless boundary is not a load; the spinner must not stick');
      expect(controller.state.error, isNull);
    });

    test('an unrecognised advance falls back to the completion path', () async {
      await playPair();
      await waitFor(() => audioService.setNextMediaCalls.isNotEmpty,
          'the next medium to be armed');

      // 後端接上去的不是控制器交出去的那一個 —— 沒有安全的跟隨方式。
      audioService.emitAdvancedToNext(
        RemotePlaybackMedia(
          url: Uri.parse('https://example.com/stranger.m4a'),
          headers: const {},
          track: _track('stranger', title: 'Stranger'),
        ),
      );

      await waitFor(() => queueManager.currentIndex == 1,
          'the completion path to advance the queue');
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

class _CountingSourceManager extends SourceManager {
  _CountingSourceManager() : super(sources: const []);

  final Map<String, int> resolveCount = {};
  late final _CountingSource _source = _CountingSource(resolveCount);

  @override
  AudioStreamSource? audioStreamSource(String type) => _source;

  @override
  void dispose() {}
}

class _CountingSource implements AudioStreamSource {
  _CountingSource(this._counts);

  final Map<String, int> _counts;

  @override
  String get sourceType => SourceIds.youtube;

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    _counts[request.sourceId] = (_counts[request.sourceId] ?? 0) + 1;
    return AudioStreamResult(
      url: 'https://example.com/${request.sourceId}.m4a',
      // 每首不同，交界之後的後設資料才分得出來是誰的。
      container: '${request.sourceId}-m4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async =>
      null;
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
