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
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/services/audio/audio_provider.dart';
import 'package:fmp/services/audio/audio_stream_manager.dart';
import 'package:fmp/services/audio/playback_side_effects.dart';
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

/// 「開始播一首歌」只有一個扇出站點。
///
/// 以前有兩個（播放請求的成功路徑、跟隨後端 gapless 交界的路徑），兩份清單靠人
/// 維持一致 —— 跟隨路徑的歌詞比對就是後來才補上的。這裡守的是兩條路徑都只經過
/// `_updatePlayingTrack`，以及一個消費者拋例外不會影響其他消費者與播放本身。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('playback side effects', () {
    late Directory tempDir;
    late Isar isar;
    late QueueManager queueManager;
    late FakeAudioService audioService;
    late DefaultStreamResolutionService streamResolutionService;
    late SettingsRepository settingsRepository;
    late QueuePersistenceManager queuePersistenceManager;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('playback_side_effects_');
      isar = await Isar.open(
        [TrackSchema, PlayQueueSchema, SettingsSchema, PlaylistSchema],
        directory: tempDir.path,
        name: 'playback_side_effects_test',
      );

      final queueRepository = QueueRepository(isar);
      final trackRepository = TrackRepository(isar);
      settingsRepository = SettingsRepository(isar);
      queuePersistenceManager = QueuePersistenceManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
      );
      streamResolutionService = DefaultStreamResolutionService(
        trackRepository: trackRepository,
        settingsRepository: settingsRepository,
        sourceManager: _StubSourceManager(),
        sourceAuthContext: FakeSourceAuthContext(),
      );
      queueManager = QueueManager(
        queueRepository: queueRepository,
        trackRepository: trackRepository,
        queuePersistenceManager: queuePersistenceManager,
      );
      audioService = FakeAudioService();
    });

    tearDown(() async {
      streamResolutionService.dispose();
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    AudioController buildController(PlaybackSideEffect sideEffects) {
      return buildTestAudioControllerIn(
        audioService: audioService,
        queueManager: queueManager,
        audioStreamManager: AudioStreamManager(
          streamResolutionService: streamResolutionService,
          sourceAuthContext: FakeSourceAuthContext(),
        ),
        toastService: ToastService(),
        nowPlayingPublisher: testNowPlayingPublisher(),
        settingsRepository: settingsRepository,
        queuePersistenceManager: queuePersistenceManager,
        playbackSideEffects: sideEffects,
      ).controller;
    }

    test('both playback paths notify the same side effects', () async {
      final effect = _RecordingSideEffect();
      final controller = buildController(effect);
      await controller.initialize();

      await controller.playAll([
        _track('alpha', title: 'Alpha'),
        _track('beta', title: 'Beta'),
      ]);
      await pumpUntil(
        () => audioService.setNextMediaCalls.isNotEmpty,
        reason: 'the next medium to be armed',
      );

      audioService.emitAdvancedToNext(audioService.setNextMediaCalls.single!);
      await pumpUntil(
        () => effect.newPlays.length == 2,
        reason:
            'both the request path and the follow path to report a new play',
      );

      expect(effect.newPlays.map((call) => call.track.sourceId), [
        'alpha',
        'beta',
      ], reason: 'the request path first, then the gapless boundary');
      // 同一條呼叫序列：先投影 UI（還不算一次播放），拿到 URL 後才算；跟隨路徑
      // 沒有前半段，但走的是同一個入口。
      expect(effect.trackStarted.map((call) => call.signature), [
        'alpha:false',
        'alpha:true',
        'beta:true',
      ]);
      expect(
        effect.calls,
        contains('onPlaybackStateChanged'),
        reason: 'the state path goes through the same registry',
      );
      expect(
        effect.calls,
        isNot(contains('onStopped')),
        reason: 'neither path stops playback',
      );
    });

    test('a throwing side effect does not stop the others', () async {
      final throwing = _ThrowingSideEffect();
      final second = _RecordingSideEffect();
      final third = _RecordingSideEffect();
      final controller = buildController(
        PlaybackSideEffectRegistry([throwing, second, third]),
      );
      await controller.initialize();

      await controller.playTrack(_track('alpha', title: 'Alpha'));
      await pumpUntil(
        () => second.newPlays.isNotEmpty && third.newPlays.isNotEmpty,
        reason: 'the two effects behind the throwing one to be notified',
      );

      expect(throwing.callCount, greaterThan(0));
      expect(second.calls, contains('onPlaybackStateChanged'));
      expect(third.calls, contains('onPlaybackStateChanged'));
      expect(
        controller.state.error,
        isNull,
        reason: 'a side effect failure is not a playback failure',
      );
    });
  });
}

typedef _TrackStartedCall = ({Track track, bool countsAsNewPlay});

extension on _TrackStartedCall {
  String get signature => '${track.sourceId}:$countsAsNewPlay';
}

class _RecordingSideEffect implements PlaybackSideEffect {
  final calls = <String>[];
  final trackStarted = <_TrackStartedCall>[];

  List<_TrackStartedCall> get newPlays =>
      trackStarted.where((call) => call.countsAsNewPlay).toList();

  @override
  void onTrackStarted(Track track, {required bool countsAsNewPlay}) {
    calls.add('onTrackStarted');
    trackStarted.add((track: track, countsAsNewPlay: countsAsNewPlay));
  }

  @override
  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot) {
    calls.add('onPlaybackStateChanged');
  }

  @override
  void onStopped() => calls.add('onStopped');

  @override
  void dispose() => calls.add('dispose');
}

class _ThrowingSideEffect implements PlaybackSideEffect {
  int callCount = 0;

  Never _fail() {
    callCount++;
    throw StateError('side effect failed');
  }

  @override
  void onTrackStarted(Track track, {required bool countsAsNewPlay}) => _fail();

  @override
  void onPlaybackStateChanged(PlaybackStateSnapshot snapshot) => _fail();

  @override
  void onStopped() => _fail();

  @override
  void dispose() => _fail();
}

Track _track(String sourceId, {required String title}) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceIds.youtube
    ..title = title
    ..artist = 'Tester';
}

class _StubSourceManager extends SourceManager {
  _StubSourceManager() : super(sources: const []);

  final _source = _StubSource();

  @override
  AudioStreamSource? audioStreamSource(String type) => _source;

  @override
  void dispose() {}
}

class _StubSource implements AudioStreamSource {
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
  ) async => null;
}
